import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/song_marker.dart';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/utils/timeline_grid.dart';

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
  final List<SongMarker> markers;
  final List<TempoMarker> tempoMarkers;

  RulerPainter({
    required this.zoomX,
    required this.bpm,
    required this.timeSigTop,
    this.markers = const [],
    this.tempoMarkers = const [],
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
    if (beatW >= 5) {
      int beatNum = 0;
      int measure = 1;
      int beatInMeasure = 0;
      double posPx = 0.0;
      while (posPx < size.width) {
        final double timelinePos = posPx / zoomX;
        final meter = TempoMarker.effectiveMeterAt(
          timelinePos,
          tempoMarkers,
          timeSigTop,
          4,
        );
        final int activeTop = meter.numerator;
        final double localBpm = TempoMarker.effectiveBpmAt(
          timelinePos,
          tempoMarkers,
          bpm.toDouble(),
        );
        final double localBeatW = (100.0 * 60.0 / localBpm * zoomX).clamp(4.0, 2000.0);
        final bool isMeasure = beatInMeasure == 0;
        canvas.drawLine(
          Offset(posPx, isMeasure ? 24 : 32),
          Offset(posPx, 40),
          isMeasure ? thickPaint : thinPaint,
        );
        if (isMeasure) {
          textPainter.text = TextSpan(
            text: '$measure',
            style: TextStyle(color: textMuted, fontSize: 10),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(posPx + 2, 20));
          measure++;
        }
        beatNum++;
        beatInMeasure = (beatInMeasure + 1) % activeTop;
        posPx += localBeatW;
        if (beatNum > 5000) break;
      }
    }

    for (final m in markers) {
      final mx = m.position * zoomX;
      if (mx < 0 || mx > size.width) continue;
      final markerColor = Color(m.colorValue);
      final flagPaint = Paint()..color = markerColor;
      final linePaint = Paint()
        ..color = markerColor.withValues(alpha: 0.75)
        ..strokeWidth = 1.5;

      canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), linePaint);
      textPainter.text = TextSpan(
        text: m.label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      final pillW = textPainter.width + 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx, 2, pillW, 14),
          const Radius.circular(3),
        ),
        flagPaint,
      );
      textPainter.paint(canvas, Offset(mx + 4, 3));
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) =>
      old.zoomX != zoomX ||
      old.bpm != bpm ||
      old.timeSigTop != timeSigTop ||
      old.markers != markers ||
      old.tempoMarkers != tempoMarkers;
}

class MidiEditorRulerPainter extends CustomPainter {
  final double zoomX;
  final int bpm;
  final int timeSigTop;
  final double clipStart;
  final double clipLength;
  final List<SongMarker> markers;
  final List<TempoMarker> tempoMarkers;

  MidiEditorRulerPainter({
    required this.zoomX,
    required this.bpm,
    required this.timeSigTop,
    required this.clipStart,
    required this.clipLength,
    this.markers = const [],
    this.tempoMarkers = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measurePaint = Paint()
      ..color = textMuted
      ..strokeWidth = 1.6;
    final beatPaint = Paint()
      ..color = textFaint
      ..strokeWidth = 1.0;
    final subPaint = Paint()
      ..color = textFaint.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final double visibleUnits = size.width / (zoomX > 0 ? zoomX : 1.0);
    final lines = buildTimelineGridLines(
      clipStart: clipStart,
      visibleUnits: visibleUnits,
      zoomX: zoomX,
      baseBpm: bpm,
      baseTimeSigTop: timeSigTop,
      tempoMarkers: tempoMarkers,
    );

    final double beatPx = (100.0 * 60.0 / bpm) * zoomX;
    for (final line in lines) {
      final double x = line.localPos * zoomX;
      if (x < -1 || x > size.width + 1) continue;
      if (line.isMeasure) {
        canvas.drawLine(Offset(x, 6), Offset(x, size.height), measurePaint);
        textPainter.text = TextSpan(
          text: '${line.measureNumber}',
          style: TextStyle(
            color: textMain,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 3, 2));
      } else if (line.isBeat) {
        canvas.drawLine(Offset(x, 15), Offset(x, size.height), beatPaint);
        if (beatPx >= 48.0) {
          textPainter.text = TextSpan(
            text: '${line.measureNumber}.${line.beatInMeasure + 1}',
            style: TextStyle(color: textMuted, fontSize: 9),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x + 3, 12));
        }
      } else {
        final bool isMajorSub =
            line.subdivisionsPerBeat >= 8 && line.subIndex.isEven;
        canvas.drawLine(
          Offset(x, isMajorSub ? 20 : 23),
          Offset(x, size.height),
          subPaint,
        );
      }
    }

    // Highlight active clip end boundary on the ruler
    final double endX = clipLength * zoomX;
    if (endX >= 0 && endX <= size.width) {
      canvas.drawLine(
        Offset(endX, 0),
        Offset(endX, size.height),
        Paint()
          ..color = lavenderAccent
          ..strokeWidth = 2.0,
      );
    }

    for (final tm in tempoMarkers) {
      final double tx = (tm.position - clipStart) * zoomX;
      if (tx < -40 || tx > size.width + 40) continue;
      final label = '${tm.bpm.round()} · ${tm.numerator}/${tm.denominator}';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      final double w = textPainter.width + 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(tx, 14, w, 12),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.cyanAccent.withValues(alpha: 0.9),
      );
      textPainter.paint(canvas, Offset(tx + 4, 14.5));
    }

    for (final m in markers) {
      final double mx = (m.position - clipStart) * zoomX;
      if (mx < -40 || mx > size.width + 40) continue;
      final markerColor = Color(m.colorValue);
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, size.height),
        Paint()
          ..color = markerColor
          ..strokeWidth = 1.5,
      );
      textPainter.text = TextSpan(
        text: m.label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      final pillW = textPainter.width + 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx, 1, pillW, 13),
          const Radius.circular(3),
        ),
        Paint()..color = markerColor,
      );
      textPainter.paint(canvas, Offset(mx + 4, 2));
    }
  }

  @override
  bool shouldRepaint(covariant MidiEditorRulerPainter old) =>
      old.zoomX != zoomX ||
      old.bpm != bpm ||
      old.timeSigTop != timeSigTop ||
      old.clipStart != clipStart ||
      old.clipLength != clipLength ||
      old.markers != markers ||
      old.tempoMarkers != tempoMarkers;
}

class GridPainter extends CustomPainter {
  final double pitchHeight;
  final double beatWidth;
  final int timeSigTop;
  final double zoomX;
  final int bpm;
  final double clipStart;
  final Set<int>? scalePitchClasses;
  final int? rootPitchClass;
  final bool isSampler;
  final List<SongMarker> markers;
  final List<TempoMarker> tempoMarkers;

  GridPainter({
    required this.pitchHeight,
    required this.beatWidth,
    required this.timeSigTop,
    this.zoomX = 1.0,
    this.bpm = 120,
    this.clipStart = 0.0,
    this.scalePitchClasses,
    this.rootPitchClass,
    this.isSampler = false,
    this.markers = const [],
    this.tempoMarkers = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = textFaint
      ..strokeWidth = 1;
    final subFinePaint = Paint()
      ..color = textFaint.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    final subUltraFinePaint = Paint()
      ..color = textFaint.withValues(alpha: 0.28)
      ..strokeWidth = 0.6;
    final beatLinePaint = Paint()
      ..color = textMuted.withValues(alpha: 0.28)
      ..strokeWidth = 1.2;
    final darkLinePaint = Paint()
      ..color = textMuted.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final measurePaint = Paint()
      ..color = textMuted.withValues(alpha: 0.48)
      ..strokeWidth = 2;

    final int numRows = (size.height / pitchHeight).round();
    for (int row = 0; row < numRows; row++) {
      final double y = row * pitchHeight;
      if (!isSampler && scalePitchClasses != null) {
        final int midiPitch = 127 - row;
        final int pc = midiPitch % 12;
        if (rootPitchClass != null && pc == rootPitchClass) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, pitchHeight),
            Paint()..color = lavenderAccent.withValues(alpha: 0.14),
          );
        } else if (!scalePitchClasses!.contains(pc)) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, pitchHeight),
            Paint()..color = Colors.black.withValues(alpha: 0.28),
          );
        }
      }
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        (!isSampler && (127 - row) % 12 == 0) ? darkLinePaint : linePaint,
      );
    }

    final double safeZoom = zoomX > 0 ? zoomX : 1.0;
    final double visibleUnits = size.width / safeZoom;
    final lines = buildTimelineGridLines(
      clipStart: clipStart,
      visibleUnits: visibleUnits,
      zoomX: safeZoom,
      baseBpm: bpm,
      baseTimeSigTop: timeSigTop,
      tempoMarkers: tempoMarkers,
    );

    for (final line in lines) {
      final double x = line.localPos * safeZoom;
      if (x < -1 || x > size.width + 1) continue;
      if (line.isMeasure) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), measurePaint);
      } else if (line.isBeat) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), beatLinePaint);
      } else {
        final bool isPrimarySub =
            line.subdivisionsPerBeat <= 4 || line.subIndex.isEven;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          isPrimarySub ? subFinePaint : subUltraFinePaint,
        );
      }
    }

    for (final m in markers) {
      final double mx = (m.position - clipStart) * safeZoom;
      if (mx < 0 || mx > size.width) continue;
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, size.height),
        Paint()
          ..color = Color(m.colorValue).withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) =>
      old.beatWidth != beatWidth ||
      old.timeSigTop != timeSigTop ||
      old.zoomX != zoomX ||
      old.bpm != bpm ||
      old.clipStart != clipStart ||
      old.scalePitchClasses != scalePitchClasses ||
      old.rootPitchClass != rootPitchClass ||
      old.isSampler != isSampler ||
      old.markers != markers ||
      old.tempoMarkers != tempoMarkers;
}

class ClipFadePainter extends CustomPainter {
  final double fadeInRatio;
  final double fadeOutRatio;
  final Color accentColor;

  ClipFadePainter({
    required this.fadeInRatio,
    required this.fadeOutRatio,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shadePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    if (fadeInRatio > 0.001) {
      final w = (fadeInRatio.clamp(0.0, 1.0)) * size.width;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..quadraticBezierTo(w * 0.4, size.height * 0.15, 0, size.height)
        ..close();
      canvas.drawPath(path, shadePaint);

      final curve = Path()
        ..moveTo(0, size.height)
        ..quadraticBezierTo(w * 0.4, size.height * 0.15, w, 0);
      canvas.drawPath(curve, strokePaint);
    }

    if (fadeOutRatio > 0.001) {
      final w = (fadeOutRatio.clamp(0.0, 1.0)) * size.width;
      final x0 = size.width - w;
      final path = Path()
        ..moveTo(x0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..quadraticBezierTo(
          x0 + w * 0.6,
          size.height * 0.15,
          x0,
          0,
        )
        ..close();
      canvas.drawPath(path, shadePaint);

      final curve = Path()
        ..moveTo(x0, 0)
        ..quadraticBezierTo(
          x0 + w * 0.6,
          size.height * 0.15,
          size.width,
          size.height,
        );
      canvas.drawPath(curve, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ClipFadePainter old) =>
      old.fadeInRatio != fadeInRatio ||
      old.fadeOutRatio != fadeOutRatio ||
      old.accentColor != accentColor;
}

/// Paints compact MIDI note ribbons inside timeline MidiClip cards plus loop notches.
class MidiClipThumbnailPainter extends CustomPainter {
  final List<MidiNote> notes;
  final double clipLength;
  final double originalLength;
  final double startOffset;
  final Color color;

  MidiClipThumbnailPainter({
    required this.notes,
    required this.clipLength,
    required this.originalLength,
    required this.startOffset,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clipLength <= 0 || size.width <= 4 || size.height <= 4) return;
    if (notes.isNotEmpty) {
      int minP = 127;
      int maxP = 0;
      for (final n in notes) {
        if (n.pitch < minP) minP = n.pitch;
        if (n.pitch > maxP) maxP = n.pitch;
      }
      final span = (maxP - minP).clamp(12, 60);
      final paint = Paint()..color = color.withValues(alpha: 0.9);
      final double cycleLen = originalLength > 10 ? originalLength : clipLength;
      final int numCycles = (clipLength / cycleLen).ceil().clamp(1, 32);

      for (int c = 0; c < numCycles; c++) {
        final cycleStart = c * cycleLen;
        for (final n in notes) {
          final relStart = (n.start - startOffset) + cycleStart;
          if (relStart >= clipLength || relStart + n.length <= 0) continue;
          final x0 = (relStart / clipLength).clamp(0.0, 1.0) * size.width;
          final x1 =
              ((relStart + n.length) / clipLength).clamp(0.0, 1.0) * size.width;
          final normY = 1.0 - ((n.pitch - minP) / span).clamp(0.0, 1.0);
          final y = 4.0 + normY * (size.height - 10.0);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(x0, y, (x1 - x0) < 2.0 ? x0 + 2.0 : x1, y + 3.0),
              const Radius.circular(1),
            ),
            paint,
          );
        }
      }
    }

    // Draw dashed loop boundary notches when stretched/looped past originalLength
    if (originalLength > 10 && clipLength > originalLength + 1.0) {
      final notchPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1.0;
      for (double pos = originalLength; pos < clipLength - 1.0; pos += originalLength) {
        final x = (pos / clipLength) * size.width;
        for (double y = 2; y < size.height - 2; y += 6) {
          canvas.drawLine(Offset(x, y), Offset(x, (y + 3).clamp(0, size.height)), notchPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant MidiClipThumbnailPainter old) =>
      old.notes != notes ||
      old.clipLength != clipLength ||
      old.originalLength != originalLength ||
      old.color != color;
}

/// Paints dashed loop-repeat ticks over AudioClips extended past originalLength.
class LoopNotchesPainter extends CustomPainter {
  final double clipLength;
  final double originalLength;

  LoopNotchesPainter({
    required this.clipLength,
    required this.originalLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalLength <= 10 || clipLength <= originalLength + 1.0) return;
    final notchPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    for (double pos = originalLength; pos < clipLength - 1.0; pos += originalLength) {
      final x = (pos / clipLength) * size.width;
      for (double y = 2; y < size.height - 2; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 3).clamp(0, size.height)), notchPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LoopNotchesPainter old) =>
      old.clipLength != clipLength || old.originalLength != originalLength;
}
