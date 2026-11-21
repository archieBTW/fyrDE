import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/midi_mapping.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/song_marker.dart';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/services/project_archive_service.dart';
import 'package:fyrdaw/services/undo_history.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:fyrdaw/utils/mixdown_renderer.dart';
import 'package:fyrdaw/utils/time_stretch.dart';
import 'package:fyrdaw/wav_writer.dart';

void _writeTestSineWav(
  String path, {
  int sampleRate = 44100,
  double durationSec = 0.5,
  double freqHz = 440.0,
  double amplitude = 0.4,
}) {
  final frames = (sampleRate * durationSec).round();
  final writer = WavWriter(path, sampleRate: sampleRate, channels: 2);
  final pcm = Int16List(frames * 2);
  for (int i = 0; i < frames; i++) {
    final s = (sin(2 * pi * freqHz * i / sampleRate) * amplitude * 32767.0)
        .round()
        .clamp(-32768, 32767);
    pcm[i * 2] = s;
    pcm[i * 2 + 1] = s;
  }
  writer.write(ByteData.view(pcm.buffer).buffer.asUint8List());
  writer.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UndoRedoStack', () {
    test('pushes, undoes, redoes, clears redo on new edit, and bounds size', () {
      final stack = UndoRedoStack<String>(maxEntries: 3);
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.undo('cur'), isNull);
      expect(stack.redo('cur'), isNull);

      stack.push('s1');
      stack.push('s2');
      stack.push('s3');
      stack.push('s4'); // evicts s1
      expect(stack.undoLength, 3);

      expect(stack.undo('s5'), 's4');
      expect(stack.undo('s4'), 's3');
      expect(stack.canRedo, isTrue);
      expect(stack.redo('s3'), 's4');

      // Pushing a new snapshot invalidates the remaining redo branch
      stack.push('s4_branch');
      expect(stack.canRedo, isFalse);
      expect(stack.undo('s5_branch'), 's4_branch');
    });
  });

  group('ProjectArchiveService', () {
    test('round-trips .adaw ZIP archive on background isolate and restores media paths', () async {
      final tmp = Directory.systemTemp.createTempSync('sb_arch_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final audioPath = '${tmp.path}/guitar_take.wav';
      final padPath = '${tmp.path}/custom_snare.wav';
      _writeTestSineWav(audioPath, durationSec: 0.25, freqHz: 330.0);
      _writeTestSineWav(padPath, durationSec: 0.15, freqHz: 220.0);

      final audioTrack = Track(
        id: 't_aud',
        name: 'Guitar',
        type: TrackType.audio,
      );
      final smpTrack = Track(
        id: 't_smp',
        name: 'Drums',
        type: TrackType.sampler,
      );
      smpTrack.samplerPads[0] = SamplerPad()
        ..midiNote = 36
        ..name = 'Custom Snare'
        ..filePath = padPath;
      smpTrack.samplerPads[1] = SamplerPad()
        ..midiNote = 37
        ..name = 'Bundled Hat'
        ..filePath = 'assets/samples/drums/808_chh.wav';

      final clip = AudioClip(
        id: 'c_1',
        name: 'Riff',
        start: 0.0,
        length: 100.0,
        color: Colors.cyan,
        filePath: audioPath,
      );

      final payload = ProjectArchiveService.buildArchivePayload(
        bpm: 128,
        timeSigTop: 4,
        timeSigBottom: 4,
        metronomeVolume: 0.7,
        masterVolume: 0.9,
        masterLimiter: true,
        masterLufsTarget: -11.0,
        masterEffectsChain: [DawEffect('Compressor', {'Thresh': 0.5})],
        midiMappings: [
          MidiCcMapping(cc: 7, channel: 0, trackId: 't_aud', param: 'volume'),
        ],
        auxReverbMix: 0.6,
        auxDelayMix: 0.4,
        songMarkers: [
          SongMarker(id: 'm1', label: 'Drop', position: 200.0, colorValue: 0xFF00FF00),
        ],
        tempoMarkers: [
          TempoMarker(id: 'tm1', position: 400.0, bpm: 132.0),
        ],
        tracks: [audioTrack, smpTrack],
        trackClips: {
          audioTrack.id: [clip],
        },
      );

      // Verify relative basenames in archive payload while keeping assets/ intact
      expect(payload.mediaFilePaths, containsAll([audioPath, padPath]));
      expect(payload.projectData['trackClips']['t_aud'][0]['filePath'], 'guitar_take.wav');
      expect(
        payload.projectData['tracks'][1]['samplerPads']['0']['filePath'],
        'custom_snare.wav',
      );
      expect(
        payload.projectData['tracks'][1]['samplerPads']['1']['filePath'],
        'assets/samples/drums/808_chh.wav',
      );

      final adawPath = '${tmp.path}/session.adaw';
      await ProjectArchiveService.saveArchiveToPath(
        outputPath: adawPath,
        projectData: payload.projectData,
        mediaFilePaths: payload.mediaFilePaths,
      );
      expect(File(adawPath).existsSync(), isTrue);

      final extractDir = '${tmp.path}/extracted_media';
      final loaded = await ProjectArchiveService.loadArchiveFromPath(
        path: adawPath,
        mediaDirPath: extractDir,
      );

      expect(loaded['bpm'], 128);
      expect(loaded['masterLufsTarget'], -11.0);
      expect(loaded['trackClips']['t_aud'][0]['filePath'], '$extractDir/guitar_take.wav');
      expect(
        loaded['tracks'][1]['samplerPads']['0']['filePath'],
        '$extractDir/custom_snare.wav',
      );
      expect(
        loaded['tracks'][1]['samplerPads']['1']['filePath'],
        'assets/samples/drums/808_chh.wav',
      );
      expect(File('$extractDir/guitar_take.wav').existsSync(), isTrue);
      expect(File('$extractDir/custom_snare.wav').existsSync(), isTrue);
    });

    test('loads legacy raw JSON .adaw files cleanly', () async {
      final tmp = Directory.systemTemp.createTempSync('sb_legacy_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final legacyPath = '${tmp.path}/legacy.adaw';
      File(legacyPath).writeAsStringSync(jsonEncode({'bpm': 95, 'tracks': []}));

      final loaded = await ProjectArchiveService.loadArchiveFromPath(
        path: legacyPath,
        mediaDirPath: '${tmp.path}/media',
      );
      expect(loaded['bpm'], 95);
    });
  });

  group('Background Isolate DSP Parity', () {
    test('MixdownRenderer isolate output is bit-identical to inline output', () async {
      final tmp = Directory.systemTemp.createTempSync('sb_iso_mix_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final srcWav = '${tmp.path}/tone.wav';
      _writeTestSineWav(srcWav, durationSec: 0.4, freqHz: 261.63, amplitude: 0.35);

      final grp = Track(id: 'grp_1', name: 'Bus', type: TrackType.group)
        ..volume = 0.9
        ..effectsChain.add(DawEffect('EQ', {'Low': 0.6, 'Mid': 0.5, 'High': 0.45}));
      final aud = Track(id: 'aud_1', name: 'Audio', type: TrackType.audio)
        ..groupTrackId = grp.id
        ..reverbSend = 0.25
        ..effectsChain.add(DawEffect('Compressor', {'Thresh': 0.4, 'Ratio': 0.5, 'Gain': 0.5}))
        ..automation['Volume'] = [
          AutomationPoint(0.0, 0.5),
          AutomationPoint(40.0, 1.0, curve: 0.35),
        ];
      final midi = Track(id: 'mid_1', name: 'Synth', type: TrackType.midi)
        ..instrumentIndex = 0
        ..synthSettings.filterCutoff = 0.65;

      final clips = <String, List<DawClip>>{
        aud.id: [
          AudioClip(
            id: 'c_a',
            start: 0.0,
            length: 40.0,
            color: Colors.blue,
            filePath: srcWav,
          ),
        ],
        midi.id: [
          MidiClip(
            id: 'c_m',
            start: 0.0,
            length: 40.0,
            color: Colors.purple,
            notes: [MidiNote(pitch: 60, start: 0.0, length: 25.0, velocity: 100)],
          ),
        ],
      };

      final outIso = '${tmp.path}/iso.wav';
      final outSync = '${tmp.path}/sync.wav';

      final okIso = await MixdownRenderer.renderToWav(
        tracks: [grp, aud, midi],
        trackClips: clips,
        outWavPath: outIso,
        bpm: 120,
        useIsolate: true,
      );
      final okSync = await MixdownRenderer.renderToWav(
        tracks: [grp, aud, midi],
        trackClips: clips,
        outWavPath: outSync,
        bpm: 120,
        useIsolate: false,
      );

      expect(okIso, isTrue);
      expect(okSync, isTrue);
      final bytesIso = File(outIso).readAsBytesSync();
      final bytesSync = File(outSync).readAsBytesSync();
      expect(bytesIso.length, greaterThan(44));
      expect(bytesIso, equals(bytesSync));
    });

    test('TimeStretchEngine.processWavFile isolate output matches inline output', () async {
      final tmp = Directory.systemTemp.createTempSync('sb_iso_stretch_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final srcWav = '${tmp.path}/in.wav';
      _writeTestSineWav(srcWav, durationSec: 0.35, freqHz: 440.0, amplitude: 0.4);

      final outIso = '${tmp.path}/out_iso.wav';
      final outSync = '${tmp.path}/out_sync.wav';

      final okIso = await TimeStretchEngine.processWavFile(
        inputPath: srcWav,
        outputPath: outIso,
        stretchFactor: 1.25,
        pitchSemitones: 2.0,
        preservePitch: true,
        useIsolate: true,
      );
      final okSync = await TimeStretchEngine.processWavFile(
        inputPath: srcWav,
        outputPath: outSync,
        stretchFactor: 1.25,
        pitchSemitones: 2.0,
        preservePitch: true,
        useIsolate: false,
      );

      expect(okIso, isTrue);
      expect(okSync, isTrue);
      expect(File(outIso).readAsBytesSync(), equals(File(outSync).readAsBytesSync()));
    });

    test('Large-file extractWavWaveform (>512 KB) runs cleanly on background isolate', () async {
      final tmp = Directory.systemTemp.createTempSync('sb_iso_wave_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      // 4 seconds stereo 16-bit 44.1 kHz ~= 705 KB (> 512 KB isolate threshold)
      final bigWav = '${tmp.path}/big.wav';
      _writeTestSineWav(bigWav, durationSec: 4.0, freqHz: 220.0, amplitude: 0.5);
      expect(File(bigWav).lengthSync(), greaterThan(524288));

      final peaks = await extractWavWaveform(bigWav, 200);
      expect(peaks, isNotNull);
      expect(peaks!.length, 200);
      expect(peaks.reduce(max), closeTo(0.5, 0.05));
    });
  });
}
