import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrdaw/main.dart';

class PanDial extends StatefulWidget {
  final double pan;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final double defaultValue;
  final double size;
  final Color? activeColor;
  final String Function(double pan)? formatLabel;

  const PanDial({
    super.key,
    required this.pan,
    required this.onChanged,
    this.onChangeStart,
    this.defaultValue = 0.0,
    this.size = 20.0,
    this.activeColor,
    this.formatLabel,
  });

  @override
  State<PanDial> createState() => _PanDialState();
}

class _PanDialState extends State<PanDial> {
  bool _isDragging = false;

  String _defaultFormat(double v) {
    if (v.abs() < 0.03) return 'C';
    final pct = (v.abs() * 100).round();
    return v < 0 ? 'L$pct' : 'R$pct';
  }

  @override
  Widget build(BuildContext context) {
    final label = (widget.formatLabel ?? _defaultFormat)(widget.pan);
    return Tooltip(
      message: _isDragging ? label : '$label (Double-click to reset, Shift for fine)',
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          onDoubleTap: () {
            widget.onChangeStart?.call();
            widget.onChanged(widget.defaultValue.clamp(-1.0, 1.0));
          },
          onVerticalDragStart: (d) {
            setState(() => _isDragging = true);
            widget.onChangeStart?.call();
          },
          onHorizontalDragStart: (d) {
            setState(() => _isDragging = true);
            widget.onChangeStart?.call();
          },
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragCancel: () => setState(() => _isDragging = false),
          onHorizontalDragCancel: () => setState(() => _isDragging = false),
          onVerticalDragUpdate: (d) {
            final fine = HardwareKeyboard.instance.isShiftPressed ? 0.004 : 0.02;
            double newVal = (widget.pan - d.delta.dy * fine).clamp(-1.0, 1.0);
            widget.onChanged(newVal);
          },
          onHorizontalDragUpdate: (d) {
            final fine = HardwareKeyboard.instance.isShiftPressed ? 0.004 : 0.02;
            double newVal = (widget.pan + d.delta.dx * fine).clamp(-1.0, 1.0);
            widget.onChanged(newVal);
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: DialPainter(
                  value: widget.pan,
                  activeColor: widget.activeColor ?? lavenderAccent,
                ),
              ),
              if (_isDragging)
                Positioned(
                  top: -18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: widget.activeColor ?? lavenderAccent,
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ValueDial extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double? defaultValue;
  final double size;
  final Color? activeColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final String Function(double value)? formatLabel;

  const ValueDial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.defaultValue,
    this.size = 20.0,
    this.activeColor,
    this.onChangeStart,
    this.formatLabel,
  });

  @override
  Widget build(BuildContext context) {
    final span = (max - min) == 0 ? 1.0 : (max - min);
    double normalized = (((value - min) / span) * 2.0 - 1.0).clamp(-1.0, 1.0);
    double defNorm = defaultValue != null
        ? (((defaultValue! - min) / span) * 2.0 - 1.0).clamp(-1.0, 1.0)
        : 0.0;
    return PanDial(
      pan: normalized,
      defaultValue: defNorm,
      size: size,
      activeColor: activeColor,
      onChangeStart: onChangeStart,
      formatLabel: (norm) {
        final actual = ((norm + 1.0) / 2.0) * span + min;
        if (formatLabel != null) return formatLabel!(actual);
        if (max <= 1.0 && min >= 0.0) return '${(actual * 100).round()}%';
        return actual.toStringAsFixed(2);
      },
      onChanged: (v) {
        double denormalized = ((v + 1.0) / 2.0) * span + min;
        onChanged(denormalized.clamp(min, max));
      },
    );
  }
}

class DialPainter extends CustomPainter {
  final double value;
  final Color activeColor;

  DialPainter({required this.value, Color? activeColor})
    : activeColor = activeColor ?? lavenderAccent;

  @override
  void paint(Canvas canvas, Size size) {
    Offset c = Offset(size.width / 2, size.height / 2);
    double r = size.width / 2;
    Paint bg = Paint()
      ..color = textMuted.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, bg);
    Paint trackArc = Paint()
      ..color = textFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    double startAngle = pi * 0.75;
    double sweepAngle = pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 2),
      startAngle,
      sweepAngle,
      false,
      trackArc,
    );

    Paint arc = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    double valAngle = ((value + 1.0) / 2.0).clamp(0.0, 1.0) * sweepAngle;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 2),
      startAngle,
      valAngle,
      false,
      arc,
    );
    Paint knob = Paint()
      ..color = const Color(0xFF2B2B33)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, max(2.0, r - 4), knob);
    double currentAngle = startAngle + valAngle;
    double indicatorLength = max(2.0, r - 5.5);
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
  bool shouldRepaint(DialPainter old) =>
      old.value != value || old.activeColor != activeColor;
}
