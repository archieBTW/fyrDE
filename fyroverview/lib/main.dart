import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'fyr_theme.dart';

void main() {
  FyrTheme.initialize();
  runApp(const OverviewApp());
}

class OverviewApp extends StatelessWidget {
  const OverviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sway Overview',
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
      home: OverviewScreen(),
    ),
    );
  }
}

class WorkspaceData {
  final String name;
  Map<String, dynamic>? rect;
  List<WindowData> windows = [];
  bool isFocused = false;
  bool isVisible = false;
  Uint8List? previewBytes;

  WorkspaceData({required this.name});
}

class WindowData {
  final int id;
  final String? appId;
  final String name;
  final Map<String, dynamic> rect;
  final bool isFocused;

  WindowData({
    required this.id,
    this.appId,
    required this.name,
    required this.rect,
    this.isFocused = false,
  });
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  List<WorkspaceData> _workspaces = [];
  int _selectedIndex = -1;
  bool _isLoading = true;
  String? _wallpaperPath;
  Timer? _captureTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _refresh() {
    _fetchWallpaper();
    _loadData();
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _refresh();
      }
    });
    _initWorkspaces();
    _fetchWallpaper();
    _captureActiveWorkspace().then((_) {
      _loadData();
    });
    _startCaptureTimer();
  }

  void _startCaptureTimer() {
    _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!_focusNode.hasFocus) {
        await _captureActiveWorkspace();
      }
    });
  }

  Future<void> _captureActiveWorkspace() async {
    try {
      final wsResult = await Process.run('swaymsg', ['-t', 'get_workspaces']);
      if (wsResult.exitCode == 0) {
        final List<dynamic> wsJson = jsonDecode(wsResult.stdout);
        int activeWs = -1;
        for (var ws in wsJson) {
          if (ws['focused'] == true) {
            activeWs = int.tryParse(ws['name'].toString()) ?? -1;
            break;
          }
        }
        if (activeWs != -1) {
          await Process.run('grim', [
            '-t',
            'jpeg',
            '-q',
            '30',
            '/tmp/fyroverview_ws_$activeWs.jpg',
          ]);
        }
      }
    } catch (e) {
      debugPrint('Failed to capture workspace: $e');
    }
  }

  void _initWorkspaces() {
    _workspaces = List.generate(
      9,
      (index) => WorkspaceData(name: '${index + 1}'),
    );
  }

  Future<void> _fetchWallpaper() async {
    try {
      final result = await Process.run('sh', ['-c', 'pgrep -a swaybg']);
      if (result.exitCode == 0) {
        final out = result.stdout.toString();
        final match = RegExp(r'-i\s+([^\s]+)').firstMatch(out);
        if (match != null) {
          setState(() {
            _wallpaperPath = match.group(1);
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch wallpaper: $e');
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      List<WorkspaceData> newWorkspaces = List.generate(
        9,
        (index) => WorkspaceData(name: '${index + 1}'),
      );
      int newSelectedIndex = _selectedIndex;

      final wsResult = await Process.run('swaymsg', ['-t', 'get_workspaces']);
      if (wsResult.exitCode == 0) {
        final List<dynamic> wsJson = jsonDecode(wsResult.stdout);
        for (var ws in wsJson) {
          final String name = ws['name'].toString();
          final int index = int.tryParse(name) ?? -1;
          if (index >= 1 && index <= 9) {
            final wsData = newWorkspaces[index - 1];
            wsData.isFocused = ws['focused'] == true;
            wsData.isVisible = ws['visible'] == true;
            wsData.rect = ws['rect'];

            final imgFile = File('/tmp/fyroverview_ws_$name.jpg');
            if (await imgFile.exists()) {
              wsData.previewBytes = await imgFile.readAsBytes();
            } else {
              wsData.previewBytes = null;
            }

            if (wsData.isFocused) {
              newSelectedIndex = index - 1;
            }
          }
        }
      }

      final treeResult = await Process.run('swaymsg', ['-t', 'get_tree']);
      if (treeResult.exitCode == 0) {
        final Map<String, dynamic> treeJson = jsonDecode(treeResult.stdout);
        _parseTree(treeJson, newWorkspaces);
      }

      if (mounted) {
        setState(() {
          _workspaces = newWorkspaces;
          _selectedIndex = newSelectedIndex;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load sway data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _parseTree(
    Map<String, dynamic> node,
    List<WorkspaceData> newWorkspaces, [
    WorkspaceData? currentWs,
  ]) {
    final String type = node['type'] ?? '';
    final String name = node['name'] ?? '';

    WorkspaceData? targetWs = currentWs;

    if (type == 'workspace') {
      final int index = int.tryParse(name) ?? -1;
      if (index >= 1 && index <= 9) {
        targetWs = newWorkspaces[index - 1];
        if (targetWs.rect == null && node['rect'] != null) {
          targetWs.rect = node['rect'];
        }
      } else {
        targetWs = null;
      }
    }

    if (targetWs != null && (type == 'con' || type == 'floating_con')) {
      final String? appId =
          node['app_id'] ?? node['window_properties']?['class'];
      final rect = node['rect'];
      final bool isFocused = node['focused'] == true;
      final int id = node['id'] ?? 0;

      if (appId != null || node['window'] != null) {
        targetWs.windows.add(
          WindowData(
            id: id,
            appId: appId ?? '',
            name: name,
            rect: rect,
            isFocused: isFocused,
          ),
        );
      }
    }

    final List<dynamic> nodes = node['nodes'] ?? [];
    final List<dynamic> floatingNodes = node['floating_nodes'] ?? [];

    for (var child in nodes) {
      _parseTree(child, newWorkspaces, targetWs);
    }
    for (var child in floatingNodes) {
      _parseTree(child, newWorkspaces, targetWs);
    }
  }

  void _hideOverview() {
    Process.start('swaymsg', [
      '[app_id="fyroverview"] move scratchpad',
    ], mode: ProcessStartMode.detached);
  }

  void _switchToWorkspace(int index) {
    Process.start('swaymsg', [
      'workspace',
      '${index + 1}',
    ], mode: ProcessStartMode.detached).then((_) {
      _hideOverview();
    });
  }

  Widget _buildAppIcon(String? iconName, {double size = 48}) {
    final defaultIcon = Icon(
      Icons.web_asset,
      color: FyrTheme.textColor.withOpacity(0.8),
      size: size * 0.8,
    );

    if (iconName == null || iconName.isEmpty) return defaultIcon;

    final lowerName = iconName.toLowerCase();

    List<String> pathsToCheck = [];
    final baseName = lowerName.replaceAll(RegExp(r'\.(png|svg|xpm)$'), '');

    pathsToCheck.add('/usr/share/pixmaps/$baseName.png');
    pathsToCheck.add('/usr/share/pixmaps/$baseName.svg');
    pathsToCheck.add('/usr/share/pixmaps/$baseName.xpm');
    pathsToCheck.add(
      '${Platform.environment['HOME']}/.local/share/icons/$baseName.png',
    );
    pathsToCheck.add(
      '${Platform.environment['HOME']}/.local/share/icons/$baseName.svg',
    );

    final themes = [FyrTheme.iconThemeName, 'hicolor', 'Adwaita', 'Yaru', 'Papirus', 'breeze', 'gnome'];
    const sizes = [
      'scalable',
      '512x512',
      '256x256',
      '128x128',
      '96x96',
      '64x64',
      '48x48',
    ];
    const categories = ['apps', 'categories'];

    for (final theme in themes) {
      for (final sz in sizes) {
        for (final category in categories) {
          pathsToCheck.add(
            '/usr/share/icons/$theme/$sz/$category/$baseName.svg',
          );
          pathsToCheck.add(
            '/usr/share/icons/$theme/$sz/$category/$baseName.png',
          );
          pathsToCheck.add(
            '${Platform.environment['HOME']}/.local/share/icons/$theme/$sz/$category/$baseName.svg',
          );
          pathsToCheck.add(
            '${Platform.environment['HOME']}/.local/share/icons/$theme/$sz/$category/$baseName.png',
          );
        }
      }
    }

    for (final path in pathsToCheck) {
      final file = File(path);
      if (file.existsSync()) {
        if (path.endsWith('.svg')) {
          return SvgPicture.file(
            file,
            width: size,
            height: size,
            placeholderBuilder: (BuildContext context) => defaultIcon,
          );
        } else {
          return Image.file(
            file,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) => defaultIcon,
          );
        }
      }
    }

    return defaultIcon;
  }

  Widget _buildWorkspacePreview(WorkspaceData ws, int index) {
    final bool isSelected = _selectedIndex == index;

    // Default 16:9 aspect ratio if no rect available
    final double wsWidth = (ws.rect != null && ws.rect!['width'] > 0)
        ? ws.rect!['width'].toDouble()
        : 1920.0;
    final double wsHeight = (ws.rect != null && ws.rect!['height'] > 0)
        ? ws.rect!['height'].toDouble()
        : 1080.0;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: GestureDetector(
        onTap: () => _switchToWorkspace(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: FyrTheme.bgColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? FyrTheme.accentColor.withOpacity(0.8)
                  : (ws.isFocused
                        ? FyrTheme.accentColor.withOpacity(0.3)
                        : FyrTheme.hoverColor),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: FyrTheme.accentColor.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Stack(
                key: ValueKey(
                  'ws_${ws.name}_${ws.isFocused}_${ws.windows.map((w) => '${w.id}_${w.rect}').join('|')}_${ws.previewBytes?.length}',
                ),
                children: [
                  if (_wallpaperPath != null &&
                      File(_wallpaperPath!).existsSync())
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.6,
                        child: Image.file(
                          File(_wallpaperPath!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                  Center(
                    child: Text(
                      ws.name,
                      style: TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.bold,
                        color: FyrTheme.hoverColor,
                      ),
                    ),
                  ),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double scaleX = constraints.maxWidth / wsWidth;
                      final double scaleY = constraints.maxHeight / wsHeight;

                      return Stack(
                        children: ws.windows.map((win) {
                          final double x =
                              ((win.rect['x'] ?? 0) - (ws.rect?['x'] ?? 0)) *
                              scaleX;
                          final double y =
                              ((win.rect['y'] ?? 0) - (ws.rect?['y'] ?? 0)) *
                              scaleY;
                          final double w = (win.rect['width'] ?? 0) * scaleX;
                          final double h = (win.rect['height'] ?? 0) * scaleY;

                          return Positioned(
                            left: x,
                            top: y,
                            width: w,
                            height: h,
                            child: GestureDetector(
                              onTap: () {
                                Process.start('swaymsg', [
                                  '[con_id="${win.id}"] focus',
                                ], mode: ProcessStartMode.detached).then((_) {
                                  _hideOverview();
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1E1E1E,
                                  ), // Dark theme app background
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: win.isFocused
                                        ? FyrTheme.accentColor
                                        : FyrTheme.textColor.withOpacity(0.2),
                                    width: win.isFocused ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: FyrTheme.bgColor.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: ws.previewBytes != null
                                        ? Colors.transparent
                                        : const Color(
                                            0xFF1E1E1E,
                                          ).withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: Builder(
                                      builder: (context) {
                                        if (ws.previewBytes != null) {
                                          return Stack(
                                            children: [
                                              Positioned(
                                                left: -x,
                                                top: -y,
                                                width: wsWidth * scaleX,
                                                height: wsHeight * scaleY,
                                                child: Image.memory(
                                                  ws.previewBytes!,
                                                  fit: BoxFit.fill,
                                                  gaplessPlayback: true,
                                                ),
                                              ),
                                            ],
                                          );
                                        }
                                        return Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Center(
                                              child: Opacity(
                                                opacity: 0.1,
                                                child: _buildAppIcon(
                                                  win.appId,
                                                  size: math.max(
                                                    w * 0.8,
                                                    h * 0.8,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Center(
                                              child: _buildAppIcon(
                                                win.appId,
                                                size: math.min(
                                                  w * 0.4,
                                                  h * 0.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                  if (ws.isFocused)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: FyrTheme.accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: FyrTheme.accentColor,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Workspace Label
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: FyrTheme.bgColor.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: FyrTheme.hoverColor,
                          ),
                        ),
                        child: Text(
                          'Workspace ${ws.name}',
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FyrTheme.bgColor.withOpacity(0.4),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _hideOverview();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_selectedIndex >= 0 && _selectedIndex < 9) {
                _switchToWorkspace(_selectedIndex);
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              setState(() {
                if (_selectedIndex < 8) _selectedIndex++;
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              setState(() {
                if (_selectedIndex > 0) _selectedIndex--;
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() {
                if (_selectedIndex < 6) _selectedIndex += 3;
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() {
                if (_selectedIndex > 2) _selectedIndex -= 3;
              });
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: FyrTheme.textColor),
              )
            : SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 96.0,
                    bottom: 48.0,
                    left: 48.0,
                    right: 48.0,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double itemWidth =
                                (constraints.maxWidth - (32 * 2)) / 3;
                            final double itemHeight =
                                (constraints.maxHeight - (32 * 2)) / 3;
                            final double aspectRatio = itemWidth / itemHeight;

                            return GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 32,
                                    mainAxisSpacing: 32,
                                    childAspectRatio: aspectRatio,
                                  ),
                              itemCount: 9,
                              itemBuilder: (context, index) {
                                return _buildWorkspacePreview(
                                  _workspaces[index],
                                  index,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
