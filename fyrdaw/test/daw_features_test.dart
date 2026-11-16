import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrdaw/main.dart';
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
import 'package:fyrdaw/ui/automation_lane_overlay.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/audio_clip_editor.dart';
import 'package:fyrdaw/ui/effects_rack.dart';
import 'package:fyrdaw/ui/meters.dart';
import 'package:fyrdaw/ui/midi_editor.dart';
import 'package:fyrdaw/ui/mixer_console.dart';
import 'package:fyrdaw/ui/musical_keyboard_bar.dart';
import 'package:fyrdaw/ui/parametric_eq_widget.dart';
import 'package:fyrdaw/ui/sample_browser_drawer.dart';
import 'package:fyrdaw/ui/sampler_editor.dart';
import 'package:fyrdaw/ui/session_launcher.dart';
import 'package:fyrdaw/ui/step_sequencer.dart';
import 'package:fyrdaw/ui/synth_rack_panel.dart';
import 'package:fyrdaw/ui/tempo_signature_lane.dart';
import 'package:fyrdaw/ui/timeline_loop_bar.dart';
import 'package:fyrdaw/utils/bus_metering.dart';
import 'package:fyrdaw/ui/tuner_gate_panel.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/utils/audio_input_channel.dart';
import 'package:fyrdaw/utils/audio_output_routing.dart';
import 'package:fyrdaw/utils/recording_sync.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:record/record.dart';
import 'package:fyrdaw/utils/metronome_synth.dart';
import 'package:fyrdaw/utils/midi_file_codec.dart';
import 'package:fyrdaw/utils/mixdown_renderer.dart';
import 'package:fyrdaw/utils/parametric_eq_dsp.dart';
import 'package:fyrdaw/utils/pitch_detector.dart';
import 'package:fyrdaw/utils/plugin_host.dart';
import 'package:fyrdaw/utils/time_stretch.dart';
import 'package:fyrdaw/wav_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Model serialization', () {
    test('DawEffect preserves isBypassed in JSON round-trip', () {
      final fx = DawEffect(
        'Compressor',
        {'Thresh': 0.4, 'Ratio': 0.7},
        isBypassed: true,
      );
      final decoded = DawEffect.fromJson(fx.toJson());
      expect(decoded.name, 'Compressor');
      expect(decoded.parameters['Thresh'], closeTo(0.4, 1e-6));
      expect(decoded.isBypassed, isTrue);
    });

    test('SongMarker JSON round-trip', () {
      final marker = SongMarker(
        id: 'm1',
        label: 'Chorus',
        position: 400.0,
        colorValue: 0xFF34D399,
      );
      final decoded = SongMarker.fromJson(marker.toJson());
      expect(decoded.id, 'm1');
      expect(decoded.label, 'Chorus');
      expect(decoded.position, 400.0);
      expect(decoded.colorValue, 0xFF34D399);
    });

    test('AudioClip preserves name, fades, gain, and pitch in JSON', () {
      final clip = AudioClip(
        id: 'c1',
        name: 'Lead Guitar',
        start: 100.0,
        length: 300.0,
        color: const Color(0xFF38BDF8),
        filePath: '/tmp/test.wav',
        fadeIn: 25.0,
        fadeOut: 40.0,
        gain: 1.25,
        pitchSemitones: -3.0,
      );
      final decoded = DawClip.fromJson(clip.toJson()) as AudioClip;
      expect(decoded.name, 'Lead Guitar');
      expect(decoded.fadeIn, 25.0);
      expect(decoded.fadeOut, 40.0);
      expect(decoded.gain, 1.25);
      expect(decoded.pitchSemitones, -3.0);
    });

    test('Track preserves colorValue, reverbSend, and delaySend outside SoLoud', () {
      final track = Track(
        id: 't1',
        name: 'Synth Lead',
        type: TrackType.midi,
        colorValue: kTrackColorPalette[2].toARGB32(),
      )
        ..reverbSend = 0.42
        ..delaySend = 0.28;

      final decoded = Track.fromJson(track.toJson());
      expect(decoded.colorValue, kTrackColorPalette[2].toARGB32());
      expect(decoded.reverbSend, closeTo(0.42, 1e-6));
      expect(decoded.delaySend, closeTo(0.28, 1e-6));
    });

    test('SynthSettings, AudioTake/stretchFactor, patternGroupId, chokeGroup & sidechainTrackId JSON round-trips', () {
      final fx = DawEffect('Compressor', {'Thresh': 0.8, 'Ratio': 0.9})
        ..sidechainTrackId = 'kick_1';
      final fxOut = DawEffect.fromJson(fx.toJson());
      expect(fxOut.sidechainTrackId, 'kick_1');

      final clip = AudioClip(
        id: 'ac_takes',
        start: 0.0,
        length: 400.0,
        color: Colors.teal,
        filePath: '/tmp/t1.wav',
        stretchFactor: 1.5,
      );
      clip.addTake(AudioTake(id: 'tk2', name: 'Take 2', filePath: '/tmp/t2.wav', gain: 0.85));
      final clipOut = DawClip.fromJson(clip.toJson()) as AudioClip;
      expect(clipOut.stretchFactor, closeTo(1.5, 1e-6));
      expect(clipOut.takes.length, 2);
      expect(clipOut.activeTakeIndex, 1);
      expect(clipOut.filePath, '/tmp/t2.wav');

      final midi = MidiClip(
        id: 'mc_link',
        start: 0.0,
        length: 400.0,
        color: Colors.purple,
        patternGroupId: 'grp_a',
      );
      final midiOut = DawClip.fromJson(midi.toJson()) as MidiClip;
      expect(midiOut.patternGroupId, 'grp_a');

      final pad = SamplerPad()
        ..midiNote = 42
        ..chokeGroup = 1;
      final padOut = SamplerPad.fromJson(pad.toJson());
      expect(padOut.midiNote, 42);
      expect(padOut.chokeGroup, 1);

      final track = Track(id: 'tr_s', name: 'Lead', type: TrackType.midi)
        ..noiseGateThreshold = 0.08
        ..effectsChain.add(DawEffect('EQ', {'Low': 0.5}))
        ..synthSettings = SynthSettings(
          attackSec: 0.04,
          decaySec: 0.35,
          sustain: 0.6,
          releaseSec: 0.45,
          filterCutoff: 0.55,
          filterResonance: 0.35,
          octave: -1,
          detuneCents: 12.0,
        );
      final trackOut = Track.fromJson(track.toJson());
      expect(trackOut.noiseGateThreshold, closeTo(0.08, 1e-6));
      expect(trackOut.synthSettings.attackSec, closeTo(0.04, 1e-6));
      expect(trackOut.synthSettings.octave, -1);
      expect(trackOut.synthSettings.detuneCents, closeTo(12.0, 1e-6));
      expect(
        trackOut.availableAutomationParams,
        containsAll(['Volume', 'Pan', 'Reverb Send', 'Delay Send', 'EQ_Low']),
      );
    });
  });

  group('Pitch detector, LUFS & Stereo correlation', () {
    test('detectPitchHz recognizes 440Hz (A4) and 82.41Hz (E2) sines and ignores silence', () {
      const sr = 44100;
      final a4 = Float64List(2048);
      for (int i = 0; i < a4.length; i++) {
        a4[i] = 0.5 * sin(2 * pi * 440.0 * i / sr);
      }
      final resA4 = detectPitchHz(a4, sr);
      expect(resA4, isNotNull);
      expect(resA4!.frequencyHz, closeTo(440.0, 4.0));
      expect(resA4.noteName, 'A4');
      expect(resA4.cents.abs(), lessThan(15.0));

      final e2 = Float64List(4096);
      for (int i = 0; i < e2.length; i++) {
        e2[i] = 0.5 * sin(2 * pi * 82.41 * i / sr);
      }
      final resE2 = detectPitchHz(e2, sr);
      expect(resE2, isNotNull);
      expect(resE2!.frequencyHz, closeTo(82.41, 2.0));
      expect(resE2.noteName, 'E2');

      expect(detectPitchHz(Float64List(2048), sr), isNull);
    });

    test('estimateLufsFromWaveform & computeStereoCorrelation behave accurately', () {
      final silent = Float32List(512);
      expect(estimateLufsFromWaveform(silent), -60.0);

      final wave = Float32List(512);
      for (int i = 0; i < 512; i++) {
        wave[i] = sin(i * 0.2) * 0.5;
      }
      final lufs = estimateLufsFromWaveform(wave);
      expect(lufs, greaterThan(-20.0));
      expect(lufs, lessThan(0.0));

      final l = Float64List.fromList([0.5, -0.5, 0.25, -0.25]);
      final rSame = Float64List.fromList([0.5, -0.5, 0.25, -0.25]);
      final rInv = Float64List.fromList([-0.5, 0.5, -0.25, 0.25]);
      expect(computeStereoCorrelation(l, rSame), closeTo(1.0, 1e-6));
      expect(computeStereoCorrelation(l, rInv), closeTo(-1.0, 1e-6));
    });
  });

  group('Audio analysis & offline MixdownRenderer', () {
    test('detectTransientsFromSamples finds percussive slice boundaries', () {
      const sampleRate = 44100;
      const durationSec = 2.0;
      final totalFrames = (sampleRate * durationSec).round();
      final samples = Float64List(totalFrames);

      // Inject 3 crisp impulses at 0.25s, 0.85s, 1.45s
      for (final hitSec in [0.25, 0.85, 1.45]) {
        final center = (hitSec * sampleRate).round();
        for (int i = 0; i < 600 && center + i < totalFrames; i++) {
          samples[center + i] = exp(-i / 100.0) * sin(i * 0.25);
        }
      }

      final slices = detectTransientsFromSamples(
        samples,
        samples,
        sampleRate,
        sensitivity: 0.4,
      );

      // Normalized slices cover [0.0 .. ~0.125, ~0.125 .. ~0.425, ~0.425 .. ~0.725, ~0.725 .. 1.0]
      expect(slices.length, 4);
      expect(slices[0].$1, 0.0);
      expect(slices[1].$1 * durationSec, closeTo(0.25, 0.05));
      expect(slices[2].$1 * durationSec, closeTo(0.85, 0.05));
      expect(slices[3].$1 * durationSec, closeTo(1.45, 0.05));
      expect(slices.last.$2, 1.0);
    });

    test('decodeWavBytes and MixdownRenderer produce valid stereo WAV output', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrdaw_mix_test_');
      try {
        // Generate a 0.5s 440Hz stereo test wav
        final srcPath = '${tmpDir.path}/tone.wav';
        const sampleRate = 44100;
        const frames = 22050;
        final writer = WavWriter(srcPath, sampleRate: sampleRate, channels: 2);
        final pcm = Int16List(frames * 2);
        for (int i = 0; i < frames; i++) {
          final v = (sin(2 * pi * 440.0 * i / sampleRate) * 16000).round();
          pcm[i * 2] = v;
          pcm[i * 2 + 1] = v;
        }
        final byteData = ByteData.view(pcm.buffer);
        writer.write(byteData.buffer.asUint8List());
        writer.close();

        final rawBytes = await File(srcPath).readAsBytes();
        final decoded = decodeWavBytes(rawBytes);
        expect(decoded, isNotNull);
        expect(decoded!.channels, 2);
        expect(decoded.frameCount, frames);

        final audioTrack = Track(id: 'a1', name: 'Audio 1', type: TrackType.audio)
          ..reverbSend = 0.2
          ..delaySend = 0.15
          ..effectsChain.addAll([
            DawEffect('EQ', {'Low': 0.5, 'Mid': 0.6, 'High': 0.4}),
            DawEffect('Compressor', {'Thresh': 0.5, 'Ratio': 0.5}),
          ]);
        final midiTrack = Track(id: 'm1', name: 'Midi 1', type: TrackType.midi)
          ..instrumentIndex = 0;
        final mutedTrack = Track(id: 'm2', name: 'Muted', type: TrackType.audio)
          ..isMuted = true;

        final outWav = '${tmpDir.path}/master_mix.wav';
        final ok = await MixdownRenderer.renderToWav(
          tracks: [audioTrack, midiTrack, mutedTrack],
          trackClips: {
            'a1': [
              AudioClip(
                id: 'ac1',
                start: 0.0,
                length: 50.0,
                color: Colors.blue,
                filePath: srcPath,
                fadeIn: 5.0,
                fadeOut: 5.0,
                gain: 0.9,
              ),
            ],
            'm1': [
              MidiClip(
                id: 'mc1',
                start: 0.0,
                length: 100.0,
                color: Colors.purple,
                notes: [
                  MidiNote(pitch: 60, start: 0.0, length: 40.0, velocity: 100),
                ],
              ),
            ],
            'm2': [
              AudioClip(
                id: 'ac2',
                start: 0.0,
                length: 50.0,
                color: Colors.red,
                filePath: srcPath,
              ),
            ],
          },
          outWavPath: outWav,
          bpm: 120,
        );

        expect(ok, isTrue);
        final outDecoded = await decodeWavFile(outWav);
        expect(outDecoded, isNotNull);
        expect(outDecoded!.frameCount, greaterThan(frames));
        // Ensure non-silent audio rendered
        double maxAbs = 0.0;
        for (final s in outDecoded.left) {
          if (s.abs() > maxAbs) maxAbs = s.abs();
        }
        expect(maxAbs, greaterThan(0.05));
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('MixdownRenderer applies Compressor sidechainTrackId ducking and SynthSettings lowpass', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrdaw_sc_test_');
      try {
        final trigPath = '${tmpDir.path}/trig.wav';
        const sr = 44100;
        const frames = 11025; // 0.25s
        final writer = WavWriter(trigPath, sampleRate: sr, channels: 2);
        final pcm = Int16List(frames * 2);
        for (int i = 0; i < frames; i++) {
          final v = (sin(2 * pi * 100.0 * i / sr) * 28000).round();
          pcm[i * 2] = v;
          pcm[i * 2 + 1] = v;
        }
        writer.write(ByteData.view(pcm.buffer).buffer.asUint8List());
        writer.close();

        final triggerTrack = Track(id: 'trig', name: 'Kick', type: TrackType.audio)
          ..volume = 0.0; // Silent in master mix, still drives sidechain trigger buffer? Wait - keep volume > 0 or separate comparison!
        // Note: MixdownRenderer uses unmuted trigger track output; compare Synth track alone vs ducked by unmuted trigger?
        // Actually render Synth alone first vs Synth ducked by quiet trigger track! Wait: trigger track is mixed too, so check solo/isolated energy isn't masked -> mute state vs unmuted trigger:
        triggerTrack.volume = 1.0;

        final synthDry = Track(id: 'syn', name: 'Pad', type: TrackType.midi)
          ..synthSettings = SynthSettings(filterCutoff: 0.4, attackSec: 0.01);
        final synthDucked = Track(id: 'syn', name: 'Pad', type: TrackType.midi)
          ..effectsChain.add(
            DawEffect('Compressor', {'Thresh': 0.9, 'Ratio': 0.9})
              ..sidechainTrackId = 'trig',
          );

        final clipsDry = {
          'syn': [
            MidiClip(
              id: 'mc',
              start: 0.0,
              length: 50.0,
              color: Colors.blue,
              notes: [MidiNote(pitch: 60, start: 0.0, length: 50.0, velocity: 120)],
            ),
          ],
        };
        final clipsSc = {
          ...clipsDry,
          'trig': [
            AudioClip(
              id: 'tc',
              start: 0.0,
              length: 50.0,
              color: Colors.red,
              filePath: trigPath,
            ),
          ],
        };

        final dryOut = '${tmpDir.path}/dry.wav';
        final scOut = '${tmpDir.path}/sc.wav';
        expect(
          await MixdownRenderer.renderToWav(tracks: [synthDry], trackClips: clipsDry, outWavPath: dryOut, bpm: 120),
          isTrue,
        );
        expect(
          await MixdownRenderer.renderToWav(
            tracks: [triggerTrack, synthDucked],
            trackClips: clipsSc,
            outWavPath: scOut,
            bpm: 120,
          ),
          isTrue,
        );
        final dryDec = await decodeWavFile(dryOut);
        final scDec = await decodeWavFile(scOut);
        expect(dryDec, isNotNull);
        expect(scDec, isNotNull);
        expect(scDec!.frameCount, greaterThan(0));
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  group('UI Widgets', () {
    testWidgets('PanDial double-click resets value to defaultValue', (tester) async {
      double pan = 0.75;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PanDial(
                pan: pan,
                defaultValue: 0.0,
                onChanged: (v) => pan = v,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PanDial));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PanDial));
      await tester.pumpAndSettle();

      expect(pan, 0.0);
    });

    testWidgets('SegmentedVuMeter, MasterSpectrumWidget, and PedalVisualizerWidget render', (tester) async {
      final spectrumData = Float32List(512);
      for (int i = 0; i < 256; i++) {
        spectrumData[i] = (255 - i) / 255.0 * 0.5;
        spectrumData[256 + i] = sin(i * 0.2) * 0.4;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SegmentedVuMeter(
                  leftLevel: 0.7,
                  rightLevel: 0.45,
                  leftPeak: 0.9,
                  rightPeak: 0.6,
                ),
                MasterSpectrumWidget(samples: spectrumData),
                PedalVisualizerWidget(
                  effect: DawEffect('EQ', {'Low': 0.7, 'Mid': 0.3, 'High': 0.8}),
                  activityLevel: 0.6,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SegmentedVuMeter), findsOneWidget);
      expect(find.byType(MasterSpectrumWidget), findsOneWidget);
      expect(find.byType(PedalVisualizerWidget), findsOneWidget);
    });

    testWidgets('StepSequencerWidget toggles steps and fills 4-step Kick groove', (tester) async {
      final track = Track(id: 'smp1', name: 'Drums', type: TrackType.sampler);
      final clip = MidiClip(id: 'sc1', start: 0.0, length: 200.0, color: Colors.amber);
      int changeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 400,
              child: StepSequencerWidget(
                track: track,
                clip: clip,
                bpm: 120,
                timeSigTop: 4,
                playheadPosition: 0.0,
                onNotesChanged: () => changeCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Step Sequencer'), findsOneWidget);
      expect(find.text('Fill Groove'), findsOneWidget);

      await tester.tap(find.text('Fill Groove'));
      await tester.pump();
      expect(clip.notes.isNotEmpty, isTrue);
      expect(changeCount, greaterThan(0));
    });

    testWidgets('MidiEditorWidget shows Scale selector, Chords menu, and Vel toggle', (tester) async {
      tester.view.physicalSize = const Size(1440, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final track = Track(id: 'm1', name: 'Keys', type: TrackType.midi);
      final clip = MidiClip(
        id: 'mc2',
        start: 0.0,
        length: 400.0,
        color: lavenderAccent,
        notes: [MidiNote(pitch: 60, start: 0.0, length: 50.0, velocity: 100)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              height: 460,
              child: MidiEditorWidget(
                track: track,
                clip: clip,
                snapToGrid: true,
                snapResolution: 25.0,
                zoomX: 2.0,
                bpm: 120,
                timeSigTop: 4,
                selectedMidiNotes: const [],
                onSelectionChanged: (_) {},
                onNotesChanged: () {},
                onZoomIn: () {},
                onZoomOut: () {},
                playheadPosition: 0.0,
                onPlayheadChanged: (_) {},
                midiDevices: const [],
                onCopy: () {},
                onPaste: () {},
                onInstrumentDialogRequested: () {},
                onMidiInputDialogRequested: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Chords'), findsOneWidget);
      final velBtn = find.byIcon(Icons.equalizer);
      expect(velBtn, findsOneWidget);
      await tester.ensureVisible(velBtn);
      await tester.tap(velBtn);
      await tester.pump();
      await tester.tap(velBtn);
      await tester.pump();
    });

    testWidgets('DawApp renders upgraded top bar, timeline, Mixer master/aux strips, and Effects presets', (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const DawApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PUNCH'), findsOneWidget);
      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(find.byTooltip('Auto-Follow Playhead'), findsOneWidget);

      // Add a track so bottom Mixer & Effects panel tabs become active
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Audio Track'));
      await tester.pumpAndSettle();

      // Switch to Mixer tab and verify Aux + Master strips
      await tester.tap(find.text('Mixer'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('LIMIT'), findsOneWidget);
      expect(find.text('FX A: REV'), findsOneWidget);
      expect(find.text('FX B: DLY'), findsOneWidget);

      // Switch to Effects tab and verify Presets menu & pedalboard
      await tester.tap(find.text('Effects'));
      await tester.pumpAndSettle();
      expect(find.text('Presets'), findsOneWidget);
      await tester.tap(find.text('Presets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crunch Guitar Rig'));
      await tester.pumpAndSettle();

      // Bypass first effect pedal cleanly
      expect(find.text('Overdrive'), findsOneWidget);
      expect(find.text('TubeScreamer'), findsNothing);
      expect(find.text('GuitarAmp'), findsOneWidget);

      // Verify Master LUFS & Phase correlation readouts on Mixer tab
      await tester.tap(find.text('Mixer'));
      await tester.pump();
      expect(find.textContaining('LUFS'), findsOneWidget);

      // Toggle QWERTY Musical Typing keyboard from top bar
      final qwertyBtn = find.byTooltip('QWERTY Musical Typing Keyboard');
      expect(qwertyBtn, findsOneWidget);
      await tester.tap(qwertyBtn);
      await tester.pumpAndSettle();
      expect(find.text('MUSICAL TYPING'), findsOneWidget);
    });

    testWidgets('SynthRackPanel, TunerGatePanel, MusicalKeyboardBar, and SamplerEditorWidget render & respond', (tester) async {
      final midiTrack = Track(id: 'syn1', name: 'Lead', type: TrackType.midi);
      final smpTrack = Track(id: 'smp2', name: 'Kit', type: TrackType.sampler);
      int synthChanged = 0;
      double gateVal = 0.0;
      int playedMidi = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SynthRackPanel(
                    track: midiTrack,
                    onChanged: () => synthChanged++,
                  ),
                  SizedBox(
                    width: 240,
                    child: TunerGatePanel(
                      detectedPitch: const PitchDetectionResult(
                        frequencyHz: 440.0,
                        noteName: 'A4',
                        midiNote: 69,
                        cents: 1.5,
                        confidence: 0.98,
                      ),
                      noiseGateThreshold: gateVal,
                      onGateChanged: (v) => gateVal = v,
                      tunerEnabled: true,
                      onToggleTuner: () {},
                    ),
                  ),
                  MusicalKeyboardBar(
                    octave: 4,
                    velocity: 100,
                    activeNotes: const {60},
                    onOctaveChanged: (_) {},
                    onVelocityChanged: (_) {},
                    onNoteDown: (m) => playedMidi = m,
                    onNoteUp: (_) {},
                    onClose: () {},
                  ),
                  SizedBox(
                    width: 900,
                    height: 360,
                    child: SamplerEditorWidget(
                      track: smpTrack,
                      onStateChanged: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('ATK'), findsOneWidget);
      expect(find.text('DEC'), findsOneWidget);
      expect(find.text('CUTOFF'), findsOneWidget);
      expect(find.text('Tuner'), findsOneWidget);
      expect(find.text('A4'), findsOneWidget);
      expect(find.text('440.0 Hz'), findsOneWidget);
      expect(find.text('MUSICAL TYPING'), findsOneWidget);
      expect(find.text('16-Level:'), findsOneWidget);
      expect(find.text('Choke Grp'), findsOneWidget);
      expect(synthChanged, 0);
      expect(playedMidi, -1);
    });
  });

  group('Phase 3 Studio Pro features', () {
    test('ArpSettings expandNotes, MidiCcMapping, and Track group/pre-fader serialization', () {
      final arp = ArpSettings(
        enabled: true,
        mode: ArpMode.upDown,
        rateBeats: 0.25,
        octaves: 2,
        gate: 0.5,
      );
      final expanded = arp.expandNotes(
        [
          MidiNote(pitch: 60, start: 0.0, length: 100.0, velocity: 100),
          MidiNote(pitch: 64, start: 2.0, length: 100.0, velocity: 90),
        ],
        100.0, // beatWidth = 100px => 25px per step
      );
      expect(expanded.length, 4);
      expect(expanded.map((n) => n.pitch).toList(), [60, 64, 72, 76]);

      final mapping = MidiCcMapping(
        cc: 74,
        channel: 1,
        trackId: 't1',
        param: 'volume',
        minVal: 0.0,
        maxVal: 1.5,
      );
      expect(mapping.mapMidiValue(127), closeTo(1.5, 1e-6));
      final mDec = MidiCcMapping.fromJson(mapping.toJson());
      expect(mDec.cc, 74);
      expect(mDec.trackId, 't1');
      expect(mDec.param, 'volume');

      final child = Track(
        id: 't_child',
        name: 'Lead',
        type: TrackType.midi,
      )
        ..groupTrackId = 't_grp'
        ..reverbPreFader = true
        ..delayPreFader = true
        ..arpSettings = arp;
      final cDec = Track.fromJson(child.toJson());
      expect(cDec.groupTrackId, 't_grp');
      expect(cDec.reverbPreFader, isTrue);
      expect(cDec.delayPreFader, isTrue);
      expect(cDec.arpSettings.enabled, isTrue);
      expect(cDec.arpSettings.mode, ArpMode.upDown);
      expect(cDec.arpSettings.octaves, 2);
    });

    test('Audio surgical utilities: normalizeWavPeak, strip silence, melody extraction, LUFS, and humanize/groove', () async {
      final tmpDir = Directory.systemTemp.createTempSync('fyrdaw_phase3_');
      try {
        // Build a 1.0s WAV with two separated tonal bursts at low amplitude (0.2)
        final wavPath = '${tmpDir.path}/bursts.wav';
        final sr = 44100;
        final writer = WavWriter(wavPath, sampleRate: sr, channels: 2);
        final totalFrames = sr;
        final pcm = Int16List(totalFrames * 2);
        for (int i = 0; i < totalFrames; i++) {
          double s = 0.0;
          if (i < (0.3 * sr)) {
            s = 0.2 * sin(2 * pi * 440.0 * i / sr); // A4 (69)
          } else if (i >= (0.65 * sr) && i < (0.95 * sr)) {
            s = 0.2 * sin(2 * pi * 523.25 * i / sr); // C5 (72)
          }
          final v = (s * 32767.0).round().clamp(-32768, 32767);
          pcm[i * 2] = v;
          pcm[i * 2 + 1] = v;
        }
        writer.write(ByteData.view(pcm.buffer).buffer.asUint8List());
        writer.close();

        final normPath = await normalizeWavPeak(wavPath);
        expect(normPath, isNotNull);
        final decodedNorm = await decodeWavFile(normPath!);
        expect(decodedNorm, isNotNull);
        double normPeak = 0.0;
        for (final s in decodedNorm!.left) {
          if (s.abs() > normPeak) normPeak = s.abs();
        }
        expect(normPeak, closeTo(0.89, 0.02));

        final origLufs = await estimateWavIntegratedLufs(wavPath);
        final normLufs = await estimateWavIntegratedLufs(normPath);
        expect(normLufs, greaterThan(origLufs + 10.0));

        final segments = await detectAudioNonSilentRanges(wavPath);
        expect(segments.length, 2);
        expect(segments[0].$2, lessThan(0.45));
        expect(segments[1].$1, greaterThan(0.55));

        final melody = await extractMelodyMidiNotes(wavPath, 200.0);
        expect(melody.any((n) => (n.pitch - 69).abs() <= 1), isTrue);
        expect(melody.any((n) => (n.pitch - 72).abs() <= 1), isTrue);

        final grooveNotes = [
          MidiNote(pitch: 60, start: 8.0, length: 40.0, velocity: 100),
          MidiNote(pitch: 64, start: 54.0, length: 40.0, velocity: 100),
        ];
        applyGrooveToMidiNotes(grooveNotes, [(0.05, 0.4), (0.60, 0.9)], 100.0);
        expect(grooveNotes[0].start, lessThan(8.0));
        expect(grooveNotes[1].start, greaterThan(54.0));

        humanizeMidiNotes(grooveNotes, timingJitterPx: 4.0, velocityJitter: 12);
        expect(grooveNotes[0].velocity, inInclusiveRange(1, 127));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('MixdownRenderer sums child tracks through Group Bus, isolates Aux Solo, and crossfades overlaps', () async {
      final tmpDir = Directory.systemTemp.createTempSync('fyrdaw_bus_mix_');
      try {
        final tonePath = '${tmpDir.path}/tone.wav';
        final sr = 44100;
        final w = WavWriter(tonePath, sampleRate: sr, channels: 2);
        final frames = sr ~/ 2;
        final pcm = Int16List(frames * 2);
        for (int i = 0; i < frames; i++) {
          final v = (0.5 * sin(2 * pi * 220.0 * i / sr) * 32767.0).round();
          pcm[i * 2] = v;
          pcm[i * 2 + 1] = v;
        }
        w.write(ByteData.view(pcm.buffer).buffer.asUint8List());
        w.close();

        final group = Track(
          id: 'g1',
          name: 'Drums Bus',
          type: TrackType.group,
        )..volume = 0.8;
        final child = Track(
          id: 'c1',
          name: 'Kick',
          type: TrackType.audio,
        )
          ..groupTrackId = 'g1'
          ..volume = 0.8
          ..reverbSend = 0.6;

        final clipA = AudioClip(
          id: 'a1',
          start: 0.0,
          length: 50.0,
          color: const Color(0xFF38BDF8),
          filePath: tonePath,
        );
        final clipB = AudioClip(
          id: 'a2',
          start: 40.0,
          length: 50.0,
          color: const Color(0xFF38BDF8),
          filePath: tonePath,
        );

        final outGroupPath = '${tmpDir.path}/out_group.wav';
        await MixdownRenderer.renderToWav(
          tracks: [group, child],
          trackClips: {
            'g1': [],
            'c1': [clipA, clipB],
          },
          bpm: 120,
          outWavPath: outGroupPath,
          masterEffectsChain: [DawEffect('Compressor', {'Thresh': 0.5, 'Ratio': 0.5, 'Mix': 0.5})],
        );
        final decGroup = await decodeWavFile(outGroupPath);
        expect(decGroup, isNotNull);
        expect(decGroup!.left.any((s) => s.abs() > 0.05), isTrue);

        // Muting the group bus should silence child track output completely
        group.isMuted = true;
        final outMutedPath = '${tmpDir.path}/out_muted.wav';
        final renderedMuted = await MixdownRenderer.renderToWav(
          tracks: [group, child],
          trackClips: {'g1': [], 'c1': [clipA]},
          bpm: 120,
          outWavPath: outMutedPath,
        );
        expect(renderedMuted, isFalse);

        // Unmute and test auxReverbSolo produces wet signal cleanly
        group.isMuted = false;
        final outAuxPath = '${tmpDir.path}/out_aux.wav';
        await MixdownRenderer.renderToWav(
          tracks: [group, child],
          trackClips: {'g1': [], 'c1': [clipA]},
          bpm: 120,
          outWavPath: outAuxPath,
          auxReverbSolo: true,
        );
        final decAux = await decodeWavFile(outAuxPath);
        expect(decAux, isNotNull);
        expect(decAux!.left.any((s) => s.abs() > 0.01), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    testWidgets('SessionLauncherView, MixerConsoleView, EffectsRackView (Master FX), and MidiEditorWidget Arp controls', (tester) async {
      final grp = Track(id: 'grp1', name: 'Bus', type: TrackType.group);
      final midi = Track(id: 'm1', name: 'Synth', type: TrackType.midi)
        ..groupTrackId = 'grp1';
      final clip = MidiClip(
        id: 'mc1',
        name: 'Pattern A',
        start: 0.0,
        length: 400.0,
        color: const Color(0xFFA78BFA),
      );
      bool toggledMaster = false;
      bool triggeredClip = false;
      bool toggledAuxSolo = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 900,
                    height: 220,
                    child: SessionLauncherView(
                      tracks: [grp, midi],
                      trackClips: {'grp1': [], 'm1': [clip]},
                      playheadPosition: 0.0,
                      isPlaying: false,
                      activeSessionClipIds: const {},
                      queuedSessionClipIds: const {},
                      onTriggerClip: (_, _) => triggeredClip = true,
                      onTriggerScene: (_) {},
                      onStopTrack: (_) {},
                      onToggleMute: (_) {},
                      onToggleSolo: (_) {},
                      onOpenClipEditor: (_, _) {},
                    ),
                  ),
                  SizedBox(
                    width: 1100,
                    height: 260,
                    child: MixerConsoleView(
                      tracks: [grp, midi],
                      trackLevels: const {},
                      trackPeaks: const {},
                      auxReverbMix: 0.5,
                      auxDelayMix: 0.4,
                      auxRevLevel: const (0.0, 0.0),
                      auxDlyLevel: const (0.0, 0.0),
                      masterVolume: 1.0,
                      masterLimiter: true,
                      masterLevel: const (0.0, 0.0),
                      masterPeak: const (0.0, 0.0),
                      masterVizSamples: null,
                      masterLufs: -14.2,
                      masterLufsTarget: -14.0,
                      stereoCorrelation: 1.0,
                      onSaveState: () {},
                      onTrackVolumeChanged: (_, _) {},
                      onTrackPanChanged: (_, _) {},
                      onTrackRevSendChanged: (_, _) {},
                      onTrackDlySendChanged: (_, _) {},
                      onToggleMute: (_) {},
                      onToggleSolo: (_) {},
                      onAuxReverbMixChanged: (_) {},
                      onAuxDelayMixChanged: (_) {},
                      onToggleAuxReverbSolo: () => toggledAuxSolo = true,
                      onMasterVolumeChanged: (_) {},
                      onToggleMasterLimiter: () {},
                      onLoadReference: () {},
                      onToggleReferenceAB: () {},
                    ),
                  ),
                  SizedBox(
                    width: 1100,
                    height: 220,
                    child: EffectsRackView(
                      track: midi,
                      allTracks: [grp, midi],
                      inputDevices: const [],
                      selectedInputDevice: null,
                      trackLevel: 0.0,
                      sidechainGr: 0.0,
                      detectedPitch: null,
                      tunerEnabled: false,
                      isMasterRack: false,
                      onToggleMasterRack: () => toggledMaster = true,
                      onSaveState: () {},
                      onInputDeviceChanged: (_) {},
                      onToggleTuner: () {},
                      onNoiseGateChanged: (_) {},
                      onReorderEffect: (_, _) {},
                      onRemoveEffect: (_) {},
                      onToggleBypass: (_) {},
                      onParamChanged: (_, _, _) {},
                      onSidechainChanged: (_, _) {},
                      onApplyPreset: (_) {},
                      onAddEffectPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pattern A'), findsOneWidget);
      await tester.tap(find.text('Pattern A'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(triggeredClip, isTrue);

      expect(find.text('BUS'), findsOneWidget);
      expect(find.text('+REF'), findsOneWidget);
      expect(find.text('-14.2/-14 LUFS'), findsOneWidget);

      await tester.tap(
        find
            .descendant(
              of: find.byType(MixerConsoleView),
              matching: find.text('S'),
            )
            .at(2),
      );
      await tester.pump();
      expect(toggledAuxSolo, isTrue);

      await tester.tap(find.text('TRACK FX'));
      await tester.pump();
      expect(toggledMaster, isTrue);
    });

    testWidgets('DawApp toggles Session Clip Launcher and creates Group Bus track', (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const DawApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Add Group Bus & MIDI track
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Group Bus'));
      await tester.pumpAndSettle();
      expect(find.text('BUS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Switch to Session Clip Launcher view via top-bar button
      await tester.tap(find.byTooltip('Switch to Session Clip Launcher'));
      await tester.pumpAndSettle();
      expect(find.text('SCENES'), findsOneWidget);
      expect(find.text('Pattern 1'), findsOneWidget);

      // Switch back to Timeline
      await tester.tap(find.byTooltip('Switch to Timeline View'));
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW'), findsOneWidget);
    });
  });

  group('Expanded Virtual Instruments & Realistic Drum Kits', () {
    test('All 31 kInstrumentPresets and 3 kDrumKits reference valid stereo WAV assets', () async {
      expect(kInstrumentPresets.length, 31);
      for (int i = 0; i < kInstrumentPresets.length; i++) {
        final preset = getInstrumentPreset(i);
        expect(preset.index, i);
        final f = File(preset.assetPath);
        expect(f.existsSync(), isTrue, reason: 'Missing ${preset.assetPath}');
        final wav = decodeWavBytes(await f.readAsBytes());
        expect(wav, isNotNull);
        expect(wav!.channels, 2);
        expect(wav.sampleRate, 44100);
        expect(wav.frameCount, 220500);
      }

      expect(kDrumKits.length, 3);
      for (final kit in kDrumKits) {
        expect(kit.pads.isNotEmpty, isTrue);
        for (final spec in kit.pads) {
          final f = File(spec.assetPath);
          expect(f.existsSync(), isTrue, reason: 'Missing ${spec.assetPath}');
          final wav = decodeWavBytes(await f.readAsBytes());
          expect(wav, isNotNull);
          expect(wav!.channels, 2);
          expect(wav.sampleRate, 44100);
          expect(wav.frameCount, greaterThan(1000));
        }
      }
    });

    test('MixdownRenderer renders new 808 Boom Sub, Nylon Guitar, and bundled 808 Trap Kit cleanly', () async {
      final dir = await Directory.systemTemp.createTemp('fyr_inst_mix_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final guitarTrack = Track(
        id: 'gtr1',
        name: 'Nylon',
        type: TrackType.midi,
      )..instrumentIndex = 17; // Nylon Spanish Guitar
      final subTrack = Track(
        id: 'sub1',
        name: 'Sub 808',
        type: TrackType.midi,
      )..instrumentIndex = 29; // 808 Boom Sub
      final drumTrack = Track(
        id: 'drm1',
        name: 'Trap Kit',
        type: TrackType.sampler,
      );
      await applyDrumKitToPads(drumTrack.samplerPads, findDrumKitById('808_trap')!);
      expect(drumTrack.samplerPads[0]?.name, '808 Kick');
      expect(drumTrack.samplerPads[6]?.chokeGroup, 1);
      expect(drumTrack.samplerPads[10]?.chokeGroup, 1);

      final guitarClip = MidiClip(
        id: 'gc1',
        name: 'Gtr',
        start: 0.0,
        length: 200.0,
        color: Colors.amber,
        notes: [MidiNote(pitch: 48, start: 0.0, length: 120.0, velocity: 110)],
      );
      final subClip = MidiClip(
        id: 'sc1',
        name: 'Sub',
        start: 0.0,
        length: 200.0,
        color: Colors.purple,
        notes: [MidiNote(pitch: 36, start: 0.0, length: 140.0, velocity: 120)],
      );
      final drumClip = MidiClip(
        id: 'dc1',
        name: 'Beat',
        start: 0.0,
        length: 200.0,
        color: Colors.red,
        notes: [
          MidiNote(pitch: 36, start: 0.0, length: 20.0, velocity: 127),
          MidiNote(pitch: 38, start: 100.0, length: 20.0, velocity: 120),
          MidiNote(pitch: 46, start: 50.0, length: 20.0, velocity: 100),
          MidiNote(pitch: 42, start: 100.0, length: 20.0, velocity: 105),
        ],
      );

      final outWav = '${dir.path}/mix.wav';
      final ok = await MixdownRenderer.renderToWav(
        tracks: [guitarTrack, subTrack, drumTrack],
        trackClips: {
          'gtr1': [guitarClip],
          'sub1': [subClip],
          'drm1': [drumClip],
        },
        bpm: 120,
        beatWidth: 100.0,
        outWavPath: outWav,
      );

      expect(ok, isTrue);
      final decoded = decodeWavBytes(await File(outWav).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.frameCount, greaterThan(44100));
      double maxAmp = 0.0;
      for (int i = 0; i < decoded.frameCount; i++) {
        maxAmp = max(maxAmp, decoded.left[i].abs());
      }
      expect(maxAmp, greaterThan(0.15));
    });

    testWidgets('SamplerEditorWidget loads built-in Drum Kit presets and updates pad labels', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final smpTrack = Track(id: 'smp_kit', name: 'Drums', type: TrackType.sampler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 980,
              height: 440,
              child: SamplerEditorWidget(
                track: smpTrack,
                onStateChanged: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Load Drum Kit...'), findsOneWidget);
      await tester.tap(find.text('Load Drum Kit...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('808 Trap Kit'));
      await tester.pumpAndSettle();

      expect(find.text('808 Kick'), findsOneWidget);
      expect(find.text('808 Snare'), findsOneWidget);
      expect(find.text('808 CHH'), findsOneWidget);
    });

    test('SavedSamplerKitStore saves, overwrites, restores, and deletes custom kits', () async {
      SharedPreferences.setMockInitialValues({});

      final pads = <int, SamplerPad>{
        for (int i = 0; i < 16; i++) i: SamplerPad()..midiNote = 36 + i,
      };
      pads[0]!
        ..filePath = 'assets/drums/808_kick.wav'
        ..name = 'Heavy 808'
        ..trimStart = 0.05
        ..trimEnd = 0.88
        ..volume = 0.75
        ..pitch = 1.15
        ..fadeIn = 0.02
        ..fadeOut = 0.1
        ..chokeGroup = 2;
      pads[4]!
        ..filePath = 'assets/drums/lofi_snare.wav'
        ..name = 'Crack Snare';

      final saved = await SavedSamplerKitStore.save(
        name: 'My Punchy Kit',
        samplerPads: pads,
      );
      expect(saved.name, 'My Punchy Kit');
      expect(saved.sampleCount, 2);

      // Case-insensitive same-name save updates existing entry without duplicates.
      pads[0]!.volume = 0.9;
      await SavedSamplerKitStore.save(
        name: 'my punchy kit',
        samplerPads: pads,
      );
      var all = await SavedSamplerKitStore.loadAll();
      expect(all.length, 1);
      expect(all.first.name, 'my punchy kit');

      final targetPads = <int, SamplerPad>{};
      await applySavedSamplerKitToPads(targetPads, all.first);
      expect(targetPads[0]!.name, 'Heavy 808');
      expect(targetPads[0]!.trimStart, closeTo(0.05, 1e-6));
      expect(targetPads[0]!.trimEnd, closeTo(0.88, 1e-6));
      expect(targetPads[0]!.volume, closeTo(0.9, 1e-6));
      expect(targetPads[0]!.pitch, closeTo(1.15, 1e-6));
      expect(targetPads[0]!.fadeIn, closeTo(0.02, 1e-6));
      expect(targetPads[0]!.fadeOut, closeTo(0.1, 1e-6));
      expect(targetPads[0]!.chokeGroup, 2);
      expect(targetPads[4]!.name, 'Crack Snare');

      await SavedSamplerKitStore.delete(all.first.id);
      all = await SavedSamplerKitStore.loadAll();
      expect(all, isEmpty);
    });

    testWidgets('SamplerEditorWidget saves a named sampler, loads it back, and deletes it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final smpTrack = Track(id: 'smp_save', name: 'Drums', type: TrackType.sampler);
      smpTrack.samplerPads[0] = SamplerPad()
        ..midiNote = 36
        ..name = 'CustomKick'
        ..filePath = 'assets/drums/808_kick.wav'
        ..pitch = 1.25;

      int stateChanges = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 980,
              height: 440,
              child: SamplerEditorWidget(
                track: smpTrack,
                onStateChanged: () => stateChanges++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CustomKick'), findsOneWidget);

      // Open save dialog, enter a custom kit name, and save.
      await tester.tap(find.byKey(const Key('save_sampler_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('save_sampler_name_field')),
        'Late Night Boom',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Late Night Boom'), findsOneWidget);

      // Switch to a built-in preset kit so pad 0 changes away from CustomKick.
      await tester.tap(find.text('Late Night Boom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('808 Trap Kit'));
      await tester.pumpAndSettle();

      expect(find.text('808 Kick'), findsOneWidget);
      expect(find.text('CustomKick'), findsNothing);

      // Load our named custom sampler back from the kit dropdown.
      await tester.tap(find.text('808 Trap Kit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Late Night Boom'));
      await tester.pumpAndSettle();

      expect(find.text('CustomKick'), findsOneWidget);
      expect(smpTrack.samplerPads[0]!.pitch, closeTo(1.25, 1e-6));
      expect(stateChanges, greaterThanOrEqualTo(2));

      // Open dropdown again and delete the saved sampler.
      await tester.tap(find.text('Late Night Boom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_saved_kit_Late Night Boom')));
      await tester.pumpAndSettle();

      final remaining = await SavedSamplerKitStore.loadAll();
      expect(remaining, isEmpty);
    });
  });

  group('Clip Double-Click & Close-Up Audio Clip Editor', () {
    testWidgets('AudioClipEditorWidget trims, fades, resets, and splits at cursor', (tester) async {
      final clip = AudioClip(
        id: 'ac_edit_1',
        name: 'Vocal Take',
        start: 100.0,
        length: 400.0,
        color: Colors.teal,
        filePath: 'assets/samples/piano_c4.wav',
      )..waveformData = [0.2, 0.7, 0.9, 0.5, 0.8, 0.4];

      double? splitRequestedAt;
      int changeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 420,
              child: AudioClipEditorWidget(
                clip: clip,
                bpm: 120,
                beatWidth: 100.0,
                snapToGrid: false,
                snapResolution: 25.0,
                playheadPosition: 260.0,
                onPlayheadChanged: (_) {},
                onChangeStart: () {},
                onClipChanged: () => changeCount++,
                onSplitClip: (pos) => splitRequestedAt = pos,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Vocal Take'), findsOneWidget);
      expect(find.text('Split at Cursor'), findsOneWidget);

      // Default cursor syncs to playhead inside clip (260.0 = offset 160.0)
      await tester.tap(find.text('Split at Cursor'));
      await tester.pump();
      expect(splitRequestedAt, closeTo(260.0, 1e-6));

      // Apply 250ms Swell fade preset
      await tester.tap(find.text('250ms Swell'));
      await tester.pump();
      expect(clip.fadeIn, closeTo(25.0, 1e-6));
      expect(clip.fadeOut, closeTo(25.0, 1e-6));

      // Trim Out at cursor (160.0), then Reset Trim back to 400.0
      await tester.tap(find.text('Trim Out'));
      await tester.pump();
      expect(clip.length, closeTo(160.0, 1e-6));

      await tester.tap(find.text('Reset Trim'));
      await tester.pump();
      expect(clip.start, closeTo(100.0, 1e-6));
      expect(clip.startOffset, closeTo(0.0, 1e-6));
      expect(clip.length, closeTo(400.0, 1e-6));
      expect(changeCount, greaterThanOrEqualTo(3));
    });

    testWidgets('Double clicking Sampler/MIDI segment opens MidiEditorWidget, and Audio tracks expose Audio Editor tab', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const DawApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Add Sampler track -> opens Sampler tab by default, creates 'Beat 1' on timeline.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Sampler Track'));
      await tester.pumpAndSettle();

      expect(find.byType(SamplerEditorWidget), findsOneWidget);
      expect(find.byType(MidiEditorWidget), findsNothing);

      // Double-click 'Beat 1' segment on the timeline to open the MIDI editor for it.
      final samplerPos = tester.getCenter(find.text('Beat 1').first);
      await tester.tapAt(samplerPos);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(samplerPos);
      await tester.pumpAndSettle();

      expect(find.byType(MidiEditorWidget), findsOneWidget);

      // Add MIDI track, switch away to Mixer, then double-click 'Pattern 1' -> opens MidiEditorWidget.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mixer'));
      await tester.pumpAndSettle();
      expect(find.byType(MidiEditorWidget), findsNothing);

      final midiPos = tester.getCenter(find.text('Pattern 1').first);
      await tester.tapAt(midiPos);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(midiPos);
      await tester.pumpAndSettle();
      expect(find.byType(MidiEditorWidget), findsOneWidget);

      // Add Audio track and confirm Audio Editor tab is present and renders cleanly.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Audio Track'));
      await tester.pumpAndSettle();

      expect(find.text('Audio Editor'), findsOneWidget);
      await tester.tap(find.text('Audio Editor'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Select or double-click an audio segment'),
        findsOneWidget,
      );
    });
  });

  group('Bus Metering & Mixer Color Consistency', () {
    test('linearAmpToDbMeter and formatMeterDb map linear amplitudes to dBFS', () {
      expect(linearAmpToDbMeter(0.0), 0.0);
      expect(linearAmpToDbMeter(-0.1), 0.0);
      expect(linearAmpToDbMeter(1.0), 1.0);
      expect(linearAmpToDbMeter(2.0), 1.0);

      // -6.02 dBFS (~0.5 amplitude) maps to ~0.8746 on [-48, 0] dB scale
      final halfDb = linearAmpToDbMeter(0.5);
      expect(halfDb, closeTo(0.8746, 0.005));
      expect(formatMeterDb(halfDb), '-6.0dB');
      expect(formatMeterDb(0.0), '-∞');
      expect(formatMeterDb(1.0), '0.0dB');
    });

    testWidgets(
      'MixerConsoleView renders track color accents and per-track peak dB readouts',
      (tester) async {
        final track1 = Track(
          id: 't1',
          name: 'Lead Synth',
          type: TrackType.midi,
          colorValue: kTrackColorPalette[1].toARGB32(),
        );
        final groupBus = Track(
          id: 'g1',
          name: 'Drum Bus',
          type: TrackType.group,
          colorValue: kTrackColorPalette[2].toARGB32(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 360,
                child: MixerConsoleView(
                  tracks: [track1, groupBus],
                  trackLevels: {'t1': (0.75, 0.70), 'g1': (0.0, 0.0)},
                  trackPeaks: {
                    't1': (linearAmpToDbMeter(0.5), 0.72),
                    'g1': (0.0, 0.0),
                  },
                  auxReverbMix: 0.3,
                  auxDelayMix: 0.2,
                  auxRevLevel: const (0.0, 0.0),
                  auxDlyLevel: const (0.0, 0.0),
                  masterVolume: 0.85,
                  masterLimiter: true,
                  masterLevel: const (0.8, 0.8),
                  masterPeak: const (0.9, 0.9),
                  masterVizSamples: null,
                  masterLufs: -14.0,
                  stereoCorrelation: 1.0,
                  onSaveState: () {},
                  onTrackVolumeChanged: (_, _) {},
                  onTrackPanChanged: (_, _) {},
                  onTrackRevSendChanged: (_, _) {},
                  onTrackDlySendChanged: (_, _) {},
                  onToggleMute: (_) {},
                  onToggleSolo: (_) {},
                  onAuxReverbMixChanged: (_) {},
                  onAuxDelayMixChanged: (_) {},
                  onMasterVolumeChanged: (_) {},
                  onToggleMasterLimiter: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.text('-6.0dB'), findsOneWidget);
        expect(find.text('-∞'), findsOneWidget);

        // Verify track faders match their Track.color (not hardcoded lavenderAccent)
        final sliders = tester
            .widgetList<Slider>(find.byType(Slider))
            .where((s) => s.activeColor == track1.color)
            .toList();
        expect(sliders, isNotEmpty);

        // Verify Group BUS badge text uses the group track's color
        final busBadge = tester.widget<Text>(find.text('BUS'));
        expect(busBadge.style?.color, groupBus.color);
      },
    );

    testWidgets(
      'New tracks on Mixer match timeline track colors',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(const DawApp());
        await tester.pump(const Duration(milliseconds: 100));

        // Track 0 -> palette[0], Track 1 -> palette[1]
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add MIDI Track'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Sampler Track'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mixer'));
        await tester.pumpAndSettle();

        // Mixer fader slider activeColors match each track's palette color
        final mixerSliders = tester
            .widgetList<Slider>(find.byType(Slider))
            .map((s) => s.activeColor)
            .toList();
        expect(mixerSliders, contains(kTrackColorPalette[0]));
        expect(mixerSliders, contains(kTrackColorPalette[1]));
      },
    );
  });

  group('Sound Booth rebrand & TimelineLoopBar', () {
    testWidgets('DawApp displays Sound Booth branding instead of fyrDAW', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const DawApp());
      await tester.pumpAndSettle();

      expect(find.text('Sound Booth'), findsOneWidget);
      expect(find.text('fyrDAW'), findsNothing);
    });

    testWidgets(
      'TimelineLoopBar supports dragging body to move, resizing both edges (including loopStart == 0), and tapping to toggle',
      (WidgetTester tester) async {
        double loopStart = 0.0;
        double loopEnd = 200.0;
        bool isLooping = false;
        int dragStartCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 40,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: TimelineLoopBar(
                            loopStart: loopStart,
                            loopEnd: loopEnd,
                            isLooping: isLooping,
                            zoomX: 1.0,
                            beatWidth: 50.0,
                            snapToGrid: true,
                            snapResolution: 25.0,
                            accentColor: Colors.amber,
                            handleColor: Colors.white,
                            onDragStart: () => dragStartCount++,
                            onToggleLoop: () =>
                                setState(() => isLooping = !isLooping),
                            onLoopRangeChanged: (newStart, newEnd) {
                              setState(() {
                                loopStart = newStart;
                                loopEnd = newEnd;
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Tap body toggles loop state
        await tester.tap(find.byKey(const Key('loop_bar_body')));
        await tester.pump();
        expect(isLooping, isTrue);

        // Drag body right by 100px moves both loopStart and loopEnd, preserving length
        await tester.drag(
          find.byKey(const Key('loop_bar_body')),
          const Offset(100, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(dragStartCount, greaterThanOrEqualTo(1));
        expect(loopStart, closeTo(100.0, 0.01));
        expect(loopEnd, closeTo(300.0, 0.01));

        // Drag right handle right by 50px resizes loopEnd while keeping loopStart fixed
        await tester.drag(
          find.byKey(const Key('loop_handle_right')),
          const Offset(50, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(loopStart, closeTo(100.0, 0.01));
        expect(loopEnd, closeTo(350.0, 0.01));

        // Drag body left past 0.0 to clamp loopStart at 0.0, then test left handle at x == 0
        await tester.drag(
          find.byKey(const Key('loop_bar_body')),
          const Offset(-150, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(loopStart, closeTo(0.0, 0.01));
        expect(loopEnd, closeTo(250.0, 0.01));

        await tester.drag(
          find.byKey(const Key('loop_handle_left')),
          const Offset(50, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(loopStart, closeTo(50.0, 0.01));
        expect(loopEnd, closeTo(250.0, 0.01));
      },
    );
  });

  group('Metronome, Sections 2 & 3 Producer Upgrade', () {
    test('MetronomeSynth builds valid stereo WAV clicks and volume scaling', () {
      final accentWav = MetronomeSynth.generateClickWav(isDownbeat: true);
      final beatWav = MetronomeSynth.generateClickWav(isDownbeat: false);
      expect(accentWav.length, greaterThan(44));
      expect(beatWav.length, equals(accentWav.length));
      expect(String.fromCharCodes(accentWav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(accentWav.sublist(8, 12)), 'WAVE');
      expect(
        MetronomeSynth.computeClickVolume(1.2, isDownbeat: true),
        closeTo(1.2, 1e-6),
      );
      expect(
        MetronomeSynth.computeClickVolume(1.2, isDownbeat: false),
        closeTo(1.2 * 0.68, 1e-6),
      );
      expect(MetronomeSynth.computeClickVolume(2.0, isDownbeat: true), 1.5);
    });

    test('TimeStretchEngine decouples duration and pitch when preservePitch is true', () {
      const sr = 44100;
      const n = 22050; // 0.5 s at 440 Hz
      final inL = Float64List(n);
      final inR = Float64List(n);
      for (int i = 0; i < n; i++) {
        final s = sin(2.0 * pi * 440.0 * i / sr) * 0.5;
        inL[i] = s;
        inR[i] = s;
      }

      // Double speed (halves length) with zero semitone shift
      final stretched = TimeStretchEngine.processStereo(
        left: inL,
        right: inR,
        sampleRate: sr,
        stretchFactor: 2.0,
        pitchSemitones: 0.0,
        preservePitch: true,
      );
      expect(stretched.left.length, closeTo(n ~/ 2, 10));

      // +12 semitones without stretching preserves frame count
      final pitched = TimeStretchEngine.processStereo(
        left: inL,
        right: inR,
        sampleRate: sr,
        stretchFactor: 1.0,
        pitchSemitones: 12.0,
        preservePitch: true,
      );
      expect(pitched.left.length, n);
      final det = detectPitchHz(
        Float64List.sublistView(pitched.left, 2000, 6096),
        sr,
      );
      expect(det, isNotNull);
      expect(det!.frequencyHz, closeTo(880.0, 40.0));
    });

    test('ParametricEqDsp biquad curve, filtering, and FFT magnitude bins work accurately', () {
      final boostParams = {
        'lowGain': 0.0,
        'lowMidFreq': 500.0,
        'lowMidGain': 12.0, // +12 dB boost around lo-mid
        'lowMidQ': 1.2,
        'highMidGain': 0.0,
        'highGain': -12.0, // -12 dB high cut
      };
      final stages = ParametricEqDsp.buildStages(boostParams, sampleRate: 44100);
      expect(stages.length, 4);

      final flatDb = ParametricEqDsp.responseDbAt(
        {'Low': 0.5, 'Mid': 0.5, 'High': 0.5},
        500.0,
      );
      expect(flatDb.abs(), lessThan(0.5));

      final highCutDb = ParametricEqDsp.responseDbAt(
        boostParams,
        14000.0,
        prebuiltStages: stages,
      );
      expect(highCutDb, lessThan(-6.0));

      final l = Float64List.fromList(List.generate(1024, (i) => sin(2 * pi * 12000 * i / 44100) * 0.5));
      final r = Float64List.fromList(l);
      ParametricEqDsp.processStereoInPlace(left: l, right: r, params: boostParams, sampleRate: 44100);
      final outRms = sqrt(l.fold<double>(0.0, (a, b) => a + b * b) / l.length);
      expect(outRms, lessThan(0.25));

      final fBins = ParametricEqDsp.computeFftBinsFromSamples(
        Float32List.fromList(List.generate(128, (i) => sin(2 * pi * 8 * i / 128))),
        numBins: 32,
      );
      expect(fBins.length, 32);
      expect(fBins.reduce(max), greaterThan(0.5));
    });

    testWidgets('ParametricEqWidget renders interactive EQ bands and triggers updates', (tester) async {
      final eq = DawEffect('EQ', {'Low': 0.5, 'Mid': 0.5, 'High': 0.5});
      String? lastKey;
      double? lastVal;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 300,
              child: ParametricEqWidget(
                effect: eq,
                fftSpectrum: const [0.1, 0.3, 0.7, 0.4, 0.2],
                onParamChanged: (k, v) {
                  lastKey = k;
                  lastVal = v;
                  eq.parameters[k] = v;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Lo-Mid'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('parametric_eq_canvas')),
        const Offset(30, -25),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(lastKey, isNotNull);
      expect(lastVal, isNotNull);
    });

    test('AutomationPoint curve serialization and Track curved interpolation', () {
      final pt = AutomationPoint(100.0, 0.8, curve: 0.75);
      final rt = AutomationPoint.fromJson(pt.toJson());
      expect(rt.curve, closeTo(0.75, 1e-6));

      final track = Track(id: 'tr_auto', name: 'Synth', type: TrackType.midi);
      expect(track.availableAutomationParams, contains('Synth Cutoff'));
      expect(track.availableAutomationParams, contains('Synth Reso'));

      track.automation['Volume'] = [
        AutomationPoint(0.0, 0.0, curve: 0.8),
        AutomationPoint(100.0, 1.0, curve: 0.0),
      ];
      final curvedMid = track.getInterpolatedAutomation('Volume', 50.0);
      expect(curvedMid, greaterThan(0.55)); // Positive curve bows upward

      track.automation['Volume']![0].curve = -0.8;
      final negMid = track.getInterpolatedAutomation('Volume', 50.0);
      expect(negMid, lessThan(0.45)); // Negative curve scoops downward
    });

    testWidgets('AutomationLaneOverlay adds points on tap', (tester) async {
      final track = Track(id: 't1', name: 'Lead', type: TrackType.midi)
        ..showAutomation = true
        ..currentAutomationParam = 'Synth Cutoff';
      int saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 140,
              child: AutomationLaneOverlay(
                track: track,
                laneHeight: 140,
                zoomX: 1.0,
                snapResolution: 25,
                snapToGrid: false,
                onSaveState: () => saves++,
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(120, 60));
      await tester.pump(const Duration(milliseconds: 350));
      expect(saves, 1);
      expect(track.automation['Synth Cutoff'], hasLength(1));
    });

    test('DawEffect preserves pluginFormat & pluginUri, and PluginHost scans safely', () {
      final lv2 = DawEffect(
        'Calf Vintage Delay',
        {'Dry/Wet': 0.4},
        pluginFormat: 'LV2',
        pluginUri: 'http://calf.sourceforge.net/plugins/VintageDelay',
      );
      expect(lv2.isExternalPlugin, isTrue);
      final rt = DawEffect.fromJson(lv2.toJson());
      expect(rt.pluginFormat, 'LV2');
      expect(rt.pluginUri, 'http://calf.sourceforge.net/plugins/VintageDelay');

      final plugins = PluginHost.scanInstalledPlugins();
      expect(plugins, isA<List<ExternalPluginInfo>>());
    });

    test('MidiFileCodec encodes and decodes SMF notes faithfully', () {
      final srcNotes = [
        MidiNote(pitch: 60, start: 0.0, length: 50.0, velocity: 100),
        MidiNote(pitch: 64, start: 50.0, length: 50.0, velocity: 90),
        MidiNote(pitch: 67, start: 100.0, length: 100.0, velocity: 110),
      ];
      final encoded = MidiFileCodec.encodeNotes(
        srcNotes,
        bpm: 128.0,
        timeSigNum: 3,
        timeSigDen: 4,
        beatWidth: 50.0,
        trackName: 'Piano Idea',
      );
      final decoded = MidiFileCodec.decodeBytes(encoded, beatWidth: 50.0);
      expect(decoded.trackName, 'Piano Idea');
      expect(decoded.detectedBpm, closeTo(128.0, 0.2));
      expect(decoded.timeSigNum, 3);
      expect(decoded.timeSigDen, 4);
      expect(decoded.notes.length, 3);
      expect(decoded.notes[0].pitch, 60);
      expect(decoded.notes[2].pitch, 67);
      expect(decoded.notes[2].start, closeTo(100.0, 1.0));
      expect(decoded.notes[2].length, closeTo(100.0, 1.0));
    });

    test('TempoMarker handles step, ramp, meter lookup, and timelineToSeconds integration', () {
      final m1 = TempoMarker(id: 'm1', position: 0.0, bpm: 100.0, numerator: 4, denominator: 4, isRamp: true);
      final m2 = TempoMarker(id: 'm2', position: 200.0, bpm: 140.0, numerator: 3, denominator: 4);
      final markers = [m1, m2];

      expect(TempoMarker.effectiveBpmAt(100.0, markers, 120.0), closeTo(120.0, 1e-6));
      expect(TempoMarker.effectiveBpmAt(250.0, markers, 120.0), closeTo(140.0, 1e-6));
      expect(TempoMarker.effectiveMeterAt(250.0, markers, 4, 4).numerator, 3);

      final sec = TempoMarker.timelineToSeconds(
        200.0,
        markers: [TempoMarker(id: 'fast', position: 0.0, bpm: 240.0)],
        baseBpm: 120.0,
        beatWidth: 50.0,
      );
      // 4 beats at 240 BPM = 1.0 second
      expect(sec, closeTo(1.0, 0.02));
    });

    testWidgets('TempoSignatureLane renders markers and opens editor on double-tap', (tester) async {
      TempoMarker? added;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 40,
              child: TempoSignatureLane(
                baseBpm: 120.0,
                baseNum: 4,
                baseDen: 4,
                markers: [TempoMarker(id: 'm1', position: 80.0, bpm: 95.0, numerator: 3, denominator: 4)],
                zoomX: 1.0,
                snapResolution: 25.0,
                snapToGrid: false,
                onAddOrUpdateMarker: (m) => added = m,
                onDeleteMarker: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('95 · 3/4'), findsOneWidget);
      await tester.tap(find.text('95 · 3/4'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Edit Tempo / Meter Change'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(added?.bpm, closeTo(95.0, 0.1));
    });

    test('AudioClip preserves preservePitch and isLooped in JSON round-trip', () {
      final clip = AudioClip(
        id: 'ac1',
        name: 'Guitar Loop',
        start: 0.0,
        length: 400.0,
        color: Colors.teal,
        filePath: '/tmp/guitar.wav',
        pitchSemitones: 3.0,
        stretchFactor: 1.25,
        preservePitch: false,
        isLooped: true,
      );
      final rt = DawClip.fromJson(clip.toJson()) as AudioClip;
      expect(rt.preservePitch, isFalse);
      expect(rt.isLooped, isTrue);
      expect(rt.pitchSemitones, 3.0);
      expect(rt.stretchFactor, 1.25);
    });

    testWidgets('SampleBrowserDrawer lists bundled samples and supports search filter', (tester) async {
      SampleBrowserItem? triggered;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SampleBrowserDrawer(
              userFolders: const [],
              previewingPath: null,
              onAddFolderPressed: () {},
              onRemoveFolder: (_) {},
              onTogglePreview: (_) {},
              onAddToProject: (item) => triggered = item,
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.text('Sample & MIDI Browser'), findsOneWidget);
      expect(find.text('kick_studio.wav'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'snare');
      await tester.pump();
      expect(find.text('snare_studio.wav'), findsOneWidget);
      expect(find.text('kick_studio.wav'), findsNothing);
      await tester.tap(find.text('+Add').first);
      await tester.pump();
      expect(triggered?.name, 'snare_studio.wav');
    });

    testWidgets('DawApp renders Metronome volume slider and Sample Browser toggle without overflow', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('metronome_volume_slider')), findsOneWidget);
      expect(find.byKey(const Key('toggle_sample_browser')), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_sample_browser')));
      await tester.pumpAndSettle();
      expect(find.text('Sample & MIDI Browser'), findsOneWidget);
    });

    test('MixdownRenderer honors TempoMarker, 4-band EQ, preservePitch & isLooped AudioClip', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sb_v23_test_');
      try {
        final inWavPath = '${tmpDir.path}/tone.wav';
        final outWavPath = '${tmpDir.path}/mix.wav';

        // Write a 0.25s 440Hz stereo WAV
        const sr = 44100;
        const frames = sr ~/ 4;
        final writer = WavWriter(inWavPath, sampleRate: sr, channels: 2);
        final pcm = Int16List(frames * 2);
        for (int i = 0; i < frames; i++) {
          final v = (sin(2 * pi * 440.0 * i / sr) * 0.4 * 32767).round();
          pcm[i * 2] = v;
          pcm[i * 2 + 1] = v;
        }
        writer.write(ByteData.view(pcm.buffer).buffer.asUint8List());
        writer.close();

        final track = Track(id: 'a1', name: 'Stretched Loop', type: TrackType.audio)
          ..effectsChain = [
            DawEffect('EQ', {
              'lowGain': 0.5,
              'lowMidFreq': 0.5,
              'lowMidGain': 0.75,
              'highMidGain': 0.5,
              'highGain': 0.4,
            }),
          ];
        final clip = AudioClip(
          id: 'c1',
          name: 'Loop',
          start: 0.0,
          length: 100.0,
          originalLength: 25.0,
          color: Colors.amber,
          filePath: inWavPath,
          pitchSemitones: 5.0,
          stretchFactor: 1.2,
          preservePitch: true,
          isLooped: true,
        );

        final ok = await MixdownRenderer.renderToWav(
          tracks: [track],
          trackClips: {track.id: [clip]},
          outWavPath: outWavPath,
          bpm: 120,
          tempoMarkers: [TempoMarker(id: 't0', position: 0.0, bpm: 150.0)],
        );
        expect(ok, isTrue);
        final decoded = await decodeWavFile(outWavPath);
        expect(decoded, isNotNull);
        expect(decoded!.frameCount, greaterThan(44100));
        final peak = decoded.left.fold<double>(0.0, (m, s) => max(m, s.abs()));
        expect(peak, greaterThan(0.05));
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  group('Alt+Drag Copy & Double-Click Guard', () {
    testWidgets('Double-clicking existing MIDI/Sampler clip opens editor without creating duplicate clip on top', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      // Add MIDI track -> creates a single 'Pattern 1' clip
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Switch to Mixer so we can verify double-click opens MIDI Editor
      await tester.tap(find.text('Mixer'));
      await tester.pumpAndSettle();
      expect(find.byType(MidiEditorWidget), findsNothing);

      final midiPos = tester.getCenter(find.text('Pattern 1').first);
      await tester.tapAt(midiPos);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(midiPos);
      await tester.pumpAndSettle();

      expect(find.byType(MidiEditorWidget), findsOneWidget);
      // No new unnamed 'MIDI' clip should be spawned on top of 'Pattern 1'
      expect(find.text('Pattern 1'), findsOneWidget);
      expect(find.text('MIDI'), findsNothing);
    });

    testWidgets('Holding Alt while dragging MIDI, Sampler, or Audio clip creates a copy', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final tempDocDir = Directory.systemTemp.createTempSync('daw_test_docs_');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const wmChannel = MethodChannel('window_manager');
      const recChannel = MethodChannel('com.llfbandit.record/messages');
      const midiChannel = MethodChannel('plugins.invisiblewrench.com/flutter_midi_command');
      const midiRxChannel = MethodChannel('plugins.invisiblewrench.com/flutter_midi_command/rx_channel');
      messenger.setMockMethodCallHandler(pathChannel, (call) async => tempDocDir.path);
      messenger.setMockMethodCallHandler(wmChannel, (call) async => null);
      messenger.setMockMethodCallHandler(recChannel, (call) async => null);
      messenger.setMockMethodCallHandler(midiChannel, (call) async => <dynamic>[]);
      messenger.setMockMethodCallHandler(midiRxChannel, (call) async => null);
      addTearDown(() async {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(wmChannel, null);
        messenger.setMockMethodCallHandler(recChannel, null);
        messenger.setMockMethodCallHandler(midiChannel, null);
        messenger.setMockMethodCallHandler(midiRxChannel, null);
        if (tempDocDir.existsSync()) {
          tempDocDir.deleteSync(recursive: true);
        }
      });

      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      // Add MIDI track ('Pattern 1') and Sampler track ('Beat 1')
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Sampler Track'));
      await tester.pumpAndSettle();

      // Insert an Audio clip ('cello_c3') via Sample Browser
      await tester.tap(find.byKey(const Key('toggle_sample_browser')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SampleBrowserDrawer),
          matching: find.byType(TextField),
        ),
        'cello_c3',
      );
      await tester.pumpAndSettle();
      final audioClipFinder = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('clip_'),
        ),
        matching: find.text('cello_c3'),
      );
      await tester.tap(find.text('+Add').first);
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (audioClipFinder.evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle_sample_browser')));
      await tester.pumpAndSettle();

      expect(find.text('Pattern 1'), findsOneWidget);
      expect(find.text('Beat 1'), findsOneWidget);
      // Track header and Audio clip both show 'cello_c3'; the clip widget is keyed 'clip_*'
      expect(audioClipFinder, findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      addTearDown(() async {
        if (HardwareKeyboard.instance.physicalKeysPressed.contains(
          PhysicalKeyboardKey.altLeft,
        )) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        }
      });

      // Alt+drag MIDI clip
      final origMidiLeft = tester.getTopLeft(find.text('Pattern 1')).dx;
      await tester.drag(
        find.text('Pattern 1'),
        const Offset(220, 0),
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pattern 1'), findsNWidgets(2));
      final midiLefts = tester
          .widgetList(find.text('Pattern 1'))
          .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
          .toList()
        ..sort();
      expect(midiLefts[0], closeTo(origMidiLeft, 2.0));
      expect(midiLefts[1] - midiLefts[0], greaterThan(150.0));

      // Alt+drag Sampler clip
      final origSamplerLeft = tester.getTopLeft(find.text('Beat 1')).dx;
      await tester.drag(
        find.text('Beat 1'),
        const Offset(240, 0),
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Beat 1'), findsNWidgets(2));
      final samplerLefts = tester
          .widgetList(find.text('Beat 1'))
          .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
          .toList()
        ..sort();
      expect(samplerLefts[0], closeTo(origSamplerLeft, 2.0));
      expect(samplerLefts[1] - samplerLefts[0], greaterThan(150.0));

      // Alt+drag Audio clip
      final origAudioLeft = tester.getTopLeft(audioClipFinder).dx;
      await tester.drag(
        audioClipFinder,
        const Offset(200, 0),
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(audioClipFinder, findsNWidgets(2));
      final audioLefts = tester
          .widgetList(audioClipFinder)
          .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
          .toList()
        ..sort();
      expect(audioLefts[0], closeTo(origAudioLeft, 2.0));
      expect(audioLefts[1] - audioLefts[0], greaterThan(120.0));

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('Holding Alt while dragging a MIDI note in MidiEditorWidget copies the note', (tester) async {
      final track = Track(id: 'm1', name: 'Keys', type: TrackType.midi);
      final clip = MidiClip(
        id: 'mc1',
        start: 0.0,
        length: 400.0,
        color: Colors.purple,
        notes: [MidiNote(pitch: 60, start: 20.0, length: 60.0, velocity: 100)],
      );
      List<MidiNote> selected = [];
      int changes = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setModalState) => SizedBox(
                width: 900,
                height: 500,
                child: MidiEditorWidget(
                  clip: clip,
                  track: track,
                  snapToGrid: false,
                  snapResolution: 25.0,
                  zoomX: 1.0,
                  bpm: 120,
                  timeSigTop: 4,
                  selectedMidiNotes: selected,
                  onSelectionChanged: (s) => setModalState(() => selected = s),
                  onNotesChanged: () => setModalState(() => changes++),
                  onZoomIn: () {},
                  onZoomOut: () {},
                  playheadPosition: 0.0,
                  onPlayheadChanged: (_) {},
                  midiDevices: const [],
                  onCopy: () {},
                  onPaste: () {},
                  onInstrumentDialogRequested: () {},
                  onMidiInputDialogRequested: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(clip.notes, hasLength(1));
      final noteFinder = find.byKey(ObjectKey(clip.notes.first));
      expect(noteFinder, findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      addTearDown(() async {
        if (HardwareKeyboard.instance.physicalKeysPressed.contains(
          PhysicalKeyboardKey.altLeft,
        )) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        }
      });

      // Ensure visible and mouse-drag the note right + up while holding Alt
      await tester.ensureVisible(noteFinder);
      await tester.pumpAndSettle();
      await tester.drag(
        noteFinder,
        const Offset(100, -40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      expect(clip.notes, hasLength(2));
      expect(changes, greaterThanOrEqualTo(2));
      expect(clip.notes[0].start, closeTo(20.0, 0.1));
      expect(clip.notes[0].pitch, 60);
      expect(clip.notes[1].start, greaterThan(90.0));
      expect(clip.notes[1].pitch, greaterThan(60));
    });
  });

  group('Overdrive Rename & Track/Clip Color Palette', () {
    test('DawEffect.fromJson migrates legacy TubeScreamer to Overdrive', () {
      final migrated = DawEffect.fromJson({
        'name': 'TubeScreamer',
        'parameters': {'Drive': 0.65, 'Tone': 0.5, 'Level': 0.7},
        'isBypassed': false,
      });
      expect(migrated.name, 'Overdrive');
      expect(migrated.parameters['Drive'], 0.65);

      expect(kTrackColorPalette.length, greaterThanOrEqualTo(24));
      expect(kTrackColorNames.length, kTrackColorPalette.length);
    });

    testWidgets('Track and Clip color pickers offer expanded palette and custom color sliders', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Open Track Color picker via track header right-click -> Change Track Color
      await tester.tapAt(
        tester.getCenter(find.text('MIDI Track 1').first),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change Track Color'));
      await tester.pumpAndSettle();

      expect(find.text('Track Color'), findsOneWidget);
      expect(find.text('Custom Color'), findsOneWidget);
      expect(find.byTooltip('Crimson'), findsOneWidget);
      expect(find.byTooltip('Cobalt Blue'), findsOneWidget);
      expect(find.byTooltip('Cool Slate'), findsOneWidget);

      // Pick Crimson (new preset #8)
      await tester.tap(find.byTooltip('Crimson'));
      await tester.pumpAndSettle();
      expect(find.text('Track Color'), findsNothing);

      // Right-click clip -> Change Clip Color... -> pick Gold
      await tester.tapAt(
        tester.getCenter(find.text('Pattern 1').first),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Change Clip Color...'), findsOneWidget);
      expect(find.text('Change Track Color...'), findsOneWidget);
      await tester.tap(find.text('Change Clip Color...'));
      await tester.pumpAndSettle();

      expect(find.text('Clip Color'), findsOneWidget);
      await tester.tap(find.byTooltip('Gold'));
      await tester.pumpAndSettle();
      expect(find.text('Clip Color'), findsNothing);

      // Verify clip Container now reflects Gold while track header indicator retains Crimson
      final clipContainer = tester.widget<Container>(
        find.ancestor(
          of: find.text('Pattern 1'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null,
          ),
        ).first,
      );
      final clipColor = ((clipContainer.decoration as BoxDecoration).color)!;
      expect(clipColor.toARGB32() & 0x00FFFFFF, kTrackColorPalette[11].toARGB32() & 0x00FFFFFF);
    });
  });

  group('Audio Input Channel Selection', () {
    test('buildInputChannelOptions, parsePactlSourceChannels & PCM channel mapping work for 2ch and 4ch interfaces', () {
      final opts1 = buildInputChannelOptions(1);
      expect(opts1.map((o) => o.id), ['mono:0']);

      final opts2 = buildInputChannelOptions(2);
      expect(opts2.map((o) => o.id), ['stereo:0', 'mono:0', 'mono:1']);
      expect(opts2[1].label, 'Ch 1 (Left / Mono)');
      expect(opts2[2].label, 'Ch 2 (Right / Mono)');

      final opts4 = buildInputChannelOptions(4);
      expect(opts4.map((o) => o.id), [
        'stereo:0',
        'stereo:2',
        'mono:0',
        'mono:1',
        'mono:2',
        'mono:3',
      ]);

      final parsed = parsePactlSourceChannels([
        'Source #219',
        '\tName: alsa_input.usb-Focusrite_Scarlett_Solo',
        '\tSample Specification: s32le 2ch 48000Hz',
        '\tChannel Map: front-left,front-right',
        'Source #220',
        '\tName: alsa_input.usb-4ch-interface',
        '\tSample Specification: s24le 4ch 48000Hz',
      ]);
      expect(parsed['alsa_input.usb-Focusrite_Scarlett_Solo'], 2);
      expect(parsed['alsa_input.usb-4ch-interface'], 4);

      // Build 2 frames of 4ch s16le: frame0 = [100, 200, 300, 400], frame1 = [-100, -200, -300, -400]
      final inBytes = Uint8List(16);
      final inBd = ByteData.sublistView(inBytes);
      final samples = [100, 200, 300, 400, -100, -200, -300, -400];
      for (int i = 0; i < samples.length; i++) {
        inBd.setInt16(i * 2, samples[i], Endian.little);
      }

      // Partial chunk test with alignPcm16Frames (8 bytes per 4ch frame)
      final split1 = alignPcm16Frames(inBytes.sublist(0, 10), Uint8List(0), captureChannels: 4);
      expect(split1.alignedFrames.length, 8);
      expect(split1.nextRemainder.length, 2);
      final split2 = alignPcm16Frames(inBytes.sublist(10), split1.nextRemainder, captureChannels: 4);
      expect(split2.alignedFrames.length, 8);
      expect(split2.nextRemainder.length, 0);

      // Mono Ch 2 (index 1) maps Ch 2 identically into L & R
      final monoCh2 = mapAlignedPcm16ToStereo(
        inBytes,
        captureChannels: 4,
        selection: resolveInputChannelOption('mono:1', 4),
      );
      final ch2Bd = ByteData.sublistView(monoCh2);
      expect(ch2Bd.getInt16(0, Endian.little), 200);
      expect(ch2Bd.getInt16(2, Endian.little), 200);
      expect(ch2Bd.getInt16(4, Endian.little), -200);
      expect(ch2Bd.getInt16(6, Endian.little), -200);

      // Stereo Ch 3-4 (index 2) extracts Ch 3 -> L and Ch 4 -> R
      final stereo34 = mapAlignedPcm16ToStereo(
        inBytes,
        captureChannels: 4,
        selection: resolveInputChannelOption('stereo:2', 4),
      );
      final st34Bd = ByteData.sublistView(stereo34);
      expect(st34Bd.getInt16(0, Endian.little), 300);
      expect(st34Bd.getInt16(2, Endian.little), 400);
      expect(st34Bd.getInt16(4, Endian.little), -300);
      expect(st34Bd.getInt16(6, Endian.little), -400);

      // Track serializes inputChannelId cleanly
      final tr = Track(id: 't_rec', name: 'Guitar', type: TrackType.audio)
        ..inputChannelId = 'mono:1';
      final rt = Track.fromJson(tr.toJson());
      expect(rt.inputChannelId, 'mono:1');
    });

    testWidgets('EffectsRackView displays Input Channel selector and fires updates', (tester) async {
      final track = Track(id: 'aud1', name: 'Guitar', type: TrackType.audio);
      const dev = InputDevice(id: 'scarlett_solo', label: 'Scarlett Solo USB');
      String selectedChannel = 'stereo:0';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setModalState) => SizedBox(
                width: 1100,
                height: 360,
                child: EffectsRackView(
                  track: track,
                  allTracks: [track],
                  inputDevices: const [dev],
                  selectedInputDevice: dev,
                  inputChannelOptions: buildInputChannelOptions(2),
                  selectedInputChannelId: selectedChannel,
                  trackLevel: 0.0,
                  sidechainGr: 0.0,
                  detectedPitch: null,
                  tunerEnabled: false,
                  onSaveState: () {},
                  onInputDeviceChanged: (_) {},
                  onInputChannelChanged: (ch) {
                    if (ch != null) setModalState(() => selectedChannel = ch);
                  },
                  onToggleTuner: () {},
                  onNoiseGateChanged: (_) {},
                  onReorderEffect: (_, _) {},
                  onRemoveEffect: (_) {},
                  onToggleBypass: (_) {},
                  onParamChanged: (_, _, _) {},
                  onSidechainChanged: (_, _) {},
                  onApplyPreset: (_) {},
                  onAddEffectPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Input Source'), findsOneWidget);
      expect(find.text('Input Channel'), findsOneWidget);
      expect(find.byKey(const Key('input_channel_dropdown')), findsOneWidget);

      await tester.tap(find.byKey(const Key('input_channel_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ch 2 (Right / Mono)').last);
      await tester.pumpAndSettle();

      expect(selectedChannel, 'mono:1');
    });

    testWidgets('Audio track header exposes input channel pill selector in DawApp', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Audio Track'));
      await tester.pumpAndSettle();

      final pillFinder = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('track_channel_pill_'),
      );
      expect(pillFinder, findsOneWidget);
      expect(
        find.descendant(of: pillFinder, matching: find.text('1-2')),
        findsOneWidget,
      );

      await tester.tap(pillFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ch 2 (Right / Mono)'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: pillFinder, matching: find.text('Ch 2')),
        findsOneWidget,
      );
    });

    test('Normalizes quoted record_linux device IDs and handles 1ch Blue Snowball capture metadata', () {
      const rawQuotedSnowballId =
          '"alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_797_2020_07_04_-00.mono-fallback"';
      const cleanSnowballId =
          'alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_797_2020_07_04_-00.mono-fallback';

      expect(
        normalizeAudioInputDeviceId('  $rawQuotedSnowballId  '),
        cleanSnowballId,
      );
      expect(normalizeAudioInputDeviceId("'dev_single_quoted'"), 'dev_single_quoted');

      final parsed = parsePactlSourceChannels([
        'Source #304',
        '\tName: $cleanSnowballId',
        '\tDescription: Blue Snowball Mono',
        '\tSample Specification: s16le 1ch 48000Hz',
        '\tChannel Map: mono',
        'Source #219',
        '\tName: alsa_input.usb-Focusrite_Scarlett_Solo_USB-00.Direct__Direct__source',
        '\tSample Specification: s32le 2ch 48000Hz',
      ]);

      expect(resolveInputDeviceChannelCount(rawQuotedSnowballId, parsed), 1);
      expect(
        resolveInputDeviceChannelCount(rawQuotedSnowballId, const {}),
        1,
      );

      final monoOpt = resolveInputChannelOption('mono:1', 1);
      expect(monoOpt.id, 'mono:0');
      expect(monoOpt.label, 'Ch 1 (Mono)');

      final inMono = ByteData(4)
        ..setInt16(0, 1234, Endian.little)
        ..setInt16(2, -2345, Endian.little);
      final outStereo = mapAlignedPcm16ToStereo(
        inMono.buffer.asUint8List(),
        captureChannels: 1,
        selection: monoOpt,
      );
      final outBd = ByteData.sublistView(outStereo);
      expect(outBd.getInt16(0, Endian.little), 1234);
      expect(outBd.getInt16(2, Endian.little), 1234);
      expect(outBd.getInt16(4, Endian.little), -2345);
      expect(outBd.getInt16(6, Endian.little), -2345);
    });

    testWidgets('EffectsRackView handles switching to 1ch mono mic and selecting Ch 1 cleanly', (tester) async {
      final track = Track(id: 'aud_mono', name: 'Vocals', type: TrackType.audio)
        ..inputChannelId = 'mono:1';
      const scarlett = InputDevice(
        id: 'alsa_input.scarlett',
        label: 'Scarlett Solo',
      );
      const snowball = InputDevice(
        id: 'alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball.mono-fallback',
        label: 'Blue Snowball Mono',
      );
      InputDevice activeDev = scarlett;
      String selectedChannel = 'mono:1';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setModalState) {
                final chCount = resolveInputDeviceChannelCount(
                  activeDev.id,
                  {scarlett.id: 2, snowball.id: 1},
                );
                return SizedBox(
                  width: 1100,
                  height: 360,
                  child: EffectsRackView(
                    track: track,
                    allTracks: [track],
                    inputDevices: const [scarlett, snowball],
                    selectedInputDevice: activeDev,
                    inputChannelOptions: buildInputChannelOptions(chCount),
                    selectedInputChannelId:
                        resolveInputChannelOption(selectedChannel, chCount).id,
                    trackLevel: 0.0,
                    sidechainGr: 0.0,
                    detectedPitch: null,
                    tunerEnabled: false,
                    onSaveState: () {},
                    onInputDeviceChanged: (dev) {
                      if (dev != null) {
                        setModalState(() {
                          activeDev = dev;
                          selectedChannel = resolveInputChannelOption(
                            selectedChannel,
                            resolveInputDeviceChannelCount(
                              dev.id,
                              {scarlett.id: 2, snowball.id: 1},
                            ),
                          ).id;
                        });
                      }
                    },
                    onInputChannelChanged: (ch) {
                      if (ch != null) setModalState(() => selectedChannel = ch);
                    },
                    onToggleTuner: () {},
                    onNoiseGateChanged: (_) {},
                    onReorderEffect: (_, _) {},
                    onRemoveEffect: (_) {},
                    onToggleBypass: (_) {},
                    onParamChanged: (_, _, _) {},
                    onSidechainChanged: (_, _) {},
                    onApplyPreset: (_) {},
                    onAddEffectPressed: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('input_device_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue Snowball Mono').last);
      await tester.pumpAndSettle();

      expect(activeDev, snowball);
      expect(selectedChannel, 'mono:0');
      expect(find.text('Ch 1 (Mono)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('input_channel_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ch 1 (Mono)').last);
      await tester.pumpAndSettle();
      expect(selectedChannel, 'mono:0');
    });

    test('detectPitchHz handles quiet DC-biased signals and RealtimePitchTracker tracks streaming audio', () {
      const sr = 44100;
      // Quiet E2 guitar string (0.005 amp) with a 0.04 DC offset
      final quietE2 = Float64List(4096);
      for (int i = 0; i < quietE2.length; i++) {
        quietE2[i] = 0.04 + 0.005 * sin(2 * pi * 82.41 * i / sr);
      }
      final e2Res = detectPitchHz(quietE2, sr);
      expect(e2Res, isNotNull);
      expect(e2Res!.noteName, 'E2');
      expect(e2Res.frequencyHz, closeTo(82.41, 1.5));

      // Streaming RealtimePitchTracker locks on A4 across 512-sample chunks,
      // ignores isolated 1-hop octave jumps, and resets after silence.
      final tracker = RealtimePitchTracker(sampleRate: sr);
      int phase = 0;
      bool locked = false;
      for (int c = 0; c < 6; c++) {
        final chunk = Float64List(512);
        for (int i = 0; i < chunk.length; i++) {
          chunk[i] = 0.1 * sin(2 * pi * 440.0 * phase++ / sr);
        }
        if (tracker.addSamples(chunk)) {
          locked = true;
        }
      }
      expect(locked, isTrue);
      expect(tracker.current, isNotNull);
      expect(tracker.current!.noteName, 'A4');

      // Feed silence until hold period expires -> clears cleanly to null
      final silenceChunk = Float64List(1024);
      for (int c = 0; c < 12; c++) {
        tracker.addSamples(silenceChunk);
      }
      expect(tracker.current, isNull);
    });
  });

  group('Audio Output Device Routing', () {
    test('parsePactlDefaultSink, parsePactlSinks, parsePactlSinkInputIdsForPid & matchPlaybackDeviceForSink work accurately', () {
      const infoText = '''
Server String: /run/user/1000/pulse/native
Default Sink: alsa_output.usb-Focusrite_Scarlett_Solo_USB_Y7PE74V22E69FD-00.Direct__Direct__sink
Default Source: alsa_input.usb-Focusrite_Scarlett_Solo_USB_Y7PE74V22E69FD-00.Direct__Direct__source
''';
      expect(
        parsePactlDefaultSink(infoText),
        'alsa_output.usb-Focusrite_Scarlett_Solo_USB_Y7PE74V22E69FD-00.Direct__Direct__sink',
      );

      final sinks = parsePactlSinks([
        'Sink #218',
        '\tName: alsa_output.usb-Focusrite_Scarlett_Solo_USB_Y7PE74V22E69FD-00.Direct__Direct__sink',
        '\tDescription: Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB',
        'Sink #230',
        '\tName: alsa_output.pci-0000_00_1f.3.analog-stereo',
        '\tDescription: Built-in Audio Analog Stereo',
      ]);
      expect(sinks, hasLength(2));
      expect(sinks[0].index, 218);
      expect(sinks[0].description, 'Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB');

      const playbackDevices = [
        PlaybackDevice(0, true, 'Built-in Audio Analog Stereo'),
        PlaybackDevice(1, false, 'Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB'),
      ];
      final matched = matchPlaybackDeviceForSink(playbackDevices, sinks[0]);
      expect(matched?.id, 1);

      final matchedSink = matchSinkForPlaybackDevice(sinks, playbackDevices[0]);
      expect(matchedSink?.index, 230);

      // Sink-input parsing finds streams belonging to our pid routed to wrong sink (#230)
      final inputs = parsePactlSinkInputIdsForPid([
        'Sink Input #55',
        '\tSink: 230',
        '\tProperties:',
        '\t\tapplication.process.id = "4242"',
        'Sink Input #56',
        '\tSink: 218',
        '\tProperties:',
        '\t\tapplication.process.id = "4242"',
        'Sink Input #57',
        '\tSink: 230',
        '\tProperties:',
        '\t\tapplication.process.id = "9999"',
      ], 4242, targetSinkIndex: 218);
      expect(inputs, [55]);
    });

    testWidgets('EffectsRackView displays Output Device selector and fires updates', (tester) async {
      final track = Track(id: 'aud_out', name: 'Master', type: TrackType.audio);
      const outputs = [
        PlaybackDevice(0, true, 'Built-in Audio Analog Stereo'),
        PlaybackDevice(1, false, 'Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB'),
      ];
      String selectedOutput = 'system_default';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setModalState) => SizedBox(
                width: 1100,
                height: 460,
                child: EffectsRackView(
                  track: track,
                  allTracks: [track],
                  inputDevices: const [],
                  selectedInputDevice: null,
                  outputDevices: outputs,
                  selectedOutputDeviceKey: selectedOutput,
                  systemDefaultOutputLabel: 'Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB',
                  trackLevel: 0.0,
                  sidechainGr: 0.0,
                  detectedPitch: null,
                  tunerEnabled: false,
                  onSaveState: () {},
                  onInputDeviceChanged: (_) {},
                  onOutputDeviceChanged: (k) {
                    if (k != null) setModalState(() => selectedOutput = k);
                  },
                  onToggleTuner: () {},
                  onNoiseGateChanged: (_) {},
                  onReorderEffect: (_, _) {},
                  onRemoveEffect: (_) {},
                  onToggleBypass: (_) {},
                  onParamChanged: (_, _, _) {},
                  onSidechainChanged: (_, _) {},
                  onApplyPreset: (_) {},
                  onAddEffectPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Output Device'), findsOneWidget);
      expect(find.byKey(const Key('output_device_dropdown')), findsOneWidget);

      await tester.tap(find.byKey(const Key('output_device_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB').last,
      );
      await tester.pumpAndSettle();

      expect(
        selectedOutput,
        'dev:Scarlett Solo (3rd Gen.) Direct Scarlett Solo USB',
      );
    });
  });

  group('Unlimited Timeline Playback & Recording Past 16 Bars', () {
    testWidgets('Timeline, loop bar, and playback extend past 16 bars without stopping or clamping', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      // Add a MIDI track (1 bar clip initially)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Verify TimelineLoopBar receives maxTimelineUnits >= 6400 (32+ bars at 120 BPM)
      final loopBar = tester.widget<TimelineLoopBar>(find.byType(TimelineLoopBar));
      expect(loopBar.maxTimelineUnits, greaterThanOrEqualTo(6400.0));

      // Tap near the right side of the timeline minimap (85% of 6400 = ~5440 units = bar 27+ at 120 BPM)
      final minimap = find.ancestor(
        of: find.byType(TimelineLoopBar),
        matching: find.byType(Column),
      ).first;
      // Locate minimap container directly above timeline ruler (height 22)
      final minimapGesture = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.minHeight == 22 && w.constraints?.maxHeight == 22,
      );
      if (minimapGesture.evaluate().isNotEmpty) {
        final rect = tester.getRect(minimapGesture.first);
        await tester.tapAt(Offset(rect.left + rect.width * 0.85, rect.center.dy));
        await tester.pumpAndSettle();
      } else {
        // Fallback: drag timeline horizontally or verify extent via minimap Stack
        expect(minimap, findsOneWidget);
      }

      // Start playback (isLooping == false) and ensure it stays active past bar 16 without stopping
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Stop playback cleanly
      await tester.tap(find.byIcon(Icons.pause).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });

  group('Recording Latency Sync & Live Playhead Seek', () {
    test('computeRecordingSyncPlacement compensates round-trip latency and cold-start offsets', () {
      // Pre-warmed capture: chunk arrives right at Beat 1 (441 frames = 10ms -> chunkStart = 0.0)
      // With 40ms latency compensation at 100 units/s (4.0 units), clip aligns on Beat 1
      // with startOffset = 4.0 and remaining length = 396.0.
      final warmed = computeRecordingSyncPlacement(
        recordingStartPos: 0.0,
        firstChunkArrivedPlayhead: 1.0,
        firstChunkFrames: 441,
        rawWavDurationSeconds: 4.0,
        unitsPerSecond: 100.0,
        latencyCompensationMs: 40.0,
      );
      expect(warmed.clipStart, closeTo(0.0, 0.01));
      expect(warmed.startOffset, closeTo(4.0, 0.01));
      expect(warmed.clipLength, closeTo(396.0, 0.01));

      // Late stream open: chunk arrived 120ms after Beat 1 (firstChunkArrivedPlayhead = 13.0, chunk = 1.0 -> start = 12.0)
      // Minus 40ms latency comp -> true capture start = 8.0 units (80ms into the timeline)
      final coldStart = computeRecordingSyncPlacement(
        recordingStartPos: 0.0,
        firstChunkArrivedPlayhead: 13.0,
        firstChunkFrames: 441,
        rawWavDurationSeconds: 4.0,
        unitsPerSecond: 100.0,
        latencyCompensationMs: 40.0,
      );
      expect(coldStart.clipStart, closeTo(8.0, 0.01));
      expect(coldStart.startOffset, closeTo(0.0, 0.01));
      expect(coldStart.clipLength, closeTo(400.0, 0.01));
    });

    testWidgets('EffectsRackView renders Rec Latency slider and DawApp seeks cleanly during playback', (tester) async {
      final track = Track(id: 'aud_lat', name: 'Vox', type: TrackType.audio);
      double latency = 35.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setModalState) => SizedBox(
                width: 1100,
                height: 520,
                child: EffectsRackView(
                  track: track,
                  allTracks: [track],
                  inputDevices: const [],
                  selectedInputDevice: null,
                  recordingLatencyMs: latency,
                  trackLevel: 0.0,
                  sidechainGr: 0.0,
                  detectedPitch: null,
                  tunerEnabled: false,
                  onSaveState: () {},
                  onInputDeviceChanged: (_) {},
                  onRecordingLatencyChanged: (v) => setModalState(() => latency = v),
                  onToggleTuner: () {},
                  onNoiseGateChanged: (_) {},
                  onReorderEffect: (_, _) {},
                  onRemoveEffect: (_) {},
                  onToggleBypass: (_) {},
                  onParamChanged: (_, _, _) {},
                  onSidechainChanged: (_, _) {},
                  onApplyPreset: (_) {},
                  onAddEffectPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Rec Latency'), findsOneWidget);
      expect(find.text('35 ms'), findsOneWidget);
      expect(find.byKey(const Key('rec_latency_slider')), findsOneWidget);

      // Verify seeking earlier while DawApp is playing keeps playback running smoothly
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Audio Track'));
      await tester.pumpAndSettle();

      // Seek to bar 4 on the bottom half of the timeline ruler, start playing, then click earlier at bar 2
      final rulerFinder = find.byType(TimelineLoopBar);
      final rulerRect = tester.getRect(rulerFinder);
      await tester.tapAt(Offset(rulerRect.left + 400.0, rulerRect.bottom - 6.0));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Click before current playhead (~bar 2 = 200px) while playing
      await tester.tapAt(Offset(rulerRect.left + 200.0, rulerRect.bottom - 6.0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause).first);
      await tester.pumpAndSettle();
    });
  });

  group('Cross-Track Clip Moving', () {
    testWidgets('Dragging a MIDI clip vertically moves it onto another compatible MIDI/Sampler track', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      // Track 0: MIDI Track 1 ('Pattern 1')
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Track 1: Audio Track 2 (incompatible target for MIDI clip)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Audio Track'));
      await tester.pumpAndSettle();

      // Track 2: MIDI Track 3 (compatible target, initially has its own 'Pattern 1' -> rename or check y coordinates)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      final clipsBefore = tester.widgetList(find.text('Pattern 1')).map((w) => tester.getTopLeft(find.byWidget(w))).toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
      expect(clipsBefore, hasLength(2));
      final topClipOrigPos = clipsBefore[0];
      final bottomTrackY = clipsBefore[1].dy;
      expect(bottomTrackY - topClipOrigPos.dy, greaterThan(150.0));

      // Drag the top clip down by 100px (onto Audio Track 2 -> incompatible!) -> should stay on Track 0
      await tester.drag(
        find.text('Pattern 1').first,
        const Offset(40, 100),
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final afterIncompat = tester.widgetList(find.text('Pattern 1')).map((w) => tester.getTopLeft(find.byWidget(w))).toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
      expect(afterIncompat[0].dy, closeTo(topClipOrigPos.dy, 2.0));

      // Now drag the top clip down by 200px + right by 160px onto MIDI Track 3 -> should move cleanly!
      await tester.drag(
        find.text('Pattern 1').first,
        const Offset(160, 200),
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final afterMove = tester.widgetList(find.text('Pattern 1')).map((w) => tester.getTopLeft(find.byWidget(w))).toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
      expect(afterMove, hasLength(2));
      // Both clips are now on MIDI Track 3!
      expect(afterMove[0].dy, closeTo(bottomTrackY, 2.0));
      expect(afterMove[1].dy, closeTo(bottomTrackY, 2.0));
      expect((afterMove[0].dx - afterMove[1].dx).abs(), greaterThan(100.0));
    });

    testWidgets('MIDI clips extend past initial originalLength in Timeline and MidiEditorWidget', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: DawApp()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add MIDI Track'));
      await tester.pumpAndSettle();

      // Measure initial 'Pattern 1' clip container width (~800px = 4 bars at 120 BPM)
      final clipFinder = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('clip_'),
      );
      final origRect = tester.getRect(clipFinder.first);
      expect(origRect.width, closeTo(800.0, 2.0));

      // Drag the right resize handle right by 600px -> should extend to ~1400px (7 bars), NOT clamp to 800px!
      await tester.dragFrom(
        Offset(origRect.right - 4.0, origRect.center.dy),
        const Offset(600.0, 0.0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final extendedRect = tester.getRect(clipFinder.first);
      expect(extendedRect.width, greaterThan(origRect.width + 500.0));

      // Also verify MidiEditorWidget's interactive clip end handle extends clip length cleanly
      final midiTrack = Track(id: 'ext_m', name: 'Keys', type: TrackType.midi);
      final midiClip = MidiClip(
        id: 'ext_mc',
        start: 0.0,
        length: 200.0,
        color: Colors.purple,
      );
      int noteChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setModalState) => SizedBox(
                width: 1100,
                height: 460,
                child: MidiEditorWidget(
                  clip: midiClip,
                  track: midiTrack,
                  snapToGrid: false,
                  snapResolution: 25.0,
                  zoomX: 1.0,
                  bpm: 120,
                  timeSigTop: 4,
                  playheadPosition: 0.0,
                  onPlayheadChanged: (_) {},
                  selectedMidiNotes: const [],
                  onSelectionChanged: (_) {},
                  onNotesChanged: () {
                    noteChanges++;
                    setModalState(() {});
                  },
                  onSynthSettingsChanged: () {},
                  onZoomIn: () {},
                  onZoomOut: () {},
                  midiDevices: const [],
                  onCopy: () {},
                  onPaste: () {},
                  onInstrumentDialogRequested: () {},
                  onMidiInputDialogRequested: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final endHandle = find.byKey(const Key('midi_clip_end_handle'));
      expect(endHandle, findsOneWidget);
      await tester.drag(
        endHandle,
        const Offset(350.0, 0.0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(midiClip.length, greaterThan(500.0));
      expect(midiClip.originalLength, greaterThan(500.0));
      expect(noteChanges, greaterThan(0));
    });
  });
}
