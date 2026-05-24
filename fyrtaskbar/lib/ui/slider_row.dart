import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class SliderRow extends StatelessWidget {
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget? trailing;

  const SliderRow({
    required this.icon,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: FyrTheme.textColor.withOpacity(0.7), size: 20),
        SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: FyrTheme.accentColor.withOpacity(0.5),
              inactiveTrackColor: FyrTheme.hoverColor,
              thumbColor: FyrTheme.textColor,
              overlayColor: FyrTheme.accentColor.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        if (trailing != null) ...[SizedBox(width: 8), trailing!],
      ],
    );
  }
}
