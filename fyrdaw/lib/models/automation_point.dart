class AutomationPoint {
  double time;
  double value;

  /// Curve tension between this point and the next point (-1.0..1.0).
  /// 0.0 is linear; positive bends fast early, negative eases slowly early.
  double curve;

  AutomationPoint(this.time, this.value, {this.curve = 0.0});

  Map<String, dynamic> toJson() => {
    'time': time,
    'value': value,
    if (curve != 0.0) 'curve': curve,
  };

  factory AutomationPoint.fromJson(Map<String, dynamic> json) =>
      AutomationPoint(
        (json['time'] as num).toDouble(),
        (json['value'] as num).toDouble(),
        curve: (json['curve'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? 0.0,
      );
}
