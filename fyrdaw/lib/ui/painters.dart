import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/automation_point.dart';

class AutomationPainter extends CustomPainter {
  final List<AutomationPoint> points;
  final double zoomX;
  AutomationPainter({required this.points, required this.zoomX});
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = Colors.cyanAccent.withAlpha(50)
      ..style = PaintingStyle.fill;
    final pointPaint = Paint()
      ..color = textMain
      ..style = PaintingStyle.fill;

    Path path = Path();
    path.moveTo(0, (1.0 - points.first.value) * size.height);

    for (int i = 0; i < points.length; i++) {
      double px = points[i].time * zoomX;
      double py = (1.0 - points[i].value) * size.height;
      if (i == 0) {
        path.moveTo(0, py);
        path.lineTo(px, py);
      } else {
        path.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 4, pointPaint);
    }
    path.lineTo(size.width, (1.0 - points.last.value) * size.height);
    canvas.drawPath(path, paint);

    Path fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(AutomationPainter old) => true;
}

class RulerPainter extends CustomPainter {
  final double zoomX;
  final int bpm;
  final int timeSigTop;
  RulerPainter({
    required this.zoomX,
    required this.bpm,
    required this.timeSigTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final thickPaint = Paint()
      ..color = textMuted
      ..strokeWidth = 2;
    final thinPaint = Paint()
      ..color = textFaint
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    double beatW = 100.0 * 60.0 / bpm * zoomX;
    if (beatW < 5) return;
    for (double i = 0; i < size.width; i += beatW) {
      int beatNum = (i / beatW).round();
      bool isMeasure = beatNum % timeSigTop == 0;
      canvas.drawLine(
        Offset(i, isMeasure ? 24 : 32),
        Offset(i, 40),
        isMeasure ? thickPaint : thinPaint,
      );
      if (isMeasure) {
        int measure = beatNum ~/ timeSigTop + 1;
        textPainter.text = TextSpan(
          text: '$measure',
          style: TextStyle(color: textMuted, fontSize: 10),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(i + 2, 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) =>
      old.zoomX != zoomX || old.bpm != bpm || old.timeSigTop != timeSigTop;
}

class GridPainter extends CustomPainter {
  final double pitchHeight;
  final double beatWidth;
  final int timeSigTop;

  GridPainter({
    required this.pitchHeight,
    required this.beatWidth,
    required this.timeSigTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = textFaint
      ..strokeWidth = 1;
    final darkLinePaint = Paint()
      ..color = textFaint
      ..strokeWidth = 1;
    final measurePaint = Paint()
      ..color = textFaint
      ..strokeWidth = 2;

    for (double i = 0; i < size.height; i += pitchHeight) {
      canvas.drawLine(
        Offset(0, i),
        Offset(size.width, i),
        i % (pitchHeight * 12) == 0 ? darkLinePaint : linePaint,
      );
    }
    if (beatWidth < 5) return;
    for (double i = 0; i < size.width; i += beatWidth) {
      int beatNum = (i / beatWidth).round();
      bool isMeasure = beatNum % timeSigTop == 0;
      canvas.drawLine(
        Offset(i, 0),
        Offset(i, size.height),
        isMeasure ? measurePaint : linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) =>
      old.beatWidth != beatWidth || old.timeSigTop != timeSigTop;
}

