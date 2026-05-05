
class MidiNote {
  int pitch;
  double start;
  double length;
  int velocity;

  MidiNote({
    required this.pitch,
    required this.start,
    required this.length,
    this.velocity = 100,
  });
  Map<String, dynamic> toJson() => {
    'pitch': pitch,
    'start': start,
    'length': length,
    'velocity': velocity,
  };
  factory MidiNote.fromJson(Map<String, dynamic> json) => MidiNote(
    pitch: json['pitch'],
    start: json['start'],
    length: json['length'],
    velocity: json['velocity'] ?? 100,
  );
}

