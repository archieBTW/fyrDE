
class DawEffect {
  String name;
  Map<String, double> parameters;
  DawEffect(this.name, this.parameters);

  Map<String, dynamic> toJson() => {'name': name, 'parameters': parameters};
  factory DawEffect.fromJson(Map<String, dynamic> json) =>
      DawEffect(json['name'], Map<String, double>.from(json['parameters']));
}

