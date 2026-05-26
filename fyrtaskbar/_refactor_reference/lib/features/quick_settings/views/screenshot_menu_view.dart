import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/ui/screenshot_button.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class ScreenshotMenuView extends StatelessWidget {
  final QuickSettingsController controller;

  const ScreenshotMenuView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back,
                  color: FyrTheme.textColor, size: 20),
              onPressed: () => controller.goBack(),
            ),
            const Text(
              "Capture Screen",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ScreenshotButton(
              icon: Icons.fullscreen,
              label: "Full Screen",
              onTap: () => controller.takeScreenshot(false),
            ),
            ScreenshotButton(
              icon: Icons.crop_free,
              label: "Crop Region",
              onTap: () => controller.takeScreenshot(true),
            ),
            ScreenshotButton(
              icon: controller.isRecording
                  ? Icons.stop_circle
                  : Icons.videocam,
              label: controller.isRecording
                  ? "Stop Record"
                  : "Screen Record",
              isActive: controller.isRecording,
              onTap: () => controller.toggleRecording(),
            ),
          ],
        ),
      ],
    );
  }
}
