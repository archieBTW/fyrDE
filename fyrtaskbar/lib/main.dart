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

class SystemState {
  static final ValueNotifier<int> batteryLevel = ValueNotifier(100);
  static final ValueNotifier<bool> isCharging = ValueNotifier(false);
  static final ValueNotifier<String?> wifiSsid = ValueNotifier(null);
  static final ValueNotifier<List<String>> bluetoothDevices = ValueNotifier([]);
  static final ValueNotifier<bool> bluetoothEnabled = ValueNotifier(false);
  static final ValueNotifier<double> volume = ValueNotifier(0.5);
  static final ValueNotifier<double> brightness = ValueNotifier(0.5);
  static final ValueNotifier<bool> nightLight = ValueNotifier(false);
  static final ValueNotifier<bool> airplaneMode = ValueNotifier(false);
  static Timer? _timer;

  static void init() {
    _update();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _update());
  }

  static Future<void> _update() async {
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

      final wifiResult = await Process.run('nmcli', [
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

      final btShowResult = await Process.run('bluetoothctl', ['show']);
      if (btShowResult.exitCode == 0) {
        bluetoothEnabled.value = btShowResult.stdout.toString().contains(
          'Powered: yes',
        );
      }

      final btResult = await Process.run('bluetoothctl', [
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

      final volResult = await Process.run('wpctl', [
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

      final brightResult = await Process.run('brightnessctl', ['-m']);
      if (brightResult.exitCode == 0) {
        final output = brightResult.stdout.toString().trim();
        final parts = output.split(',');
        if (parts.length >= 4) {
          final percent = parts[3].replaceAll('%', '');
          brightness.value = int.parse(percent) / 100.0;
        }
      }

      final nlResult = await Process.run('pgrep', ['wlsunset']);
      nightLight.value = nlResult.exitCode == 0;

      final rfkillResult = await Process.run('rfkill', ['list', 'all']);
      if (rfkillResult.exitCode == 0) {
        final output = rfkillResult.stdout.toString();
        airplaneMode.value =
            output.contains('Soft blocked: yes') &&
            !output.contains('Soft blocked: no');
      }
    } catch (_) {}
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

  final waylandLayerShellPlugin = WaylandLayerShell();
  bool isSupported = await waylandLayerShellPlugin.initialize(1920, 56);
  if (isSupported) {
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeTop, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeLeft, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeRight, true);
    await waylandLayerShellPlugin.setExclusiveZone(56);
    await waylandLayerShellPlugin.setKeyboardMode(
      ShellKeyboardMode.keyboardModeOnDemand,
    );
  }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1920, 56),
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

  DesktopApp({required this.name, required this.exec, required this.icon});
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
                apps.add(DesktopApp(name: name, exec: exec, icon: icon ?? ''));
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
  bool _isStartMenuOpen = false;
  bool _isQuickSettingsOpen = false;

  void _toggleStartMenu() async {
    setState(() {
      _isStartMenuOpen = !_isStartMenuOpen;
      if (_isStartMenuOpen) _isQuickSettingsOpen = false;
    });
    _updateWindowSize();
  }

  void _toggleQuickSettings() async {
    setState(() {
      _isQuickSettingsOpen = !_isQuickSettingsOpen;
      if (_isQuickSettingsOpen) _isStartMenuOpen = false;
    });
    _updateWindowSize();
  }

  void _closeMenus() {
    if (_isStartMenuOpen || _isQuickSettingsOpen) {
      setState(() {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
      });
      _updateWindowSize();
    }
  }

  void _updateWindowSize() async {
    const channel = MethodChannel('fyrtaskbar/resize');
    if (_isStartMenuOpen || _isQuickSettingsOpen) {
      try {
        await channel.invokeMethod('setSize', {'width': 1920, 'height': 1080});
      } catch (_) {}
      await windowManager.setSize(Size(1920, 1080));
    } else {
      try {
        await channel.invokeMethod('setSize', {'width': 1920, 'height': 56});
      } catch (_) {}
      await windowManager.setSize(Size(1920, 56));
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _toggleStartMenu,
                    hoverColor: FyrTheme.hoverColor,
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
                  const ClockWidget(),
                  InkWell(
                    onTap: _toggleQuickSettings,
                    hoverColor: FyrTheme.hoverColor,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.center,
                      child: Row(
                        children: [
                          ValueListenableBuilder<String?>(
                            valueListenable: SystemState.wifiSsid,
                            builder: (context, ssid, _) {
                              return Icon(
                                ssid != null ? Icons.wifi : Icons.wifi_off,
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
                                      : FyrTheme.textColor.withOpacity(0.9);

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
            // Popups
            Expanded(
              child: GestureDetector(
                onTap: _closeMenus,
                behavior: HitTestBehavior.opaque,
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
    return Center(
      child: Text(
        _timeString,
        style: TextStyle(
          color: FyrTheme.textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
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
        Process.start(parts[0], parts.sublist(1));
      } catch (e) {
        print('Failed to launch: \$e');
      }
    }
  }

  void _runCommand(String command, List<String> args) {
    widget.onClose();
    Process.start(command, args);
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

enum QuickSettingsMenu { main, wifi, bluetooth }

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

  List<Map<String, String>> _wifiNetworks = [];
  List<Map<String, String>> _btDevices = [];
  bool _isScanning = false;

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

    SystemState.brightness.addListener(_onStateChange);
    SystemState.bluetoothEnabled.addListener(_onStateChange);
    SystemState.volume.addListener(_onStateChange);
    SystemState.nightLight.addListener(_onStateChange);
    SystemState.wifiSsid.addListener(_onStateChange);
    SystemState.airplaneMode.addListener(_onStateChange);
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
      });
    }
  }

  void _runCmd(String cmd, List<String> args) {
    Process.start(cmd, args);
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

  void _showWifiPasswordDialog(String ssid) {
    final TextEditingController _passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FyrTheme.bgColor,
          title: Text('Connect to $ssid', style: TextStyle(color: FyrTheme.textColor)),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            style: TextStyle(color: FyrTheme.textColor),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: FyrTheme.textColorMuted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.cardColor)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.accentColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _connectWifi(ssid, _passwordController.text);
              },
              child: Text('Connect', style: TextStyle(color: FyrTheme.accentColor)),
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
      case QuickSettingsMenu.main:
      default:
        return _buildMainMenu();
    }
  }

  Widget _buildMainMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
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
              SizedBox(width: 12),
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
              SizedBox(width: 12),
              _QuickToggle(
                icon: Icons.airplanemode_active,
                label: "Airplane",
                isActive: _airplaneModeEnabled,
                onTap: _toggleAirplaneMode,
              ),
              SizedBox(width: 12),
              _QuickToggle(
                icon: Icons.nightlight_round,
                label: "Night Light",
                isActive: _nightLightEnabled,
                onTap: _toggleNightLight,
              ),
              SizedBox(width: 12),
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
              SizedBox(width: 12),
              _QuickToggle(
                icon: Icons.settings,
                label: "Settings",
                isActive: false,
                onTap: () {
                  _runCmd('/opt/fyrsettings/fyrsettings', []);
                  widget.onClose();
                },
              ),
              // SizedBox(width: 32),
            ],
          ),
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
                  if (net['security'] != null && net['security'] != '' && net['security'] != '--') {
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

  const _SliderRow({
    required this.icon,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
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
      ],
    );
  }
}
