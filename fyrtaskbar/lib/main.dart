import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/taskbar_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wayland_layer_shell/wayland_layer_shell.dart';
import 'package:wayland_layer_shell/types.dart';
import 'fyr_theme.dart';

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
