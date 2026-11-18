import 'package:flutter/material.dart';

/// Number of samples kept by the performance charts.
///
/// 40 samples × 1.5 s polling = the 60 second scrolling window Task Manager
/// style charts show.
const int kChartSamples = 40;

/// One drawn line (plus its filled area) inside a [SmoothAreaChart].
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;

  /// Oldest first; the newest value is pinned to the right edge of the chart.
  final List<double> values;
}

/// A 60 second, smoothly interpolated area chart drawn with a [CustomPainter].
///
/// No chart package is used: the whole widget is a single `CustomPaint`, which
/// keeps the per-frame cost negligible while the chart is scrolling.
class SmoothAreaChart extends StatelessWidget {
  const SmoothAreaChart({
    super.key,
    required this.series,
    required this.maxValue,
    this.height = 132,
    this.gridLines = 4,
    this.showGrid = true,
    this.strokeWidth = 2,
    this.fillOpacity = 0.32,
  });

  final List<ChartSeries> series;

  /// Fixed or auto-scaled ceiling. Values are clamped into `0..maxValue`.
  final double maxValue;
  final double height;
  final int gridLines;
  final bool showGrid;
  final double strokeWidth;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SmoothAreaChartPainter(
            series: series,
            maxValue: maxValue,
            gridLines: gridLines,
            dividerColor: divider,
            showGrid: showGrid,
            strokeWidth: strokeWidth,
            fillOpacity: fillOpacity,
          ),
        ),
      ),
    );
  }
}

class _SmoothAreaChartPainter extends CustomPainter {
  _SmoothAreaChartPainter({
    required this.series,
    required this.maxValue,
    required this.gridLines,
    required this.dividerColor,
    required this.showGrid,
    required this.strokeWidth,
    required this.fillOpacity,
  });

  final List<ChartSeries> series;
  final double maxValue;
  final int gridLines;
  final Color dividerColor;
  final bool showGrid;
  final double strokeWidth;
  final double fillOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (showGrid) _paintGrid(canvas, size);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final line in series) {
      _paintSeries(canvas, size, line);
    }
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dividerColor
      ..strokeWidth = 1;
    for (var i = 0; i <= gridLines; i++) {
      final y = size.height * (i / gridLines);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintSeries(Canvas canvas, Size size, ChartSeries line) {
    final values = line.values;
    if (values.isEmpty) return;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(
        Offset(
          _x(index: i, length: values.length, width: size.width),
          _y(value: values[i], height: size.height),
        ),
      );
    }

    final stroke = _smoothPath(points);
    final fill = Path.from(stroke)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          line.color.withValues(alpha: fillOpacity),
          line.color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line.color;
    canvas.drawPath(stroke, strokePaint);
  }

  /// Newest sample sits on the right edge, so a partially filled chart scrolls
  /// in from the right instead of stretching across the whole width.
  double _x({required int index, required int length, required double width}) {
    const capacity = kChartSamples;
    final step = width / (capacity - 1);
    return width - (length - 1 - index) * step;
  }

  double _y({required double value, required double height}) {
    final ceiling = maxValue <= 0 ? 1.0 : maxValue;
    final normalized = (value / ceiling).clamp(0.0, 1.0);
    return height - normalized * height;
  }

  /// Catmull-Rom spline converted into cubic bezier segments: cheap to compute
  /// and smooth enough to hide the 1.5 s sampling interval.
  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _SmoothAreaChartPainter oldDelegate) {
    return oldDelegate.maxValue != maxValue ||
        oldDelegate.series.length != series.length ||
        !identical(oldDelegate.series, series) ||
        oldDelegate.dividerColor != dividerColor ||
        oldDelegate.showGrid != showGrid;
  }
}
