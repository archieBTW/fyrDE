import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/utils/parametric_eq_dsp.dart';

/// Interactive 4-Band Visual Parametric EQ graph with real-time FFT spectrum
/// overlay, draggable frequency/gain nodes, and Q bandwidth controls.
class ParametricEqWidget extends StatefulWidget {
  final DawEffect effect;
  final List<double> fftSpectrum;
  final double height;
  final bool showBandControls;
  final void Function(String key, double value) onParamChanged;

  const ParametricEqWidget({
    super.key,
    required this.effect,
    this.fftSpectrum = const [],
    this.height = 170,
    this.showBandControls = true,
    required this.onParamChanged,
  });

  @override
  State<ParametricEqWidget> createState() => _ParametricEqWidgetState();
}

class _ParametricEqWidgetState extends State<ParametricEqWidget> {
  static const double _minHz = 20.0;
  static const double _maxHz = 20000.0;
  static const double _minDb = -15.0;
  static const double _maxDb = 15.0;

  static const List<Color> _bandColors = [
    Color(0xFF38BDF8), // Low Shelf (Sky)
    Color(0xFF34D399), // Lo-Mid Bell (Emerald)
    Color(0xFFFBBF24), // Hi-Mid Bell (Amber)
    Color(0xFFF472B6), // High Shelf (Pink)
  ];

  int _selectedBand = 1;
  int? _draggingBand;

  double _freqToX(double hz, double width) {
    final clamped = hz.clamp(_minHz, _maxHz);
    final norm = (log(clamped / _minHz) / ln10) / (log(_maxHz / _minHz) / ln10);
    return norm * width;
  }

  double _xToFreq(double x, double width) {
    final norm = (x / max(1.0, width)).clamp(0.0, 1.0);
    return _minHz * pow(_maxHz / _minHz, norm).toDouble();
  }

  double _dbToY(double db, double height) {
    final norm = ((db - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0);
    return (1.0 - norm) * height;
  }

  double _yToDb(double y, double height) {
    final norm = (1.0 - (y / max(1.0, height))).clamp(0.0, 1.0);
    return _minDb + norm * (_maxDb - _minDb);
  }

  void _syncLegacyKnob(EqBandSpec band, double gainDb) {
    final legacyNorm = (gainDb / 24.0 + 0.5).clamp(0.0, 1.0);
    if (band.index == 0) widget.onParamChanged('Low', legacyNorm);
    if (band.index == 1) widget.onParamChanged('Mid', legacyNorm);
    if (band.index == 3) widget.onParamChanged('High', legacyNorm);
  }

  void _updateBandFromPoint(Offset localPos, double width, double height) {
    final bandIdx = _draggingBand ?? _selectedBand;
    final band = kParametricEqBands[bandIdx];
    final newFreq = _xToFreq(localPos.dx, width).clamp(
      band.minFreq,
      band.maxFreq,
    );
    final newGain = _yToDb(localPos.dy, height).clamp(_minDb, _maxDb);
    widget.onParamChanged(band.freqKey, newFreq);
    widget.onParamChanged(band.gainKey, newGain);
    _syncLegacyKnob(band, newGain);
  }

  @override
  Widget build(BuildContext context) {
    final activeSpec = kParametricEqBands[_selectedBand];
    final activeColor = _bandColors[_selectedBand];
    final activeFreq = ParametricEqDsp.bandFreq(
      widget.effect.parameters,
      activeSpec,
    );
    final activeGain = ParametricEqDsp.bandGainDb(
      widget.effect.parameters,
      activeSpec,
    );
    final activeQ = ParametricEqDsp.bandQ(widget.effect.parameters, activeSpec);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              int hitTestBand(Offset pos) {
                int best = _selectedBand;
                double minDist = 26.0;
                for (final band in kParametricEqBands) {
                  final bx = _freqToX(
                    ParametricEqDsp.bandFreq(widget.effect.parameters, band),
                    w,
                  );
                  final by = _dbToY(
                    ParametricEqDsp.bandGainDb(widget.effect.parameters, band),
                    h,
                  );
                  final d = (Offset(bx, by) - pos).distance;
                  if (d < minDist) {
                    minDist = d;
                    best = band.index;
                  }
                }
                return best;
              }

              return GestureDetector(
                key: const Key('parametric_eq_canvas'),
                onTapDown: (d) {
                  final hit = hitTestBand(d.localPosition);
                  setState(() => _selectedBand = hit);
                },
                onDoubleTapDown: (d) {
                  final hit = hitTestBand(d.localPosition);
                  final band = kParametricEqBands[hit];
                  setState(() => _selectedBand = hit);
                  widget.onParamChanged(band.gainKey, 0.0);
                  _syncLegacyKnob(band, 0.0);
                },
                onPanStart: (d) {
                  final hit = hitTestBand(d.localPosition);
                  setState(() {
                    _selectedBand = hit;
                    _draggingBand = hit;
                  });
                  _updateBandFromPoint(d.localPosition, w, h);
                },
                onPanUpdate: (d) => _updateBandFromPoint(d.localPosition, w, h),
                onPanEnd: (_) => setState(() => _draggingBand = null),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _ParametricEqPainter(
                      params: widget.effect.parameters,
                      fftSpectrum: widget.fftSpectrum,
                      selectedBand: _selectedBand,
                      bandColors: _bandColors,
                      isBypassed: widget.effect.isBypassed,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.showBandControls) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (final band in kParametricEqBands)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      band.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _selectedBand == band.index
                            ? Colors.black
                            : textMain,
                      ),
                    ),
                    selected: _selectedBand == band.index,
                    selectedColor: _bandColors[band.index],
                    backgroundColor: bgDark,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        setState(() => _selectedBand = band.index),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  for (final b in kParametricEqBands) {
                    widget.onParamChanged(b.freqKey, b.defaultFreq);
                    widget.onParamChanged(b.gainKey, 0.0);
                    if (b.qKey != null) {
                      widget.onParamChanged(b.qKey!, b.defaultQ);
                    }
                    _syncLegacyKnob(b, 0.0);
                  }
                },
                child: Text(
                  'Flat',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bgDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: activeColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Text(
                  '${activeSpec.label}: ',
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${activeFreq >= 1000 ? "${(activeFreq / 1000).toStringAsFixed(2)}k" : activeFreq.round()} Hz',
                  style: TextStyle(color: textMain, fontSize: 11),
                ),
                const SizedBox(width: 10),
                Text(
                  '${activeGain >= 0 ? "+" : ""}${activeGain.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    color: activeGain.abs() < 0.1 ? textMuted : activeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (activeSpec.qKey != null) ...[
                  const SizedBox(width: 12),
                  Text('Q:', style: TextStyle(color: textMuted, fontSize: 10)),
                  Expanded(
                    child: Slider(
                      value: activeQ.clamp(0.35, 6.0),
                      min: 0.35,
                      max: 6.0,
                      activeColor: activeColor,
                      inactiveColor: borderMain,
                      onChanged: (v) =>
                          widget.onParamChanged(activeSpec.qKey!, v),
                    ),
                  ),
                  Text(
                    activeQ.toStringAsFixed(1),
                    style: TextStyle(color: textMain, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ParametricEqPainter extends CustomPainter {
  final Map<String, double> params;
  final List<double> fftSpectrum;
  final int selectedBand;
  final List<Color> bandColors;
  final bool isBypassed;

  _ParametricEqPainter({
    required this.params,
    required this.fftSpectrum,
    required this.selectedBand,
    required this.bandColors,
    required this.isBypassed,
  });

  double _freqToX(double hz, double w) {
    final norm =
        (log(hz.clamp(20.0, 20000.0) / 20.0) / ln10) /
        (log(20000.0 / 20.0) / ln10);
    return norm * w;
  }

  double _xToFreq(double x, double w) {
    final norm = (x / max(1.0, w)).clamp(0.0, 1.0);
    return 20.0 * pow(1000.0, norm).toDouble();
  }

  double _dbToY(double db, double h) =>
      (1.0 - ((db + 15.0) / 30.0).clamp(0.0, 1.0)) * h;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF10131C),
    );

    // Log frequency grid lines & labels
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    const freqLabels = [50, 100, 250, 500, 1000, 2500, 5000, 10000];
    for (final hz in freqLabels) {
      final x = _freqToX(hz.toDouble(), w);
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: hz >= 1000
              ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k'
              : '$hz',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, h - 12));
    }

    // 0 dB center & +-6/+12 dB lines
    canvas.drawLine(
      Offset(0, h / 2),
      Offset(w, h / 2),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    for (final db in [-6.0, 6.0, -12.0, 12.0]) {
      final y = _dbToY(db, h);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Live FFT spectrum overlay behind EQ curve
    if (fftSpectrum.isNotEmpty) {
      final fftPath = Path()..moveTo(0, h);
      for (int px = 0; px <= w.ceil(); px += 3) {
        final hz = _xToFreq(px.toDouble(), w);
        // Map log frequency across FFT bins (Nyquist ~22050 Hz)
        final double binPos =
            (hz / 22050.0) * max(1, fftSpectrum.length - 1);
        final int idx = binPos.floor().clamp(0, fftSpectrum.length - 1);
        final double mag = fftSpectrum[idx].clamp(0.0, 1.0);
        final double y = h - (pow(mag, 0.55) * (h * 0.85));
        fftPath.lineTo(px.toDouble(), y);
      }
      fftPath.lineTo(w, h);
      fftPath.close();
      canvas.drawPath(
        fftPath,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        fftPath,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.45)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    // Exact biquad composite EQ frequency response curve
    final stages = ParametricEqDsp.buildStages(params);
    final curvePath = Path();
    final fillPath = Path()..moveTo(0, h / 2);
    for (int px = 0; px <= w.ceil(); px += 2) {
      final hz = _xToFreq(px.toDouble(), w);
      final db = isBypassed
          ? 0.0
          : ParametricEqDsp.responseDbAt(
              params,
              hz,
              prebuiltStages: stages,
            );
      final y = _dbToY(db, h);
      if (px == 0) {
        curvePath.moveTo(0, y);
      } else {
        curvePath.lineTo(px.toDouble(), y);
      }
      fillPath.lineTo(px.toDouble(), y);
    }
    fillPath.lineTo(w, h / 2);
    fillPath.close();

    final curveColor = isBypassed ? Colors.grey : lavenderAccent;
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = curveColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = curveColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );

    // Draw interactive band nodes
    for (final band in kParametricEqBands) {
      final bx = _freqToX(ParametricEqDsp.bandFreq(params, band), w);
      final by = _dbToY(ParametricEqDsp.bandGainDb(params, band), h);
      final col = isBypassed ? Colors.grey : bandColors[band.index];
      final selected = band.index == selectedBand;
      if (selected) {
        canvas.drawCircle(
          Offset(bx, by),
          11,
          Paint()..color = col.withValues(alpha: 0.25),
        );
      }
      canvas.drawCircle(Offset(bx, by), selected ? 6.5 : 5.0, Paint()..color = col);
      canvas.drawCircle(
        Offset(bx, by),
        selected ? 6.5 : 5.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final numTp = TextPainter(
        text: TextSpan(
          text: '${band.index + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numTp.paint(canvas, Offset(bx - numTp.width / 2, by - numTp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ParametricEqPainter oldDelegate) => true;
}
