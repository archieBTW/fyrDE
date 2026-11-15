import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/utils/pitch_detector.dart';

/// Compact Guitar Tuner + Input Noise Gate widget displayed in the audio
/// track Input Source strip.
class TunerGatePanel extends StatelessWidget {
  final PitchDetectionResult? detectedPitch;
  final double noiseGateThreshold;
  final ValueChanged<double> onGateChanged;
  final bool tunerEnabled;
  final VoidCallback onToggleTuner;

  const TunerGatePanel({
    super.key,
    required this.detectedPitch,
    required this.noiseGateThreshold,
    required this.onGateChanged,
    required this.tunerEnabled,
    required this.onToggleTuner,
  });

  @override
  Widget build(BuildContext context) {
    final cents = detectedPitch?.cents ?? 0.0;
    final bool inTune = detectedPitch != null && cents.abs() < 6.0;
    final Color statusColor = detectedPitch == null
        ? textFaint
        : (inTune ? Colors.greenAccent : Colors.amberAccent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tuner',
              style: TextStyle(
                color: textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            InkWell(
              onTap: onToggleTuner,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tunerEnabled
                      ? lavenderAccent.withValues(alpha: 0.25)
                      : bgDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: tunerEnabled ? lavenderAccent : borderMain,
                  ),
                ),
                child: Text(
                  tunerEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: tunerEnabled ? lavenderLight : textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (tunerEnabled) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgDark,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderMain),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      detectedPitch?.noteName ?? '--',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      detectedPitch != null
                          ? '${detectedPitch!.frequencyHz.toStringAsFixed(1)} Hz'
                          : 'Listening...',
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 8,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _TunerNeedlePainter(
                      cents: cents,
                      hasPitch: detectedPitch != null,
                      inTune: inTune,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Noise Gate',
              style: TextStyle(color: textMuted, fontSize: 10),
            ),
            Text(
              noiseGateThreshold <= 0.001
                  ? 'Off'
                  : '${(noiseGateThreshold * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: textFaint, fontSize: 10),
            ),
          ],
        ),
        SizedBox(
          height: 20,
          child: SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: noiseGateThreshold.clamp(0.0, 0.25),
              min: 0.0,
              max: 0.25,
              activeColor: Colors.amberAccent,
              onChanged: onGateChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TunerNeedlePainter extends CustomPainter {
  final double cents;
  final bool hasPitch;
  final bool inTune;

  _TunerNeedlePainter({
    required this.cents,
    required this.hasPitch,
    required this.inTune,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midX = size.width * 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = Colors.white10,
    );
    canvas.drawLine(
      Offset(midX, 0),
      Offset(midX, size.height),
      Paint()
        ..color = Colors.white30
        ..strokeWidth = 1.5,
    );
    if (!hasPitch) return;

    final norm = (cents / 50.0).clamp(-1.0, 1.0);
    final px = midX + norm * (size.width * 0.46);
    canvas.drawCircle(
      Offset(px, size.height * 0.5),
      3.5,
      Paint()..color = inTune ? Colors.greenAccent : Colors.amberAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _TunerNeedlePainter old) =>
      old.cents != cents || old.hasPitch != hasPitch || old.inTune != inTune;
}

