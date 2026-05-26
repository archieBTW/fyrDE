import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/ui/quick_toggle.dart';
import 'package:fyrtaskbar/ui/slider_row.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class MainMenuView extends StatelessWidget {
  final QuickSettingsController controller;

  const MainMenuView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                QuickToggle(
                  icon: controller.wifiEnabled ? Icons.wifi : Icons.wifi_off,
                  label: controller.wifiLabel,
                  isActive: controller.wifiEnabled,
                  onTap: () => controller.toggleWifi(),
                  onLongPress: () => controller.scanWifi(),
                ),
                QuickToggle(
                  icon: controller.hasConnectedBt
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                  label: controller.bluetoothLabel,
                  isActive: controller.bluetoothEnabled,
                  onTap: () => controller.toggleBluetooth(),
                  onLongPress: () => controller.scanBluetooth(),
                ),
                QuickToggle(
                  icon: Icons.airplanemode_active,
                  label: "Airplane",
                  isActive: controller.airplaneModeEnabled,
                  onTap: () => controller.toggleAirplaneMode(),
                ),
                QuickToggle(
                  icon: Icons.nightlight_round,
                  label: "Night Light",
                  isActive: controller.nightLightEnabled,
                  onTap: () => controller.toggleNightLight(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                QuickToggle(
                  icon: Icons.screenshot_monitor,
                  label: "Screenshot",
                  isActive: false,
                  onTap: () => controller.goTo(QuickSettingsMenu.screenshot),
                ),
                QuickToggle(
                  icon: Icons.visibility_off,
                  label: "Dock Autohide",
                  isActive: controller.dockAutohideEnabled,
                  onTap: () => controller.toggleDockAutohide(),
                ),
                QuickToggle(
                  icon: controller.isDarkMode
                      ? Icons.dark_mode
                      : Icons.light_mode,
                  label: controller.isDarkMode ? "Dark Mode" : "Light Mode",
                  isActive: controller.isDarkMode,
                  onTap: () => controller.toggleTheme(),
                ),
                QuickToggle(
                  icon: Icons.settings,
                  label: "Settings",
                  isActive: false,
                  onTap: () => controller.openSettings(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        SliderRow(
          icon: Icons.light_mode,
          value: controller.brightness,
          onChanged: (v) => controller.setBrightness(v),
        ),
        const SizedBox(height: 16),
        SliderRow(
          icon: Icons.volume_up,
          value: controller.volume,
          onChanged: (v) => controller.setVolume(v),
          onChangeEnd: (v) => controller.onVolumeChangeEnd(v),
          trailing: IconButton(
            icon: Icon(Icons.keyboard_arrow_right,
                color: FyrTheme.textColor),
            onPressed: () {
              controller.loadAudioDevices();
              controller.goTo(QuickSettingsMenu.audio);
            },
          ),
        ),
      ],
    );
  }
}
