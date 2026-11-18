import 'package:flutter/material.dart';

import '../fyr_theme.dart';

/// Rounded panel used by the Performance tab.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.accent,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? FyrTheme.accentColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

/// Big current value shown at the top of a chart card.
class CardMetric extends StatelessWidget {
  const CardMetric({
    super.key,
    required this.value,
    this.caption,
    this.color,
  });

  final String value;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null)
            TextSpan(
              text: '  $caption',
              style: TextStyle(
                color: FyrTheme.textColorMuted,
                fontSize: 10.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small coloured dot + label used for chart legends.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 10.5),
        ),
      ],
    );
  }
}
