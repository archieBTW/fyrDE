import 'package:flutter/material.dart';
import 'dart:math';
import 'package:fyrdaw/main.dart';

class PanDial extends StatelessWidget {
  final double pan;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  const PanDial({super.key, required this.pan, required this.onChanged, this.onChangeStart});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        onVerticalDragStart: (d) => onChangeStart?.call(),
        onHorizontalDragStart: (d) => onChangeStart?.call(),
        onVerticalDragUpdate: (d) {
          double newVal = (pan - d.delta.dy * 0.02).clamp(-1.0, 1.0);
          onChanged(newVal);
        },
        onHorizontalDragUpdate: (d) {
          double newVal = (pan + d.delta.dx * 0.02).clamp(-1.0, 1.0);
          onChanged(newVal);
        },
        child: CustomPaint(
          size: Size(20, 20),
          painter: DialPainter(value: pan),
        ),
      ),
    );
  }
}

class ValueDial extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;

  const ValueDial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
  });

  @override
  Widget build(BuildContext context) {
    double normalized = ((value - min) / (max - min)) * 2.0 - 1.0;
    return PanDial(
      pan: normalized,
      onChangeStart: onChangeStart,
      onChanged: (v) {
        double denormalized = ((v + 1.0) / 2.0) * (max - min) + min;
        onChanged(denormalized);
      },
    );
  }
}

class DialPainter extends CustomPainter {
  final double value;
  DialPainter({required this.value});
  @override
  void paint(Canvas canvas, Size size) {
    Offset c = Offset(size.width / 2, size.height / 2);
    double r = size.width / 2;
    Paint bg = Paint()
      ..color = textMuted
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, bg);
    Paint arc = Paint()
      ..color = lavenderAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    double startAngle = 3.14 * 0.75;
    double sweepAngle = 3.14 * 1.5;
    double valAngle = (value + 1.0) / 2.0 * sweepAngle;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 2),
      startAngle,
      valAngle,
      false,
      arc,
    );
    Paint knob = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r - 4, knob);
    double currentAngle = startAngle + valAngle;
    double indicatorLength = r - 6;
    Offset indicatorEnd = Offset(
      c.dx + cos(currentAngle) * indicatorLength,
      c.dy + sin(currentAngle) * indicatorLength,
    );
    Paint linePaint = Paint()
      ..color = textMain
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, indicatorEnd, linePaint);
  }

  @override
  bool shouldRepaint(DialPainter old) => old.value != value;
}
