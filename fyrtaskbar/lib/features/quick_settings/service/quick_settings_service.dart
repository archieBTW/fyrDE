import 'dart:io';

import 'package:fyrtaskbar/features/quick_settings/model/bluetooth_device.dart';
import 'package:fyrtaskbar/features/quick_settings/model/wifi_network.dart';
import 'package:intl/intl.dart';

class QuickSettingsService {
  static void _detached(String cmd, List<String> args) {
    Process.start(cmd, args, mode: ProcessStartMode.detached);
  }

  // wifi

  static void setWifiRadio(bool on) {
    _detached('nmcli', ['radio', 'wifi', on ? 'on' : 'off']);
  }

  static Future<List<WifiNetwork>> scanWifi() async {
    final result = await Process.run('nmcli', [
      '-t',
      '-f',
      'ssid,signal,security',
      'dev',
      'wifi',
    ]);
    if (result.exitCode != 0) return [];

    final seenSsids = <String>{};
    final networks = <WifiNetwork>[];
    for (final line in result.stdout.toString().split('\n')) {
      final parts = line.split(':');
      if (parts.length > 2 && parts[0].isNotEmpty) {
        if (seenSsids.contains(parts[0])) continue;
        seenSsids.add(parts[0]);
        networks.add(
          WifiNetwork(
            ssid: parts[0],
            signal: parts[1],
            security: parts.length > 2 ? parts[2] : '',
          ),
        );
      }
    }
    return networks;
  }

  // bluetooth
  static void setBluetoothPower(bool on) {
    if (on) {
      _detached('rfkill', ['unblock', 'bluetooth']);
    }
    _detached('bluetoothctl', ['power', on ? 'on' : 'off']);
  }

  static Future<List<BluetoothDevice>> scanBluetooth() async {
    await Process.run('bluetoothctl', ['--timeout', '5', 'scan', 'on']);
    final result = await Process.run('bluetoothctl', ['devices']);
    if (result.exitCode != 0) return [];

    final devices = <BluetoothDevice>[];
    for (final line in result.stdout.toString().trim().split('\n')) {
      final parts = line.split(' ');
      if (parts.length >= 3) {
        devices.add(
          BluetoothDevice(address: parts[1], name: parts.sublist(2).join(' ')),
        );
      }
    }
    return devices;
  }

  static void connectBluetooth(String address) {
    _detached('bluetoothctl', ['connect', address]);
  }

  //night light
  void setNightLight(bool on) {
    if (on) {
      _detached('wlsunset', ['-T', '5000', '-t', '3000']);
    } else {
      _detached('killall', ['wlsunset']);
    }
  }

  // screen capture

  static Future<void> takeScreenshot(bool cropped) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final directory = Directory(
      '${Platform.environment['Home']}/Pictures/screenshots',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final filePath = '${directory.path}/screenshot_$timestamp.png';

    if (cropped) {
      final slurpResult = await Process.run('slurp', []);

      if (slurpResult.exitCode != 0) return;

      await Process.run('grim', [
        '-g',
        slurpResult.stdout.toString().trim(),
        filePath,
      ]);
    } else {
      await Process.run('grim', [filePath]);
    }

    _detached('canberra-gtk-play', ['-i', 'screen-capture']);
    Process.run('sh', ['-c', 'wl-copy <', "$filePath"]);

    _detached('notify-send', [
      'Screenshot Taken',
      'Saved to Pictures/screenshots',
      '-i',
      filePath,
    ]);
  }
}
