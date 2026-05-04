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

void main() async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  bool isSupported = await waylandLayerShellPlugin.initialize(800, 200);
  if (isSupported) {
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
    await windowManager.show();
  });

  runApp(const FyrDockApp());
}

class FyrDockApp extends StatelessWidget {
  const FyrDockApp({super.key});

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
  List<Map<String, dynamic>> _openWindows = [];
  Timer? _timer;
  bool _isVisible = true;
  bool _autohide = false; // Static by default
  bool _initializedAutohide = false;
  double _dockWidth = -1.0;
  bool _isHoveredMain = false;
  String? _previewId;
  String? _previewExec;
  double? _previewX;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadPinnedApps();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _loadConfig();
      _loadPinnedApps();
      _checkWindowVisibility();
    });
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
              waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
            } else {
              waylandLayerShellPlugin.setExclusiveZone(0);
              waylandLayerShellPlugin.setLayer(ShellLayer.layerBottom);
            }
          }
        }
      } catch (_) {}
    } else {
      if (!_autohide && !_initializedAutohide) {
        _initializedAutohide = true;
        waylandLayerShellPlugin.setExclusiveZone(72);
        waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
      }
    }
  }

  Future<void> _checkWindowVisibility() async {
    try {
      final treeResult = await Process.run('swaymsg', ['-t', 'get_tree']);
      if (treeResult.exitCode == 0) {
        final tree = jsonDecode(treeResult.stdout);
        List<Map<String, dynamic>> windows = [];
        bool hasVisibleWindows = false;

        void traverse(
          Map<String, dynamic> node,
          bool isScratch,
          String? currentWorkspace,
        ) {
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
            if (!appId.contains('fyrtaskbar') &&
                !appId.contains('fyrdock') &&
                !appId.contains('fyrsearch') &&
                !appId.contains('fyroverview') &&
                !appId.contains('fyrhelp') &&
                !appId.contains('fyremoji') &&
                !appId.contains('sway_launcher')) {
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
              if (!currentScratch && node['visible'] == true) {
                if (node['rect'] != null) {
                  double wx = (node['rect']['x'] as num).toDouble();
                  double wy = (node['rect']['y'] as num).toDouble();
                  double ww = (node['rect']['width'] as num).toDouble();
                  double wh = (node['rect']['height'] as num).toDouble();
                  double dockX = (1920 - _dockWidth) / 2;
                  double dockY = 1080 - 72;
                  if (wx < dockX + _dockWidth &&
                      wx + ww > dockX &&
                      wy < dockY + 72 &&
                      wy + wh > dockY) {
                    hasVisibleWindows = true;
                  }
                }
              }
            }
          }
          for (var child in (node['nodes'] ?? []))
            traverse(child, currentScratch, ws);
          for (var child in (node['floating_nodes'] ?? []))
            traverse(child, currentScratch, ws);
        }

        traverse(tree, false, null);

        if (mounted) {
          setState(() {
            _openWindows = windows;
            if (_autohide) {
              _isVisible = !hasVisibleWindows;
            } else {
              _isVisible = true;
            }
          });
          _updateWindowWidth();
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

    if (_dockWidth == width) return;
    _dockWidth = width;

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
      '/usr/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$iconName.svg',
      '/usr/share/icons/${FyrTheme.iconThemeName}/48/apps/$iconName.svg',
      '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$iconName.svg',
      '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/48/apps/$iconName.svg',
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
    setState(() {
      _pinnedApps.removeWhere((p) => p['exec'] == exec);
    });
    await _savePinnedApps();
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

  bool _matchesApp(
    Map<String, dynamic> pinnedApp,
    Map<String, dynamic> window,
  ) {
    final exec = (pinnedApp['exec'] as String).toLowerCase();
    final appId = (window['app_id'] as String).toLowerCase();
    final name = (pinnedApp['name'] as String).toLowerCase();
    if (exec.contains(appId) || appId.contains(exec.split(' ')[0])) return true;
    if (name.contains(appId) || appId.contains(name)) return true;
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
      String? targetWs;
      for (var mark in window['marks'] ?? []) {
        if (mark.toString().startsWith("fyr_minimized_ws_")) {
          targetWs = mark.toString().substring("fyr_minimized_ws_".length);
          Process.run('swaymsg', [
            '[con_id="${window['con_id']}"] unmark "$mark"',
          ]);
          break;
        }
      }
      if (targetWs != null) {
        Process.run('swaymsg', [
          'workspace $targetWs; [con_id="${window['con_id']}"] scratchpad show',
        ]);
      } else {
        Process.run('swaymsg', [
          '[con_id="${window['con_id']}"] scratchpad show',
        ]);
      }
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
      onTap: () => Process.run('swaymsg', [
        '[app_id="(?i).*fyrsearch.*"] scratchpad show, border none, resize set 1920 1080, move absolute position 0 0',
      ]),
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
        color: FyrTheme.bgColor.withOpacity(0.95),
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
        onEnter: (_) {
          setState(() => _isHoveredMain = true);
          waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
        },
        onExit: (_) {
          setState(() => _isHoveredMain = false);
          if (_autohide) {
            waylandLayerShellPlugin.setLayer(ShellLayer.layerBottom);
          }
        },
        child: AnimatedOpacity(
          opacity: (_isVisible || _isHoveredMain) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: EdgeInsets.only(bottom: 20),
                  height: 64,
                  decoration: BoxDecoration(
                    color: FyrTheme.bgColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: FyrTheme.cardColor, width: 1),
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
    );
  }
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
