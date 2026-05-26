import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/features/quick_settings/views/wifi_password_dialog.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class WifiMenuView extends StatelessWidget {
  final QuickSettingsController controller;

  const WifiMenuView({super.key, required this.controller});

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
              "Wi-Fi Networks",
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
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: controller.wifiNetworks.length,
            itemBuilder: (context, index) {
              final net = controller.wifiNetworks[index];
              return ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  net.ssid,
                  style: TextStyle(
                      fontSize: 13, color: FyrTheme.textColor),
                ),
                trailing: Icon(Icons.network_wifi,
                    size: 16,
                    color: FyrTheme.textColor.withOpacity(0.7)),
                onTap: () {
                  if (net.isSecure) {
                    showWifiPasswordDialog(context, net.ssid, controller);
                  } else {
                    controller.connectWifi(net.ssid);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
