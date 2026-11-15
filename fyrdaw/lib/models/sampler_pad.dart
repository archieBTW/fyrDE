import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/utils/audio_utils.dart';

class SamplerPad {
  String? filePath;
  String? name;
  AudioSource? source;
  SoundHandle? currentHandle;
  List<double>? waveformData;
  double trimStart = 0.0;
  double trimEnd = 1.0;
  double volume = 1.0;
  double pitch = 1.0;
  double fadeIn = 0.0;
  double fadeOut = 0.0;
  int midiNote = 36;
  int chokeGroup = 0; // 0 = Off, 1..4 = Choke A..D

  SamplerPad();

  Future<void> extractWaveform() async {
    if (filePath == null) return;
    final data = await extractWavWaveform(filePath!, 200);
    if (data != null) {
      waveformData = data;
    }
  }

  /// Loads [path] (either a bundled `'assets/...'` asset or a disk file path)
  /// into SoLoud (when initialized) and extracts waveform peaks.
  Future<void> loadSample(String path, {String? label}) async {
    filePath = path;
    if (label != null) {
      name = label;
    }
    try {
      if (SoLoud.instance.isInitialized) {
        if (source != null) {
          SoLoud.instance.disposeSource(source!);
        }
        source = path.startsWith('assets/')
            ? await SoLoud.instance.loadAsset(path)
            : await SoLoud.instance.loadFile(path);
        source!.filters.pitchShiftFilter.activate();
      }
    } catch (_) {}
    await extractWaveform();
  }

  void stopActive() {
    if (currentHandle == null) return;
    try {
      if (SoLoud.instance.getIsValidVoiceHandle(currentHandle!)) {
        SoLoud.instance.stop(currentHandle!);
      }
    } catch (_) {}
    currentHandle = null;
  }

  void play([
    double velocity = 127.0,
    Bus? bus,
    double trackVolume = 1.0,
    double trackPan = 0.0,
    Iterable<SamplerPad>? trackPads,
    double? pitchMultiplierOverride,
  ]) {
    if (source == null) return;
    try {
      if (chokeGroup > 0 && trackPads != null) {
        for (final other in trackPads) {
          if (!identical(other, this) && other.chokeGroup == chokeGroup) {
            other.stopActive();
          }
        }
      }
      stopActive();

      final totalLen = SoLoud.instance.getLength(source!);
      final startPos = totalLen * trimStart;
      final endPos = totalLen * trimEnd;
      final playLength = endPos - startPos;

      if (playLength <= Duration.zero) return;

      final handle = bus != null
          ? bus.play(source!, volume: 0.0, pan: trackPan, paused: true)
          : SoLoud.instance.play(
              source!,
              volume: 0.0,
              pan: trackPan,
              paused: true,
            );
      currentHandle = handle;
      SoLoud.instance.seek(handle, startPos);
      source!.filters.pitchShiftFilter.shift(soundHandle: handle).value =
          (pitch * (pitchMultiplierOverride ?? 1.0)).clamp(0.1, 4.0);
      SoLoud.instance.setPause(handle, false);

      double targetVol = volume * (velocity / 127.0) * trackVolume;
      if (fadeIn > 0.0) {
        SoLoud.instance.fadeVolume(
          handle,
          targetVol,
          Duration(milliseconds: (fadeIn * 1000).toInt()),
        );
      } else {
        SoLoud.instance.setVolume(handle, targetVol);
      }

      if (fadeOut > 0.0) {
        Duration fadeOutTime = Duration(milliseconds: (fadeOut * 1000).toInt());
        if (fadeOutTime > playLength) fadeOutTime = playLength;
        Duration waitTime = playLength - fadeOutTime;
        Timer(waitTime, () {
          if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
            SoLoud.instance.fadeVolume(handle, 0.0, fadeOutTime);
          }
        });
      }

      Timer(playLength, () {
        if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
          SoLoud.instance.stop(handle);
        }
      });
    } catch (_) {}
  }

  bool reversed = false;
  String? originalFilePath;

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'name': name,
    'trimStart': trimStart,
    'trimEnd': trimEnd,
    'volume': volume,
    'pitch': pitch,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'reversed': reversed,
    'originalFilePath': originalFilePath,
    'midiNote': midiNote,
    'chokeGroup': chokeGroup,
  };

  factory SamplerPad.fromJson(Map<String, dynamic> json) {
    return SamplerPad()
      ..filePath = json['filePath']
      ..name = json['name']
      ..trimStart = json['trimStart'] ?? 0.0
      ..trimEnd = json['trimEnd'] ?? 1.0
      ..volume = json['volume'] ?? 1.0
      ..pitch = json['pitch'] ?? 1.0
      ..fadeIn = json['fadeIn'] ?? 0.0
      ..fadeOut = json['fadeOut'] ?? 0.0
      ..reversed = json['reversed'] ?? false
      ..originalFilePath = json['originalFilePath']
      ..midiNote = json['midiNote'] ?? 36
      ..chokeGroup = json['chokeGroup'] ?? 0;
  }

  Future<void> toggleReverse(VoidCallback onDone) async {
    if (filePath == null) return;
    reversed = !reversed;

    double oldStart = trimStart;
    trimStart = 1.0 - trimEnd;
    trimEnd = 1.0 - oldStart;

    originalFilePath ??= filePath;

    if (reversed) {
      final dir = await getProjectMediaDirectory();
      String revPath =
          '${dir.path}/rev_pad_${DateTime.now().millisecondsSinceEpoch}.wav';
      await reverseWavFile(originalFilePath!, revPath);
      filePath = revPath;
    } else {
      filePath = originalFilePath;
    }

    await loadSample(filePath!);
    onDone();
  }
}

/// Populates a sampler track's pad map [samplerPads] from a built-in [kit]
/// preset, initializing all 16 MIDI note slots (36..51) and choke groups.
Future<void> applyDrumKitToPads(
  Map<int, SamplerPad> samplerPads,
  DrumKitPreset kit,
) async {
  for (final existing in samplerPads.values) {
    existing.stopActive();
    try {
      if (existing.source != null && SoLoud.instance.isInitialized) {
        SoLoud.instance.disposeSource(existing.source!);
      }
    } catch (_) {}
  }
  samplerPads.clear();
  for (int i = 0; i < 16; i++) {
    samplerPads[i] = SamplerPad()..midiNote = 36 + i;
  }
  for (final spec in kit.pads) {
    final pad = samplerPads[spec.padIndex] ?? SamplerPad();
    pad.midiNote = spec.midiNote;
    pad.chokeGroup = spec.chokeGroup;
    pad.name = spec.label;
    samplerPads[spec.padIndex] = pad;
    await pad.loadSample(spec.assetPath, label: spec.label);
  }
}
