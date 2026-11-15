/// Maps a hardware MIDI CC controller knob/slider (`0xB0`) to a DAW target parameter.
class MidiCcMapping {
  int cc;
  int? channel;
  String trackId; // track ID or '__master__'
  String param; // 'volume', 'pan', 'reverbSend', 'delaySend', 'fx:<idx>:<key>', 'synth:cutoff'
  double minVal;
  double maxVal;

  MidiCcMapping({
    required this.cc,
    this.channel,
    required this.trackId,
    required this.param,
    this.minVal = 0.0,
    this.maxVal = 1.0,
  });

  String get displayLabel => 'CC $cc -> $param';

  double mapMidiValue(int val) {
    final norm = (val.clamp(0, 127)) / 127.0;
    return minVal + norm * (maxVal - minVal);
  }

  Map<String, dynamic> toJson() => {
    'cc': cc,
    'channel': channel,
    'trackId': trackId,
    'param': param,
    'minVal': minVal,
    'maxVal': maxVal,
  };

  factory MidiCcMapping.fromJson(Map<String, dynamic> json) => MidiCcMapping(
    cc: (json['cc'] as num).toInt(),
    channel: (json['channel'] as num?)?.toInt(),
    trackId: json['trackId'] ?? '',
    param: json['param'] ?? 'volume',
    minVal: (json['minVal'] as num?)?.toDouble() ?? 0.0,
    maxVal: (json['maxVal'] as num?)?.toDouble() ?? 1.0,
  );
}

