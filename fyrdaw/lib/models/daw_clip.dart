import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:fyrdaw/models/midi_note.dart';

abstract class DawClip {
  String id;
  double start;
  double length;
  double originalLength;
  double startOffset;
  Color color;
  ClipType get type;

  DawClip({
    required this.id,
    required this.start,
    required this.length,
    required this.color,
    double? originalLength,
    this.startOffset = 0.0,
  }) : originalLength = originalLength ?? length;

  Map<String, dynamic> toJson();

  static DawClip fromJson(Map<String, dynamic> json) {
    if (json['type'] == ClipType.audio.index) {
      return AudioClip(
        id: json['id'],
        start: json['start'],
        length: json['length'],
        originalLength: json['originalLength'],
        startOffset: json['startOffset'] ?? 0.0,
        color: Color(json['color']),
        filePath: json['filePath'],
      );
    } else {
      var mc = MidiClip(
        id: json['id'],
        start: json['start'],
        length: json['length'],
        originalLength: json['originalLength'],
        startOffset: json['startOffset'] ?? 0.0,
        color: Color(json['color']),
      );
      if (json['notes'] != null) {
        mc.notes = (json['notes'] as List)
            .map((n) => MidiNote.fromJson(n))
            .toList();
      }
      return mc;
    }
  }
}

class AudioClip extends DawClip {
  String filePath;
  AudioSource? source;
  SoundHandle? currentHandle;
  List<double>? waveformData;

  @override
  ClipType get type => ClipType.audio;

  AudioClip({
    required super.id,
    required super.start,
    required super.length,
    required super.color,
    super.originalLength,
    super.startOffset,
    required this.filePath,
  }) {
    _extractWaveform();
  }

  bool reversed = false;
  String? originalFilePath;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start,
    'length': length,
    'originalLength': originalLength,
    'startOffset': startOffset,
    'color': color.value,
    'type': type.index,
    'filePath': filePath,
    'reversed': reversed,
    'originalFilePath': originalFilePath,
  };

  Future<void> toggleReverse() async {
    reversed = !reversed;
    originalFilePath ??= filePath;

    if (reversed) {
      final dir = await getProjectMediaDirectory();
      String revPath =
          '${dir.path}/rev_${DateTime.now().millisecondsSinceEpoch}.wav';
      await reverseWavFile(originalFilePath!, revPath);
      filePath = revPath;
    } else {
      filePath = originalFilePath!;
    }

    if (SoLoud.instance.isInitialized) {
      if (source != null) {
        SoLoud.instance.disposeSource(source!);
      }
      source = await SoLoud.instance.loadFile(filePath);
    }
    _extractWaveform();
  }

  void _extractWaveform() async {
    final data = await extractWavWaveform(filePath, 200);
    if (data != null) {
      waveformData = data;
    }
  }
}

class MidiClip extends DawClip {
  List<MidiNote> notes;
  @override
  ClipType get type => ClipType.midi;

  MidiClip({
    required super.id,
    required super.start,
    required super.length,
    required super.color,
    super.originalLength,
    super.startOffset,
    List<MidiNote>? notes,
  }) : notes = notes ?? [];

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start,
    'length': length,
    'originalLength': originalLength,
    'startOffset': startOffset,
    'color': color.value,
    'type': type.index,
    'notes': notes.map((n) => n.toJson()).toList(),
  };
}
