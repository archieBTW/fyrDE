import 'dart:math';

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

/// Pure, isolate-safe interpolation over sorted [AutomationPoint] keyframes.
/// Returns `-1.0` when [points] is null or empty.
double interpolateAutomationPoints(
  List<AutomationPoint>? points,
  double currentPos,
) {
  if (points == null || points.isEmpty) return -1.0;
  if (currentPos <= points.first.time) return points.first.value;
  if (currentPos >= points.last.time) return points.last.value;
  for (int i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
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
