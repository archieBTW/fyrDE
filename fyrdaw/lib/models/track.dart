import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/sampler_pad.dart';

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
  int instrumentIndex = 0;
  String? midiInputId;
  List<DawEffect> effectsChain = [];
  AudioSource? synthSource;
  String? synthSourcePath;
  List<SoundHandle> activeMidiHandles = [];
  bool showAutomation = false;
  String currentAutomationParam = 'Volume';
  Map<String, List<AutomationPoint>> automation = {'Volume': [], 'Pan': []};
  Map<int, SamplerPad> samplerPads = {};

  Bus? bus;

  Track({required this.id, required this.name, required this.type}) {
    if (type == TrackType.sampler) {
      for (int i = 0; i < 16; i++) {
        samplerPads[i] = SamplerPad()..midiNote = 36 + i;
      }
    }
  }

  double getInterpolatedAutomation(String param, double currentPos) {
    var list = automation[param];
    if (list == null || list.isEmpty) return -1.0;
    if (currentPos <= list.first.time) return list.first.value;
    if (currentPos >= list.last.time) return list.last.value;
    for (int i = 0; i < list.length - 1; i++) {
      if (currentPos >= list[i].time && currentPos <= list[i + 1].time) {
        double t =
            (currentPos - list[i].time) / (list[i + 1].time - list[i].time);
        return list[i].value + t * (list[i + 1].value - list[i].value);
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
    'instrumentIndex': instrumentIndex,
    'midiInputId': midiInputId,
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
    );
    t.isMuted = json['isMuted'];
    t.isSolo = json['isSolo'];
    t.isArmed = json['isArmed'];
    t.volume = json['volume'];
    t.pan = json['pan'];
    t.instrumentIndex = json['instrumentIndex'] ?? 0;
    t.midiInputId = json['midiInputId'];
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
    t.bus = Bus();
    t.bus!.playOnEngine();
    return t;
  }
}

