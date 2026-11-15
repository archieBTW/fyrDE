import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/services/osd_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/taskbar_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wayland_layer_shell/wayland_layer_shell.dart';
import 'package:wayland_layer_shell/types.dart';
import 'fyr_theme.dart';

void main(List<String> args) async {
  final isDesktopLayer = args.contains('--desktop');
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (!isDesktopLayer) {
    SystemState.init();
    await OsdService.init();

    FyrTheme.accentColorNotifier.addListener(() {
      AppService.cachedApps = null;
      AppService.getInstalledApps();
    });

    await AppService.getInstalledApps();
  }

  int screenWidth = 1920;
  int screenHeight = 1080;

  try {
    final swayRes = await Process.run('swaymsg', ['-t', 'get_outputs']);
    if (swayRes.exitCode == 0 && swayRes.stdout.toString().trim().isNotEmpty) {
      final List<dynamic> outputs = jsonDecode(swayRes.stdout.toString());
      String? primaryName;
      final primaryFile = File('${Platform.environment['HOME']}/.config/fyr/primary_display');
      if (await primaryFile.exists()) {
        final content = (await primaryFile.readAsString()).trim();
        if (content.isNotEmpty) primaryName = content;
      }
      if (primaryName == null) {
        final configFile = File('${Platform.environment['HOME']}/.config/sway/config');
        if (await configFile.exists()) {
          final configContent = await configFile.readAsString();
          final match = RegExp(r'assign\s+\[app_id="fyrtaskbar"\]\s+output\s+([^\s]+)').firstMatch(configContent);
          if (match != null) primaryName = match.group(1);
        }
      }
      final target = outputs.firstWhere(
        (o) => o['name'] == primaryName && o['active'] == true,
        orElse: () => outputs.firstWhere(
          (o) => o['focused'] == true,
          orElse: () => outputs.firstWhere(
            (o) => o['active'] == true,
            orElse: () => outputs.isNotEmpty ? outputs.first : null,
          ),
        ),
      );
      if (target != null && target['rect'] != null) {
        screenWidth = (target['rect']['width'] as num?)?.toInt() ?? screenWidth;
        screenHeight = (target['rect']['height'] as num?)?.toInt() ?? screenHeight;
      }
    } else {
      throw Exception('Sway outputs unavailable');
    }
  } catch (_) {
    try {
      final res = await Process.run('sh', [
        '-c',
        'cat /sys/class/drm/*/modes | head -n 1',
      ]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final parts = res.stdout.toString().trim().split('x');
        screenWidth = int.parse(parts[0]);
        screenHeight = int.parse(parts[1]);
      }
    } catch (_) {}
  }

  SystemState.screenWidth = screenWidth;
  SystemState.screenHeight = screenHeight;

  final waylandLayerShellPlugin = WaylandLayerShell();
  if (isDesktopLayer) {
    bool isSupported = await waylandLayerShellPlugin.initialize(
      screenWidth,
      screenHeight,
    );
    if (isSupported) {
      try {
        await const MethodChannel('fyrtaskbar/resize').invokeMethod(
          'setNamespace',
          'fyrdesktop',
        );
      } catch (_) {}
      await waylandLayerShellPlugin.setLayer(ShellLayer.layerBottom);
      await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeTop, true);
      await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeBottom, true);
      await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeLeft, true);
      await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeRight, true);
      await waylandLayerShellPlugin.setExclusiveZone(-1);
      await waylandLayerShellPlugin.setKeyboardMode(
        ShellKeyboardMode.keyboardModeNone,
      );
    }

    const channel = MethodChannel('fyrtaskbar/resize');
    try {
      await channel.invokeMethod('setSize', {
        'width': screenWidth,
        'height': screenHeight,
      });
    } catch (_) {}

    WindowOptions windowOptions = WindowOptions(
      size: Size(screenWidth.toDouble(), screenHeight.toDouble()),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSize(
        Size(screenWidth.toDouble(), screenHeight.toDouble()),
      );
      await windowManager.show();
    });

    runApp(const FyrDesktopLayerApp());
    return;
  }

  bool isSupported = await waylandLayerShellPlugin.initialize(screenWidth, 56);
  if (isSupported) {
    try {
      await const MethodChannel('fyrtaskbar/resize').invokeMethod(
        'setNamespace',
        'fyrtaskbar',
      );
    } catch (_) {}
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

class FyrDesktopLayerApp extends StatelessWidget {
  const FyrDesktopLayerApp({super.key});

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
        home: const DesktopBackgroundScreen(),
      ),
    );
  }
}

class DesktopBackgroundScreen extends StatefulWidget {
  const DesktopBackgroundScreen({super.key});

  @override
  State<DesktopBackgroundScreen> createState() =>
      _DesktopBackgroundScreenState();
}

class _DesktopBackgroundScreenState extends State<DesktopBackgroundScreen> {
  Offset? _menuPosition;

  void _launch(String binaryName, List<String> args) {
    setState(() => _menuPosition = null);
    final home = Platform.environment['HOME'] ?? '';
    String cmd = binaryName;
    if (home.isNotEmpty && File('$home/.local/bin/$binaryName').existsSync()) {
      cmd = '$home/.local/bin/$binaryName';
    }
    Process.start(cmd, args, mode: ProcessStartMode.detached);
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: FyrTheme.accentColor.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: FyrTheme.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const double menuWidth = 250;
    const double menuHeight = 230;
    double left = (_menuPosition?.dx ?? 0);
    double top = (_menuPosition?.dy ?? 0);
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - menuWidth - 12;
    }
    if (top + menuHeight > screenSize.height - 12) {
      top = screenSize.height - menuHeight - 12;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_menuPosition != null) {
            setState(() => _menuPosition = null);
          }
        },
        onSecondaryTapDown: (details) {
          setState(() {
            _menuPosition = details.globalPosition;
          });
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0x01000000),
          child: Stack(
            children: [
              if (_menuPosition != null)
                Positioned(
                  left: left,
                  top: top,
                  child: Container(
                    width: menuWidth,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: FyrTheme.panelBgColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: FyrTheme.cardColor,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMenuItem(
                          icon: Icons.wallpaper,
                          label: 'Change Wallpaper...',
                          onTap: () => _launch('fyrsettings', ['--appearance']),
                        ),
                        _buildMenuItem(
                          icon: Icons.palette_outlined,
                          label: 'Appearance Settings',
                          onTap: () => _launch('fyrsettings', ['--appearance']),
                        ),
                        _buildMenuItem(
                          icon: Icons.monitor,
                          label: 'Display Settings',
                          onTap: () => _launch('fyrsettings', ['--displays']),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Divider(
                            height: 1,
                            color: FyrTheme.textColor.withOpacity(0.12),
                          ),
                        ),
                        _buildMenuItem(
                          icon: Icons.folder_open,
                          label: 'Open File Manager',
                          onTap: () => _launch('fyrfiles', []),
                        ),
                        _buildMenuItem(
                          icon: Icons.terminal,
                          label: 'Open Terminal',
                          onTap: () => _launch('fyrterm', []),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
