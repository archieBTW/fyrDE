import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/notification_service.dart';
import 'package:fyrtaskbar/phone_service.dart';
import 'package:fyrtaskbar/services/mpris_service.dart';
import 'package:fyrtaskbar/services/tray_service.dart';
import 'package:fyrtaskbar/services/update_scheduler.dart';

class ScreenshotPreview {
  final String filePath;
  final String label;
  final DateTime timestamp;

  const ScreenshotPreview({
    required this.filePath,
    required this.label,
    required this.timestamp,
  });
}

class SystemState {
  static final ValueNotifier<int> batteryLevel = ValueNotifier(100);
  static final ValueNotifier<bool> isCharging = ValueNotifier(false);
  static int screenWidth = 1920;
  static int screenHeight = 1080;
  static final ValueNotifier<String?> wifiSsid = ValueNotifier(null);
  static final ValueNotifier<List<String>> bluetoothDevices = ValueNotifier([]);
  static final ValueNotifier<bool> bluetoothEnabled = ValueNotifier(false);
  static final ValueNotifier<double> volume = ValueNotifier(0.5);
  static final ValueNotifier<double> brightness = ValueNotifier(0.5);
  static final ValueNotifier<bool> nightLight = ValueNotifier(false);
  static final ValueNotifier<bool> airplaneMode = ValueNotifier(false);
  static final ValueNotifier<bool> floatingMode = ValueNotifier(false);
  static final ValueNotifier<bool> windowFloatingMode = ValueNotifier(false);
  static final ValueNotifier<bool> dockAutohide = ValueNotifier(false);
  static final ValueNotifier<bool> isRecording = ValueNotifier(false);
  static final ValueNotifier<List<Map<String, dynamic>>> workspaces =
      ValueNotifier([]);
  static final ValueNotifier<String> splitLayout = ValueNotifier('none');
  static final ValueNotifier<String> weatherLocation = ValueNotifier('London');
  static final ValueNotifier<double?> weatherTemp = ValueNotifier(null);
  static final ValueNotifier<String?> weatherDesc = ValueNotifier(null);
  static final ValueNotifier<IconData> weatherIcon = ValueNotifier(Icons.cloud);
  static final ValueNotifier<PhoneInfo?> primaryPhone = ValueNotifier(null);

  static final ValueNotifier<List<FyrNotification>> notifications =
      ValueNotifier([]);
  static final ValueNotifier<List<FyrNotification>> activePopups =
      ValueNotifier([]);
  static final ValueNotifier<bool> doNotDisturb = ValueNotifier(false);
  static final ValueNotifier<ScreenshotPreview?> activeScreenshotToast =
      ValueNotifier(null);
  static Timer? _screenshotTimer;
  static int _nextNotificationId = 1;

  static bool _isUpdating = false;
  static bool _isUpdatingSway = false;
  static int _updateCount = 0;
  static Timer? _timer;
  static SwaySubscription? _swaySub;
  static Process? _pactlSub;
  static StreamSubscription<FileSystemEvent>? _swayDirSub;
  static StreamSubscription<FileSystemEvent>? _dockDirSub;

  static List<Map<String, dynamic>>? _findFocusedPath(
    Map<String, dynamic> node,
  ) {
    if (node['focused'] == true) return [node];
    for (var child in (node['nodes'] ?? [])) {
      final res = _findFocusedPath(child);
      if (res != null) return [node, ...res];
    }
    for (var child in (node['floating_nodes'] ?? [])) {
      final res = _findFocusedPath(child);
      if (res != null) return [node, ...res];
    }
    return null;
  }

  static Future<ProcessResult> _runWithTimeout(
    String cmd,
    List<String> args, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final process = await Process.start(cmd, args);
    final timer = Timer(timeout, () {
      process.kill();
    });
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    timer.cancel();
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }

  static void init() {
    update();
    updateSwayState();
    _loadWeatherLocation();
    _loadTaskbarSettings();
    NotificationService.init();
    PhoneService.init();
    MprisService.init();
    TrayService.init();
    UpdateScheduler.init();
    // Periodic fallback runs at 15s for slow-changing hardware stats (battery, wifi, bt)
    // while Sway, volume, and Fyr config changes arrive immediately via event streams.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      update();
      _updateCount++;
      if (_updateCount % 20 == 0) {
        _fetchWeather();
      }
    });
    _startSwaySubscription();
    _startAudioSubscription();
    _startConfigWatchers();
  }

  static Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _screenshotTimer?.cancel();
    _screenshotTimer = null;
    await _swaySub?.cancel();
    _swaySub = null;
    _pactlSub?.kill();
    _pactlSub = null;
    await _swayDirSub?.cancel();
    _swayDirSub = null;
    await _dockDirSub?.cancel();
    _dockDirSub = null;
    await MprisService.dispose();
    await TrayService.dispose();
    UpdateScheduler.dispose();
  }

  static Future<void> _loadTaskbarSettings() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrtaskbar/settings.json',
    );
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['do_not_disturb'] is bool) {
          doNotDisturb.value = data['do_not_disturb'] as bool;
        }
      } catch (_) {}
    }
  }

  static Future<void> setDoNotDisturb(bool enabled) async {
    doNotDisturb.value = enabled;
    if (enabled) {
      activePopups.value = [];
    }
    try {
      final file = File(
        '${Platform.environment['HOME']}/.config/fyrtaskbar/settings.json',
      );
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        try {
          data = Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map,
          );
        } catch (_) {}
      }
      data['do_not_disturb'] = enabled;
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> toggleDoNotDisturb() async {
    await setDoNotDisturb(!doNotDisturb.value);
  }

  static void showScreenshotPreview(
    String filePath, {
    String label = 'Screenshot saved',
  }) {
    activeScreenshotToast.value = ScreenshotPreview(
      filePath: filePath,
      label: label,
      timestamp: DateTime.now(),
    );
    resumeScreenshotPreviewTimer();
  }

  static void pauseScreenshotPreviewTimer() {
    _screenshotTimer?.cancel();
    _screenshotTimer = null;
  }

  static void resumeScreenshotPreviewTimer() {
    _screenshotTimer?.cancel();
    _screenshotTimer = Timer(const Duration(seconds: 9), () {
      activeScreenshotToast.value = null;
    });
  }

  static void dismissScreenshotPreview() {
    _screenshotTimer?.cancel();
    _screenshotTimer = null;
    activeScreenshotToast.value = null;
  }

  static void _startSwaySubscription() {
    _swaySub?.cancel();
    _swaySub = SwayIpc.subscribe(
      const ['workspace', 'window', 'binding'],
      onEvent: (_) => updateSwayState(),
    );
  }

  static void _startAudioSubscription() {
    Process.start('pactl', ['subscribe']).then((process) {
      _pactlSub = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.contains("'change' on sink") ||
                  line.contains("'new' on sink") ||
                  line.contains('server')) {
                _refreshVolume();
              }
            },
            onDone: () {
              Future.delayed(
                const Duration(seconds: 3),
                _startAudioSubscription,
              );
            },
            onError: (_) {},
          );
      process.stderr.drain<void>().catchError((_) {});
    }).catchError((_) {});
  }

  static Future<void> _refreshVolume() async {
    try {
      final volResult = await _runWithTimeout('wpctl', [
        'get-volume',
        '@DEFAULT_AUDIO_SINK@',
      ]);
      if (volResult.exitCode == 0) {
        final output = volResult.stdout.toString().trim();
        final match = RegExp(r'Volume: (\d+\.\d+)').firstMatch(output);
        if (match != null) {
          volume.value = double.parse(match.group(1)!);
        }
      }
    } catch (_) {}
  }

  static void _startConfigWatchers() {
    final home = Platform.environment['HOME'] ?? '';
    try {
      final swayDir = Directory('$home/.config/sway');
      if (swayDir.existsSync()) {
        _swayDirSub?.cancel();
        _swayDirSub = swayDir.watch().listen((event) {
          if (event.path.contains('floating.conf')) {
            _refreshFloatingMode();
          }
        }, onError: (_) {});
      }
    } catch (_) {}
    try {
      final dockDir = Directory('$home/.config/fyrdock');
      if (dockDir.existsSync()) {
        _dockDirSub?.cancel();
        _dockDirSub = dockDir.watch().listen((event) {
          if (event.path.contains('config.json')) {
            _refreshDockAutohide();
          }
        }, onError: (_) {});
      }
    } catch (_) {}
  }

  static Future<void> _refreshFloatingMode() async {
    try {
      final floatingFile = File(
        '${Platform.environment['HOME']}/.config/sway/floating.conf',
      );
      if (await floatingFile.exists()) {
        final content = await floatingFile.readAsString();
        floatingMode.value = content.contains('floating enable');
      } else {
        floatingMode.value = false;
      }
    } catch (_) {}
  }

  static Future<void> _refreshDockAutohide() async {
    try {
      final dockConfigFile = File(
        '${Platform.environment['HOME']}/.config/fyrdock/config.json',
      );
      if (await dockConfigFile.exists()) {
        final data = jsonDecode(await dockConfigFile.readAsString());
        dockAutohide.value = data['autohide'] ?? false;
      }
    } catch (_) {}
  }

  static Future<void> update() async {
    if (_isUpdating) return;
    _isUpdating = true;
    try {
      final capacityFile = File('/sys/class/power_supply/BAT0/capacity');
      if (await capacityFile.exists()) {
        batteryLevel.value = int.parse(
          (await capacityFile.readAsString()).trim(),
        );
      }
      final statusFile = File('/sys/class/power_supply/BAT0/status');
      if (await statusFile.exists()) {
        isCharging.value =
            (await statusFile.readAsString()).trim() == 'Charging';
      }

      final wifiResult = await _runWithTimeout('nmcli', [
        '-t',
        '-f',
        'active,ssid',
        'dev',
        'wifi',
        'list',
        '--rescan',
        'no',
      ]);
      if (wifiResult.exitCode == 0) {
        final lines = wifiResult.stdout.toString().split('\n');
        String? ssid;
        for (var line in lines) {
          if (line.startsWith('yes:')) {
            ssid = line.substring(4);
            break;
          }
        }
        wifiSsid.value = ssid;
      }

      final btShowResult = await _runWithTimeout('bluetoothctl', ['show']);
      if (btShowResult.exitCode == 0) {
        bluetoothEnabled.value = btShowResult.stdout.toString().contains(
          'Powered: yes',
        );
      }

      final btResult = await _runWithTimeout('bluetoothctl', [
        'devices',
        'Connected',
      ]);
      if (btResult.exitCode == 0) {
        final lines = btResult.stdout.toString().trim().split('\n');
        bluetoothDevices.value = lines
            .where((l) => l.isNotEmpty)
            .map((l) => l.split(' ').sublist(2).join(' '))
            .toList();
      }

      await _refreshVolume();

      final brightResult = await _runWithTimeout('brightnessctl', ['-m']);
      if (brightResult.exitCode == 0) {
        final output = brightResult.stdout.toString().trim();
        final parts = output.split(',');
        if (parts.length >= 4) {
          final percent = parts[3].replaceAll('%', '');
          brightness.value = int.parse(percent) / 100.0;
        }
      }

      final nlResult = await _runWithTimeout('pgrep', ['wlsunset']);
      nightLight.value = nlResult.exitCode == 0;

      final rfkillResult = await _runWithTimeout('rfkill', ['list', 'all']);
      if (rfkillResult.exitCode == 0) {
        final output = rfkillResult.stdout.toString();
        airplaneMode.value =
            output.contains('Soft blocked: yes') &&
            !output.contains('Soft blocked: no');
      }

      await _refreshFloatingMode();
      await _refreshDockAutohide();

      final recResult = await _runWithTimeout('pgrep', ['wf-recorder']);
      isRecording.value = recResult.exitCode == 0;
    } catch (_) {
    } finally {
      _isUpdating = false;
    }
  }

  static Future<void> updateSwayState() async {
    if (_isUpdatingSway) return;
    _isUpdatingSway = true;
    try {
      final wsResult = await _runWithTimeout('swaymsg', [
        '-t',
        'get_workspaces',
      ]);
      if (wsResult.exitCode == 0) {
        final List<dynamic> wss = jsonDecode(wsResult.stdout);
        workspaces.value = wss.map((w) => w as Map<String, dynamic>).toList();
      }

      final treeResult = await _runWithTimeout('swaymsg', ['-t', 'get_tree']);
      if (treeResult.exitCode == 0) {
        final Map<String, dynamic> tree = jsonDecode(treeResult.stdout);
        final path = _findFocusedPath(tree);
        if (path != null) {
          bool isFloating = path.any((n) => n['type'] == 'floating_con');
          windowFloatingMode.value = isFloating;
          String layout = 'none';
          for (var n in path.reversed) {
            if (n['layout'] == 'splith' || n['layout'] == 'splitv') {
              layout = n['layout'];
              break;
            }
          }
          splitLayout.value = layout;
        }
      }
    } catch (_) {
    } finally {
      _isUpdatingSway = false;
    }
  }

  static Future<void> _loadWeatherLocation() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrtaskbar/weather.json',
    );
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data['location'] != null) {
          weatherLocation.value = data['location'];
        }
      } catch (_) {}
    }
    _fetchWeather();
  }

  static Future<void> saveWeatherLocation(String loc) async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrtaskbar/weather.json',
    );
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode({'location': loc}));
    weatherLocation.value = loc;
    _fetchWeather();
  }

  static Future<void> _fetchWeather() async {
    try {
      final loc = weatherLocation.value;
      final geoResult = await _runWithTimeout('curl', [
        '-s',
        '--max-time',
        '5',
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(loc)}&count=1&language=en&format=json',
      ]);
      if (geoResult.exitCode == 0) {
        final geoData = jsonDecode(geoResult.stdout);
        if (geoData['results'] != null && geoData['results'].isNotEmpty) {
          final lat = geoData['results'][0]['latitude'];
          final lon = geoData['results'][0]['longitude'];

          final weatherResult = await _runWithTimeout('curl', [
            '-s',
            '--max-time',
            '5',
            'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&temperature_unit=fahrenheit',
          ]);
          if (weatherResult.exitCode == 0) {
            final weatherData = jsonDecode(weatherResult.stdout);
            if (weatherData['current_weather'] != null) {
              final cw = weatherData['current_weather'];
              weatherTemp.value = cw['temperature']?.toDouble();
              final code = cw['weathercode'];
              weatherDesc.value = _getWeatherDescription(code);
              weatherIcon.value = _getWeatherIcon(code);
            }
          }
        }
      }
    } catch (_) {}
  }

  static String _getWeatherDescription(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1 || code == 2 || code == 3) return 'Partly cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code >= 85 && code <= 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Unknown';
  }

  static IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code == 1 || code == 2 || code == 3) return Icons.cloud;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 67) return Icons.water_drop;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 82) return Icons.grain;
    if (code >= 85 && code <= 86) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.cloud;
  }

  static void addNotification({
    required String appName,
    required String title,
    required String body,
    String? icon,
    int? timeout,
    List<String> actions = const [],
  }) {
    final notification = FyrNotification(
      id: _nextNotificationId++,
      appName: appName,
      title: title,
      body: body,
      icon: icon ?? '',
      timestamp: DateTime.now(),
      timeout: timeout ?? 5000,
      actions: actions,
    );

    notifications.value = [notification, ...notifications.value];

    final isPriority =
        title.toLowerCase().contains('find my') ||
        title.toLowerCase().contains('incoming call') ||
        appName.toLowerCase().contains('phone');

    if (!doNotDisturb.value || isPriority) {
      activePopups.value = [...activePopups.value, notification];
      _playNotificationSound(appName, title);

      if (notification.timeout > 0) {
        Timer(Duration(milliseconds: notification.timeout), () {
          dismissPopup(notification.id, reason: 1); // 1 = expired
        });
      }
    }
  }

  static void _playNotificationSound(String appName, String title) async {
    bool isPriority =
        title.toLowerCase().contains('find my') ||
        title.toLowerCase().contains('incoming call') ||
        appName.toLowerCase().contains('phone');

    if (isPriority) {
      // Regardless of silent mode: unmute and set volume high for this sound
      Process.run('sh', [
        '-c',
        'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0; canberra-gtk-play -i phone-incoming-call; sleep 2; wpctl set-volume @DEFAULT_AUDIO_SINK@ ${volume.value}',
      ]);
    } else {
      Process.run('canberra-gtk-play', ['-i', 'message']);
    }
  }

  static void dismissPopup(int id, {int reason = 2}) {
    activePopups.value = activePopups.value.where((n) => n.id != id).toList();
  }

  static void dismissNotification(int id, {int reason = 3}) {
    notifications.value = notifications.value.where((n) => n.id != id).toList();
    dismissPopup(id);
    NotificationService.sendNotificationClosed(id, reason);
  }

  static void dismissAppNotifications(String appName) {
    final ids = notifications.value
        .where((n) => n.appName == appName)
        .map((n) => n.id)
        .toSet();
    notifications.value =
        notifications.value.where((n) => n.appName != appName).toList();
    activePopups.value =
        activePopups.value.where((n) => !ids.contains(n.id)).toList();
    for (final id in ids) {
      NotificationService.sendNotificationClosed(id, 3);
    }
  }

  static void clearAllNotifications() {
    notifications.value = [];
    activePopups.value = [];
  }
}
