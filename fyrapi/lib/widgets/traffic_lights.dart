import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class TrafficLights extends StatelessWidget {
  const TrafficLights({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildButton(
          color: const Color(0xFFFF5F56),
          onTap: () => windowManager.close(),
          icon: Icons.close,
        ),
        const SizedBox(width: 8),
        _buildButton(
          color: const Color(0xFFFFBD2E),
          onTap: () => windowManager.minimize(),
          icon: Icons.remove,
        ),
        const SizedBox(width: 8),
        _buildButton(
          color: const Color(0xFF27C93F),
          onTap: () => windowManager.maximize(),
          icon: Icons.add,
        ),
      ],
    );
  }

  Widget _buildButton({
    required Color color,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              icon,
              size: 8,
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}
