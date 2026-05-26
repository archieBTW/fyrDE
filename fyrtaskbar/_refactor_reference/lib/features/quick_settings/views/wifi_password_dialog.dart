import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

void showWifiPasswordDialog(
  BuildContext context,
  String ssid,
  QuickSettingsController controller,
) {
  final passwordController = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: Text(
          'Connect to $ssid',
          style: const TextStyle(color: FyrTheme.textColor),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: const TextStyle(color: FyrTheme.textColor),
          decoration: const InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(color: FyrTheme.textColorMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FyrTheme.cardColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FyrTheme.accentColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.connectWifi(ssid, passwordController.text);
            },
            child: const Text(
              'Connect',
              style: TextStyle(color: FyrTheme.accentColor),
            ),
          ),
        ],
      );
    },
  );
}
