import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wayland_layer_shell/wayland_layer_shell.dart';
import 'package:wayland_layer_shell/types.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'fyr_theme.dart';

void main() async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final waylandLayerShellPlugin = WaylandLayerShell();
  bool isSupported = await waylandLayerShellPlugin.initialize(800, 200);
  if (isSupported) {
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeBottom, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeLeft, false);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeRight, false);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeTop, false);

    await waylandLayerShellPlugin.setLayer(ShellLayer.layerBottom);

    await waylandLayerShellPlugin.setMargin(ShellEdge.edgeBottom, 12);

    await waylandLayerShellPlugin.setKeyboardMode(
      ShellKeyboardMode.keyboardModeNone,
    );
  }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 200),
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

  runApp(const FyrDockApp());
}

class FyrDockApp extends StatelessWidget {
  const FyrDockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: FyrTheme.themeMode,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.dark(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
        ),
      ),
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.light(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
        ),
      ),
      home: DockScreen(),
    ),
    );
  }
}

class DockScreen extends StatefulWidget {
  const DockScreen({super.key});

  @override
  State<DockScreen> createState() => _DockScreenState();
}

class _DockScreenState extends State<DockScreen> {
  List<dynamic> _pinnedApps = [];
  Timer? _timer;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _loadPinnedApps();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _loadPinnedApps();
      _checkWindowVisibility();
    });
  }

  Future<void> _checkWindowVisibility() async {
    try {
      final result = await Process.run('swaymsg', ['-t', 'get_workspaces']);
      if (result.exitCode == 0) {
        final List workspaces = jsonDecode(result.stdout);
        bool hasWindows = false;
        for (var ws in workspaces) {
          if (ws['focused'] == true || ws['visible'] == true) {
            List focus = ws['focus'] ?? [];
            if (focus.isNotEmpty) {
              hasWindows = true;
              break;
            }
          }
        }

        if (mounted && _isVisible != !hasWindows) {
          setState(() {
            _isVisible = !hasWindows;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPinnedApps() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/pinned_apps.json',
    );
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final apps = jsonDecode(content);
        if (mounted && content != jsonEncode(_pinnedApps)) {
          setState(() {
            _pinnedApps = apps;
          });
          _updateWindowWidth();
        }
      } catch (_) {}
    } else {
      if (_pinnedApps.isNotEmpty) {
        setState(() => _pinnedApps = []);
        _updateWindowWidth();
      }
    }
  }

  void _updateWindowWidth() async {
    double width = _pinnedApps.length * 64.0 + 32.0;
    if (width < 100) width = 100;

    const channel = MethodChannel('fyrdock/resize');
    try {
      await channel.invokeMethod('setSize', {
        'width': width.toInt(),
        'height': 200,
      });
    } catch (_) {}
    await windowManager.setSize(Size(width, 200));
  }

  Future<String?> _findIcon(String? iconName) async {
    if (iconName == null || iconName.isEmpty) return null;
    if (iconName.startsWith('/')) return iconName;

    final possiblePaths = [
      '/usr/share/pixmaps/$iconName.png',
      '/usr/share/pixmaps/$iconName.svg',
      '/usr/share/icons/hicolor/scalable/apps/$iconName.svg',
      '/usr/share/icons/hicolor/48x48/apps/$iconName.png',
      '/usr/share/icons/hicolor/128x128/apps/$iconName.png',
      '/usr/share/icons/Adwaita/scalable/apps/$iconName.svg',
      '/usr/share/icons/breeze/apps/48/$iconName.svg',
      '/usr/share/icons/Papirus/48x48/apps/$iconName.svg',
      '${Platform.environment['HOME']}/.local/share/icons/hicolor/scalable/apps/$iconName.svg',
      '${Platform.environment['HOME']}/.local/share/icons/hicolor/48x48/apps/$iconName.png',
      '${Platform.environment['HOME']}/.local/share/icons/hicolor/128x128/apps/$iconName.png',
      '${Platform.environment['HOME']}/.local/share/icons/hicolor/256x256/apps/$iconName.png',
      '${Platform.environment['HOME']}/.local/share/icons/hicolor/512x512/apps/$iconName.png',
      '${Platform.environment['HOME']}/.local/share/icons/$iconName.png',
      '${Platform.environment['HOME']}/.local/share/icons/$iconName.svg',
    ];

    for (var p in possiblePaths) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  void _unpinApp(String exec) async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/pinned_apps.json',
    );
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        List<dynamic> pinned = jsonDecode(content);
        pinned.removeWhere((p) => p['exec'] == exec);
        await file.writeAsString(jsonEncode(pinned));
        _loadPinnedApps(); // reload immediately
      } catch (_) {}
    }
  }

  void _launchApp(String exec) {
    final parts = exec.split(' ');
    if (parts.isNotEmpty) {
      try {
        Process.start(parts[0], parts.sublist(1));
      } catch (e) {
        print(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: _isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.only(bottom: 8),
            height: 64,
            decoration: BoxDecoration(
              color: FyrTheme.bgColor.withOpacity(0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: FyrTheme.cardColor,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _pinnedApps.map((app) {
                    return FutureBuilder<String?>(
                      future: _findIcon(app['icon']),
                      builder: (context, snapshot) {
                        final iconPath = snapshot.data;
                        Widget iconWidget;
                        if (iconPath != null) {
                          if (iconPath.toLowerCase().endsWith('.svg')) {
                            iconWidget = SvgPicture.file(
                              File(iconPath),
                              width: 48,
                              height: 48,
                              fit: BoxFit.scaleDown,
                            );
                          } else {
                            iconWidget = Image.file(
                              File(iconPath),
                              width: 48,
                              height: 48,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.widgets,
                                    color: FyrTheme.textColor.withOpacity(0.8),
                                    size: 32,
                                  ),
                            );
                          }
                        } else {
                          iconWidget = Icon(
                            Icons.widgets,
                            color: FyrTheme.textColor.withOpacity(0.8),
                            size: 32,
                          );
                        }

                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Tooltip(
                            message: app['name'] ?? '',
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                showMenu(
                                  context: context,
                                  position: RelativeRect.fromLTRB(
                                    details.globalPosition.dx,
                                    details.globalPosition.dy - 50,
                                    details.globalPosition.dx,
                                    0,
                                  ),
                                  items: [
                                    PopupMenuItem(
                                      value: 'unpin',
                                      child: Text('Unpin from Dock'),
                                      onTap: () => _unpinApp(app['exec']),
                                    ),
                                  ],
                                );
                              },
                              child: InkWell(
                                onTap: () => _launchApp(app['exec']),
                                borderRadius: BorderRadius.circular(16),
                                hoverColor: FyrTheme.hoverColor,
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  alignment: Alignment.center,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    child: iconWidget,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
