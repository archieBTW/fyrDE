import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/utils/bus_metering.dart';

const List<Color> kTrackColorPalette = [
  Color(0xFFB57EDC), // Lavender
  Color(0xFF38BDF8), // Sky Blue
  Color(0xFF34D399), // Emerald
  Color(0xFFFBBF24), // Amber
  Color(0xFFF472B6), // Pink
  Color(0xFFFB7185), // Rose
  Color(0xFF818CF8), // Indigo
  Color(0xFF2DD4BF), // Teal
];

class SynthSettings {
  double attackSec;
  double decaySec;
  double sustain;
  double releaseSec;
  double filterCutoff; // normalized 0..1 (1.0 = wide open)
  double filterResonance; // 0..1
  int octave; // -2..+2
  double detuneCents; // -50..+50

  SynthSettings({
    this.attackSec = 0.005,
    this.decaySec = 0.15,
    this.sustain = 0.85,
    this.releaseSec = 0.14,
    this.filterCutoff = 1.0,
    this.filterResonance = 0.1,
    this.octave = 0,
    this.detuneCents = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'attackSec': attackSec,
    'decaySec': decaySec,
    'sustain': sustain,
    'releaseSec': releaseSec,
    'filterCutoff': filterCutoff,
    'filterResonance': filterResonance,
    'octave': octave,
    'detuneCents': detuneCents,
  };

  factory SynthSettings.fromJson(Map<String, dynamic> json) => SynthSettings(
    attackSec: (json['attackSec'] as num?)?.toDouble() ?? 0.005,
    decaySec: (json['decaySec'] as num?)?.toDouble() ?? 0.15,
    sustain: (json['sustain'] as num?)?.toDouble() ?? 0.85,
    releaseSec: (json['releaseSec'] as num?)?.toDouble() ?? 0.14,
    filterCutoff: (json['filterCutoff'] as num?)?.toDouble() ?? 1.0,
    filterResonance: (json['filterResonance'] as num?)?.toDouble() ?? 0.1,
    octave: (json['octave'] as num?)?.toInt() ?? 0,
    detuneCents: (json['detuneCents'] as num?)?.toDouble() ?? 0.0,
  );
}

class ArpSettings {
  bool enabled;
  ArpMode mode;
  double rateBeats; // e.g., 0.25 = 1/16th, 0.5 = 1/8th, 1.0 = 1/4
  int octaves; // 1..3
  double gate; // 0.2..1.0

  ArpSettings({
    this.enabled = false,
    this.mode = ArpMode.up,
    this.rateBeats = 0.25,
    this.octaves = 1,
    this.gate = 0.8,
  });

  /// Expands simultaneous/held MIDI notes into arpeggiated step notes when [enabled] is true.
  List<MidiNote> expandNotes(List<MidiNote> sourceNotes, double beatWidth) {
    if (!enabled || sourceNotes.isEmpty) return sourceNotes;
    final stepPx = (rateBeats * beatWidth).clamp(4.0, beatWidth * 4.0);
    final noteDur = (stepPx * gate).clamp(3.0, stepPx);
    final out = <MidiNote>[];

    // Group notes starting around the same beat slice (chord buckets)
    final sorted = [...sourceNotes]..sort((a, b) => a.start.compareTo(b.start));
    final List<List<MidiNote>> clusters = [];
    for (final n in sorted) {
      if (clusters.isEmpty || (n.start - clusters.last.first.start).abs() > stepPx * 0.45) {
        clusters.add([n]);
      } else {
        clusters.last.add(n);
      }
    }

    final rng = Random(42);
    for (final cluster in clusters) {
      final double windowStart = cluster.first.start;
      double windowLen = cluster.fold<double>(0.0, (mx, n) => max(mx, n.length));
      if (windowLen < stepPx) windowLen = stepPx;

      final pitches = <int>[];
      final base = cluster.map((n) => n.pitch).toSet().toList()..sort();
      for (int o = 0; o < octaves.clamp(1, 3); o++) {
        for (final p in base) {
          final shifted = p + o * 12;
          if (shifted <= 127) pitches.add(shifted);
        }
      }
      if (pitches.isEmpty) continue;

      List<int> pattern;
      switch (mode) {
        case ArpMode.up:
          pattern = pitches;
        case ArpMode.down:
          pattern = pitches.reversed.toList();
        case ArpMode.upDown:
          pattern = [
            ...pitches,
            if (pitches.length > 2) ...pitches.sublist(1, pitches.length - 1).reversed,
          ];
        case ArpMode.random:
          pattern = [...pitches];
      }

      final avgVel = (cluster.fold<int>(0, (s, n) => s + n.velocity) / cluster.length).round().clamp(1, 127);
      final steps = max(1, (windowLen / stepPx).floor());
      for (int s = 0; s < steps; s++) {
        final pitch = mode == ArpMode.random
            ? pattern[rng.nextInt(pattern.length)]
            : pattern[s % pattern.length];
        out.add(
          MidiNote(
            pitch: pitch,
            start: windowStart + s * stepPx,
            length: noteDur,
            velocity: avgVel,
          ),
        );
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.index,
    'rateBeats': rateBeats,
    'octaves': octaves,
    'gate': gate,
  };

  factory ArpSettings.fromJson(Map<String, dynamic> json) => ArpSettings(
    enabled: json['enabled'] ?? false,
    mode: ArpMode.values[(json['mode'] as num?)?.toInt().clamp(0, ArpMode.values.length - 1) ?? 0],
    rateBeats: (json['rateBeats'] as num?)?.toDouble() ?? 0.25,
    octaves: (json['octaves'] as num?)?.toInt() ?? 1,
    gate: (json['gate'] as num?)?.toDouble() ?? 0.8,
  );
}

class Track {
  String id;
  String name;
  TrackType type;
  bool isMuted = false;
  bool isSolo = false;
  bool isArmed = false;
  bool isMonitoring = false;
  double volume = 0.75;
  double pan = 0.0;
  double reverbSend = 0.0;
  double delaySend = 0.0;
  bool reverbPreFader = false;
  bool delayPreFader = false;
  double noiseGateThreshold = 0.0; // 0.0..0.25 amplitude gate
  int colorValue;
  int instrumentIndex = 0;
  String? midiInputId;
  String? groupTrackId;
  bool isGroupCollapsed = false;
  SynthSettings synthSettings = SynthSettings();
  ArpSettings arpSettings = ArpSettings();
  List<DawEffect> effectsChain = [];
  AudioSource? synthSource;
  String? synthSourcePath;
  List<SoundHandle> activeMidiHandles = [];
  bool showAutomation = false;
  String currentAutomationParam = 'Volume';
  Map<String, List<AutomationPoint>> automation = {'Volume': [], 'Pan': []};
  Map<int, SamplerPad> samplerPads = {};

  Bus? bus;
  AudioSource? monitorSource;
  SoundHandle? monitorHandle;

  Color get color => Color(colorValue);

  List<String> get availableAutomationParams {
    final params = <String>['Volume', 'Pan', 'Reverb Send', 'Delay Send'];
    if (type == TrackType.midi) {
      params.addAll(['Synth Cutoff', 'Synth Reso']);
    }
    for (final fx in effectsChain) {
      for (final key in fx.parameters.keys) {
        params.add('${fx.name}_$key');
      }
    }
    return params;
  }

  Track({
    required this.id,
    required this.name,
    required this.type,
    int? colorValue,
  }) : colorValue = colorValue ?? kTrackColorPalette[0].toARGB32() {
    if (type == TrackType.sampler) {
      for (int i = 0; i < 16; i++) {
        samplerPads[i] = SamplerPad()..midiNote = 36 + i;
      }
    }
    try {
      if (SoLoud.instance.isInitialized) {
        bus = ensureActiveBus(bus);
      }
    } catch (_) {}
  }

  double getInterpolatedAutomation(String param, double currentPos) {
    var list = automation[param];
    if (list == null || list.isEmpty) return -1.0;
    if (currentPos <= list.first.time) return list.first.value;
    if (currentPos >= list.last.time) return list.last.value;
    for (int i = 0; i < list.length - 1; i++) {
      final a = list[i];
      final b = list[i + 1];
      if (currentPos >= a.time && currentPos <= b.time) {
        final span = b.time - a.time;
        if (span <= 1e-6) return b.value;
        double t = ((currentPos - a.time) / span).clamp(0.0, 1.0);
        if (a.curve.abs() > 0.001) {
          // Smooth tension exponent: curve in [-1..1] maps power in [3.5..0.28]
          final exponent = pow(3.5, -a.curve.clamp(-1.0, 1.0)).toDouble();
          t = pow(t, exponent).toDouble();
        }
        return a.value + t * (b.value - a.value);
      }
    }
    return -1.0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.index,
    'isMuted': isMuted,
    'isSolo': isSolo,
    'isArmed': isArmed,
    'volume': volume,
    'pan': pan,
    'reverbSend': reverbSend,
    'delaySend': delaySend,
    'reverbPreFader': reverbPreFader,
    'delayPreFader': delayPreFader,
    'noiseGateThreshold': noiseGateThreshold,
    'colorValue': colorValue,
    'instrumentIndex': instrumentIndex,
    'midiInputId': midiInputId,
    'groupTrackId': groupTrackId,
    'isGroupCollapsed': isGroupCollapsed,
    'synthSettings': synthSettings.toJson(),
    'arpSettings': arpSettings.toJson(),
    'effectsChain': effectsChain.map((e) => e.toJson()).toList(),
    'showAutomation': showAutomation,
    'currentAutomationParam': currentAutomationParam,
    'automation': automation.map(
      (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
    ),
    'samplerPads': samplerPads.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    ),
  };

  factory Track.fromJson(Map<String, dynamic> json) {
    var t = Track(
      id: json['id'],
      name: json['name'],
      type: TrackType.values[json['type']],
      colorValue: json['colorValue'],
    );
    t.isMuted = json['isMuted'];
    t.isSolo = json['isSolo'];
    t.isArmed = json['isArmed'];
    t.volume = (json['volume'] as num).toDouble();
    t.pan = (json['pan'] as num).toDouble();
    t.reverbSend = (json['reverbSend'] as num?)?.toDouble() ?? 0.0;
    t.delaySend = (json['delaySend'] as num?)?.toDouble() ?? 0.0;
    t.reverbPreFader = json['reverbPreFader'] ?? false;
    t.delayPreFader = json['delayPreFader'] ?? false;
    t.noiseGateThreshold =
        (json['noiseGateThreshold'] as num?)?.toDouble() ?? 0.0;
    t.instrumentIndex = json['instrumentIndex'] ?? 0;
    t.midiInputId = json['midiInputId'];
    t.groupTrackId = json['groupTrackId'];
    t.isGroupCollapsed = json['isGroupCollapsed'] ?? false;
    if (json['synthSettings'] != null) {
      t.synthSettings = SynthSettings.fromJson(json['synthSettings']);
    }
    if (json['arpSettings'] != null) {
      t.arpSettings = ArpSettings.fromJson(json['arpSettings']);
    }
    if (json['effectsChain'] != null) {
      t.effectsChain = (json['effectsChain'] as List)
          .map((e) => DawEffect.fromJson(e))
          .toList();
    }
    t.showAutomation = json['showAutomation'] ?? false;
    t.currentAutomationParam = json['currentAutomationParam'] ?? 'Volume';
    if (json['automation'] != null) {
      t.automation = (json['automation'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          k,
          (v as List).map((e) => AutomationPoint.fromJson(e)).toList(),
        ),
      );
    } else {
      t.automation = {'Volume': [], 'Pan': []};
    }
    if (json['samplerPads'] != null) {
      t.samplerPads = (json['samplerPads'] as Map).map(
        (k, v) => MapEntry(int.parse(k), SamplerPad.fromJson(v)),
      );
    }
    try {
      if (SoLoud.instance.isInitialized) {
        t.bus = ensureActiveBus(t.bus);
      }
    } catch (_) {}
    return t;
  }
}

