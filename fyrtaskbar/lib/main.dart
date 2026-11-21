import 'dart:async';
import 'dart:io';
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

const MethodChannel _taskbarChannel = MethodChannel('fyrtaskbar/resize');

String? _parseOutputArg(List<String> args) {
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--output=')) {
      final val = arg.substring('--output='.length).trim();
      return val.isEmpty ? null : val;
    }
    if (arg == '--output' && i + 1 < args.length) {
      final val = args[i + 1].trim();
      return val.isEmpty ? null : val;
    }
  }
  return null;
}

Future<bool> _bindWindowToOutput(DisplayOutputInfo? target) async {
  if (target == null) return false;
  try {
    final res = await _taskbarChannel.invokeMethod<bool>(
      'setMonitor',
      target.toMonitorArgs(),
    );
    return res ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> _applyWindowSize(int width, int height) async {
  try {
    await _taskbarChannel.invokeMethod('setSize', {
      'width': width,
      'height': height,
    });
  } catch (_) {}
  try {
    await windowManager.setSize(Size(width.toDouble(), height.toDouble()));
  } catch (_) {}
}

/// Manages one `--desktop` layer surface per active Sway output so desktop
/// right-click works across every monitor, including on hotplug.
class _DesktopLayerCoordinator {
  DisplayOutputInfo? ownTarget;
  final Map<String, Process> _workers = {};
  SwaySubscription? _swaySub;
  Timer? _syncDebounce;
  bool _disposed = false;

  _DesktopLayerCoordinator(this.ownTarget);

  Future<void> start() async {
    await _reconcileOutputs();
    _swaySub = SwayIpc.subscribe(
      const ['output'],
      onEvent: (_) => _scheduleReconcile(),
    );
    try {
      ProcessSignal.sigterm.watch().listen((_) async {
        await stop();
        exit(0);
      });
      ProcessSignal.sigint.watch().listen((_) async {
        await stop();
        exit(0);
      });
    } catch (_) {}
  }

  void _scheduleReconcile() {
    if (_disposed) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 250), _reconcileOutputs);
  }

  Future<void> _reconcileOutputs() async {
    if (_disposed) return;
    final outputs = await getActiveSwayOutputs();
    if (outputs.isEmpty) return;

    final preferred = await readConfiguredPrimaryDisplay();
    DisplayOutputInfo nextOwn;
    if (ownTarget != null && outputs.any((o) => o.name == ownTarget!.name)) {
      nextOwn = outputs.firstWhere((o) => o.name == ownTarget!.name);
    } else {
      nextOwn =
          resolvePrimaryOutput(outputs, preferredName: preferred) ??
          outputs.first;
    }

    // Ensure no child worker duplicates our own output before rebinding self.
    final staleSelfWorker = _workers.remove(nextOwn.name);
    staleSelfWorker?.kill();

    if (!nextOwn.samePlacement(ownTarget)) {
      ownTarget = nextOwn;
      SystemState.screenWidth = nextOwn.width;
      SystemState.screenHeight = nextOwn.height;
      await _bindWindowToOutput(nextOwn);
      await _applyWindowSize(nextOwn.width, nextOwn.height);
    }

    final activeOtherNames = outputs
        .where((o) => o.name != nextOwn.name)
        .map((o) => o.name)
        .toSet();

    for (final existingName in _workers.keys.toList()) {
      if (!activeOtherNames.contains(existingName)) {
        _workers.remove(existingName)?.kill();
      }
    }

    for (final name in activeOtherNames) {
      if (!_workers.containsKey(name)) {
        await _spawnWorker(name);
      }
    }
  }

  Future<void> _spawnWorker(String outputName) async {
    if (_disposed) return;
    try {
      final proc = await Process.start(
        Platform.resolvedExecutable,
        ['--desktop', '--output=$outputName'],
      );
      _workers[outputName] = proc;
      proc.exitCode.then((_) {
        if (_workers[outputName] == proc) {
          _workers.remove(outputName);
        }
      });
    } catch (_) {}
  }

  Future<void> stop() async {
    _disposed = true;
    _syncDebounce?.cancel();
    _swaySub?.cancel();
    for (final proc in _workers.values) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _workers.clear();
  }
}

/// Watches Sway output changes for a dedicated `--desktop --output=<name>`
/// worker, resizing or exiting cleanly when its monitor disconnects.
void _watchWorkerOutput(DisplayOutputInfo initialTarget) {
  DisplayOutputInfo current = initialTarget;
  Timer? debounce;
  SwayIpc.subscribe(const ['output'], onEvent: (_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () async {
      final next = await resolveTargetDisplayOutput(
        requestedOutput: current.name,
      );
      if (next == null) {
        exit(0);
      }
      if (!next.samePlacement(current)) {
        current = next;
        SystemState.screenWidth = next.width;
        SystemState.screenHeight = next.height;
        await _bindWindowToOutput(next);
        await _applyWindowSize(next.width, next.height);
      }
    });
  });
}

/// Keeps the primary taskbar bound to the shared primary display output.
void _watchTaskbarPrimaryOutput(DisplayOutputInfo? initialTarget) {
  DisplayOutputInfo? current = initialTarget;
  Timer? debounce;

  Future<void> sync() async {
    final next = await resolveTargetDisplayOutput();
    if (next == null || next.samePlacement(current)) return;
    current = next;
    SystemState.screenWidth = next.width;
    SystemState.screenHeight = next.height;
    await _bindWindowToOutput(next);
    await _applyWindowSize(next.width, 56);
  }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), sync);
  }

  SwayIpc.subscribe(const ['output'], onEvent: (_) => schedule());

  try {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final dir = Directory('$home/.config/fyr');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      dir.watch().listen((event) {
        if (event.path.endsWith('primary_display')) {
          schedule();
        }
      }, onError: (_) {});
    }
  } catch (_) {}
}

void main(List<String> args) async {
  final isDesktopLayer = args.contains('--desktop');
  final requestedOutput = _parseOutputArg(args);
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (!isDesktopLayer) {
    SystemState.init();
    await OsdService.init();

    void refreshThemeApps() {
      AppService.getInstalledAppsSync(forceRefresh: true);
    }
    FyrTheme.accentColorNotifier.addListener(refreshThemeApps);
    FyrTheme.themeModeNotifier.addListener(refreshThemeApps);

    AppService.getInstalledAppsSync();
  }

  int screenWidth = 1920;
  int screenHeight = 1080;

  final DisplayOutputInfo? initialTarget = await resolveTargetDisplayOutput(
    requestedOutput: isDesktopLayer ? requestedOutput : null,
  );
  if (isDesktopLayer && requestedOutput != null && initialTarget == null) {
    exit(0);
  }

  if (initialTarget != null) {
    screenWidth = initialTarget.width;
    screenHeight = initialTarget.height;
  } else {
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
    // gtk_layer_init_for_window is performed natively in my_application.cc
    // before gtk_widget_realize so wlroots >= 0.20 never sees an unanchored 0x0
    // initial configure request.
    bool isSupported = false;
    try {
      isSupported =
          await _taskbarChannel.invokeMethod<bool>('isLayerSupported') ?? false;
    } catch (_) {}
    if (isSupported) {
      await _applyWindowSize(screenWidth, screenHeight);
      try {
        await _taskbarChannel.invokeMethod(
          'setNamespace',
          'fyrdesktop',
        );
      } catch (_) {}
      await _bindWindowToOutput(initialTarget);
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

    await _applyWindowSize(screenWidth, screenHeight);

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
      await _bindWindowToOutput(initialTarget);
      await _applyWindowSize(screenWidth, screenHeight);
      await windowManager.show();
    });

    if (requestedOutput != null && initialTarget != null) {
      _watchWorkerOutput(initialTarget);
    } else {
      _DesktopLayerCoordinator(initialTarget).start();
    }

    runApp(const FyrDesktopLayerApp());
    return;
  }

  bool isSupported = false;
  try {
    isSupported =
        await _taskbarChannel.invokeMethod<bool>('isLayerSupported') ?? false;
  } catch (_) {}
  if (isSupported) {
    await _applyWindowSize(screenWidth, 56);
    try {
      await _taskbarChannel.invokeMethod(
        'setNamespace',
        'fyrtaskbar',
      );
    } catch (_) {}
    await _bindWindowToOutput(initialTarget);
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
    await _bindWindowToOutput(initialTarget);
    await windowManager.show();
  });

  _watchTaskbarPrimaryOutput(initialTarget);
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
