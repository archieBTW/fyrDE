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
  runApp(const WindowOverviewApp());
}

class WindowOverviewApp extends StatelessWidget {
  const WindowOverviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fyr Window Overview',
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
        home: const WindowOverviewScreen(),
      ),
    );
  }
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

class WindowOverviewScreen extends StatefulWidget {
  const WindowOverviewScreen({super.key});

  @override
  State<WindowOverviewScreen> createState() => _WindowOverviewScreenState();
}

class _WindowOverviewScreenState extends State<WindowOverviewScreen>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  List<WindowData> _windows = [];
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _wallpaperPath;
  Uint8List? _workspacePreview;
  double _wsWidth = 1920;
  double _wsHeight = 1080;

  Timer? _captureTimer;
  Timer? _focusedWinCaptureTimer;
  int? _lastCapturedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _refresh();
      }
    });
    _refresh();
    _startCaptureTimers();
  }

  void _startCaptureTimers() {
    _captureTimer?.cancel();
    _focusedWinCaptureTimer?.cancel();
    
    // 1. Workspace-wide capture (fallback)
    _captureTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_focusNode.hasFocus) {
        _captureActiveWorkspace();
      }
    });

    // 2. Focused window capture (for "clean" previews)
    _focusedWinCaptureTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_focusNode.hasFocus) {
        _captureFocusedWindow();
      }
    });
  }

  Future<void> _captureActiveWorkspace() async {
    try {
      await Process.run('grim', [
        '-t', 'jpeg', '-q', '40', '/tmp/fyrwindowoverview_ws.jpg'
      ]);
    } catch (e) {
      debugPrint('Failed to capture workspace: $e');
    }
  }

  Future<void> _captureFocusedWindow() async {
    try {
      final result = await Process.run('swaymsg', ['-t', 'get_tree']);
      if (result.exitCode == 0) {
        final Map<String, dynamic> tree = jsonDecode(result.stdout);
        final focusedNode = _findFocusedNode(tree);
        if (focusedNode != null) {
          final int? id = focusedNode['id'];
          
          // Only capture if focus changed or periodically if it's the same
          if (id == _lastCapturedId) return;

          final String? appId = focusedNode['app_id'] ?? focusedNode['window_properties']?['class'];
          final rect = focusedNode['rect'];
          
          if (id != null && appId != null && rect != null) {
             final shellComponents = ['fyrwindowoverview', 'fyroverview', 'fyrtaskbar', 'fyrdock', 'fyrsearch', 'fyremoji'];
             if (!shellComponents.contains(appId.toLowerCase())) {
                final String geometry = "${rect['x']},${rect['y']} ${rect['width']}x${rect['height']}";
                await Process.run('grim', [
                  '-g', geometry, '-t', 'jpeg', '-q', '55', '/tmp/fyr_win_$id.jpg'
                ]);
                _lastCapturedId = id;
             }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to capture focused window: $e');
    }
  }

  void _cleanupCache() {
    try {
      final dir = Directory('/tmp');
      final activeIds = _windows.map((w) => w.id).toSet();
      
      dir.listSync().forEach((file) {
        if (file is File && file.path.contains('fyr_win_')) {
          final match = RegExp(r'fyr_win_(\d+)\.jpg').firstMatch(file.path);
          if (match != null) {
            final id = int.parse(match.group(1)!);
            if (!activeIds.contains(id)) {
              file.deleteSync();
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Cache cleanup failed: $e');
    }
  }

  Map<String, dynamic>? _findFocusedNode(Map<String, dynamic> node) {
    if (node['focused'] == true && node['type'] != 'workspace') return node;
    
    final List<dynamic> nodes = node['nodes'] ?? [];
    final List<dynamic> floatingNodes = node['floating_nodes'] ?? [];
    
    for (var child in nodes) {
      final found = _findFocusedNode(child);
      if (found != null) return found;
    }
    for (var child in floatingNodes) {
      final found = _findFocusedNode(child);
      if (found != null) return found;
    }
    return null;
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _focusedWinCaptureTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    _fetchWallpaper();
    _loadData();
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
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

  Future<void> _loadData() async {
    try {
      // 1. Get current workspace name and resolution
      final wsResult = await Process.run('swaymsg', ['-t', 'get_workspaces']);
      String? currentWsName;
      double wsW = 1920;
      double wsH = 1080;

      if (wsResult.exitCode == 0) {
        final List<dynamic> wsJson = jsonDecode(wsResult.stdout);
        for (var ws in wsJson) {
          if (ws['focused'] == true) {
            currentWsName = ws['name'].toString();
            wsW = ws['rect']['width'].toDouble();
            wsH = ws['rect']['height'].toDouble();
            break;
          }
        }
      }

      if (currentWsName == null) return;

      // 2. Load existing preview
      final imgFile = File('/tmp/fyrwindowoverview_ws.jpg');
      Uint8List? preview;
      if (await imgFile.exists()) {
        preview = await imgFile.readAsBytes();
      }

      // 3. Get tree and find windows in current workspace
      final treeResult = await Process.run('swaymsg', ['-t', 'get_tree']);
      if (treeResult.exitCode == 0) {
        final Map<String, dynamic> treeJson = jsonDecode(treeResult.stdout);
        List<WindowData> newWindows = [];
        _parseTree(treeJson, currentWsName, newWindows);
        
        if (mounted) {
          setState(() {
            _windows = newWindows;
            _isLoading = false;
            _wsWidth = wsW;
            _wsHeight = wsH;
            _workspacePreview = preview;
            if (_selectedIndex >= _windows.length) {
              _selectedIndex = 0;
            }
          });
          _cleanupCache();
        }
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

  void _parseTree(Map<String, dynamic> node, String currentWsName, List<WindowData> windows, [bool inTargetWs = false]) {
    final String type = node['type'] ?? '';
    final String name = node['name'] ?? '';
    
    bool currentlyInTarget = inTargetWs;
    if (type == 'workspace' && name == currentWsName) {
      currentlyInTarget = true;
    } else if (type == 'workspace') {
      currentlyInTarget = false;
    }

    if (currentlyInTarget && (type == 'con' || type == 'floating_con')) {
      final String? appId = node['app_id'] ?? node['window_properties']?['class'];
      final rect = node['rect'];
      final bool isFocused = node['focused'] == true;
      final int id = node['id'] ?? 0;

      if (appId != null || node['window'] != null) {
        // Exclude only the background shell components
        final lowerAppId = appId?.toLowerCase() ?? '';
        final lowerName = name.toLowerCase();
        
        final shellComponents = ['fyrwindowoverview', 'fyroverview', 'fyrtaskbar', 'fyrdock', 'fyrsearch', 'fyremoji'];
        bool isShellComponent = shellComponents.any((comp) => lowerAppId == comp || lowerName == comp);

        if (isShellComponent) {
           // Skip these windows
        } else {
          windows.add(WindowData(
            id: id,
            appId: appId ?? '',
            name: name,
            rect: rect,
            isFocused: isFocused,
          ));
        }
      }
    }

    final List<dynamic> nodes = node['nodes'] ?? [];
    final List<dynamic> floatingNodes = node['floating_nodes'] ?? [];

    for (var child in nodes) {
      _parseTree(child, currentWsName, windows, currentlyInTarget);
    }
    for (var child in floatingNodes) {
      _parseTree(child, currentWsName, windows, currentlyInTarget);
    }
  }

  void _hideOverview() {
    Process.start('swaymsg', [
      '[app_id="fyrwindowoverview"] move scratchpad',
    ], mode: ProcessStartMode.detached);
  }

  void _focusWindow(WindowData win) {
    Process.start('swaymsg', [
      '[con_id="${win.id}"] focus',
    ], mode: ProcessStartMode.detached).then((_) {
      _hideOverview();
    });
  }

  Widget _buildAppIcon(String? iconName, {double size = 48}) {
    final defaultIcon = Icon(
      Icons.web_asset,
      color: Colors.white.withOpacity(0.8),
      size: size * 0.8,
    );

    if (iconName == null || iconName.isEmpty) return defaultIcon;

    final lowerName = iconName.toLowerCase();
    final baseName = lowerName.replaceAll(RegExp(r'\.(png|svg|xpm)$'), '');

    List<String> pathsToCheck = [
      '/usr/share/pixmaps/$baseName.png',
      '/usr/share/pixmaps/$baseName.svg',
      '${Platform.environment['HOME']}/.local/share/icons/$baseName.png',
      '${Platform.environment['HOME']}/.local/share/icons/$baseName.svg',
    ];

    final themes = [FyrTheme.iconThemeName, 'hicolor', 'Papirus', 'Adwaita'];
    const sizes = ['scalable', '512x512', '128x128', '64x64', '48x48'];
    const categories = ['apps', 'categories'];

    for (final theme in themes) {
      for (final sz in sizes) {
        for (final category in categories) {
          pathsToCheck.add('/usr/share/icons/$theme/$sz/$category/$baseName.svg');
          pathsToCheck.add('/usr/share/icons/$theme/$sz/$category/$baseName.png');
        }
      }
    }

    for (final path in pathsToCheck) {
      final file = File(path);
      if (file.existsSync()) {
        if (path.endsWith('.svg')) {
          return SvgPicture.file(file, width: size, height: size, placeholderBuilder: (_) => defaultIcon);
        } else {
          return Image.file(file, width: size, height: size, errorBuilder: (_, __, ___) => defaultIcon);
        }
      }
    }

    return defaultIcon;
  }

  Widget _buildWindowItem(WindowData win, int index) {
    final bool isSelected = _selectedIndex == index;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _selectedIndex = index),
      child: GestureDetector(
        onTap: () => _focusWindow(win),
        child: AnimatedScale(
          scale: isSelected ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? FyrTheme.accentColor : FyrTheme.hoverColor,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected ? [
                BoxShadow(color: FyrTheme.accentColor.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
              ] : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  // Individual Window Preview (Clean)
                  FutureBuilder<bool>(
                    future: File('/tmp/fyr_win_${win.id}.jpg').exists(),
                    builder: (context, snapshot) {
                      if (snapshot.data == true) {
                        return Positioned.fill(
                          child: Image.file(
                            File('/tmp/fyr_win_${win.id}.jpg'),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        );
                      }
                      
                      // Fallback: Cropped Workspace Preview
                      if (_workspacePreview != null) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final double winX = win.rect['x'].toDouble();
                            final double winY = win.rect['y'].toDouble();
                            final double winW = win.rect['width'].toDouble();
                            final double winH = win.rect['height'].toDouble();
                            
                            final double scaleX = constraints.maxWidth / winW;
                            final double scaleY = constraints.maxHeight / winH;
                            
                            return Stack(
                              children: [
                                Positioned(
                                  left: -winX * scaleX,
                                  top: -winY * scaleY,
                                  width: _wsWidth * scaleX,
                                  height: _wsHeight * scaleY,
                                  child: Image.memory(
                                    _workspacePreview!,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      }
                      return Container();
                    },
                  ),
                  
                  // Darken a bit to make text/icon readable
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.4),
                        ],
                      ),
                    ),
                  ),
                  
                  // App Info Overlay
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _buildAppIcon(win.appId, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            win.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (win.isFocused)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: FyrTheme.accentColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Active",
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
      backgroundColor: Colors.transparent, // Background blur handled by Sway
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _hideOverview();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_windows.isNotEmpty) _focusWindow(_windows[_selectedIndex]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              setState(() => _selectedIndex = (_selectedIndex + 1) % _windows.length);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              setState(() => _selectedIndex = (_selectedIndex - 1 + _windows.length) % _windows.length);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
           decoration: BoxDecoration(
             color: Colors.black.withOpacity(0), // Very subtle darken for blur contrast
           ),
           child: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.white))
            : SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 80),
                    Expanded(
                      child: _windows.isEmpty 
                        ? Center(child: Text("No windows open", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 24)))
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 64.0),
                            child: GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 450,
                                mainAxisSpacing: 40,
                                crossAxisSpacing: 40,
                                childAspectRatio: 1.6,
                              ),
                              itemCount: _windows.length,
                              itemBuilder: (context, index) => _buildWindowItem(_windows[index], index),
                            ),
                          ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}
