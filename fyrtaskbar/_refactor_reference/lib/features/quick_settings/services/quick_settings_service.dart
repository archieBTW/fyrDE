import 'dart:convert';
import 'dart:io';

import 'package:fyrtaskbar/features/quick_settings/models/audio_device.dart';
import 'package:fyrtaskbar/features/quick_settings/models/bluetooth_device.dart';
import 'package:fyrtaskbar/features/quick_settings/models/wifi_network.dart';
import 'package:intl/intl.dart';

class QuickSettingsService {
  static void _detached(String cmd, List<String> args) {
    Process.start(cmd, args, mode: ProcessStartMode.detached);
  }

  // --- WiFi ---

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
      if (parts.length >= 2 && parts[0].isNotEmpty) {
        if (seenSsids.contains(parts[0])) continue;
        seenSsids.add(parts[0]);
        networks.add(WifiNetwork(
          ssid: parts[0],
          signal: parts[1],
          security: parts.length > 2 ? parts[2] : '',
        ));
      }
    }
    return networks;
  }

  static void connectWifi(String ssid, [String? password]) {
    if (password != null && password.isNotEmpty) {
      _detached('nmcli', ['dev', 'wifi', 'connect', ssid, 'password', password]);
    } else {
      _detached('nmcli', ['dev', 'wifi', 'connect', ssid]);
    }
  }

  // --- Bluetooth ---

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
        devices.add(BluetoothDevice(
          address: parts[1],
          name: parts.sublist(2).join(' '),
        ));
      }
    }
    return devices;
  }

  static void connectBluetooth(String address) {
    _detached('bluetoothctl', ['connect', address]);
  }

  // --- Night Light ---

  static void setNightLight(bool on) {
    if (on) {
      _detached('wlsunset', ['-T', '5000', '-t', '3000']);
    } else {
      _detached('killall', ['wlsunset']);
    }
  }

  // --- Airplane Mode ---

  static void setAirplaneMode(bool on) {
    _detached('rfkill', [on ? 'block' : 'unblock', 'all']);
  }

  // --- Screen Capture ---

  static Future<void> takeScreenshot(bool cropped) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final directory = Directory(
      '${Platform.environment['HOME']}/Pictures/screenshots',
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
    Process.run('sh', ['-c', 'wl-copy < "$filePath"']);
    _detached('notify-send', [
      'Screenshot Taken',
      'Saved to Pictures/screenshots',
      '-i',
      filePath,
    ]);
  }

  static Future<void> startRecording() async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final directory = Directory(
      '${Platform.environment['HOME']}/Videos/recordings',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath = '${directory.path}/recording_$timestamp.mp4';

    Process.start('wf-recorder', ['-f', filePath]).then((p) {
      p.stdout.listen((_) {});
      p.stderr.listen((_) {});
    });
    _detached('notify-send', ['Recording Started', 'Capturing screen...']);
  }

  static Future<void> stopRecording() async {
    await Process.run('killall', ['-s', 'SIGINT', 'wf-recorder']);
    _detached('notify-send', [
      'Recording Stopped',
      'Video saved to Videos/recordings',
    ]);
  }

  static Future<bool> checkRecordingStatus() async {
    final result = await Process.run('pgrep', ['wf-recorder']);
    return result.exitCode == 0;
  }

  // --- Brightness ---

  static void setBrightness(double value) {
    final percent = (value * 100).toInt();
    _detached('brightnessctl', ['set', '$percent%']);
  }

  // --- Volume ---

  static void setVolume(double value) {
    final percent = (value * 100).toInt();
    _detached('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '$percent%']);
  }

  static void playVolumeChangeSound() {
    _detached('canberra-gtk-play', ['-i', 'audio-volume-change']);
  }

  // --- Audio Devices ---

  static Future<AudioDeviceList> loadAudioDevices() async {
    final sinksRes = await Process.run('pactl', ['-f', 'json', 'list', 'sinks']);
    final sourcesRes = await Process.run('pactl', [
      '-f', 'json', 'list', 'sources',
    ]);
    final defaultSinkRes = await Process.run('pactl', ['get-default-sink']);
    final defaultSourceRes = await Process.run('pactl', [
      'get-default-source',
    ]);

    final rawSinks = jsonDecode(sinksRes.stdout) as List;
    final rawSources = (jsonDecode(sourcesRes.stdout) as List)
        .where((s) => !s['name'].toString().contains('.monitor'))
        .toList();

    return AudioDeviceList(
      sinks: rawSinks
          .map((s) => AudioDevice(
                name: s['name'],
                description: s['description'] ?? s['name'],
              ))
          .toList(),
      sources: rawSources
          .map((s) => AudioDevice(
                name: s['name'],
                description: s['description'] ?? s['name'],
              ))
          .toList(),
      defaultSink: defaultSinkRes.stdout.toString().trim(),
      defaultSource: defaultSourceRes.stdout.toString().trim(),
    );
  }

  static void setDefaultSink(String name) {
    Process.run('pactl', ['set-default-sink', name]);
  }

  static void setDefaultSource(String name) {
    Process.run('pactl', ['set-default-source', name]);
  }

  // --- Dock Autohide ---

  static Future<void> writeDockConfig(bool autohide) async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/config.json',
    );
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString());
      } catch (_) {}
    } else {
      await file.create(recursive: true);
    }
    data['autohide'] = autohide;
    await file.writeAsString(jsonEncode(data));
  }

  // --- Settings ---

  static void launchSettings() {
    _detached('/opt/fyrsettings/fyrsettings', []);
  }
}

class AudioDeviceList {
  final List<AudioDevice> sinks;
  final List<AudioDevice> sources;
  final String defaultSink;
  final String defaultSource;

  const AudioDeviceList({
    required this.sinks,
    required this.sources,
    required this.defaultSink,
    required this.defaultSource,
  });
}
