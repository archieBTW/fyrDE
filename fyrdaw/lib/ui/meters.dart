import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_effect.dart';

/// Segmented stereo L/R LED VU meter with peak-hold indicator.
class SegmentedVuMeter extends StatelessWidget {
  final double leftLevel;
  final double rightLevel;
  final double leftPeak;
  final double rightPeak;
  final double width;
  final double height;
  final int segments;

  const SegmentedVuMeter({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    this.leftPeak = 0.0,
    this.rightPeak = 0.0,
    this.width = 16.0,
    this.height = 120.0,
    this.segments = 16,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _VuMeterPainter(
        leftLevel: leftLevel,
        rightLevel: rightLevel,
        leftPeak: leftPeak,
        rightPeak: rightPeak,
        segments: segments,
      ),
    );
  }
}

class _VuMeterPainter extends CustomPainter {
  final double leftLevel;
  final double rightLevel;
  final double leftPeak;
  final double rightPeak;
  final int segments;

  _VuMeterPainter({
    required this.leftLevel,
    required this.rightLevel,
    required this.leftPeak,
    required this.rightPeak,
    required this.segments,
  });

  Color _segmentColor(int idxFromBottom) {
    final ratio = (idxFromBottom + 1) / segments;
    if (ratio >= 0.88) return const Color(0xFFFF4B4B);
    if (ratio >= 0.68) return const Color(0xFFFBBF24);
    return const Color(0xFF34D399);
  }

  void _drawChannel(
    Canvas canvas,
    double x,
    double chWidth,
    double height,
    double level,
    double peak,
  ) {
    const gap = 1.5;
    final segH = (height - (segments - 1) * gap) / segments;
    if (segH <= 0) return;

    final clamped = level.clamp(0.0, 1.0);
    final litCount = (clamped * segments).ceil();
    final peakIdx = (peak.clamp(0.0, 1.0) * (segments - 1)).round();

    for (int i = 0; i < segments; i++) {
      final y = height - (i + 1) * segH - i * gap;
      final isLit = i < litCount;
      final isPeak = peak > 0.02 && i == peakIdx;
      final baseColor = _segmentColor(i);
      final paint = Paint()
        ..color = (isLit || isPeak)
            ? baseColor
            : baseColor.withValues(alpha: 0.14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, chWidth, segH),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chW = (size.width - 2) / 2;
    if (chW <= 0) return;
    _drawChannel(canvas, 0, chW, size.height, leftLevel, leftPeak);
    _drawChannel(canvas, chW + 2, chW, size.height, rightLevel, rightPeak);
  }

  @override
  bool shouldRepaint(covariant _VuMeterPainter old) =>
      old.leftLevel != leftLevel ||
      old.rightLevel != rightLevel ||
      old.leftPeak != leftPeak ||
      old.rightPeak != rightPeak;
}

/// Real-time Master FFT spectrum + waveform oscilloscope widget.
class MasterSpectrumWidget extends StatelessWidget {
  final Float32List? samples;
  final double width;
  final double height;
  final Color? accentColor;
  final bool showWaveform;

  const MasterSpectrumWidget({
    super.key,
    required this.samples,
    this.width = 128,
    this.height = 28,
    this.accentColor,
    this.showWaveform = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderMain),
      ),
      child: CustomPaint(
        painter: _SpectrumPainter(
          samples: samples,
          accentColor: accentColor ?? lavenderAccent,
          showWaveform: showWaveform,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final Float32List? samples;
  final Color accentColor;
  final bool showWaveform;

  _SpectrumPainter({
    required this.samples,
    required this.accentColor,
    required this.showWaveform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int barCount = 24;
    final barW = (size.width - (barCount - 1) * 1.5) / barCount;

    for (int i = 0; i < barCount; i++) {
      double mag = 0.0;
      if (samples != null && samples!.length >= 256) {
        // Log-ish frequency bin mapping across first 140 FFT bins
        final startBin = (pow(i / barCount, 1.6) * 120).floor().clamp(0, 255);
        final endBin = (pow((i + 1) / barCount, 1.6) * 120)
            .ceil()
            .clamp(startBin + 1, 256);
        double peak = 0.0;
        for (int b = startBin; b < endBin; b++) {
          if (samples![b] > peak) peak = samples![b];
        }
        mag = (peak * 1.35).clamp(0.0, 1.0);
      }

      final barH = max(1.5, mag * size.height);
      final x = i * (barW + 1.5);
      final color = mag > 0.85
          ? const Color(0xFFFF4B4B)
          : Color.lerp(accentColor, Colors.cyanAccent, i / barCount)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, barW, barH),
          const Radius.circular(1),
        ),
        Paint()..color = color.withValues(alpha: mag > 0.02 ? 0.9 : 0.2),
      );
    }

    if (showWaveform && samples != null && samples!.length >= 512) {
      final wavePath = Path();
      final midY = size.height * 0.5;
      for (int i = 0; i < 64; i++) {
        final s = samples![256 + i * 4].clamp(-1.0, 1.0);
        final x = (i / 63) * size.width;
        final y = midY + s * (size.height * 0.42);
        if (i == 0) {
          wavePath.moveTo(x, y);
        } else {
          wavePath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        wavePath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => true;
}

/// Compact live-reactive visualizer embedded inside stompbox effect pedals.
/// When [effect.name] == 'EQ' and [onParamChanged] is supplied, dragging left/mid/right
/// frequency zones interactively shapes Low/Mid/High gain.
class PedalVisualizerWidget extends StatelessWidget {
  final DawEffect effect;
  final double activityLevel;
  final double gainReduction;
  final double height;
  final void Function(String paramKey, double val)? onParamChanged;

  const PedalVisualizerWidget({
    super.key,
    required this.effect,
    this.activityLevel = 0.0,
    this.gainReduction = 0.0,
    this.height = 30.0,
    this.onParamChanged,
  });

  void _handleEqDrag(Offset localPos, double width) {
    if (effect.name != 'EQ' || onParamChanged == null || width <= 0) return;
    final normX = (localPos.dx / width).clamp(0.0, 1.0);
    final normVal = (1.0 - (localPos.dy / height)).clamp(0.0, 1.0);
    if (normX < 0.34) {
      onParamChanged!('Low', normVal);
    } else if (normX < 0.67) {
      onParamChanged!('Mid', normVal);
    } else {
      onParamChanged!('High', normVal);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
        final child = Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: CustomPaint(
            size: Size(double.infinity, height),
            painter: _PedalVizPainter(
              effect: effect,
              activityLevel: activityLevel,
              gainReduction: gainReduction,
              showEqHandles: onParamChanged != null,
            ),
          ),
        );
        if (effect.name == 'EQ' && onParamChanged != null) {
          return GestureDetector(
            onPanDown: (d) => _handleEqDrag(d.localPosition, w - 16),
            onPanUpdate: (d) => _handleEqDrag(d.localPosition, w - 16),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: child,
            ),
          );
        }
        return child;
      },
    );
  }
}

class _PedalVizPainter extends CustomPainter {
  final DawEffect effect;
  final double activityLevel;
  final double gainReduction;
  final bool showEqHandles;

  _PedalVizPainter({
    required this.effect,
    required this.activityLevel,
    required this.gainReduction,
    this.showEqHandles = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activeAlpha = effect.isBypassed ? 0.35 : 0.95;
    final midY = size.height * 0.5;

    // Subtle baseline
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()..color = Colors.white12,
    );

    if (effect.name == 'EQ') {
      final low = (effect.parameters['Low'] ?? 0.5) - 0.5;
      final mid = (effect.parameters['Mid'] ?? 0.5) - 0.5;
      final high = (effect.parameters['High'] ?? 0.5) - 0.5;
      final path = Path();
      for (int i = 0; i <= 32; i++) {
        final t = i / 32.0;
        final wLow = exp(-pow((t - 0.15) / 0.22, 2));
        final wMid = exp(-pow((t - 0.50) / 0.24, 2));
        final wHigh = exp(-pow((t - 0.85) / 0.22, 2));
        final gainOffset = low * wLow + mid * wMid + high * wHigh;
        final y = (midY - gainOffset * size.height * 0.85).clamp(2.0, size.height - 2.0);
        final x = t * size.width;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.lightBlueAccent.withValues(alpha: activeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      if (showEqHandles) {
        for (final h in [
          (0.15, effect.parameters['Low'] ?? 0.5),
          (0.50, effect.parameters['Mid'] ?? 0.5),
          (0.85, effect.parameters['High'] ?? 0.5),
        ]) {
          final hx = h.$1 * size.width;
          final hy = (1.0 - h.$2).clamp(0.05, 0.95) * size.height;
          canvas.drawCircle(
            Offset(hx, hy),
            3.2,
            Paint()..color = Colors.white.withValues(alpha: activeAlpha),
          );
        }
      }
    } else if (effect.name == 'Compressor') {
      final thresh = (effect.parameters['Thresh'] ?? 0.5);
      final ratio = (effect.parameters['Ratio'] ?? 0.5);
      final kneeX = (1.0 - thresh * 0.75) * size.width;
      final kneeY = size.height - (1.0 - thresh * 0.75) * size.height;
      final slope = 1.0 / (1.0 + ratio * 6.0);
      final endY = kneeY - (size.width - kneeX) * (size.height / size.width) * slope;

      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(kneeX, kneeY)
        ..lineTo(size.width, endY.clamp(2.0, size.height - 2.0));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.greenAccent.withValues(alpha: activeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // Gain reduction bar on right (real-time sidechain + signal GR)
      final gr = effect.isBypassed
          ? 0.0
          : max(
              gainReduction,
              activityLevel * (0.3 + thresh * 0.7) * (0.2 + ratio * 0.8),
            ).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(size.width - 6, 2, 4, gr * (size.height - 4)),
        Paint()..color = Colors.amberAccent.withValues(alpha: activeAlpha),
      );
    } else if (effect.name == 'Reverb' || effect.name == 'Echo') {
      final decay = effect.parameters['Decay'] ?? 0.5;
      final mix = effect.parameters['Mix'] ?? 0.5;
      final taps = effect.name == 'Echo' ? 6 : 12;
      for (int i = 0; i < taps; i++) {
        final t = i / (taps - 1);
        final amp = pow(0.25 + decay * 0.65, i) * (0.3 + mix * 0.7);
        final h = max(2.0, amp * (size.height - 6));
        final x = 6 + t * (size.width - 14);
        canvas.drawLine(
          Offset(x, size.height - 3),
          Offset(x, size.height - 3 - h),
          Paint()
            ..color = Colors.purpleAccent.withValues(alpha: activeAlpha)
            ..strokeWidth = effect.name == 'Echo' ? 2.5 : 1.5,
        );
      }
    } else {
      // Nonlinear drive / modulation transfer wave
      final drive = effect.parameters['Drive'] ??
          effect.parameters['Boost'] ??
          effect.parameters['Rate'] ??
          0.5;
      final path = Path();
      for (int i = 0; i <= 32; i++) {
        final t = (i / 32.0) * 2.0 - 1.0;
        final x = (i / 32.0) * size.width;
        final shaped = (effect.name == 'Overdrive' ||
                effect.name == 'TubeScreamer' ||
                effect.name == 'GuitarAmp')
            ? (1.0 - exp(-t.abs() * (1.5 + drive * 6.0))) * (t >= 0 ? 1 : -1)
            : sin(t * pi * (1.0 + drive * 2.5));
        final y = midY - shaped * (size.height * 0.38);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.orangeAccent.withValues(alpha: activeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PedalVizPainter old) => true;
}

/// Stereo Phase Correlation bar (-1.0 out of phase .. +1.0 mono/in-phase).
class StereoCorrelationMeter extends StatelessWidget {
  final double correlation;
  final double width;

  const StereoCorrelationMeter({
    super.key,
    required this.correlation,
    this.width = 120,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 10,
      child: CustomPaint(painter: _CorrelationPainter(correlation)),
    );
  }
}

class _CorrelationPainter extends CustomPainter {
  final double corr;
  _CorrelationPainter(this.corr);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      Paint()..color = const Color(0xFF0E0E14),
    );
    final midX = size.width * 0.5;
    canvas.drawLine(
      Offset(midX, 0),
      Offset(midX, size.height),
      Paint()..color = Colors.white24,
    );
    final c = corr.clamp(-1.0, 1.0);
    final x = midX + c * (size.width * 0.45);
    final barColor = c < -0.15 ? Colors.redAccent : Colors.cyanAccent;
    final rect = c >= 0
        ? Rect.fromLTRB(midX, 2, x, size.height - 2)
        : Rect.fromLTRB(x, 2, midX, size.height - 2);
    canvas.drawRect(rect, Paint()..color = barColor);
  }

  @override
  bool shouldRepaint(covariant _CorrelationPainter old) => old.corr != corr;
}

