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

final waylandLayerShellPlugin = WaylandLayerShell();
const MethodChannel _dockChannel = MethodChannel('fyrdock/resize');

Future<bool> _bindDockToOutput(DisplayOutputInfo? target) async {
  if (target == null) return false;
  try {
    final res = await _dockChannel.invokeMethod<bool>(
      'setMonitor',
      target.toMonitorArgs(),
    );
    return res ?? false;
  } catch (_) {
    return false;
  }
}

/// Returns true when [rawAppId] identifies the Fyr search/launcher overlay.
bool isSearchOverlayAppId(String rawAppId) {
  final id = rawAppId.toLowerCase();
  return id == 'launcher' ||
      id.contains('fyrsearch') ||
      id.contains('sway_launcher');
}

void main() async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final DisplayOutputInfo? initialTarget = await resolveTargetDisplayOutput();

  // gtk_layer_init_for_window is performed natively in my_application.cc
  // before gtk_widget_realize so wlroots >= 0.20 always sees valid geometry.
  bool isSupported = false;
  try {
    isSupported =
        await _dockChannel.invokeMethod<bool>('isLayerSupported') ?? false;
  } catch (_) {}
  if (isSupported) {
    try {
      await _dockChannel.invokeMethod(
        'setNamespace',
        'fyrdock',
      );
    } catch (_) {}
    await _bindDockToOutput(initialTarget);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeBottom, true);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeLeft, false);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeRight, false);
    await waylandLayerShellPlugin.setAnchor(ShellEdge.edgeTop, false);

    await waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
    await waylandLayerShellPlugin.setMargin(ShellEdge.edgeBottom, 0);
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
    await _bindDockToOutput(initialTarget);
    await windowManager.show();
  });

  runApp(FyrDockApp(initialTarget: initialTarget));
}

class FyrDockApp extends StatelessWidget {
  final DisplayOutputInfo? initialTarget;
  const FyrDockApp({super.key, this.initialTarget});

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
        home: DockScreen(initialTarget: initialTarget),
      ),
    );
  }
}

class DockScreen extends StatefulWidget {
  final DisplayOutputInfo? initialTarget;
  const DockScreen({super.key, this.initialTarget});

  @override
  State<DockScreen> createState() => _DockScreenState();
}

class _DockScreenState extends State<DockScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _pinnedApps = [];
  List<Map<String, dynamic>> _openWindows = [];
  Timer? _hideDebounce;
  Timer? _visibilityDebounce;
  Timer? _fullscreenRecheckTimer;
  Timer? _geometryPollTimer;
  Timer? _monitorSyncDebounce;
  DisplayOutputInfo? _boundTarget;
  SwaySubscription? _swaySub;
  StreamSubscription<FileSystemEvent>? _dockDirSub;
  StreamSubscription<FileSystemEvent>? _fyrDirSub;
  bool _isVisible = true;
  bool _isSearchOverlayOpen = false;
  bool _hasFullscreenWindow = false;
  bool _hasTrackableVisibleWindows = false;
  bool _didInitialVisibilityCheck = false;
  bool _checkingVisibility = false;
  bool _pendingVisibilityRecheck = false;
  bool _autohide = false; // Static by default
  bool _initializedAutohide = false;
  double _dockWidth = -1.0;
  double _dockHeight = -1.0;
  String _inputMode = '';
  bool _isHoveredMain = false;
  String? _previewId;
  String? _previewExec;
  double? _previewX;
  late final AnimationController _fadeController;

  bool get _forceHidden => _isSearchOverlayOpen || _hasFullscreenWindow;

  bool get _shouldShowDock =>
      _initializedAutohide &&
      !_forceHidden &&
      (!_autohide || _isVisible || _isHoveredMain || _previewId != null);

  void _syncVisibilityAnimation() {
    if (_forceHidden) {
      if (_fadeController.value != 0.0 || _fadeController.isAnimating) {
        _fadeController.value = 0.0;
      }
      return;
    }
    if (_shouldShowDock) {
      if (_fadeController.status != AnimationStatus.forward &&
          _fadeController.status != AnimationStatus.completed) {
        _fadeController.forward();
      }
    } else {
      if (_fadeController.status != AnimationStatus.reverse &&
          _fadeController.status != AnimationStatus.dismissed) {
        _fadeController.reverse();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 0.0,
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && mounted) {
          setState(() {});
        }
      });
    _initializeDock();
  }

  Future<void> _initializeDock() async {
    _boundTarget = widget.initialTarget;
    await _loadConfig();
    await _loadPinnedApps();
    await _syncDockMonitor(forceRebind: _boundTarget == null);
    await _checkWindowVisibility();
    _startSwaySubscription();
    _startConfigWatcher();
  }

  void _startSwaySubscription() {
    _swaySub?.cancel();
    _swaySub = SwayIpc.subscribe(
      const ['window', 'workspace', 'output'],
      onEvent: (event) {
        if (!event.containsKey('container') && !event.containsKey('current')) {
          _scheduleMonitorSync();
        }
        _scheduleVisibilityCheck();
      },
    );
  }

  void _scheduleMonitorSync() {
    _monitorSyncDebounce?.cancel();
    _monitorSyncDebounce = Timer(
      const Duration(milliseconds: 150),
      () => _syncDockMonitor(),
    );
  }

  Future<void> _syncDockMonitor({bool forceRebind = false}) async {
    final next = await resolveTargetDisplayOutput();
    if (next == null) return;
    if (!forceRebind && next.samePlacement(_boundTarget)) return;
    _boundTarget = next;
    await _bindDockToOutput(next);
    _scheduleVisibilityCheck();
  }

  void _scheduleVisibilityCheck() {
    _visibilityDebounce?.cancel();
    _visibilityDebounce = Timer(
      const Duration(milliseconds: 16),
      _checkWindowVisibility,
    );
  }

  void _startConfigWatcher() {
    _dockDirSub?.cancel();
    try {
      final dir = Directory(
        '${Platform.environment['HOME']}/.config/fyrdock',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _dockDirSub = dir
          .watch(
            events:
                FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.move |
                FileSystemEvent.delete,
          )
          .listen(
            (event) {
              if (event.path.contains('config.json')) {
                _loadConfig();
              } else if (event.path.contains('pinned_apps.json')) {
                _loadPinnedApps();
              }
            },
            onError: (_) {},
          );
    } catch (_) {}

    _fyrDirSub?.cancel();
    try {
      final fyrDir = Directory(
        '${Platform.environment['HOME']}/.config/fyr',
      );
      if (!fyrDir.existsSync()) {
        fyrDir.createSync(recursive: true);
      }
      _fyrDirSub = fyrDir.watch().listen(
        (event) {
          if (event.path.endsWith('primary_display')) {
            _scheduleMonitorSync();
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _loadConfig() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/config.json',
    );
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data['autohide'] != null) {
          bool newAutohide = data['autohide'];
          if (newAutohide != _autohide || !_initializedAutohide) {
            setState(() {
              _autohide = newAutohide;
            });
            _initializedAutohide = true;
            if (!_autohide) {
              waylandLayerShellPlugin.setExclusiveZone(72);
              waylandLayerShellPlugin.setLayer(
                _isSearchOverlayOpen
                    ? ShellLayer.layerBottom
                    : ShellLayer.layerTop,
              );
            } else {
              waylandLayerShellPlugin.setExclusiveZone(0);
              waylandLayerShellPlugin.setLayer(
                _isSearchOverlayOpen
                    ? ShellLayer.layerBottom
                    : ShellLayer.layerTop,
              );
            }
            if (_autohide) {
              await _checkWindowVisibility();
            } else {
              _syncGeometryPollTimer();
              if (mounted) {
                setState(() => _isVisible = !_forceHidden);
              }
              _updateWindowWidth();
            }
          }
        }
      } catch (_) {}
    }
    if (!_initializedAutohide) {
      _initializedAutohide = true;
      waylandLayerShellPlugin.setExclusiveZone(_autohide ? 0 : 72);
      waylandLayerShellPlugin.setLayer(
        _isSearchOverlayOpen ? ShellLayer.layerBottom : ShellLayer.layerTop,
      );
      _updateWindowWidth();
    }
  }

  void _syncGeometryPollTimer() {
    final shouldPoll =
        mounted &&
        _autohide &&
        !_isSearchOverlayOpen &&
        _hasTrackableVisibleWindows;
    if (shouldPoll) {
      if (_geometryPollTimer == null || !_geometryPollTimer!.isActive) {
        _geometryPollTimer = Timer.periodic(
          const Duration(milliseconds: 200),
          (_) {
            if (!_checkingVisibility) {
              _checkWindowVisibility();
            }
          },
        );
      }
    } else {
      _geometryPollTimer?.cancel();
      _geometryPollTimer = null;
    }
  }

  static bool _windowsDiffer(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      final wa = a[i];
      final wb = b[i];
      if (wa['con_id'] != wb['con_id'] ||
          wa['app_id'] != wb['app_id'] ||
          wa['name'] != wb['name'] ||
          wa['is_minimized'] != wb['is_minimized'] ||
          wa['is_focused'] != wb['is_focused'] ||
          wa['workspace'] != wb['workspace']) {
        return true;
      }
      final ma = wa['marks'] as List? ?? const [];
      final mb = wb['marks'] as List? ?? const [];
      if (ma.length != mb.length) return true;
      for (int j = 0; j < ma.length; j++) {
        if (ma[j] != mb[j]) return true;
      }
    }
    return false;
  }

  Future<Map<String, int>?> _getMonitorRect() async {
    try {
      const channel = MethodChannel('fyrdock/resize');
      final res = await channel.invokeMethod('getMonitorRect');
      if (res is Map) {
        return {
          'x': (res['x'] as num).toInt(),
          'y': (res['y'] as num).toInt(),
          'width': (res['width'] as num).toInt(),
          'height': (res['height'] as num).toInt(),
        };
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getPrimaryDisplayName() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      final file = File('$home/.config/fyr/primary_display');
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isNotEmpty) return content;
      }
    } catch (_) {}
    return null;
  }

  String? _resolveDockOutputName(
    Map<String, dynamic> tree,
    Map<String, int>? monitorRect,
    String? primaryDisplayName,
  ) {
    final outputs = (tree['nodes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((n) => n['type'] == 'output' && n['name'] != '__i3')
        .toList();
    if (outputs.isEmpty) return null;

    if (primaryDisplayName != null) {
      for (final out in outputs) {
        if (out['name']?.toString() == primaryDisplayName) {
          // If GDK currently places the dock on a different rect than the primary
          // output, trigger a monitor rebind so taskbar and dock stay synced.
          if (monitorRect != null && out['rect'] is Map) {
            final rect = out['rect'] as Map;
            final x = (rect['x'] as num?)?.toInt() ?? 0;
            final y = (rect['y'] as num?)?.toInt() ?? 0;
            final w = (rect['width'] as num?)?.toInt() ?? 0;
            final h = (rect['height'] as num?)?.toInt() ?? 0;
            if ((x - monitorRect['x']!).abs() > 2 ||
                (y - monitorRect['y']!).abs() > 2 ||
                (w - monitorRect['width']!).abs() > 2 ||
                (h - monitorRect['height']!).abs() > 2) {
              _scheduleMonitorSync();
            }
          }
          return primaryDisplayName;
        }
      }
    }

    if (monitorRect != null) {
      for (final out in outputs) {
        final rect = out['rect'];
        if (rect is Map) {
          final x = (rect['x'] as num?)?.toInt() ?? 0;
          final y = (rect['y'] as num?)?.toInt() ?? 0;
          final w = (rect['width'] as num?)?.toInt() ?? 0;
          final h = (rect['height'] as num?)?.toInt() ?? 0;
          if ((x - monitorRect['x']!).abs() <= 2 &&
              (y - monitorRect['y']!).abs() <= 2 &&
              (w - monitorRect['width']!).abs() <= 2 &&
              (h - monitorRect['height']!).abs() <= 2) {
            return out['name']?.toString();
          }
        }
      }
    }

    for (final out in outputs) {
      final rect = out['rect'];
      if (rect is Map &&
          (rect['x'] as num?)?.toInt() == 0 &&
          (rect['y'] as num?)?.toInt() == 0) {
        return out['name']?.toString();
      }
    }
    return outputs.first['name']?.toString();
  }

  Future<void> _checkWindowVisibility() async {
    if (_checkingVisibility) {
      _pendingVisibilityRecheck = true;
      return;
    }
    _checkingVisibility = true;
    try {
      final results = await Future.wait<dynamic>([
        SwayIpc.getTree(),
        _getMonitorRect(),
        _getPrimaryDisplayName(),
      ]);
      final tree = results[0] as Map<String, dynamic>?;
      final monitorRect = results[1] as Map<String, int>?;
      final primaryDisplayName = results[2] as String?;
      if (tree != null) {
        final dockOutputName = _resolveDockOutputName(
          tree,
          monitorRect,
          primaryDisplayName,
        );
        List<Map<String, dynamic>> windows = [];
        bool hasVisibleWindows = false;
        bool hasSearchOverlay = false;
        bool hasFullscreenWindow = false;
        bool hasTrackableVisible = false;
        double screenX = 0;
        double screenY = 0;
        double screenWidth = 1920;
        double screenHeight = 1080;

        if (tree['rect'] != null) {
          final w = (tree['rect']['width'] as num?)?.toDouble() ?? 0;
          final h = (tree['rect']['height'] as num?)?.toDouble() ?? 0;
          if (w > 0 && h > 0) {
            screenWidth = w;
            screenHeight = h;
          }
        }

        void traverse(
          Map<String, dynamic> node,
          bool isScratch,
          String? currentWorkspace,
          bool isDockOutput,
        ) {
          bool nodeOnDockOutput = isDockOutput;
          if (node['type'] == 'output' &&
              node['name'] != '__i3' &&
              node['rect'] != null) {
            nodeOnDockOutput =
                dockOutputName == null ||
                node['name']?.toString() == dockOutputName;
            final w = (node['rect']['width'] as num?)?.toDouble() ?? 0;
            final h = (node['rect']['height'] as num?)?.toDouble() ?? 0;
            if (nodeOnDockOutput && w > 0 && h > 0) {
              screenX = (node['rect']['x'] as num?)?.toDouble() ?? 0;
              screenY = (node['rect']['y'] as num?)?.toDouble() ?? 0;
              screenWidth = w;
              screenHeight = h;
            }
          }

          bool currentScratch = isScratch || node['name'] == '__i3_scratch';
          String? ws = node['type'] == 'workspace'
              ? node['name']
              : currentWorkspace;

          if ((node['type'] == 'con' || node['type'] == 'floating_con') &&
              (node['app_id'] != null ||
                  node['window_properties']?['class'] != null ||
                  node['name'] != null)) {
            final appId =
                (node['app_id'] ??
                        node['window_properties']?['class'] ??
                        node['name'])
                    .toString()
                    .toLowerCase();
            if (isSearchOverlayAppId(appId)) {
              if (!currentScratch && node['visible'] == true) {
                hasSearchOverlay = true;
              }
            } else if (!appId.contains('fyrtaskbar') &&
                !appId.contains('fyrdock') &&
                !appId.contains('fyroverview') &&
                !appId.contains('fyrhelp') &&
                !appId.contains('fyremoji') &&
                !appId.contains('fyrwindowoverview') &&
                !appId.contains('fyrdesktop')) {
              windows.add({
                'app_id': appId,
                'name': node['name'],
                'pid': node['pid'],
                'is_minimized': currentScratch,
                'is_focused': node['focused'] == true,
                'con_id': node['id'],
                'workspace': ws,
                'marks': node['marks'] ?? [],
              });
              final int fsMode =
                  (node['fullscreen_mode'] as num?)?.toInt() ?? 0;
              final bool isGlobalFullscreen = fsMode == 2;
              if (!currentScratch &&
                  node['visible'] == true &&
                  (nodeOnDockOutput || isGlobalFullscreen)) {
                hasTrackableVisible = true;
                if (fsMode > 0) {
                  hasVisibleWindows = true;
                  hasFullscreenWindow = true;
                } else if (node['rect'] != null) {
                  double wx = (node['rect']['x'] as num).toDouble();
                  double wy = (node['rect']['y'] as num).toDouble();
                  double ww = (node['rect']['width'] as num).toDouble();
                  double wh = (node['rect']['height'] as num).toDouble();
                  double effectiveDockWidth = _dockWidth > 0 ? _dockWidth : 400;
                  double dockX = screenX + (screenWidth - effectiveDockWidth) / 2;
                  double dockY = screenY + screenHeight - 88;
                  if (wx < dockX + effectiveDockWidth &&
                      wx + ww > dockX &&
                      wy < dockY + 88 &&
                      wy + wh > dockY) {
                    hasVisibleWindows = true;
                  }
                }
              }
            }
          }
          for (var child in (node['nodes'] ?? []))
            traverse(child, currentScratch, ws, nodeOnDockOutput);
          for (var child in (node['floating_nodes'] ?? []))
            traverse(child, currentScratch, ws, nodeOnDockOutput);
        }

        traverse(tree, false, null, dockOutputName == null);

        if (mounted) {
          _hasTrackableVisibleWindows = hasTrackableVisible;
          final nextForceHidden = hasSearchOverlay || hasFullscreenWindow;
          final nextIsVisible = nextForceHidden
              ? false
              : (_autohide ? !hasVisibleWindows : true);
          final wasFullscreen = _hasFullscreenWindow;
          final overlayChanged = hasSearchOverlay != _isSearchOverlayOpen;
          final stateChanged =
              !_didInitialVisibilityCheck ||
              nextIsVisible != _isVisible ||
              hasSearchOverlay != _isSearchOverlayOpen ||
              hasFullscreenWindow != _hasFullscreenWindow ||
              _windowsDiffer(_openWindows, windows);
          _didInitialVisibilityCheck = true;

          if (stateChanged) {
            setState(() {
              _openWindows = windows;
              _isSearchOverlayOpen = hasSearchOverlay;
              _hasFullscreenWindow = hasFullscreenWindow;
              if (nextForceHidden) {
                _isHoveredMain = false;
                _previewId = null;
                _previewExec = null;
                _isVisible = false;
              } else {
                _isVisible = nextIsVisible;
              }
            });
            if (overlayChanged) {
              waylandLayerShellPlugin.setLayer(
                hasSearchOverlay ? ShellLayer.layerBottom : ShellLayer.layerTop,
              );
            }
            if (wasFullscreen && !hasFullscreenWindow) {
              _fullscreenRecheckTimer?.cancel();
              _fullscreenRecheckTimer = Timer(
                const Duration(milliseconds: 250),
                _checkWindowVisibility,
              );
            } else if (hasFullscreenWindow) {
              _fullscreenRecheckTimer?.cancel();
            }
            _updateWindowWidth();
          }
          _syncGeometryPollTimer();
        }
      }
    } catch (_) {} finally {
      _checkingVisibility = false;
      if (_pendingVisibilityRecheck && mounted) {
        _pendingVisibilityRecheck = false;
        _checkWindowVisibility();
      }
    }
  }

  @override
  void dispose() {
    _hideDebounce?.cancel();
    _visibilityDebounce?.cancel();
    _fullscreenRecheckTimer?.cancel();
    _geometryPollTimer?.cancel();
    _monitorSyncDebounce?.cancel();
    _swaySub?.cancel();
    _dockDirSub?.cancel();
    _fyrDirSub?.cancel();
    _fadeController.dispose();
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

  Future<void> _savePinnedApps() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/pinned_apps.json',
    );
    await file.writeAsString(jsonEncode(_pinnedApps));
  }

  void _updateWindowWidth() async {
    double width =
        (_pinnedApps.length + 1) * 64.0 + 32.0; // +1 for All Apps button
    // Add width for unpinned running apps
    int unpinnedCount = _getUnpinnedWindows().length;
    width += unpinnedCount * 64.0;
    if (unpinnedCount > 0) width += 16.0; // divider width

    if (_previewId != null) {
      List<Map<String, dynamic>> prevWindows = [];
      for (var p in _pinnedApps) {
        if (p['exec'] == _previewId) {
          prevWindows = _openWindows.where((w) => _matchesApp(p, w)).toList();
          break;
        }
      }
      if (prevWindows.isEmpty) {
        prevWindows = _openWindows
            .where((w) => w['app_id'] == _previewId)
            .toList();
      }
      double previewWidth = prevWindows.length * 140.0 + 32.0;
      if (previewWidth > width) {
        width = previewWidth;
      }
    }

    if (width < 100) width = 100;

    _syncVisibilityAnimation();
    bool shouldShow = _shouldShowDock;
    // Keep the layer surface at a normal height (88 / 200) and toggle the
    // pointer input region instead of shrinking GtkWindow below FlView's
    // minimum height (which stalls GTK/EGL frame scheduling under Wayland).
    double height = _previewId != null ? 200.0 : 88.0;
    final String nextInputMode = _forceHidden
        ? 'empty'
        : (!shouldShow ? 'edge' : 'full');

    final bool sizeChanged = _dockWidth != width || _dockHeight != height;
    final bool inputChanged = _inputMode != nextInputMode || (sizeChanged && nextInputMode == 'edge');
    if (!sizeChanged && !inputChanged) return;

    _dockWidth = width;
    _dockHeight = height;
    _inputMode = nextInputMode;

    const channel = MethodChannel('fyrdock/resize');
    if (sizeChanged) {
      try {
        await channel.invokeMethod('setSize', {
          'width': width.toInt(),
          'height': height.toInt(),
        });
      } catch (_) {}
      await windowManager.setSize(Size(width, height));
    }
    if (inputChanged) {
      try {
        if (nextInputMode == 'empty') {
          await channel.invokeMethod('setInputRegion', {'empty': true});
        } else if (nextInputMode == 'edge') {
          await channel.invokeMethod('setInputRegion', {
            'x': 0,
            'y': height.toInt() - 8,
            'width': width.toInt(),
            'height': 8,
          });
        } else {
          await channel.invokeMethod('setInputRegion', {'full': true});
        }
      } catch (_) {}
    }
  }

  Future<String?> _findIcon(String? iconName) async {
    if (iconName == null || iconName.isEmpty) return null;
    if (iconName.startsWith('/')) return iconName;

    final name = iconName
        .toLowerCase()
        .replaceAll('dev.fyrde.', '')
        .replaceAll('com.fyr.', '')
        .replaceAll('com.example.', '')
        .replaceAll('fyr_', 'fyr');
    final possibleNames = [iconName, name, name.replaceAll('fyr', '')];
    
    final List<String> possiblePaths = [];
    for (var n in possibleNames) {
      possiblePaths.addAll([
        '/usr/share/pixmaps/$n.png',
        '/usr/share/pixmaps/$n.svg',
        '/usr/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$n.svg',
        '/usr/share/icons/${FyrTheme.iconThemeName}/48/apps/$n.svg',
        '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$n.svg',
        '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/48/apps/$n.svg',
        '/usr/share/icons/hicolor/scalable/apps/$n.svg',
        '/usr/share/icons/hicolor/48x48/apps/$n.png',
        '/usr/share/icons/hicolor/128x128/apps/$n.png',
        '/usr/share/icons/hicolor/256x256/apps/$n.png',
        '/usr/share/icons/hicolor/512x512/apps/$n.png',
        '/usr/share/icons/Adwaita/scalable/apps/$n.svg',
        '/usr/share/icons/breeze/apps/48/$n.svg',
        '/usr/share/icons/Papirus/48x48/apps/$n.svg',
        '${Platform.environment['HOME']}/.local/share/icons/hicolor/scalable/apps/$n.svg',
        '${Platform.environment['HOME']}/.local/share/icons/hicolor/48x48/apps/$n.png',
        '${Platform.environment['HOME']}/.local/share/icons/hicolor/128x128/apps/$n.png',
        '${Platform.environment['HOME']}/.local/share/icons/hicolor/256x256/apps/$n.png',
        '${Platform.environment['HOME']}/.local/share/icons/hicolor/512x512/apps/$n.png',
        '${Platform.environment['HOME']}/.local/share/icons/$n.png',
        '${Platform.environment['HOME']}/.local/share/icons/$n.svg',
      ]);
    }

    for (var p in possiblePaths) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  void _unpinApp(String exec) async {
    setState(() {
      _pinnedApps.removeWhere((p) => p['exec'] == exec);
    });
    await _savePinnedApps();
  }

  void _launchApp(String exec) {
    final parts = exec.split(' ');
    if (parts.isNotEmpty) {
      try {
        final home = Platform.environment['HOME'] ?? '';
        final currentPath = Platform.environment['PATH'] ?? '';
        final env = Map<String, String>.from(Platform.environment);
        if (home.isNotEmpty && !currentPath.contains('$home/.local/bin')) {
          env['PATH'] = '$home/.local/bin:$currentPath';
        }
        var cmd = parts[0];
        final baseName = cmd.split('/').last;
        if (home.isNotEmpty && File('$home/.local/bin/$baseName').existsSync()) {
          cmd = '$home/.local/bin/$baseName';
        }
        Process.start(cmd, parts.sublist(1), environment: env);
      } catch (e) {
        print(e);
      }
    }
  }

  bool _matchesApp(
    Map<String, dynamic> pinnedApp,
    Map<String, dynamic> window,
  ) {
    final exec = (pinnedApp['exec'] as String).toLowerCase();
    final appId = (window['app_id'] as String).toLowerCase();
    final strippedId = appId
        .replaceAll('dev.fyrde.', '')
        .replaceAll('com.fyr.', '')
        .replaceAll('com.example.', '')
        .replaceAll('fyr_', 'fyr');
    final name = (pinnedApp['name'] as String).toLowerCase();
    
    if (exec.contains(appId) || appId.contains(exec.split(' ')[0])) return true;
    if (exec.contains(strippedId) || strippedId.contains(exec.split(' ')[0])) return true;
    if (name.contains(appId) || appId.contains(name)) return true;
    if (name.contains(strippedId) || strippedId.contains(name)) return true;
    return false;
  }

  List<Map<String, dynamic>> _getUnpinnedWindows() {
    List<Map<String, dynamic>> unpinned = [];
    for (var win in _openWindows) {
      bool isPinned = false;
      for (var p in _pinnedApps) {
        if (_matchesApp(p, win)) {
          isPinned = true;
          break;
        }
      }
      if (!isPinned) {
        // Check if we already added this app_id to group them
        if (!unpinned.any((u) => u['app_id'] == win['app_id'])) {
          unpinned.add(win);
        }
      }
    }
    return unpinned;
  }

  void _handleAppTap(
    List<Map<String, dynamic>> windows,
    String? exec,
    String appId,
    BuildContext context,
  ) {
    bool hasMinimized = windows.any((w) => w['is_minimized']);
    bool allUp = windows.isNotEmpty && !hasMinimized;
    String matchId = exec ?? appId;

    if (windows.isNotEmpty && (appId.contains('fyrbrowser') || (exec?.contains('fyrbrowser') ?? false))) {
      _resumeWindow(windows.first);
      return;
    }

    if (windows.isEmpty || allUp) {
      if (exec != null) _launchApp(exec);
      setState(() {
        _previewId = null;
        _previewExec = null;
      });
      _updateWindowWidth();
      return;
    }

    if (_previewId != matchId) {
      final box = context.findRenderObject() as RenderBox;
      final position = box.localToGlobal(Offset.zero);
      setState(() {
        _previewId = matchId;
        _previewExec = exec;
        _previewX = position.dx + box.size.width / 2;
      });
    } else {
      if (exec != null) _launchApp(exec);
      setState(() {
        _previewId = null;
        _previewExec = null;
      });
    }
    _updateWindowWidth();
  }

  void _resumeWindow(Map<String, dynamic> window) {
    if (window['is_minimized']) {

      Process.run('swaymsg', [
        '[con_id="${window['con_id']}"] scratchpad show',
      ]);
    } else {
      Process.run('swaymsg', [
        '[con_id="${window['con_id']}"] focus',
      ]);
    }
    setState(() {
      _previewId = null;
      _previewExec = null;
    });
    _updateWindowWidth();
  }

  Widget _buildIconWidget(String? iconPath, String fallbackName) {
    if (iconPath != null) {
      if (iconPath.toLowerCase().endsWith('.svg')) {
        return SvgPicture.file(
          File(iconPath),
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        );
      } else {
        return Image.file(
          File(iconPath),
          width: 48,
          height: 48,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.widgets,
            color: FyrTheme.textColor.withOpacity(0.8),
            size: 32,
          ),
        );
      }
    }
    return Icon(
      Icons.widgets,
      color: FyrTheme.textColor.withOpacity(0.8),
      size: 32,
    );
  }

  Widget _buildAllAppsButton() {
    return _DockIcon(
      name: 'All Apps',
      iconWidget: Icon(Icons.apps, color: FyrTheme.textColor, size: 32),
      onTap: () async {
        final home = Platform.environment['HOME'] ?? '';
        final launcherScript = '$home/.config/fyr/launcher_toggle.sh';
        if (File(launcherScript).existsSync()) {
          await Process.run(launcherScript, []);
        } else {
          await Process.start(
            '/opt/fyrsearch/fyrsearch',
            ['--show'],
            mode: ProcessStartMode.detached,
          );
        }
        await _checkWindowVisibility();
      },
      onUnpin: null,
      isOpen: false,
      isMinimized: false,
      isFocused: false,
    );
  }

  Widget _buildPreviewPopup(List<Map<String, dynamic>> prevWindows) {
    if (prevWindows.isEmpty) return const SizedBox();

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FyrTheme.panelBgColor.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FyrTheme.cardColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: prevWindows.map((w) {
          return FutureBuilder<String?>(
            future: _findIcon(w['app_id']),
            builder: (context, snapshot) {
              return InkWell(
                onTap: () => _resumeWindow(w),
                borderRadius: BorderRadius.circular(8),
                hoverColor: FyrTheme.hoverColor,
                child: Container(
                  width: 140,
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIconWidget(snapshot.data, w['app_id'] ?? ''),
                      SizedBox(height: 8),
                      Text(
                        w['name'] ?? 'Window',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> unpinnedWindows = _getUnpinnedWindows();

    Widget? previewWidget;
    if (_previewId != null && _previewX != null) {
      List<Map<String, dynamic>> prevWindows = [];
      for (var p in _pinnedApps) {
        if (p['exec'] == _previewId) {
          prevWindows = _openWindows.where((w) => _matchesApp(p, w)).toList();
          break;
        }
      }
      if (prevWindows.isEmpty) {
        prevWindows = _openWindows
            .where((w) => w['app_id'] == _previewId)
            .toList();
      }
      
      if (prevWindows.isNotEmpty) {
        double previewWidth = prevWindows.length * 140.0 + 16.0;
        double leftPos = _previewX! - (previewWidth / 2);
        if (leftPos < 16) leftPos = 16;
        if (leftPos + previewWidth > _dockWidth - 16) leftPos = _dockWidth - previewWidth - 16;

        previewWidget = Positioned(
          bottom: 84, // 64 (dock height) + 20 (margin)
          left: leftPos,
          child: _buildPreviewPopup(prevWindows),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        hitTestBehavior: HitTestBehavior.opaque,
        onEnter: (_) {
          _hideDebounce?.cancel();
          if (_forceHidden) return;
          if (!_isHoveredMain) {
            setState(() => _isHoveredMain = true);
            _updateWindowWidth();
          }
          waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
        },
        onHover: (_) {
          _hideDebounce?.cancel();
          if (_forceHidden) return;
          if (!_isHoveredMain) {
            setState(() => _isHoveredMain = true);
            _updateWindowWidth();
          }
        },
        onExit: (_) {
          _hideDebounce?.cancel();
          _hideDebounce = Timer(const Duration(milliseconds: 180), () {
            if (mounted) {
              setState(() {
                _isHoveredMain = false;
                if (_autohide && !_isVisible) {
                  _previewId = null;
                  _previewExec = null;
                }
              });
              _updateWindowWidth();
            }
          });
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.transparent,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: 200,
              alignment: Alignment.bottomCenter,
              child: (!_shouldShowDock && _fadeController.isDismissed)
                  ? SizedBox(
                      width: _dockWidth > 0 ? _dockWidth : 800,
                      height: 200,
                      child: const CustomPaint(painter: _ClearSurfacePainter()),
                    )
                  : FadeTransition(
                      opacity: _fadeController,
                      child: SizedBox(
                        width: _dockWidth > 0 ? _dockWidth : 800,
                  height: 200,
                  child: Stack(
                    children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: EdgeInsets.only(bottom: 20),
                  height: 64,
                  decoration: BoxDecoration(
                    color: FyrTheme.panelBgColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: FyrTheme.isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.12),
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
                        children: [
                          _buildAllAppsButton(),
                          SizedBox(width: 8),
                          // Pinned Apps (Reorderable)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _pinnedApps.asMap().entries.map((entry) {
                              int index = entry.key;
                              var app = entry.value;
                              List<Map<String, dynamic>> runningWindows = [];
                              for (var w in _openWindows) {
                                if (_matchesApp(app, w)) {
                                  runningWindows.add(w);
                                }
                              }

                              Widget iconChild = FutureBuilder<String?>(
                                future: _findIcon(app['icon']),
                                builder: (context, snapshot) {
                                  return _DockIcon(
                                    name: app['name'] ?? '',
                                    iconWidget: _buildIconWidget(
                                      snapshot.data,
                                      app['name'] ?? '',
                                    ),
                                    onTap: () => _handleAppTap(
                                      runningWindows,
                                      app['exec'],
                                      app['exec'],
                                      context,
                                    ),
                                    onUnpin: () => _unpinApp(app['exec']),
                                    isOpen: runningWindows.isNotEmpty,
                                    isMinimized:
                                        runningWindows.isNotEmpty &&
                                        runningWindows.every(
                                          (w) => w['is_minimized'] == true,
                                        ),
                                    isFocused: runningWindows.any(
                                      (w) => w['is_focused'] == true,
                                    ),
                                  );
                                },
                              );

                              return DragTarget<int>(
                                onAcceptWithDetails: (details) {
                                  setState(() {
                                    final item = _pinnedApps.removeAt(
                                      details.data,
                                    );
                                    _pinnedApps.insert(index, item);
                                  });
                                  _savePinnedApps();
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                      return Draggable<int>(
                                        data: index,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: Opacity(
                                            opacity: 0.8,
                                            child: iconChild,
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.3,
                                          child: iconChild,
                                        ),
                                        child: iconChild,
                                      );
                                    },
                              );
                            }).toList(),
                          ),
                          if (unpinnedWindows.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 12.0,
                              ),
                              child: VerticalDivider(
                                color: FyrTheme.textColor.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            // Unpinned Running Apps
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: unpinnedWindows.map((win) {
                                return FutureBuilder<String?>(
                                  future: _findIcon(win['app_id']),
                                  builder: (context, snapshot) {
                                    return _DockIcon(
                                      name: win['name'] ?? win['app_id'],
                                      iconWidget: _buildIconWidget(
                                        snapshot.data,
                                        win['app_id'],
                                      ),
                                      onTap: () {
                                        List<Map<String, dynamic>> group =
                                            _openWindows
                                                .where(
                                                  (w) =>
                                                      w['app_id'] ==
                                                      win['app_id'],
                                                )
                                                .toList();
                                        _handleAppTap(
                                          group,
                                          null,
                                          win['app_id'],
                                          context,
                                        );
                                      },
                                      onUnpin: null, // cannot unpin
                                      isOpen: true,
                                      isMinimized: _openWindows
                                          .where(
                                            (w) => w['app_id'] == win['app_id'],
                                          )
                                          .every(
                                            (w) => w['is_minimized'] == true,
                                          ),
                                      isFocused: _openWindows
                                          .where(
                                            (w) => w['app_id'] == win['app_id'],
                                          )
                                          .any((w) => w['is_focused'] == true),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (previewWidget != null) previewWidget,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearSurfacePainter extends CustomPainter {
  const _ClearSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(covariant _ClearSurfacePainter oldDelegate) => false;
}

class _DockIcon extends StatefulWidget {
  final String name;
  final Widget iconWidget;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;
  final bool isOpen;
  final bool isMinimized;
  final bool isFocused;

  const _DockIcon({
    super.key,
    required this.name,
    required this.iconWidget,
    required this.onTap,
    this.onUnpin,
    required this.isOpen,
    required this.isMinimized,
    required this.isFocused,
  });

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: widget.name,
        child: GestureDetector(
          onSecondaryTapDown: widget.onUnpin == null
              ? null
              : (details) {
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
                        onTap: widget.onUnpin,
                      ),
                    ],
                  );
                },
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              hoverColor: FyrTheme.hoverColor,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                width: _isHovered ? 64 : 56,
                height: 64,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: _isHovered ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: widget.iconWidget,
                    ),
                    if (widget.isOpen)
                      Container(
                        margin: EdgeInsets.only(top: 4),
                        width: widget.isFocused
                            ? 16
                            : (widget.isMinimized ? 24 : 8),
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.isMinimized
                              ? FyrTheme.accentColor
                              : FyrTheme.textColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
