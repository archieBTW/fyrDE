import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/utils/audio_utils.dart';

class SamplerPad {
  String? filePath;
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

  SamplerPad();

  void extractWaveform() async {
    if (filePath == null) return;
    final data = await extractWavWaveform(filePath!, 200);
    if (data != null) {
      waveformData = data;
    }
  }

  void play([double velocity = 127.0]) {
    if (source == null) return;
    try {
      if (currentHandle != null &&
          SoLoud.instance.getIsValidVoiceHandle(currentHandle!)) {
        SoLoud.instance.stop(currentHandle!);
      }

      final totalLen = SoLoud.instance.getLength(source!);
      final startPos = totalLen * trimStart;
      final endPos = totalLen * trimEnd;
      final playLength = endPos - startPos;

      if (playLength <= Duration.zero) return;

      final handle = SoLoud.instance.play(source!, volume: 0.0, paused: true);
      currentHandle = handle;
      SoLoud.instance.seek(handle, startPos);
      source!.filters.pitchShiftFilter.shift(soundHandle: handle).value = pitch;
      SoLoud.instance.setPause(handle, false);

      double targetVol = volume * (velocity / 127.0);
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
    'trimStart': trimStart,
    'trimEnd': trimEnd,
    'volume': volume,
    'pitch': pitch,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'reversed': reversed,
    'originalFilePath': originalFilePath,
    'midiNote': midiNote,
  };

  factory SamplerPad.fromJson(Map<String, dynamic> json) {
    return SamplerPad()
      ..filePath = json['filePath']
      ..trimStart = json['trimStart'] ?? 0.0
      ..trimEnd = json['trimEnd'] ?? 1.0
      ..volume = json['volume'] ?? 1.0
      ..pitch = json['pitch'] ?? 1.0
      ..fadeIn = json['fadeIn'] ?? 0.0
      ..fadeOut = json['fadeOut'] ?? 0.0
      ..reversed = json['reversed'] ?? false
      ..originalFilePath = json['originalFilePath']
      ..midiNote = json['midiNote'] ?? 36;
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

    if (SoLoud.instance.isInitialized) {
      if (source != null) {
        SoLoud.instance.disposeSource(source!);
      }
      source = await SoLoud.instance.loadFile(filePath!);
      source!.filters.pitchShiftFilter.activate();
    }
    extractWaveform();
    onDone();
  }
}
