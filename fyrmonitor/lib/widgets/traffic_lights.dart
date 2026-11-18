import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// macOS-style window controls used by fyrDE apps.
///
/// Close / minimize / maximize live on the *left* of the title bar, with the
/// same 12px circles and colours as fyrEMU, fyrDirector and fyrGraphics.
class TrafficLights extends StatelessWidget {
  const TrafficLights({super.key, this.size = 12, this.spacing = 8});

  /// Diameter of every circle.
  final double size;

  /// Gap between two circles.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrafficLight(
          color: const Color(0xFFFF5F56),
          size: size,
          tooltip: 'Close',
          icon: Icons.close,
          onTap: () => windowManager.close(),
        ),
        SizedBox(width: spacing),
        _TrafficLight(
          color: const Color(0xFFFFBD2E),
          size: size,
          tooltip: 'Minimize',
          icon: Icons.remove,
          onTap: () => windowManager.minimize(),
        ),
        SizedBox(width: spacing),
        _TrafficLight(
          color: const Color(0xFF27C93F),
          size: size,
          tooltip: 'Maximize',
          icon: Icons.add,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
      ],
    );
  }
}

class _TrafficLight extends StatelessWidget {
  const _TrafficLight({
    required this.color,
    required this.size,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final double size;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Icon(
                icon,
                size: size * 0.64,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
