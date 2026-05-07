import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'search_providers.dart';
import 'fyr_theme.dart';

void main() {
  FyrTheme.initialize();
  runApp(const LauncherApp());
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sway Launcher',
      themeMode: FyrTheme.themeMode,
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.dark(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
          surface: FyrTheme.surfaceColor,
        ),
      ),
      theme: ThemeData.light().copyWith(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.light(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
          surface: FyrTheme.surfaceColor,
        ),
      ),
      home: LauncherScreen(),
    ),
    );
  }
}

class DesktopApp {
  final String id;
  final String name;
  final String exec;
  final String? icon;
  final bool noDisplay;

  DesktopApp({
    required this.id,
    required this.name,
    required this.exec,
    this.icon,
    this.noDisplay = false,
  });
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();

  List<DesktopApp> _allApps = [];
  List<DesktopApp> _defaultApps = [];
  List<DesktopApp> _filteredApps = [];

  int _selectedIndex = -1;
  int _currentPage = 0;

  final int _crossAxisCount = 5;
  final int _rowsPerPage = 2;
  late final int _itemsPerPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemsPerPage = _crossAxisCount * _rowsPerPage;
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _searchController.clear();
        _filterApps('');
      });
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    }
  }


  Future<void> _loadApps() async {
    final List<String> searchPaths = [
      '/usr/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];

    List<DesktopApp> loadedApps = [];

    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final files = dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.desktop'),
        );

        for (var file in files) {
          final content = await file.readAsLines();
          final fileId = file.path.split('/').last;

          String? name;
          String? exec;
          String? icon;
          bool noDisplay = false;

          for (var line in content) {
            if (line.startsWith('Name=') && name == null) {
              name = line.substring(5).trim();
            }
            if (line.startsWith('Icon=') && icon == null) {
              icon = line.substring(5).trim();
            }
            if (line.startsWith('NoDisplay=') ) {
              noDisplay = line.substring(10).trim().toLowerCase() == 'true';
            }
            if (line.startsWith('Exec=') && exec == null) {
              exec = line
                  .substring(5)
                  .replaceAll(RegExp(r'%[a-zA-Z]'), '')
                  .replaceAll('@@u', '')
                  .trim();
            }
          }

          if (name != null && exec != null) {
            loadedApps.add(
              DesktopApp(
                id: fileId,
                name: name,
                exec: exec,
                icon: icon,
                noDisplay: noDisplay,
              ),
            );
          }
        }
      }
    }

    final uniqueApps = {
      for (var app in loadedApps) app.name: app,
    }.values.toList();

    const orderedIds = [
      'fyrbrowser.desktop',
      'fyrfiles.desktop',
      'fyrterm.desktop',
      'fyrstore.desktop',
      'fyrsettings.desktop',
      'fyrdaw.desktop',
      'fyrjournal.desktop',
      'fyrvirt.desktop',
      'fyrphotos.desktop',
      'fyrav.desktop',
    ];

    uniqueApps.sort((a, b) {
      int indexA = orderedIds.indexOf(a.id);
      int indexB = orderedIds.indexOf(b.id);

      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final defaultApps = uniqueApps.where((app) => !app.noDisplay).toList();

    setState(() {
      _allApps = uniqueApps;
      _defaultApps = defaultApps;
      _filteredApps = defaultApps;
    });
  }

  Future<void> _filterApps(String query) async {
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_defaultApps);
      } else {
        _filteredApps =
            _allApps.where((app) {
              return !app.noDisplay && app.name.toLowerCase().contains(query.toLowerCase());
            }).toList()..sort((a, b) {
              final lowerQuery = query.toLowerCase();
              final aName = a.name.toLowerCase();
              final bName = b.name.toLowerCase();

              bool aStarts = aName.startsWith(lowerQuery);
              bool bStarts = bName.startsWith(lowerQuery);

              if (aStarts && !bStarts) return -1;
              if (!aStarts && bStarts) return 1;

              return aName.compareTo(bName);
            });
      }
      _selectedIndex = -1;
      _currentPage = 0;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    if (query.isNotEmpty) {
      final fileSearch = FileSearchProvider();
      final files = await fileSearch.search(query);
      if (files.isNotEmpty && _searchController.text == query) {
        setState(() {
          _filteredApps.addAll(files);
        });
      }
    }
  }

  Future<void> _launchApp(String exec) async {
    try {
      await Process.start('sh', ['-c', exec], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Failed to launch app: $e');
    } finally {
      _hideLauncher();
    }
  }

  void _hideLauncher() {
    Process.start('swaymsg', [
      'move',
      'scratchpad',
    ], mode: ProcessStartMode.detached);
    setState(() {
      _searchController.clear();
      _filterApps('');
    });
  }

  Widget _buildAppIcon(DesktopApp app, {double size = 96}) {
    IconData defaultIconData = Icons.app_shortcut_outlined;
    if (app.exec.startsWith('xdg-open')) {
      final n = app.name.toLowerCase();
      if (n.endsWith('.png') ||
          n.endsWith('.jpg') ||
          n.endsWith('.jpeg') ||
          n.endsWith('.gif') ||
          n.endsWith('.webp') ||
          n.endsWith('.svg') ||
          n.endsWith('.bmp')) {
        defaultIconData = Icons.image;
      } else {
        defaultIconData = Icons.insert_drive_file;
      }
    }

    final defaultIcon = Icon(defaultIconData, color: FyrTheme.textColor, size: size);

    final iconName = app.icon;
    if (iconName == null || iconName.isEmpty) return defaultIcon;

    List<String> pathsToCheck = [];

    if (iconName.startsWith('/')) {
      pathsToCheck.add(iconName);
    } else {
      final baseName = iconName.replaceAll(RegExp(r'\.(png|svg|xpm)$'), '');

      pathsToCheck.add('/usr/share/pixmaps/$baseName.png');
      pathsToCheck.add('/usr/share/pixmaps/$baseName.svg');
      pathsToCheck.add('/usr/share/pixmaps/$baseName.xpm');
      pathsToCheck.add(
        '${Platform.environment['HOME']}/.local/share/icons/$baseName.png',
      );
      pathsToCheck.add(
        '${Platform.environment['HOME']}/.local/share/icons/$baseName.svg',
      );

      final themes = [
        FyrTheme.iconThemeName,
        'hicolor',
        'Adwaita',
        'Yaru',
        'Papirus',
        'breeze',
        'gnome',
      ];
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

  void _syncPageToSelection() {
    if (_selectedIndex < 0 || !_pageController.hasClients) return;

    final int targetPage = _selectedIndex ~/ _itemsPerPage;
    final int visiblePage = _pageController.page?.round() ?? 0;

    if (targetPage != visiblePage) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _handleGridNavigation(LogicalKeyboardKey key) {
    if (_filteredApps.isEmpty) return false;

    bool handled = true;

    setState(() {
      int maxIndex = _filteredApps.length - 1;

      if (_selectedIndex < 0) {
        if (key == LogicalKeyboardKey.arrowDown) {
          int target = _currentPage * _itemsPerPage;
          _selectedIndex = target <= maxIndex ? target : maxIndex;
        } else if (key == LogicalKeyboardKey.arrowUp) {
          int startIndex = _currentPage * _itemsPerPage;
          int appsOnPage = _filteredApps.length - startIndex;
          if (appsOnPage > _itemsPerPage) appsOnPage = _itemsPerPage;

          if (appsOnPage > 0) {
            int lastRowInPage = (appsOnPage - 1) ~/ _crossAxisCount;
            int target = startIndex + (lastRowInPage * _crossAxisCount);
            _selectedIndex = target <= maxIndex ? target : maxIndex;
          }
        } else {
          handled = false;
        }
      } else {
        int pageIndex = _selectedIndex ~/ _itemsPerPage;
        int indexInPage = _selectedIndex % _itemsPerPage;
        int rowInPage = indexInPage ~/ _crossAxisCount;
        int colInPage = indexInPage % _crossAxisCount;

        if (key == LogicalKeyboardKey.arrowRight) {
          if (colInPage == _crossAxisCount - 1) {
            int targetIndex =
                ((pageIndex + 1) * _itemsPerPage) +
                (rowInPage * _crossAxisCount);
            if (targetIndex <= maxIndex) {
              _selectedIndex = targetIndex;
            } else if ((pageIndex + 1) * _itemsPerPage <= maxIndex) {
              _selectedIndex = maxIndex;
            }
          } else {
            if (_selectedIndex < maxIndex) _selectedIndex++;
          }
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          if (colInPage == 0) {
            if (pageIndex > 0) {
              _selectedIndex =
                  ((pageIndex - 1) * _itemsPerPage) +
                  (rowInPage * _crossAxisCount) +
                  (_crossAxisCount - 1);
            }
          } else {
            _selectedIndex--;
          }
        } else if (key == LogicalKeyboardKey.arrowDown) {
          int target = _selectedIndex + _crossAxisCount;
          if (rowInPage < (_rowsPerPage - 1) && target <= maxIndex) {
            _selectedIndex = target;
          } else {
            _selectedIndex = -1;
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          if (rowInPage == 0) {
            _selectedIndex = -1;
          } else {
            _selectedIndex -= _crossAxisCount;
          }
        }
      }
    });

    if (handled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncPageToSelection();
      });
    }

    return handled;
  }

  @override
  Widget build(BuildContext context) {
    final int pageCount = _filteredApps.isEmpty
        ? 0
        : ((_filteredApps.length - 1) / _itemsPerPage).floor() + 1;

    final double screenHeight = MediaQuery.of(context).size.height;
    final double scale = (screenHeight / 1080).clamp(0.5, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideLauncher,
        child: Focus(
          canRequestFocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _hideLauncher();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.backspace) {
              if (!_focusNode.hasFocus && _searchController.text.isNotEmpty) {
                _focusNode.requestFocus();
                _searchController.text = _searchController.text.substring(
                  0,
                  _searchController.text.length - 1,
                );
                _searchController.selection = TextSelection.collapsed(
                  offset: _searchController.text.length,
                );
                _filterApps(_searchController.text);
                return KeyEventResult.handled;
              }
            } else if (event.character != null && event.character!.isNotEmpty) {
              final charCode = event.character!.codeUnitAt(0);
              if (charCode >= 32 && charCode != 127) {
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                  _searchController.text += event.character!;
                  _searchController.selection = TextSelection.collapsed(
                    offset: _searchController.text.length,
                  );
                  _filterApps(_searchController.text);
                  return KeyEventResult.handled;
                }
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 180),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: 12,
                      top: 48.0,
                      left: 24,
                      right: 24,
                    ),
                    child: Center(
                      child: Container(
                        width: 700 * scale,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: FyrTheme.surfaceColor.withOpacity(0),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                  color: FyrTheme.dividerColor,
                                ),
                              ),
                              child: Focus(
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.escape) {
                                _hideLauncher();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.enter) {
                                if (_filteredApps.isNotEmpty) {
                                  final indexToLaunch = _selectedIndex >= 0
                                      ? _selectedIndex
                                      : 0;
                                  _launchApp(_filteredApps[indexToLaunch].exec);
                                }
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight) {
                                final isHandled = _handleGridNavigation(
                                  event.logicalKey,
                                );
                                return isHandled
                                    ? KeyEventResult.handled
                                    : KeyEventResult.ignored;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            autofocus: true,
                            controller: _searchController,
                            focusNode: _focusNode,
                            onChanged: _filterApps,
                            onSubmitted: (_) {
                              if (_filteredApps.isNotEmpty) {
                                final indexToLaunch = _selectedIndex >= 0
                                    ? _selectedIndex
                                    : 0;
                                _launchApp(_filteredApps[indexToLaunch].exec);
                              }
                            },
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontSize: 22,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type to search...',
                              hintStyle: TextStyle(
                                color: FyrTheme.textColor.withOpacity(0.6),
                              ),
                              filled: false,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(
                                  left: 24.0,
                                  right: 16.0,
                                ),
                                child: Icon(
                                  Icons.search,
                                  color: FyrTheme.textColor,
                                  size: 28,
                                ),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: _filteredApps.isNotEmpty
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            PageView.builder(
                              controller: _pageController,
                              itemCount: pageCount,
                              onPageChanged: (page) {
                                setState(() => _currentPage = page);
                              },
                              itemBuilder: (context, pageIndex) {
                                      final int startIndex =
                                          pageIndex * _itemsPerPage;
                                      final int endIndex =
                                          (startIndex + _itemsPerPage >
                                              _filteredApps.length)
                                          ? _filteredApps.length
                                          : startIndex + _itemsPerPage;
                                      final List<DesktopApp> pageApps =
                                          _filteredApps.sublist(
                                            startIndex,
                                            endIndex,
                                          );

                                      return AnimatedBuilder(
                                        animation: _pageController,
                                        builder: (context, child) {
                                          double pageOffset = 0.0;

                                          if (_pageController
                                              .position
                                              .haveDimensions) {
                                            pageOffset =
                                                _pageController.page! -
                                                pageIndex;
                                          } else {
                                            pageOffset =
                                                (_currentPage - pageIndex)
                                                    .toDouble();
                                          }

                                          final double scale =
                                              (1 - (pageOffset.abs() * 0.15))
                                                  .clamp(0.85, 1.0);
                                          final double opacity =
                                              (1 - pageOffset.abs()).clamp(
                                                0.0,
                                                1.0,
                                              );

                                          return Opacity(
                                            opacity: opacity,
                                            child: Transform.scale(
                                              scale: scale,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Center(
                                          child: GridView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 88,
                                            ),
                                            itemCount: pageApps.length,
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      _crossAxisCount,
                                                  crossAxisSpacing: 4,
                                                  mainAxisSpacing: 32,
                                                  childAspectRatio: 0.85,
                                                ),
                                            itemBuilder: (context, index) {
                                              final int globalIndex =
                                                  startIndex + index;
                                              final app = pageApps[index];
                                              final isSelected =
                                                  globalIndex == _selectedIndex;
                                              bool isHovered = false;
                                              return StatefulBuilder(
                                                builder: (context, setLocalState) {
                                                  return Padding(
                                                    padding:
                                                        EdgeInsets.all(
                                                          16.0,
                                                        ),
                                                    child: InkWell(
                                                      onHover: (hovering) {
                                                        setLocalState(() {
                                                          isHovered = hovering;
                                                        });
                                                        if (hovering &&
                                                            _selectedIndex !=
                                                                globalIndex) {
                                                          setState(() {
                                                            _selectedIndex =
                                                                globalIndex;
                                                          });
                                                        }
                                                      },
                                                      onTap: () =>
                                                          _launchApp(app.exec),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            24,
                                                          ),
                                                      hoverColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      splashColor:
                                                          Colors.transparent,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? FyrTheme.textColor
                                                                    .withOpacity(
                                                                      0.1,
                                                                    )
                                                              : Colors
                                                                    .transparent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                24,
                                                              ),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? FyrTheme.accentColor
                                                                      .withOpacity(
                                                                        0.4,
                                                                      )
                                                                : Colors
                                                                      .transparent,
                                                          ),
                                                        ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            AnimatedScale(
                                                              scale: isSelected
                                                                  ? 1.15
                                                                  : 1.0,
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        200,
                                                                  ),
                                                              curve: Curves
                                                                  .easeOutCubic,
                                                              child:
                                                                  _buildAppIcon(
                                                                    app,
                                                                    size: 96 * scale,
                                                                  ),
                                                            ),
                                                            SizedBox(
                                                              height: 16,
                                                            ),
                                                            Text(
                                                              app.name,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                shadows: [
                                                                  Shadow(
                                                                    offset:
                                                                        Offset(
                                                                          0,
                                                                          1,
                                                                        ),
                                                                    blurRadius:
                                                                        4,
                                                                    color: Colors
                                                                        .black54,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (_currentPage > 0)
                                    Positioned(
                                      left: 0,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.chevron_left,
                                          size: 48,
                                        ),
                                        color: FyrTheme.textColor.withOpacity(0.5),
                                        hoverColor: FyrTheme.textColor.withOpacity(
                                          0.2,
                                        ),
                                        splashRadius: 32,
                                        onPressed: () {
                                          _pageController.previousPage(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        },
                                      ),
                                    ),
                                  if (_currentPage < pageCount - 1)
                                    Positioned(
                                      right: 0,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.chevron_right,
                                          size: 48,
                                        ),
                                        color: FyrTheme.textColor.withOpacity(0.5),
                                        hoverColor: FyrTheme.textColor.withOpacity(
                                          0.2,
                                        ),
                                        splashRadius: 32,
                                        onPressed: () {
                                          _pageController.nextPage(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              )
                            : Center(
                                child: Text(
                                  "No apps found",
                                  style: TextStyle(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 96),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
