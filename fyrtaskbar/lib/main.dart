import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wayland_layer_shell/wayland_layer_shell.dart';
import 'package:wayland_layer_shell/types.dart';
import 'dart:convert';
import 'fyr_theme.dart';
import 'calendar_weather.dart';
import 'workspace_switcher.dart';
import 'notification_service.dart';
import 'phone_service.dart';

class FyrNotification {
  final int id;
  final String appName;
  final String title;
  final String body;
  final String icon;
  final DateTime timestamp;
  final List<String> actions;
  final int timeout;

  FyrNotification({
    required this.id,
    required this.appName,
    required this.title,
    required this.body,
    required this.icon,
    required this.timestamp,
    this.actions = const [],
    this.timeout = 5000,
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
  static int _nextNotificationId = 1;

  static bool _isUpdating = false;
  static bool _isUpdatingSway = false;
  static int _updateCount = 0;
  static Timer? _timer;

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
    _update();
    _updateSwayState();
    _loadWeatherLocation();
    NotificationService.init();
    PhoneService.init();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _update();
      _updateCount++;
      if (_updateCount % 60 == 0) {
        _fetchWeather();
      }
    });
    _startSwaySubscription();
  }

  static void _startSwaySubscription() {
    Process.start('swaymsg', [
      '-t',
      'subscribe',
      '-m',
      '["workspace", "window", "binding"]',
    ]).then((process) {
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _updateSwayState();
          }, onDone: () {
            Future.delayed(const Duration(seconds: 2), _startSwaySubscription);
          }, onError: (_) {
            Future.delayed(const Duration(seconds: 2), _startSwaySubscription);
          });
      process.stderr.listen((_) {});
    });
  }

  static Future<void> _update() async {
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

      final floatingFile = File(
        '${Platform.environment['HOME']}/.config/sway/floating.conf',
      );
      if (await floatingFile.exists()) {
        final content = await floatingFile.readAsString();
        floatingMode.value = content.contains('floating enable');
      } else {
        floatingMode.value = false;
      }

      final dockConfigFile = File(
        '${Platform.environment['HOME']}/.config/fyrdock/config.json',
      );
      if (await dockConfigFile.exists()) {
        try {
          final data = jsonDecode(await dockConfigFile.readAsString());
          dockAutohide.value = data['autohide'] ?? false;
        } catch (_) {}
      }

      final recResult = await _runWithTimeout('pgrep', ['wf-recorder']);
      isRecording.value = recResult.exitCode == 0;

      await _updateSwayState();
    } catch (_) {} finally {
      _isUpdating = false;
    }
  }

  static Future<void> _updateSwayState() async {
    if (_isUpdatingSway) return;
    _isUpdatingSway = true;
    try {
      final wsResult = await _runWithTimeout('swaymsg', ['-t', 'get_workspaces']);
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
    } catch (_) {} finally {
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
        '--max-time', '5',
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(loc)}&count=1&language=en&format=json',
      ]);
      if (geoResult.exitCode == 0) {
        final geoData = jsonDecode(geoResult.stdout);
        if (geoData['results'] != null && geoData['results'].isNotEmpty) {
          final lat = geoData['results'][0]['latitude'];
          final lon = geoData['results'][0]['longitude'];

          final weatherResult = await _runWithTimeout('curl', [
            '-s',
            '--max-time', '5',
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
    activePopups.value = [...activePopups.value, notification];

    if (notification.timeout > 0) {
      Timer(Duration(milliseconds: notification.timeout), () {
        dismissPopup(notification.id, reason: 1); // 1 = expired
      });
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

  static void clearAllNotifications() {
    notifications.value = [];
    activePopups.value = [];
  }
}

void main() async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  SystemState.init();

  FyrTheme.accentColorNotifier.addListener(() {
    AppService.cachedApps = null;
    AppService.getInstalledApps();
  });

  await AppService.getInstalledApps();

  int screenWidth = 1920;
  int screenHeight = 1080;
  
  try {
    final res = await Process.run('sh', ['-c', 'cat /sys/class/drm/*/modes | head -n 1']);
    if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
      final parts = res.stdout.toString().trim().split('x');
      screenWidth = int.parse(parts[0]);
      screenHeight = int.parse(parts[1]);
    }
  } catch (_) {}

  SystemState.screenWidth = screenWidth;
  SystemState.screenHeight = screenHeight;

  final waylandLayerShellPlugin = WaylandLayerShell();
  bool isSupported = await waylandLayerShellPlugin.initialize(screenWidth, 56);
  if (isSupported) {
    await waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeTop, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeLeft, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeRight, true);
    await waylandLayerShellPlugin.setExclusiveZone(56);
    await waylandLayerShellPlugin.setKeyboardMode(
      ShellKeyboardMode.keyboardModeOnDemand,
    );
  }

  WindowOptions windowOptions = WindowOptions(
    size: Size(screenWidth.toDouble(), 56),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.show();
  });

  runApp(const FyrTaskbarApp());
}

class DesktopApp {
  final String name;
  final String exec;
  final String icon;
  final String path;

  DesktopApp({required this.name, required this.exec, required this.icon, required this.path});
}

class AppService {
  static List<DesktopApp>? cachedApps;

  static Future<List<DesktopApp>> getInstalledApps() async {
    if (cachedApps != null) return cachedApps!;

    List<DesktopApp> apps = [];
    List<String> searchPaths = [
      '/usr/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];

    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            try {
              final content = await entity.readAsString();
              String? name;
              String? exec;
              String? icon;
              bool noDisplay = false;

              for (var line in content.split('\n')) {
                if (line.startsWith('Name=') && name == null) {
                  name = line.substring(5);
                } else if (line.startsWith('Exec=') && exec == null) {
                  exec = line.substring(5);
                } else if (line.startsWith('Icon=') && icon == null) {
                  icon = line.substring(5);
                } else if (line.startsWith('NoDisplay=true')) {
                  noDisplay = true;
                }
              }

              if (name != null && exec != null && !noDisplay) {
                // clean up exec line
                exec = exec.replaceAll(RegExp(r' %[fFuU]'), '');
                if (icon != null && !icon.startsWith('/')) {
                  final possiblePaths = [
                    '/usr/share/pixmaps/$icon.png',
                    '/usr/share/pixmaps/$icon.svg',
                    '/usr/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$icon.svg',
                    '/usr/share/icons/${FyrTheme.iconThemeName}/48/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/48/apps/$icon.svg',
                    '/usr/share/icons/hicolor/scalable/apps/$icon.svg',
                    '/usr/share/icons/hicolor/48x48/apps/$icon.png',
                    '/usr/share/icons/hicolor/128x128/apps/$icon.png',
                    '/usr/share/icons/hicolor/256x256/apps/$icon.png',
                    '/usr/share/icons/hicolor/512x512/apps/$icon.png',
                    '/usr/share/icons/Adwaita/scalable/apps/$icon.svg',
                    '/usr/share/icons/breeze/apps/48/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/scalable/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/48x48/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/128x128/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/256x256/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/512x512/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/$icon.svg',
                  ];
                  for (var p in possiblePaths) {
                    if (await File(p).exists()) {
                      icon = p;
                      break;
                    }
                  }
                }
                apps.add(DesktopApp(name: name, exec: exec, icon: icon ?? '', path: entity.path));
              }
            } catch (e) {}
          }
        }
      }
    }

    apps.sort((a, b) => a.name.compareTo(b.name));
    cachedApps = apps;
    return apps;
  }
}

class FyrTaskbarApp extends StatelessWidget {
  const FyrTaskbarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'San Francisco',
          ),
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'San Francisco',
          ),
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        home: TaskbarScreen(),
      ),
    );
  }
}

class TaskbarScreen extends StatefulWidget {
  const TaskbarScreen({super.key});

  @override
  State<TaskbarScreen> createState() => _TaskbarScreenState();
}

class _TaskbarScreenState extends State<TaskbarScreen> {
  @override
  void initState() {
    super.initState();
    SystemState.activePopups.addListener(_onPopupsChanged);
  }

  @override
  void dispose() {
    SystemState.activePopups.removeListener(_onPopupsChanged);
    super.dispose();
  }

  void _onPopupsChanged() {
    if (mounted) {
      _updateWindowSize();
    }
  }

  bool _isStartMenuOpen = false;
  bool _isQuickSettingsOpen = false;
  bool _isCalendarOpen = false;
  bool _isPhoneMenuOpen = false;

  void _toggleStartMenu() async {
    setState(() {
      _isStartMenuOpen = !_isStartMenuOpen;
      if (_isStartMenuOpen) {
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _toggleQuickSettings() async {
    setState(() {
      _isQuickSettingsOpen = !_isQuickSettingsOpen;
      if (_isQuickSettingsOpen) {
        _isStartMenuOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _toggleCalendar() async {
    setState(() {
      _isCalendarOpen = !_isCalendarOpen;
      if (_isCalendarOpen) {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _closeMenus() {
    if (_isStartMenuOpen || _isQuickSettingsOpen || _isCalendarOpen || _isPhoneMenuOpen) {
      setState(() {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      });
      _updateWindowSize();
    }
  }

  void _togglePhoneMenu() async {
    setState(() {
      _isPhoneMenuOpen = !_isPhoneMenuOpen;
      if (_isPhoneMenuOpen) {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _updateWindowSize() async {
    const channel = MethodChannel('fyrtaskbar/resize');
    if (_isStartMenuOpen ||
        _isQuickSettingsOpen ||
        _isCalendarOpen ||
        _isPhoneMenuOpen ||
        SystemState.activePopups.value.isNotEmpty) {
      try {
        await channel.invokeMethod('setSize', {'width': SystemState.screenWidth, 'height': SystemState.screenHeight});
      } catch (_) {}
      await windowManager.setSize(Size(SystemState.screenWidth.toDouble(), SystemState.screenHeight.toDouble()));
    } else {
      try {
        await channel.invokeMethod('setSize', {'width': SystemState.screenWidth, 'height': 56});
      } catch (_) {}
      await windowManager.setSize(Size(SystemState.screenWidth.toDouble(), 56));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _closeMenus();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(color: FyrTheme.bgColor),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: _toggleCalendar,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.transparent,
                        child: const ClockWidget(),
                      ),
                    ),
                  ),
                  const NotificationPopupOverlay(),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _toggleStartMenu,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/icons/fyr_icon.png',
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                        const WorkspaceSwitcher(),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await Process.run('swaymsg', [
                              '[app_id="fyroverview"] scratchpad show, resize set ${SystemState.screenWidth} ${SystemState.screenHeight}, border none, move absolute position 0 0',
                            ]);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.dashboard,
                              color: FyrTheme.textColor.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run(
                              '${Platform.environment['HOME']}/.config/fyr/retile.py',
                              [],
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.sort,
                              color: FyrTheme.textColor.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run(
                              '${Platform.environment['HOME']}/.config/fyr/toggle_floating.sh',
                              [],
                            );
                            await SystemState._update();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: SystemState.floatingMode,
                              builder: (context, isFloating, _) {
                                return Icon(
                                  isFloating ? Icons.layers : Icons.grid_view,
                                  color: FyrTheme.textColor.withOpacity(0.9),
                                  size: 18,
                                );
                              },
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run('swaymsg', [
                              'layout toggle splitv splith',
                            ]);
                            SystemState._updateSwayState();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: ValueListenableBuilder<String>(
                              valueListenable: SystemState.splitLayout,
                              builder: (context, split, _) {
                                IconData icon = Icons.crop_square;
                                if (split == 'splitv') icon = Icons.splitscreen;
                                if (split == 'splith')
                                  icon = Icons.vertical_split;
                                return Icon(
                                  icon,
                                  color: FyrTheme.textColor.withOpacity(0.9),
                                  size: 18,
                                );
                              },
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _toggleQuickSettings,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.only(left: 12, right: 20),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: SystemState.isRecording,
                                  builder: (context, isRecording, _) {
                                    if (!isRecording)
                                      return const SizedBox.shrink();
                                    return GestureDetector(
                                      onTap: () async {
                                        await Process.run('killall', [
                                          '-s',
                                          'SIGINT',
                                          'wf-recorder',
                                        ]);
                                        Process.run('notify-send', [
                                          'Recording Stopped',
                                          'Video saved to Videos/recordings',
                                        ]);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: Colors.redAccent,
                                              size: 10,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              "REC",
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<PhoneInfo?>(
                                  valueListenable: SystemState.primaryPhone,
                                  builder: (context, phone, _) {
                                    return GestureDetector(
                                      onTap: () {
                                        if (phone == null || !phone.isPaired) {
                                          Process.run('fyrphone', []);
                                        } else {
                                          _togglePhoneMenu();
                                        }
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: Row(
                                        children: [
                                          Icon(
                                            phone != null && phone.isConnected
                                                ? Icons.smartphone
                                                : Icons.phonelink_erase,
                                            color: phone != null && phone.isConnected
                                                ? FyrTheme.textColor.withOpacity(0.9)
                                                : FyrTheme.textColor.withOpacity(0.4),
                                            size: 18,
                                          ),
                                          if (phone != null && phone.isConnected) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              "${phone.batteryLevel}%",
                                              style: TextStyle(
                                                color: FyrTheme.textColor.withOpacity(0.7),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 12),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<String?>(
                                  valueListenable: SystemState.wifiSsid,
                                  builder: (context, ssid, _) {
                                    return Icon(
                                      ssid != null
                                          ? Icons.wifi
                                          : Icons.wifi_off,
                                      color: ssid != null
                                          ? FyrTheme.textColor.withOpacity(0.9)
                                          : FyrTheme.textColor.withOpacity(0.4),
                                      size: 18,
                                    );
                                  },
                                ),
                                SizedBox(width: 12),
                                ValueListenableBuilder<List<String>>(
                                  valueListenable: SystemState.bluetoothDevices,
                                  builder: (context, devices, _) {
                                    return Icon(
                                      devices.isNotEmpty
                                          ? Icons.bluetooth_connected
                                          : Icons.bluetooth,
                                      color: devices.isNotEmpty
                                          ? FyrTheme.textColor.withOpacity(0.9)
                                          : FyrTheme.textColor.withOpacity(0.4),
                                      size: 18,
                                    );
                                  },
                                ),
                                SizedBox(width: 12),
                                ValueListenableBuilder<bool>(
                                  valueListenable: SystemState.isCharging,
                                  builder: (context, isCharging, _) {
                                    return ValueListenableBuilder<int>(
                                      valueListenable: SystemState.batteryLevel,
                                      builder: (context, level, _) {
                                        IconData batteryIcon = isCharging
                                            ? Icons.battery_charging_full
                                            : (level > 20
                                                  ? Icons.battery_full
                                                  : Icons.battery_alert);
                                        Color batteryColor =
                                            level <= 20 && !isCharging
                                            ? Colors.redAccent
                                            : FyrTheme.textColor.withOpacity(
                                                0.9,
                                              );

                                        return Row(
                                          children: [
                                            Icon(
                                              batteryIcon,
                                              color: batteryColor,
                                              size: 18,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              "${level}%",
                                              style: TextStyle(
                                                color: batteryColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Popups
            Expanded(
              child: GestureDetector(
                onTap: _closeMenus,
                behavior: HitTestBehavior.opaque,
                child: ClipRect(
                  child: Stack(
                    children: [
                      if (_isStartMenuOpen)
                        Positioned(
                          top: 0,
                          left: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () {},
                            child: StartMenuPopup(
                              key: ValueKey(FyrTheme.iconThemeName),
                              onClose: _toggleStartMenu,
                            ),
                          ),
                        ),
                      if (_isCalendarOpen)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () {},
                              child: CalendarMenuPopup(
                                onClose: _toggleCalendar,
                              ),
                            ),
                          ),
                        ),
                      if (_isPhoneMenuOpen)
                        Positioned(
                          top: 0,
                          right: 60,
                          child: GestureDetector(
                            onTap: () {},
                            child: PhoneMenuPopup(onClose: _togglePhoneMenu),
                          ),
                        ),
                      if (_isQuickSettingsOpen)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: GestureDetector(
                            onTap: () {}, // absorb taps
                            child: QuickSettingsPopup(
                              onClose: _toggleQuickSettings,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _timer;
  String _timeString = "";

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
  }

  void _updateTime() {
    final String formattedDateTime = DateFormat(
      'EEE, MMM d  •  h:mm a',
    ).format(DateTime.now());
    if (mounted) {
      setState(() {
        _timeString = formattedDateTime;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double?>(
          valueListenable: SystemState.weatherTemp,
          builder: (context, temp, _) {
            if (temp == null) return const SizedBox();
            return Row(
              children: [
                ValueListenableBuilder<IconData>(
                  valueListenable: SystemState.weatherIcon,
                  builder: (context, icon, _) {
                    return Icon(icon, color: FyrTheme.textColor, size: 14);
                  },
                ),
                SizedBox(width: 4),
                Text(
                  '${temp.round()}°F',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 12),
              ],
            );
          },
        ),
        Text(
          _timeString,
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        ValueListenableBuilder<List<FyrNotification>>(
          valueListenable: SystemState.notifications,
          builder: (context, notifications, _) {
            if (notifications.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(
                Icons.notifications_active,
                color: FyrTheme.accentColor,
                size: 14,
              ),
            );
          },
        ),
      ],
    );
  }
}

class StartMenuPopup extends StatefulWidget {
  final VoidCallback onClose;
  const StartMenuPopup({super.key, required this.onClose});

  @override
  State<StartMenuPopup> createState() => _StartMenuPopupState();
}

class _StartMenuPopupState extends State<StartMenuPopup>
    with SingleTickerProviderStateMixin {
  List<DesktopApp> _apps = AppService.cachedApps ?? [];
  late List<DesktopApp> _filteredApps;
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _animationController.forward();

    _filteredApps = _apps;
    if (_apps.isEmpty) {
      _loadApps();
    }
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    AppService.cachedApps = null;
    final apps = await AppService.getInstalledApps();
    if (mounted) {
      setState(() {
        _apps = apps;
        _filteredApps = apps;
      });
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _apps
          .where((app) => app.name.toLowerCase().contains(query))
          .toList();
    });
  }

  void _launchApp(String exec) {
    widget.onClose();
    final parts = exec.split(' ');
    if (parts.isNotEmpty) {
      try {
        Process.start(parts[0], parts.sublist(1), mode: ProcessStartMode.detached);
      } catch (e) {
        print('Failed to launch: \$e');
      }
    }
  }

  void _runCommand(String command, List<String> args) {
    widget.onClose();
    Process.start(command, args, mode: ProcessStartMode.detached);
  }

  void _pinApp(DesktopApp app) async {
    final dir = Directory('${Platform.environment['HOME']}/.config/fyrdock');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/pinned_apps.json');
    List<dynamic> pinned = [];
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        pinned = jsonDecode(content);
      } catch (_) {}
    }
    if (!pinned.any((p) => p['exec'] == app.exec)) {
      pinned.add({'name': app.name, 'exec': app.exec, 'icon': app.icon});
      await file.writeAsString(jsonEncode(pinned));
      if (mounted) {}
    } else {
      pinned.removeWhere((p) => p['exec'] == app.exec);
      await file.writeAsString(jsonEncode(pinned));
      if (mounted) {}
    }
  }

  void _renameApp(DesktopApp app) async {
    final TextEditingController _nameController = TextEditingController(text: app.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: Text('Rename App', style: TextStyle(color: FyrTheme.textColor)),
        content: TextField(
          controller: _nameController,
          style: TextStyle(color: FyrTheme.textColor),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New Name',
            hintStyle: TextStyle(color: FyrTheme.textColor.withOpacity(0.4)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _nameController.text), child: Text('Rename', style: TextStyle(color: FyrTheme.accentColor))),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != app.name) {
      bool needsSudo = app.path.startsWith('/usr/share/applications');
      if (needsSudo) {
        // For system files, we still use sed but with better escaping
        final escapedName = newName.replaceAll("'", "'\\''");
        String script = "sed -i \"s/^Name=.*/Name=$escapedName/\" \"${app.path}\"";
        _runWithAuth(script);
      } else {
        try {
          final file = File(app.path);
          final lines = await file.readAsLines();
          final newLines = lines.map((line) {
            if (line.startsWith('Name=')) {
              return 'Name=$newName';
            }
            return line;
          }).toList();
          await file.writeAsString(newLines.join('\n'));
          _loadApps();
        } catch (e) {
          debugPrint('Failed to rename local app: $e');
        }
      }
    }
  }

  void _removeApp(DesktopApp app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: Text('Remove App', style: TextStyle(color: FyrTheme.textColor)),
        content: Text('Are you sure you want to remove ${app.name}?', style: TextStyle(color: FyrTheme.textColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      bool needsSudo = app.path.startsWith('/usr/share/applications');
      if (needsSudo) {
        _runWithAuth("rm \"${app.path}\"");
      } else {
        await File(app.path).delete();
        _loadApps();
      }
    }
  }

  void _runWithAuth(String command) async {
    final TextEditingController _passController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: Text('Authentication Required', style: TextStyle(color: FyrTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter password to perform this action:', style: TextStyle(color: FyrTheme.textColor, fontSize: 14)),
            SizedBox(height: 16),
            TextField(
              controller: _passController,
              obscureText: true,
              autofocus: true,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: InputDecoration(hintText: 'Password', hintStyle: TextStyle(color: FyrTheme.textColor.withOpacity(0.4))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _passController.text), child: Text('Authorize', style: TextStyle(color: FyrTheme.accentColor))),
        ],
      ),
    );

    if (password != null) {
      final res = await Process.run('sh', ['-c', 'echo "$password" | sudo -S $command']);
      if (res.exitCode == 0) {
        _loadApps();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: check password'), backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          border: Border(right: BorderSide(color: FyrTheme.cardColor)),
        ),
        child: Column(
          children: [
            SizedBox(height: 24),
            Expanded(
              child: _apps.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredApps[index];
                        return GestureDetector(
                          onSecondaryTapDown: (details) {
                            showMenu(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                details.globalPosition.dx,
                                details.globalPosition.dy,
                                details.globalPosition.dx,
                                details.globalPosition.dy,
                              ),
                              items: [
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text('Toggle Pin to Dock'),
                                  onTap: () => _pinApp(app),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename App'),
                                  onTap: () => _renameApp(app),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove App', style: TextStyle(color: Colors.redAccent)),
                                  onTap: () => _removeApp(app),
                                ),
                              ],
                            );
                          },
                          child: InkWell(
                            onTap: () => _launchApp(app.exec),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: FyrTheme.cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: app.icon.startsWith('/')
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child:
                                                app.icon.toLowerCase().endsWith(
                                                  '.svg',
                                                )
                                                ? SvgPicture.file(
                                                    File(app.icon),
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.contain,
                                                  )
                                                : Image.file(
                                                    File(app.icon),
                                                    width: 24,
                                                    height: 24,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Icon(
                                                          Icons.widgets,
                                                          color: FyrTheme
                                                              .textColor
                                                              .withOpacity(0.8),
                                                          size: 20,
                                                        ),
                                                  ),
                                          )
                                        : Icon(
                                            Icons.widgets,
                                            color: FyrTheme.textColor
                                                .withOpacity(0.8),
                                            size: 20,
                                          ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      app.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FyrTheme.textColor.withOpacity(0.02),
                border: Border(top: BorderSide(color: FyrTheme.cardColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PowerButton(
                    icon: Icons.lock_outline,
                    label: "Lock",
                    onTap: () => _runCommand('dbus-send', [
                      '--system',
                      '--type=method_call',
                      '--dest=org.freedesktop.DisplayManager',
                      '/org/freedesktop/DisplayManager/Seat0',
                      'org.freedesktop.DisplayManager.Seat.SwitchToGreeter'
                    ]),
                  ),
                  _PowerButton(
                    icon: Icons.logout,
                    label: "Logout",
                    onTap: () => _runCommand('swaymsg', ['exit']),
                  ),
                  _PowerButton(
                    icon: Icons.restart_alt,
                    label: "Restart",
                    onTap: () => _runCommand('systemctl', ['reboot']),
                  ),
                  _PowerButton(
                    icon: Icons.power_settings_new,
                    label: "Shutdown",
                    onTap: () => _runCommand('systemctl', ['poweroff']),
                    isDanger: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  const _PowerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Icon(
              icon,
              color: isDanger
                  ? const Color(0xFFFF6584)
                  : FyrTheme.textColor.withOpacity(0.8),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: FyrTheme.textColor.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum QuickSettingsMenu { main, wifi, bluetooth, screenshot, audio }

class QuickSettingsPopup extends StatefulWidget {
  final VoidCallback onClose;
  const QuickSettingsPopup({super.key, required this.onClose});

  @override
  State<QuickSettingsPopup> createState() => _QuickSettingsPopupState();
}

class _QuickSettingsPopupState extends State<QuickSettingsPopup>
    with SingleTickerProviderStateMixin {
  QuickSettingsMenu _currentMenu = QuickSettingsMenu.main;
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _wifiEnabled = true;
  bool _bluetoothEnabled = true;
  bool _nightLightEnabled = false;
  bool _airplaneModeEnabled = false;
  bool _dockAutohideEnabled = false;
  bool _isRecording = false;

  List<Map<String, String>> _wifiNetworks = [];
  List<Map<String, String>> _btDevices = [];
  bool _isScanning = false;

  List<dynamic> _sinks = [];
  List<dynamic> _sources = [];
  String _defaultSink = '';
  String _defaultSource = '';

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _animationController.forward();

    _brightness = SystemState.brightness.value;
    _volume = SystemState.volume.value;
    _wifiEnabled = SystemState.wifiSsid.value != null;
    _bluetoothEnabled = SystemState.bluetoothEnabled.value;
    _nightLightEnabled = SystemState.nightLight.value;
    _airplaneModeEnabled = SystemState.airplaneMode.value;
    _dockAutohideEnabled = SystemState.dockAutohide.value;
    _isRecording = SystemState.isRecording.value;
    _checkRecordingStatus();

    SystemState.brightness.addListener(_onStateChange);
    SystemState.bluetoothEnabled.addListener(_onStateChange);
    SystemState.volume.addListener(_onStateChange);
    SystemState.nightLight.addListener(_onStateChange);
    SystemState.wifiSsid.addListener(_onStateChange);
    SystemState.airplaneMode.addListener(_onStateChange);
    SystemState.isRecording.addListener(_onStateChange);
    SystemState.dockAutohide.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _animationController.dispose();
    SystemState.brightness.removeListener(_onStateChange);
    SystemState.bluetoothEnabled.removeListener(_onStateChange);
    SystemState.volume.removeListener(_onStateChange);
    SystemState.nightLight.removeListener(_onStateChange);
    SystemState.wifiSsid.removeListener(_onStateChange);
    SystemState.airplaneMode.removeListener(_onStateChange);
    SystemState.isRecording.removeListener(_onStateChange);
    SystemState.dockAutohide.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {
        _brightness = SystemState.brightness.value;
        _volume = SystemState.volume.value;
        _nightLightEnabled = SystemState.nightLight.value;
        _wifiEnabled = SystemState.wifiSsid.value != null;
        _bluetoothEnabled = SystemState.bluetoothEnabled.value;
        _airplaneModeEnabled = SystemState.airplaneMode.value;
        _isRecording = SystemState.isRecording.value;
        _dockAutohideEnabled = SystemState.dockAutohide.value;
      });
    }
  }

  void _runCmd(String cmd, List<String> args) {
    Process.start(cmd, args, mode: ProcessStartMode.detached);
  }

  void _toggleWifi() {
    setState(() => _wifiEnabled = !_wifiEnabled);
    _runCmd('nmcli', ['radio', 'wifi', _wifiEnabled ? 'on' : 'off']);
  }

  void _toggleBluetooth() {
    if (!_bluetoothEnabled) {
      _runCmd('rfkill', ['unblock', 'bluetooth']);
    }
    _runCmd('bluetoothctl', ['power', !_bluetoothEnabled ? 'on' : 'off']);
    setState(() => _bluetoothEnabled = !_bluetoothEnabled);
  }

  void _toggleNightLight() {
    setState(() => _nightLightEnabled = !_nightLightEnabled);
    if (_nightLightEnabled) {
      _runCmd('wlsunset', ['-T', '5000', '-t', '3000']);
    } else {
      _runCmd('killall', ['wlsunset']);
    }
  }

  void _toggleAirplaneMode() {
    setState(() => _airplaneModeEnabled = !_airplaneModeEnabled);
    if (_airplaneModeEnabled) {
      _runCmd('rfkill', ['block', 'all']);
    } else {
      _runCmd('rfkill', ['unblock', 'all']);
    }
  }

  void _checkRecordingStatus() async {
    final result = await Process.run('pgrep', ['wf-recorder']);
    if (mounted) {
      setState(() => _isRecording = result.exitCode == 0);
    }
  }

  void _takeScreenshot(bool cropped) async {
    widget.onClose();
    await Future.delayed(const Duration(milliseconds: 200));

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final directory = Directory(
      '${Platform.environment['HOME']}/Pictures/screenshots',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath = '${directory.path}/screenshot_$timestamp.png';

    List<String> args = [];
    if (cropped) {
      final slurpResult = await Process.run('slurp', []);
      if (slurpResult.exitCode != 0) return;
      args = ['-g', slurpResult.stdout.toString().trim(), filePath];
    } else {
      args = [filePath];
    }

    final result = await Process.run('grim', args);
    if (result.exitCode == 0) {
      Process.run('canberra-gtk-play', ['-i', 'screen-capture']);
      Process.run('sh', ['-c', 'wl-copy < "$filePath"']);
      Process.run('notify-send', [
        'Screenshot Taken',
        'Saved to Pictures/screenshots',
        '-i',
        filePath,
      ]);
    }
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await Process.run('killall', ['-s', 'SIGINT', 'wf-recorder']);
      if (mounted) setState(() => _isRecording = false);
      SystemState.isRecording.value = false;
      Process.run('notify-send', [
        'Recording Stopped',
        'Video saved to Videos/recordings',
      ]);
    } else {
      widget.onClose();
      await Future.delayed(const Duration(milliseconds: 200));

      final timestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(DateTime.now());
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
      if (mounted) setState(() => _isRecording = true);
      SystemState.isRecording.value = true;
      Process.run('notify-send', ['Recording Started', 'Capturing screen...']);
    }
  }

  void _toggleDockAutohide() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/config.json',
    );
    bool newVal = !SystemState.dockAutohide.value;
    SystemState.dockAutohide.value = newVal;
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString());
      } catch (_) {}
    } else {
      await file.create(recursive: true);
    }
    data['autohide'] = newVal;
    await file.writeAsString(jsonEncode(data));
  }

  void _setBrightness(double value) {
    setState(() => _brightness = value);
    final percent = (value * 100).toInt();
    _runCmd('brightnessctl', ['set', '$percent%']);
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    final percent = (value * 100).toInt();
    _runCmd('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '$percent%']);
  }

  void _playVolumeSound() {
    _runCmd('canberra-gtk-play', ['-i', 'audio-volume-change']);
  }

  Future<void> _scanWifi() async {
    setState(() {
      _isScanning = true;
      _currentMenu = QuickSettingsMenu.wifi;
    });
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'ssid,signal,security',
        'dev',
        'wifi',
      ]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final networks = <Map<String, String>>[];
        final seenSsids = <String>{};
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2 && parts[0].isNotEmpty) {
            if (seenSsids.contains(parts[0])) continue;
            seenSsids.add(parts[0]);
            networks.add({
              'ssid': parts[0],
              'signal': parts[1],
              'security': parts.length > 2 ? parts[2] : '',
            });
          }
        }
        setState(() => _wifiNetworks = networks);
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _scanBluetooth() async {
    setState(() {
      _isScanning = true;
      _currentMenu = QuickSettingsMenu.bluetooth;
    });
    try {
      await Process.run('bluetoothctl', ['--timeout', '5', 'scan', 'on']);
      final result = await Process.run('bluetoothctl', ['devices']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        final devices = <Map<String, String>>[];
        for (var line in lines) {
          final parts = line.split(' ');
          if (parts.length >= 3) {
            devices.add({
              'address': parts[1],
              'name': parts.sublist(2).join(' '),
            });
          }
        }
        setState(() => _btDevices = devices);
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _connectWifi(String ssid, [String? password]) {
    if (password != null && password.isNotEmpty) {
      _runCmd('nmcli', ['dev', 'wifi', 'connect', ssid, 'password', password]);
    } else {
      _runCmd('nmcli', ['dev', 'wifi', 'connect', ssid]);
    }
    setState(() => _currentMenu = QuickSettingsMenu.main);
  }

  Future<void> _loadAudioDevices() async {
    setState(() => _isScanning = true);
    try {
      final sinksRes = await Process.run('pactl', ['-f', 'json', 'list', 'sinks']);
      final sourcesRes = await Process.run('pactl', ['-f', 'json', 'list', 'sources']);
      
      final defaultSinkRes = await Process.run('pactl', ['get-default-sink']);
      final defaultSourceRes = await Process.run('pactl', ['get-default-source']);

      if (mounted) {
        setState(() {
          _sinks = jsonDecode(sinksRes.stdout);
          _sources = (jsonDecode(sourcesRes.stdout) as List)
              .where((s) => !s['name'].toString().contains('.monitor'))
              .toList();
          _defaultSink = defaultSinkRes.stdout.toString().trim();
          _defaultSource = defaultSourceRes.stdout.toString().trim();
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _setDefaultSink(String name) {
    Process.run('pactl', ['set-default-sink', name]);
    setState(() => _defaultSink = name);
  }

  void _setDefaultSource(String name) {
    Process.run('pactl', ['set-default-source', name]);
    setState(() => _defaultSource = name);
  }

  void _showWifiPasswordDialog(String ssid) {
    final TextEditingController _passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FyrTheme.bgColor,
          title: Text(
            'Connect to $ssid',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            style: TextStyle(color: FyrTheme.textColor),
            decoration: InputDecoration(
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
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _connectWifi(ssid, _passwordController.text);
              },
              child: Text(
                'Connect',
                style: TextStyle(color: FyrTheme.accentColor),
              ),
            ),
          ],
        );
      },
    );
  }

  void _connectBluetooth(String address) {
    _runCmd('bluetoothctl', ['connect', address]);
    setState(() => _currentMenu = QuickSettingsMenu.main);
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 472,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
          border: Border.all(color: FyrTheme.cardColor),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: _buildCurrentMenu(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentMenu() {
    switch (_currentMenu) {
      case QuickSettingsMenu.wifi:
        return _buildWifiMenu();
      case QuickSettingsMenu.bluetooth:
        return _buildBluetoothMenu();
      case QuickSettingsMenu.screenshot:
        return _buildScreenshotMenu();
      case QuickSettingsMenu.audio:
        return _buildAudioMenu();
      case QuickSettingsMenu.main:
      default:
        return _buildMainMenu();
    }
  }

  Widget _buildMainMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: SystemState.wifiSsid,
                  builder: (context, ssid, _) {
                    return _QuickToggle(
                      icon: ssid != null ? Icons.wifi : Icons.wifi_off,
                      label: ssid ?? "Wi-Fi",
                      isActive: _wifiEnabled,
                      onTap: _toggleWifi,
                      onLongPress: _scanWifi,
                    );
                  },
                ),
                ValueListenableBuilder<List<String>>(
                  valueListenable: SystemState.bluetoothDevices,
                  builder: (context, devices, _) {
                    final hasDevices = devices.isNotEmpty;
                    return _QuickToggle(
                      icon: hasDevices
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      label: hasDevices ? devices.first : "Bluetooth",
                      isActive: _bluetoothEnabled,
                      onTap: _toggleBluetooth,
                      onLongPress: _scanBluetooth,
                    );
                  },
                ),
                _QuickToggle(
                  icon: Icons.airplanemode_active,
                  label: "Airplane",
                  isActive: _airplaneModeEnabled,
                  onTap: _toggleAirplaneMode,
                ),
                _QuickToggle(
                  icon: Icons.nightlight_round,
                  label: "Night Light",
                  isActive: _nightLightEnabled,
                  onTap: _toggleNightLight,
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _QuickToggle(
                  icon: Icons.screenshot_monitor,
                  label: "Screenshot",
                  isActive: false,
                  onTap: () {
                    setState(() => _currentMenu = QuickSettingsMenu.screenshot);
                  },
                ),
                _QuickToggle(
                  icon: Icons.visibility_off,
                  label: "Dock Autohide",
                  isActive: _dockAutohideEnabled,
                  onTap: _toggleDockAutohide,
                ),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: FyrTheme.themeModeNotifier,
                  builder: (context, themeMode, _) {
                    final isDark = themeMode == ThemeMode.dark;
                    return _QuickToggle(
                      icon: isDark ? Icons.dark_mode : Icons.light_mode,
                      label: isDark ? "Dark Mode" : "Light Mode",
                      isActive: isDark,
                      onTap: () {
                        FyrTheme.setThemeMode(
                          isDark ? ThemeMode.light : ThemeMode.dark,
                        );
                      },
                    );
                  },
                ),
                _QuickToggle(
                  icon: Icons.settings,
                  label: "Settings",
                  isActive: false,
                  onTap: () {
                    _runCmd('/opt/fyrsettings/fyrsettings', []);
                    widget.onClose();
                  },
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 24),
        _SliderRow(
          icon: Icons.light_mode,
          value: _brightness,
          onChanged: _setBrightness,
        ),
        SizedBox(height: 16),
        _SliderRow(
          icon: Icons.volume_up,
          value: _volume,
          onChanged: _setVolume,
          onChangeEnd: (_) => _playVolumeSound(),
          trailing: IconButton(
            icon: Icon(Icons.keyboard_arrow_right, color: FyrTheme.textColor),
            onPressed: () {
              _loadAudioDevices();
              setState(() => _currentMenu = QuickSettingsMenu.audio);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWifiMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Wi-Fi Networks",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _wifiNetworks.length,
            itemBuilder: (context, index) {
              final net = _wifiNetworks[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  net['ssid']!,
                  style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                ),
                trailing: Icon(
                  Icons.network_wifi,
                  size: 16,
                  color: FyrTheme.textColor.withOpacity(0.7),
                ),
                onTap: () {
                  if (net['security'] != null &&
                      net['security'] != '' &&
                      net['security'] != '--') {
                    _showWifiPasswordDialog(net['ssid']!);
                  } else {
                    _connectWifi(net['ssid']!);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Bluetooth Devices",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _btDevices.length,
            itemBuilder: (context, index) {
              final dev = _btDevices[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  Icons.bluetooth,
                  size: 16,
                  color: FyrTheme.textColorMuted,
                ),
                title: Text(
                  dev['name']!,
                  style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                ),
                onTap: () => _connectBluetooth(dev['address']!),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Capture Screen",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ScreenshotButton(
              icon: Icons.fullscreen,
              label: "Full Screen",
              onTap: () => _takeScreenshot(false),
            ),
            _ScreenshotButton(
              icon: Icons.crop_free,
              label: "Crop Region",
              onTap: () => _takeScreenshot(true),
            ),
            _ScreenshotButton(
              icon: _isRecording ? Icons.stop_circle : Icons.videocam,
              label: _isRecording ? "Stop Record" : "Screen Record",
              isActive: _isRecording,
              onTap: _toggleRecording,
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildAudioMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Audio Devices",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text("Output (Speakers)", style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                ..._sinks.map((s) {
                  bool isDefault = s['name'] == _defaultSink;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.speaker,
                      size: 16,
                      color: isDefault ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s['description'] ?? s['name'],
                      style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault ? Icon(Icons.check, color: FyrTheme.accentColor, size: 16) : null,
                    onTap: () => _setDefaultSink(s['name']),
                  );
                }).toList(),
                Divider(color: FyrTheme.textColor.withOpacity(0.1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text("Input (Microphone)", style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                ..._sources.map((s) {
                  bool isDefault = s['name'] == _defaultSource;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.mic,
                      size: 16,
                      color: isDefault ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s['description'] ?? s['name'],
                      style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault ? Icon(Icons.check, color: FyrTheme.accentColor, size: 16) : null,
                    onTap: () => _setDefaultSource(s['name']),
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

class _ScreenshotButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ScreenshotButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isActive
              ? FyrTheme.accentColor.withOpacity(0.2)
              : FyrTheme.textColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? FyrTheme.accentColor.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? FyrTheme.accentColor : FyrTheme.textColor,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: FyrTheme.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _QuickToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? FyrTheme.accentColor.withOpacity(0.3)
                    : FyrTheme.cardColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive
                    ? FyrTheme.textColor
                    : FyrTheme.textColor.withOpacity(0.7),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget? trailing;

  const _SliderRow({
    required this.icon,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: FyrTheme.textColor.withOpacity(0.7), size: 20),
        SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: FyrTheme.accentColor.withOpacity(0.5),
              inactiveTrackColor: FyrTheme.hoverColor,
              thumbColor: FyrTheme.textColor,
              overlayColor: FyrTheme.accentColor.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class NotificationPopupOverlay extends StatelessWidget {
  const NotificationPopupOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 66,
      right: 20,
      child: ValueListenableBuilder<List<FyrNotification>>(
        valueListenable: SystemState.activePopups,
        builder: (context, popups, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: popups.take(3).map((n) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NotificationCard(
                  notification: n,
                  isPopup: true,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class NotificationCard extends StatelessWidget {
  final FyrNotification notification;
  final bool isPopup;

  const NotificationCard({
    super.key,
    required this.notification,
    this.isPopup = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (notification.actions.contains('default')) {
          NotificationService.sendActionInvoked(notification.id, 'default');
          SystemState.dismissNotification(notification.id);
        }
      },
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FyrTheme.cardColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.appName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: FyrTheme.accentColor,
                                letterSpacing: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm').format(notification.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: FyrTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: FyrTheme.textColor.withOpacity(0.8),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (notification.actions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: notification.actions
                                .asMap()
                                .entries
                                .where((entry) => entry.key % 2 == 0 && entry.value != 'default')
                                .map((entry) {
                              final key = entry.value;
                              final label = notification.actions[entry.key + 1];
                              return TextButton(
                                onPressed: () {
                                  NotificationService.sendActionInvoked(notification.id, key);
                                  SystemState.dismissNotification(notification.id);
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: FyrTheme.accentColor.withOpacity(0.1),
                                  foregroundColor: FyrTheme.accentColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: FyrTheme.textColorMuted,
                  ),
                  onPressed: () {
                    if (isPopup) {
                      SystemState.dismissPopup(notification.id);
                    } else {
                      SystemState.dismissNotification(notification.id);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (notification.icon.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: FyrTheme.accentColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.notifications,
          color: FyrTheme.accentColor,
          size: 24,
        ),
      );
    }

    if (notification.icon.startsWith('/')) {
      final file = File(notification.icon);
      if (file.existsSync()) {
        if (notification.icon.endsWith('.svg')) {
          return SvgPicture.file(
            file,
            width: 40,
            height: 40,
          );
        } else {
          return Image.file(
            file,
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          );
        }
      }
    }

    // Try to find icon in theme if it's just a name
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: FyrTheme.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.notifications,
        color: FyrTheme.accentColor,
        size: 24,
      ),
    );
  }
}

class PhoneMenuPopup extends StatefulWidget {
  final VoidCallback onClose;
  const PhoneMenuPopup({super.key, required this.onClose});

  @override
  State<PhoneMenuPopup> createState() => _PhoneMenuPopupState();
}

class _PhoneMenuPopupState extends State<PhoneMenuPopup> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutQuart,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: FyrTheme.cardColor),
        ),
        child: ValueListenableBuilder<PhoneInfo?>(
          valueListenable: SystemState.primaryPhone,
          builder: (context, phone, _) {
            if (phone == null) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.smartphone, color: FyrTheme.accentColor, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phone.name,
                              style: TextStyle(
                                color: FyrTheme.textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              phone.isConnected ? "Connected • ${phone.batteryLevel}%" : "Disconnected",
                              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: () {
                          widget.onClose();
                          Process.run('fyrphone', []);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _buildMenuItem(
                  icon: Icons.notifications,
                  label: "Ping Phone",
                  onTap: () => PhoneService.ping(phone.id),
                ),
                _buildMenuItem(
                  icon: Icons.folder_open,
                  label: "Browse Files",
                  onTap: () => PhoneService.mountSftp(phone.id),
                ),
                _buildMenuItem(
                  icon: Icons.content_paste,
                  label: "Sync Clipboard",
                  onTap: () async {
                    final res = await Process.run('xclip', ['-o', '-selection', 'clipboard']);
                    if (res.exitCode == 0) {
                      PhoneService.shareText(phone.id, res.stdout.toString());
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: () {
        onTap();
        widget.onClose();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: FyrTheme.textColor.withOpacity(0.7), size: 20),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: FyrTheme.textColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
