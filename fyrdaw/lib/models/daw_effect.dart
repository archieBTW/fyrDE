class DawEffect {
  String name;
  Map<String, double> parameters;
  bool isBypassed;
  String? sidechainTrackId;

  DawEffect(
    this.name,
    this.parameters, {
    this.isBypassed = false,
    this.sidechainTrackId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'parameters': parameters,
    'isBypassed': isBypassed,
    'sidechainTrackId': sidechainTrackId,
  };

  factory DawEffect.fromJson(Map<String, dynamic> json) => DawEffect(
    json['name'],
    Map<String, double>.from(json['parameters']),
    isBypassed: json['isBypassed'] ?? false,
    sidechainTrackId: json['sidechainTrackId'],
  );
}
