class SongMarker {
  String id;
  String label;
  double position;
  int colorValue;

  SongMarker({
    required this.id,
    required this.label,
    required this.position,
    this.colorValue = 0xFF00E5FF,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'position': position,
    'colorValue': colorValue,
  };

  factory SongMarker.fromJson(Map<String, dynamic> json) => SongMarker(
    id: json['id'],
    label: json['label'] ?? 'Section',
    position: (json['position'] as num?)?.toDouble() ?? 0.0,
    colorValue: json['colorValue'] ?? 0xFF00E5FF,
  );
}

