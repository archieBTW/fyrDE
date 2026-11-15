import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';

/// Compact live Synth Rack panel for tweaking per-track ADSR envelopes,
/// Biquad low-pass Filter Cutoff/Resonance, Octave shift, and fine Detune.
class SynthRackPanel extends StatelessWidget {
  final Track track;
  final VoidCallback? onChangeStart;
  final VoidCallback onChanged;

  const SynthRackPanel({
    super.key,
    required this.track,
    this.onChangeStart,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = track.synthSettings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(bottom: BorderSide(color: borderMain)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 44,
              child: CustomPaint(
                painter: _AdsrPreviewPainter(settings: s, accent: track.color),
              ),
            ),
            const SizedBox(width: 12),
            _dialCol(
              'ATK',
              s.attackSec,
              0.002,
              1.0,
              0.005,
              Colors.cyanAccent,
              (v) => '${(v * 1000).round()}ms',
              (v) {
                s.attackSec = v;
                onChanged();
              },
            ),
            _dialCol(
              'DEC',
              s.decaySec,
              0.02,
              1.5,
              0.15,
              Colors.cyanAccent,
              (v) => '${(v * 1000).round()}ms',
              (v) {
                s.decaySec = v;
                onChanged();
              },
            ),
            _dialCol(
              'SUS',
              s.sustain,
              0.0,
              1.0,
              0.85,
              Colors.cyanAccent,
              (v) => '${(v * 100).round()}%',
              (v) {
                s.sustain = v;
                onChanged();
              },
            ),
            _dialCol(
              'REL',
              s.releaseSec,
              0.02,
              2.5,
              0.14,
              Colors.cyanAccent,
              (v) => '${(v * 1000).round()}ms',
              (v) {
                s.releaseSec = v;
                onChanged();
              },
            ),
            Container(
              width: 1,
              height: 36,
              color: borderMain,
              margin: const EdgeInsets.symmetric(horizontal: 10),
            ),
            _dialCol(
              'CUTOFF',
              s.filterCutoff,
              0.05,
              1.0,
              1.0,
              Colors.amberAccent,
              (v) => '${(120 * (1 + v * v * 140)).round()}Hz',
              (v) {
                s.filterCutoff = v;
                onChanged();
              },
            ),
            _dialCol(
              'RESO',
              s.filterResonance,
              0.05,
              0.95,
              0.1,
              Colors.amberAccent,
              (v) => '${(v * 100).round()}%',
              (v) {
                s.filterResonance = v;
                onChanged();
              },
            ),
            Container(
              width: 1,
              height: 36,
              color: borderMain,
              margin: const EdgeInsets.symmetric(horizontal: 10),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('OCTAVE', style: TextStyle(fontSize: 8, color: textMuted)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _miniStepBtn(Icons.remove, () {
                      onChangeStart?.call();
                      s.octave = (s.octave - 1).clamp(-2, 2);
                      onChanged();
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        s.octave > 0 ? '+${s.octave}' : '${s.octave}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: lavenderLight,
                        ),
                      ),
                    ),
                    _miniStepBtn(Icons.add, () {
                      onChangeStart?.call();
                      s.octave = (s.octave + 1).clamp(-2, 2);
                      onChanged();
                    }),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 10),
            _dialCol(
              'DETUNE',
              s.detuneCents,
              -50.0,
              50.0,
              0.0,
              lavenderAccent,
              (v) => '${v >= 0 ? '+' : ''}${v.round()}ct',
              (v) {
                s.detuneCents = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialCol(
    String label,
    double value,
    double min,
    double max,
    double defVal,
    Color color,
    String Function(double) fmt,
    ValueChanged<double> onSet,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueDial(
            value: value.clamp(min, max),
            min: min,
            max: max,
            defaultValue: defVal,
            size: 20,
            activeColor: color,
            formatLabel: fmt,
            onChangeStart: onChangeStart,
            onChanged: onSet,
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 8, color: textMuted)),
        ],
      ),
    );
  }

  Widget _miniStepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: panelLight,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: borderMain),
        ),
        child: Icon(icon, size: 12, color: textMain),
      ),
    );
  }
}

class _AdsrPreviewPainter extends CustomPainter {
  final SynthSettings settings;
  final Color accent;

  _AdsrPreviewPainter({required this.settings, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = panelDark,
    );

    final aX = (settings.attackSec / 1.0).clamp(0.03, 0.30) * size.width;
    final dX = aX + (settings.decaySec / 1.5).clamp(0.05, 0.30) * size.width;
    final susY = (1.0 - settings.sustain.clamp(0.0, 1.0)) * (size.height - 8) + 4;
    final rStartX = max(dX + 8, size.width * 0.72);
    final rEndX = min(
      size.width - 2,
      rStartX + (settings.releaseSec / 2.5).clamp(0.05, 0.28) * size.width,
    );

    final path = Path()
      ..moveTo(2, size.height - 4)
      ..lineTo(aX, 4)
      ..lineTo(dX, susY)
      ..lineTo(rStartX, susY)
      ..lineTo(rEndX, size.height - 4);

    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  double max(double a, double b) => a > b ? a : b;
  double min(double a, double b) => a < b ? a : b;

  @override
  bool shouldRepaint(covariant _AdsrPreviewPainter old) => true;
}

