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
  String name;
  double start;
  double length;
  double originalLength;
  double startOffset;
  Color color;
  ClipType get type;

  DawClip({
    required this.id,
    this.name = '',
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
        name: json['name'] ?? '',
        start: (json['start'] as num).toDouble(),
        length: (json['length'] as num).toDouble(),
        originalLength: (json['originalLength'] as num?)?.toDouble(),
        startOffset: (json['startOffset'] as num?)?.toDouble() ?? 0.0,
        color: Color(json['color']),
        filePath: json['filePath'],
        fadeIn: (json['fadeIn'] as num?)?.toDouble() ?? 0.0,
        fadeOut: (json['fadeOut'] as num?)?.toDouble() ?? 0.0,
        gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
        pitchSemitones: (json['pitchSemitones'] as num?)?.toDouble() ?? 0.0,
        stretchFactor: (json['stretchFactor'] as num?)?.toDouble() ?? 1.0,
        reversed: json['reversed'] ?? false,
        originalFilePath: json['originalFilePath'],
        takes: json['takes'] != null
            ? (json['takes'] as List)
                  .map((e) => AudioTake.fromJson(e))
                  .toList()
            : null,
        activeTakeIndex: json['activeTakeIndex'] ?? 0,
      );
    } else {
      var mc = MidiClip(
        id: json['id'],
        name: json['name'] ?? '',
        start: (json['start'] as num).toDouble(),
        length: (json['length'] as num).toDouble(),
        originalLength: (json['originalLength'] as num?)?.toDouble(),
        startOffset: (json['startOffset'] as num?)?.toDouble() ?? 0.0,
        color: Color(json['color']),
        patternGroupId: json['patternGroupId'],
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

class AudioTake {
  String id;
  String name;
  String filePath;
  double gain;

  AudioTake({
    required this.id,
    required this.name,
    required this.filePath,
    this.gain = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'gain': gain,
  };

  factory AudioTake.fromJson(Map<String, dynamic> json) => AudioTake(
    id: json['id'] ?? '',
    name: json['name'] ?? 'Take',
    filePath: json['filePath'] ?? '',
    gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
  );
}

class AudioClip extends DawClip {
  String filePath;
  AudioSource? source;
  SoundHandle? currentHandle;
  SoundHandle? reverbSendHandle;
  SoundHandle? delaySendHandle;
  List<double>? waveformData;
  double fadeIn;
  double fadeOut;
  double gain;
  double pitchSemitones;
  double stretchFactor;
  List<AudioTake> takes;
  int activeTakeIndex;

  @override
  ClipType get type => ClipType.audio;

  AudioClip({
    required super.id,
    super.name,
    required super.start,
    required super.length,
    required super.color,
    super.originalLength,
    super.startOffset,
    required this.filePath,
    this.fadeIn = 0.0,
    this.fadeOut = 0.0,
    this.gain = 1.0,
    this.pitchSemitones = 0.0,
    this.stretchFactor = 1.0,
    this.reversed = false,
    this.originalFilePath,
    List<AudioTake>? takes,
    this.activeTakeIndex = 0,
  }) : takes = takes ?? [] {
    _extractWaveform();
  }

  bool reversed = false;
  String? originalFilePath;

  void addTake(AudioTake take) {
    if (takes.isEmpty && filePath.isNotEmpty) {
      takes.add(
        AudioTake(
          id: '${id}_t1',
          name: 'Take 1',
          filePath: filePath,
          gain: gain,
        ),
      );
    }
    takes.add(take);
    activeTakeIndex = takes.length - 1;
    filePath = take.filePath;
    gain = take.gain;
    _extractWaveform();
  }

  void selectTake(int index) {
    if (index < 0 || index >= takes.length) return;
    activeTakeIndex = index;
    final t = takes[index];
    filePath = t.filePath;
    gain = t.gain;
    _extractWaveform();
  }

  /// Refreshes cached peak waveform after offline destructive audio edits.
  void refreshWaveform() => _extractWaveform();

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'length': length,
    'originalLength': originalLength,
    'startOffset': startOffset,
    'color': color.toARGB32(),
    'type': type.index,
    'filePath': filePath,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'gain': gain,
    'pitchSemitones': pitchSemitones,
    'stretchFactor': stretchFactor,
    'reversed': reversed,
    'originalFilePath': originalFilePath,
    'takes': takes.map((t) => t.toJson()).toList(),
    'activeTakeIndex': activeTakeIndex,
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
  String? patternGroupId;

  @override
  ClipType get type => ClipType.midi;

  MidiClip({
    required super.id,
    super.name,
    required super.start,
    required super.length,
    required super.color,
    super.originalLength,
    super.startOffset,
    List<MidiNote>? notes,
    this.patternGroupId,
  }) : notes = notes ?? [];

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'length': length,
    'originalLength': originalLength,
    'startOffset': startOffset,
    'color': color.toARGB32(),
    'type': type.index,
    'patternGroupId': patternGroupId,
    'notes': notes.map((n) => n.toJson()).toList(),
  };
}
