import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class BluetoothMenuView extends StatelessWidget {
  final QuickSettingsController controller;

  const BluetoothMenuView({super.key, required this.controller});

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
              "Bluetooth Devices",
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
            itemCount: controller.btDevices.length,
            itemBuilder: (context, index) {
              final dev = controller.btDevices[index];
              return ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.bluetooth,
                    size: 16, color: FyrTheme.textColorMuted),
                title: Text(
                  dev.name,
                  style: TextStyle(
                      fontSize: 13, color: FyrTheme.textColor),
                ),
                onTap: () => controller.connectBluetooth(dev.address),
              );
            },
          ),
        ),
      ],
    );
  }
}
