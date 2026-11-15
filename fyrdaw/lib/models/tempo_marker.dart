/// Represents a tempo and/or time-signature change marker on the arrangement timeline.
class TempoMarker {
  String id;
  double position; // timeline coordinate (pixels at zoomX == 1.0, beatWidth == 50)
  double bpm;
  int numerator;
  int denominator;
  bool isRamp; // linearly interpolate BPM up to the next marker

  TempoMarker({
    required this.id,
    required this.position,
    required this.bpm,
    this.numerator = 4,
    this.denominator = 4,
    this.isRamp = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position,
    'bpm': bpm,
    'numerator': numerator,
    'denominator': denominator,
    'isRamp': isRamp,
  };

  factory TempoMarker.fromJson(Map<String, dynamic> json) => TempoMarker(
    id: json['id'] ?? '',
    position: (json['position'] as num).toDouble(),
    bpm: (json['bpm'] as num).toDouble().clamp(20.0, 300.0),
    numerator: (json['numerator'] as num?)?.toInt() ?? 4,
    denominator: (json['denominator'] as num?)?.toInt() ?? 4,
    isRamp: json['isRamp'] ?? false,
  );

  /// Computes effective BPM at [pos] given sorted [markers] and [baseBpm].
  static double effectiveBpmAt(
    double pos,
    List<TempoMarker> markers,
    double baseBpm,
  ) {
    if (markers.isEmpty) return baseBpm;
    final sorted = [...markers]..sort((a, b) => a.position.compareTo(b.position));
    if (pos < sorted.first.position) {
      return baseBpm;
    }
    for (int i = 0; i < sorted.length; i++) {
      final cur = sorted[i];
      final next = (i + 1 < sorted.length) ? sorted[i + 1] : null;
      if (next == null || pos < next.position) {
        if (cur.isRamp && next != null && next.position > cur.position) {
          final t = ((pos - cur.position) / (next.position - cur.position))
              .clamp(0.0, 1.0);
          return cur.bpm + t * (next.bpm - cur.bpm);
        }
        return cur.bpm;
      }
    }
    return sorted.last.bpm;
  }

  /// Computes effective meter (numerator, denominator) active at [pos].
  static ({int numerator, int denominator}) effectiveMeterAt(
    double pos,
    List<TempoMarker> markers,
    int baseNum,
    int baseDen,
  ) {
    if (markers.isEmpty) return (numerator: baseNum, denominator: baseDen);
    int num = baseNum;
    int den = baseDen;
    final sorted = [...markers]..sort((a, b) => a.position.compareTo(b.position));
    for (final m in sorted) {
      if (m.position <= pos + 0.001) {
        num = m.numerator;
        den = m.denominator;
      } else {
        break;
      }
    }
    return (numerator: num, denominator: den);
  }

  /// Converts a timeline delta [timelinePos] -> seconds via piecewise tempo
  /// integration so offline mixdown honors mid-song tempo markers.
  static double timelineToSeconds(
    double timelinePos, {
    required List<TempoMarker> markers,
    required double baseBpm,
    required double beatWidth,
  }) {
    if (timelinePos <= 0.0) return 0.0;
    if (markers.isEmpty) {
      return (timelinePos / beatWidth) * (60.0 / baseBpm);
    }
    // Step integrate across small beat subdivisions for accuracy with ramps & steps
    const double step = 5.0; // 1/10th beat
    double sec = 0.0;
    double p = 0.0;
    while (p < timelinePos) {
      final double dp = (timelinePos - p < step) ? (timelinePos - p) : step;
      final double localBpm = effectiveBpmAt(p + dp * 0.5, markers, baseBpm);
      sec += (dp / beatWidth) * (60.0 / localBpm.clamp(20.0, 300.0));
      p += dp;
    }
    return sec;
  }
}
