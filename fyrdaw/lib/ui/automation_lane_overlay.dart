import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/track.dart';

/// Interactive timeline automation curve overlay with smooth curve tension
/// handles between keyframes, live value tooltips, drag-to-edit, and delete.
class AutomationLaneOverlay extends StatefulWidget {
  final Track track;
  final double laneHeight;
  final double zoomX;
  final double snapResolution;
  final bool snapToGrid;
  final VoidCallback onSaveState;
  final VoidCallback onChanged;

  const AutomationLaneOverlay({
    super.key,
    required this.track,
    required this.laneHeight,
    required this.zoomX,
    required this.snapResolution,
    required this.snapToGrid,
    required this.onSaveState,
    required this.onChanged,
  });

  @override
  State<AutomationLaneOverlay> createState() => _AutomationLaneOverlayState();
}

class _AutomationLaneOverlayState extends State<AutomationLaneOverlay> {
  int? _draggingPointIdx;
  int? _draggingCurveIdx;
  double _curveOrigin = 0.0;
  double _curveStartY = 0.0;
  int? _activeInfoIdx;

  List<AutomationPoint> get _points =>
      widget.track.automation[widget.track.currentAutomationParam] ?? [];

  List<AutomationPoint> _ensurePoints() {
    return widget.track.automation.putIfAbsent(
      widget.track.currentAutomationParam,
      () => [],
    );
  }

  String _formatValue(double v) {
    final p = widget.track.currentAutomationParam;
    if (p == 'Volume') {
      if (v <= 0.005) return '-∞ dB';
      final db = 20.0 * (log(v * 1.25) / ln10);
      return '${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)} dB';
    }
    if (p == 'Pan') {
      final pan = (v * 2.0) - 1.0;
      if (pan.abs() < 0.03) return 'Center';
      return pan < 0
          ? '${(pan.abs() * 100).round()}% L'
          : '${(pan * 100).round()}% R';
    }
    if (p == 'Synth Cutoff') {
      final hz = 100.0 * pow(180.0, v.clamp(0.0, 1.0));
      return hz >= 1000
          ? '${(hz / 1000).toStringAsFixed(1)} kHz'
          : '${hz.round()} Hz';
    }
    return '${(v * 100).round()}%';
  }

  ({int? pointIdx, int? curveIdx}) _hitTest(Offset pos) {
    final pts = _points;
    for (int i = 0; i < pts.length; i++) {
      final px = pts[i].time * widget.zoomX;
      final py = (1.0 - pts[i].value) * widget.laneHeight;
      if ((Offset(px, py) - pos).distance <= 14.0) {
        return (pointIdx: i, curveIdx: null);
      }
    }
    // Check midpoint curve-tension handle on each segment
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final midT = (a.time + b.time) * 0.5;
      final midVal = widget.track.getInterpolatedAutomation(
        widget.track.currentAutomationParam,
        midT,
      );
      final mx = midT * widget.zoomX;
      final my = (1.0 - midVal) * widget.laneHeight;
      if ((Offset(mx, my) - pos).distance <= 13.0) {
        return (pointIdx: null, curveIdx: i);
      }
    }
    return (pointIdx: null, curveIdx: null);
  }

  void _removePointAt(int idx) {
    final pts = _points;
    if (idx < 0 || idx >= pts.length) return;
    widget.onSaveState();
    pts.removeAt(idx);
    _activeInfoIdx = null;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    return GestureDetector(
      key: Key('automation_overlay_${widget.track.id}'),
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit.pointIdx != null) {
          _removePointAt(hit.pointIdx!);
        } else if (hit.curveIdx != null) {
          widget.onSaveState();
          pts[hit.curveIdx!].curve = 0.0;
          widget.onChanged();
        }
      },
      onDoubleTapDown: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit.pointIdx != null) {
          _removePointAt(hit.pointIdx!);
        }
      },
      onTapDown: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit.pointIdx != null || hit.curveIdx != null) {
          setState(() => _activeInfoIdx = hit.pointIdx);
          return;
        }
        widget.onSaveState();
        double time = max(0.0, d.localPosition.dx / widget.zoomX);
        if (widget.snapToGrid && widget.snapResolution > 0) {
          time = (time / widget.snapResolution).round() * widget.snapResolution;
        }
        final double val = (1.0 - (d.localPosition.dy / widget.laneHeight))
            .clamp(0.0, 1.0);
        final list = _ensurePoints();
        list.add(AutomationPoint(time, val));
        list.sort((a, b) => a.time.compareTo(b.time));
        setState(() {
          _activeInfoIdx = list.indexWhere((p) => p.time == time && p.value == val);
        });
        widget.onChanged();
      },
      onPanStart: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit.pointIdx != null) {
          widget.onSaveState();
          setState(() {
            _draggingPointIdx = hit.pointIdx;
            _activeInfoIdx = hit.pointIdx;
          });
        } else if (hit.curveIdx != null) {
          widget.onSaveState();
          setState(() {
            _draggingCurveIdx = hit.curveIdx;
            _curveOrigin = pts[hit.curveIdx!].curve;
            _curveStartY = d.localPosition.dy;
          });
        }
      },
      onPanUpdate: (d) {
        if (_draggingPointIdx != null && _draggingPointIdx! < pts.length) {
          final p = pts[_draggingPointIdx!];
          double newTime = max(0.0, d.localPosition.dx / widget.zoomX);
          if (widget.snapToGrid && widget.snapResolution > 0) {
            newTime =
                (newTime / widget.snapResolution).round() * widget.snapResolution;
          }
          p.time = newTime;
          p.value = (1.0 - (d.localPosition.dy / widget.laneHeight)).clamp(
            0.0,
            1.0,
          );
          pts.sort((a, b) => a.time.compareTo(b.time));
          _draggingPointIdx = pts.indexOf(p);
          _activeInfoIdx = _draggingPointIdx;
          widget.onChanged();
        } else if (_draggingCurveIdx != null &&
            _draggingCurveIdx! < pts.length - 1) {
          final deltaY = _curveStartY - d.localPosition.dy;
          final a = pts[_draggingCurveIdx!];
          final b = pts[_draggingCurveIdx! + 1];
          final dir = b.value >= a.value ? 1.0 : -1.0;
          a.curve = (_curveOrigin + (deltaY / 50.0) * dir).clamp(-1.0, 1.0);
          widget.onChanged();
        }
      },
      onPanEnd: (_) => setState(() {
        _draggingPointIdx = null;
        _draggingCurveIdx = null;
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AutomationCurvePainter(
                track: widget.track,
                zoomX: widget.zoomX,
                laneHeight: widget.laneHeight,
                activeIndex: _activeInfoIdx,
              ),
            ),
          ),
          if (_activeInfoIdx != null &&
              _activeInfoIdx! >= 0 &&
              _activeInfoIdx! < pts.length)
            Positioned(
              left: max(
                4.0,
                pts[_activeInfoIdx!].time * widget.zoomX + 8.0,
              ),
              top: ((1.0 - pts[_activeInfoIdx!].value) * widget.laneHeight - 20)
                  .clamp(2.0, max(2.0, widget.laneHeight - 22)),
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: widget.track.color),
                  ),
                  child: Text(
                    _formatValue(pts[_activeInfoIdx!].value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AutomationCurvePainter extends CustomPainter {
  final Track track;
  final double zoomX;
  final double laneHeight;
  final int? activeIndex;

  _AutomationCurvePainter({
    required this.track,
    required this.zoomX,
    required this.laneHeight,
    required this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = track.automation[track.currentAutomationParam] ?? [];
    final h = laneHeight;
    final col = track.color;

    // Reference lines (25%, 50%, 75%)
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    for (final frac in [0.25, 0.5, 0.75]) {
      final y = h * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }

    if (pts.isEmpty) return;

    final linePath = Path();
    final fillPath = Path();

    final double firstX = pts.first.time * zoomX;
    final double firstY = (1.0 - pts.first.value) * h;
    linePath.moveTo(0, firstY);
    linePath.lineTo(firstX, firstY);
    fillPath.moveTo(0, h);
    fillPath.lineTo(0, firstY);
    fillPath.lineTo(firstX, firstY);

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      if (a.curve.abs() < 0.01) {
        final bx = b.time * zoomX;
        final by = (1.0 - b.value) * h;
        linePath.lineTo(bx, by);
        fillPath.lineTo(bx, by);
      } else {
        const steps = 16;
        for (int s = 1; s <= steps; s++) {
          final t = a.time + ((b.time - a.time) * (s / steps));
          final val = track.getInterpolatedAutomation(
            track.currentAutomationParam,
            t,
          );
          final px = t * zoomX;
          final py = (1.0 - val) * h;
          linePath.lineTo(px, py);
          fillPath.lineTo(px, py);
        }
      }
    }

    final double lastY = (1.0 - pts.last.value) * h;
    linePath.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, h);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = col.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = col
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Draw curve-tension diamond handles between adjacent points
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      if ((b.time - a.time) * zoomX < 28) continue;
      final midT = (a.time + b.time) * 0.5;
      final midVal = track.getInterpolatedAutomation(
        track.currentAutomationParam,
        midT,
      );
      final mx = midT * zoomX;
      final my = (1.0 - midVal) * h;
      final diamond = Path()
        ..moveTo(mx, my - 4)
        ..lineTo(mx + 4, my)
        ..lineTo(mx, my + 4)
        ..lineTo(mx - 4, my)
        ..close();
      canvas.drawPath(
        diamond,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    // Draw keyframe nodes
    for (int i = 0; i < pts.length; i++) {
      final px = pts[i].time * zoomX;
      final py = (1.0 - pts[i].value) * h;
      final isActive = i == activeIndex;
      canvas.drawCircle(
        Offset(px, py),
        isActive ? 6.0 : 4.5,
        Paint()..color = isActive ? Colors.white : col,
      );
      canvas.drawCircle(
        Offset(px, py),
        isActive ? 6.0 : 4.5,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AutomationCurvePainter oldDelegate) => true;
}
