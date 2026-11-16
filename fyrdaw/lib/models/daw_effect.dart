class DawEffect {
  String name;
  Map<String, double> parameters;
  bool isBypassed;
  String? sidechainTrackId;

  /// Optional external plugin hosting metadata ('LV2' or 'VST3') + URI/path.
  String? pluginFormat;
  String? pluginUri;

  DawEffect(
    this.name,
    this.parameters, {
    this.isBypassed = false,
    this.sidechainTrackId,
    this.pluginFormat,
    this.pluginUri,
  });

  bool get isExternalPlugin => pluginFormat != null && pluginUri != null;

  Map<String, dynamic> toJson() => {
    'name': name,
    'parameters': parameters,
    'isBypassed': isBypassed,
    'sidechainTrackId': sidechainTrackId,
    if (pluginFormat != null) 'pluginFormat': pluginFormat,
    if (pluginUri != null) 'pluginUri': pluginUri,
  };

  factory DawEffect.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String;
    final normalizedName = rawName == 'TubeScreamer' ? 'Overdrive' : rawName;
    return DawEffect(
      normalizedName,
      Map<String, double>.from(
        (json['parameters'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      ),
      isBypassed: json['isBypassed'] ?? false,
      sidechainTrackId: json['sidechainTrackId'],
      pluginFormat: json['pluginFormat'],
      pluginUri: json['pluginUri'],
    );
  }
}
