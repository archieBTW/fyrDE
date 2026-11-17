import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SamplerPad {
  String? filePath;
  String? name;
  AudioSource? source;
  SoundHandle? currentHandle;
  final List<SoundHandle> activeHandles = [];
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
        // Do NOT pre-activate pitchShiftFilter unconditionally: Signalsmith
        // Stretch adds ~120ms STFT analysis/synthesis latency even at 1.0x pitch.
      }
    } catch (_) {}
    await extractWaveform();
  }

  /// Returns the other pads on the track that should be silenced when
  /// [triggered] starts (only pads sharing a non-zero [chokeGroup]).
  static List<SamplerPad> padsToChoke(
    SamplerPad triggered,
    Iterable<SamplerPad>? trackPads,
  ) {
    if (triggered.chokeGroup <= 0 || trackPads == null) return const [];
    return trackPads
        .where(
          (other) =>
              !identical(other, triggered) &&
              other.chokeGroup == triggered.chokeGroup,
        )
        .toList();
  }

  void stopActive() {
    final handlesToStop = <SoundHandle>{
      ...activeHandles,
      ?currentHandle,
    };
    for (final h in handlesToStop) {
      try {
        if (SoLoud.instance.getIsValidVoiceHandle(h)) {
          SoLoud.instance.stop(h);
        }
      } catch (_) {}
    }
    activeHandles.clear();
    currentHandle = null;
  }

  void play([
    double velocity = 127.0,
    Bus? bus,
    double trackVolume = 1.0,
    double trackPan = 0.0,
    Iterable<SamplerPad>? trackPads,
    double? pitchMultiplierOverride,
    bool isAuxSend = false,
  ]) {
    if (source == null) return;
    try {
      if (!isAuxSend) {
        for (final other in padsToChoke(this, trackPads)) {
          other.stopActive();
        }
        // Only choke prior hits on this pad when assigned to a choke group;
        // unchoked drum/cymbal pads ring polyphonically across rapid rolls.
        if (chokeGroup > 0) {
          stopActive();
        }
      }

      activeHandles.removeWhere((h) {
        try {
          return !SoLoud.instance.getIsValidVoiceHandle(h);
        } catch (_) {
          return true;
        }
      });
      while (activeHandles.length >= 8) {
        final oldest = activeHandles.removeAt(0);
        try {
          if (SoLoud.instance.getIsValidVoiceHandle(oldest)) {
            SoLoud.instance.stop(oldest);
          }
        } catch (_) {}
      }

      final totalLen = SoLoud.instance.getLength(source!);
      final startPos = totalLen * trimStart;
      final endPos = totalLen * trimEnd;
      final playLength = endPos - startPos;

      if (playLength <= Duration.zero) return;

      final double effPitch =
          (pitch * (pitchMultiplierOverride ?? 1.0)).clamp(0.1, 4.0);
      final bool needsPitchShift = (effPitch - 1.0).abs() > 0.005;
      if (needsPitchShift && !source!.filters.pitchShiftFilter.isActive) {
        source!.filters.pitchShiftFilter.activate();
      }

      final double targetVol = volume * (velocity / 127.0) * trackVolume;
      final double initialVol = fadeIn > 0.0 ? 0.0 : targetVol;
      final handle = bus != null
          ? bus.play(source!, volume: initialVol, pan: trackPan, paused: true)
          : SoLoud.instance.play(
              source!,
              volume: initialVol,
              pan: trackPan,
              paused: true,
            );
      activeHandles.add(handle);
      if (!isAuxSend) {
        currentHandle = handle;
      }
      if (trimStart > 0.0005 && startPos > Duration.zero) {
        SoLoud.instance.seek(handle, startPos);
      }
      if (source!.filters.pitchShiftFilter.isActive) {
        if (needsPitchShift) {
          source!.filters.pitchShiftFilter.wet(soundHandle: handle).value = 1.0;
          source!.filters.pitchShiftFilter
              .shift(soundHandle: handle)
              .value = effPitch;
        } else {
          // Dry bypass avoids ~120ms STFT lookahead delay on un-pitched hits.
          source!.filters.pitchShiftFilter.wet(soundHandle: handle).value = 0.0;
        }
      }
      SoLoud.instance.setPause(handle, false);

      if (fadeIn > 0.0) {
        SoLoud.instance.fadeVolume(
          handle,
          targetVol,
          Duration(milliseconds: (fadeIn * 1000).toInt()),
        );
      }

      if (fadeOut > 0.0) {
        Duration fadeOutTime = Duration(milliseconds: (fadeOut * 1000).toInt());
        if (fadeOutTime > playLength) fadeOutTime = playLength;
        Duration waitTime = playLength - fadeOutTime;
        Timer(waitTime, () {
          try {
            if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
              SoLoud.instance.fadeVolume(handle, 0.0, fadeOutTime);
            }
          } catch (_) {}
        });
      }

      Timer(playLength, () {
        activeHandles.remove(handle);
        if (currentHandle == handle) currentHandle = null;
        try {
          if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
            SoLoud.instance.stop(handle);
          }
        } catch (_) {}
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

/// Stops active voices, disposes loaded SoLoud sources, and resets all
/// 16 pad slots (MIDI notes 36..51) in [samplerPads].
void _clearSamplerPads(Map<int, SamplerPad> samplerPads) {
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
}

/// Populates a sampler track's pad map [samplerPads] from a built-in [kit]
/// preset, initializing all 16 MIDI note slots (36..51) and choke groups.
Future<void> applyDrumKitToPads(
  Map<int, SamplerPad> samplerPads,
  DrumKitPreset kit,
) async {
  _clearSamplerPads(samplerPads);
  for (final spec in kit.pads) {
    final pad = samplerPads[spec.padIndex] ?? SamplerPad();
    pad.midiNote = spec.midiNote;
    pad.chokeGroup = spec.chokeGroup;
    pad.name = spec.label;
    samplerPads[spec.padIndex] = pad;
    await pad.loadSample(spec.assetPath, label: spec.label);
  }
}

/// User-saved 16-pad sampler kit preserving each pad's sample path and
/// per-pad settings (trim, volume, pitch, fades, reverse, MIDI note, choke).
class SavedSamplerKit {
  final String id;
  final String name;
  final DateTime updatedAt;
  final Map<int, Map<String, dynamic>> padsJson;

  const SavedSamplerKit({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.padsJson,
  });

  /// Number of pads that have an assigned sample file or asset path.
  int get sampleCount => padsJson.values
      .where((pad) => pad['filePath'] is String && (pad['filePath'] as String).isNotEmpty)
      .length;

  /// Captures a deep snapshot of all 16 pad slots from [samplerPads].
  factory SavedSamplerKit.fromPads({
    required String name,
    required Map<int, SamplerPad> samplerPads,
    String? id,
    DateTime? updatedAt,
  }) {
    final trimmed = name.trim();
    final pads = <int, Map<String, dynamic>>{};
    for (int i = 0; i < 16; i++) {
      final pad = samplerPads[i] ?? (SamplerPad()..midiNote = 36 + i);
      pads[i] = Map<String, dynamic>.from(pad.toJson());
    }
    final ts = updatedAt ?? DateTime.now();
    return SavedSamplerKit(
      id: id ?? 'user_${ts.microsecondsSinceEpoch}',
      name: trimmed,
      updatedAt: ts,
      padsJson: pads,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'pads': {
      for (final entry in padsJson.entries) entry.key.toString(): entry.value,
    },
  };

  factory SavedSamplerKit.fromJson(Map<String, dynamic> json) {
    final rawPads = json['pads'];
    final parsedPads = <int, Map<String, dynamic>>{};
    if (rawPads is Map) {
      for (final entry in rawPads.entries) {
        final idx = int.tryParse(entry.key.toString());
        if (idx != null && idx >= 0 && idx < 16 && entry.value is Map) {
          parsedPads[idx] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return SavedSamplerKit(
      id: (json['id'] as String?) ?? 'user_unknown',
      name: (json['name'] as String?) ?? 'Untitled Sampler',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      padsJson: parsedPads,
    );
  }
}

/// Persistent store for user-saved sampler kits backed by [SharedPreferences].
class SavedSamplerKitStore {
  static const String storageKey = 'fyrdaw_saved_sampler_kits_v1';

  /// Loads all saved sampler kits sorted by most recently updated first.
  static Future<List<SavedSamplerKit>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final kits = decoded
          .whereType<Map>()
          .map(
            (item) => SavedSamplerKit.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      kits.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return kits;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeAll(List<SavedSamplerKit> kits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(kits.map((k) => k.toJson()).toList()),
    );
  }

  /// Saves the current [samplerPads] under [name], overwriting any existing
  /// saved kit with the same name (case-insensitive) or [overwriteId].
  static Future<SavedSamplerKit> save({
    required String name,
    required Map<int, SamplerPad> samplerPads,
    String? overwriteId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Sampler name cannot be empty.');
    }
    final kits = await loadAll();
    final existingIdx = kits.indexWhere(
      (k) =>
          (overwriteId != null && k.id == overwriteId) ||
          k.name.toLowerCase() == trimmed.toLowerCase(),
    );
    final kit = SavedSamplerKit.fromPads(
      name: trimmed,
      samplerPads: samplerPads,
      id: existingIdx >= 0 ? kits[existingIdx].id : null,
    );
    if (existingIdx >= 0) {
      kits.removeAt(existingIdx);
    }
    kits.insert(0, kit);
    await _writeAll(kits);
    return kit;
  }

  /// Deletes the saved sampler kit matching [id].
  static Future<void> delete(String id) async {
    final kits = await loadAll();
    kits.removeWhere((k) => k.id == id);
    await _writeAll(kits);
  }
}

/// Restores a previously saved user [kit] into [samplerPads], reloading each
/// pad's audio sample and restoring all per-pad parameters.
Future<void> applySavedSamplerKitToPads(
  Map<int, SamplerPad> samplerPads,
  SavedSamplerKit kit,
) async {
  _clearSamplerPads(samplerPads);
  for (int i = 0; i < 16; i++) {
    final raw = kit.padsJson[i];
    if (raw == null) continue;
    final pad = SamplerPad.fromJson(raw);
    samplerPads[i] = pad;
    final path = pad.filePath;
    if (path != null && path.isNotEmpty) {
      await pad.loadSample(path, label: pad.name);
    }
  }
}
