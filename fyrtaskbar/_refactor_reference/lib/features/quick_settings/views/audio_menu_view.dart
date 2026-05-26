import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class AudioMenuView extends StatelessWidget {
  final QuickSettingsController controller;

  const AudioMenuView({super.key, required this.controller});

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
              "Audio Devices",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (controller.isScanning)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    "Output (Speakers)",
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...controller.sinks.map((s) {
                  final isDefault = s.name == controller.defaultSink;
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.speaker,
                      size: 16,
                      color: isDefault
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s.description,
                      style: TextStyle(
                          fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault
                        ? Icon(Icons.check,
                            color: FyrTheme.accentColor, size: 16)
                        : null,
                    onTap: () => controller.setDefaultSink(s.name),
                  );
                }).toList(),
                Divider(
                    color: FyrTheme.textColor.withOpacity(0.1)),
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    "Input (Microphone)",
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...controller.sources.map((s) {
                  final isDefault =
                      s.name == controller.defaultSource;
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.mic,
                      size: 16,
                      color: isDefault
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s.description,
                      style: TextStyle(
                          fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault
                        ? const Icon(Icons.check,
                            color: FyrTheme.accentColor, size: 16)
                        : null,
                    onTap: () =>
                        controller.setDefaultSource(s.name),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
