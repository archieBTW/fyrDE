import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/features/quick_settings/views/audio_menu_view.dart';
import 'package:fyrtaskbar/features/quick_settings/views/bluetooth_menu_view.dart';
import 'package:fyrtaskbar/features/quick_settings/views/main_menu_view.dart';
import 'package:fyrtaskbar/features/quick_settings/views/screenshot_menu_view.dart';
import 'package:fyrtaskbar/features/quick_settings/views/wifi_menu_view.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class QuickSettingsView extends StatelessWidget {
  final QuickSettingsController controller;

  const QuickSettingsView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: controller.slideAnimation,
      child: Container(
        width: 472,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
          ),
          border: Border.all(color: FyrTheme.cardColor),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: _buildMenu(context),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    switch (controller.currentMenu) {
      case QuickSettingsMenu.wifi:
        return WifiMenuView(controller: controller);
      case QuickSettingsMenu.bluetooth:
        return BluetoothMenuView(controller: controller);
      case QuickSettingsMenu.screenshot:
        return ScreenshotMenuView(controller: controller);
      case QuickSettingsMenu.audio:
        return AudioMenuView(controller: controller);
      case QuickSettingsMenu.main:
        return MainMenuView(controller: controller);
    }
  }
}
