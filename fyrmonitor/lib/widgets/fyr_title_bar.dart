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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FyrTheme.sidebarColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 14),
            Icon(icon, color: FyrTheme.accentColor, size: 17),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 7),
              Text(
                subtitle!,
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 10.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
            if (status != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status!,
                  style: TextStyle(
                    color: FyrTheme.accentColor,
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
