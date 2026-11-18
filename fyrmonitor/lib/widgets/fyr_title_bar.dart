import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../fyr_theme.dart';
import 'traffic_lights.dart';

/// Shared custom title bar used by every fyrDE native Flutter window.
///
/// The window itself is created with [TitleBarStyle.hidden], so this widget
/// owns dragging and the window controls: the same left-aligned traffic lights
/// (close / minimize / maximize) that the rest of the fyrDE suite uses.
class FyrTitleBar extends StatelessWidget {
  const FyrTitleBar({
    super.key,
    required this.title,
    this.icon = Icons.monitor_heart_outlined,
    this.subtitle,
    this.status,
    this.trailing = const [],
  });

  final String title;
  final IconData icon;
  final String? subtitle;

  /// Optional live text (e.g. "412 processes").
  final String? status;

  /// Extra buttons rendered on the right, before the drag area.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final accent = FyrTheme.accentColor;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FyrTheme.sidebarColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 14),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent,
                    accent.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: FyrTheme.getContrastingColor(accent),
                size: 14,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              title,
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    color: FyrTheme.textColorMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
            if (status != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  status!,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
