import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import 'package:http/http.dart' as http;
import 'fyr_theme.dart';

enum ResizeZoneEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class ResizableWindow extends StatelessWidget {
  final Widget child;
  const ResizableWindow({super.key, required this.child});

  static const _resizeThickness = 6.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        _ResizeHandle(edge: ResizeZoneEdge.left, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.right, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.top, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottom, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.topLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.topRight, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomRight, size: _resizeThickness),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ResizeZoneEdge edge;
  final double size;

  const _ResizeHandle({required this.edge, required this.size});

  SystemMouseCursor get cursor {
    switch (edge) {
      case ResizeZoneEdge.left:
      case ResizeZoneEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case ResizeZoneEdge.top:
      case ResizeZoneEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeZoneEdge.topLeft:
      case ResizeZoneEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeZoneEdge.topRight:
      case ResizeZoneEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  ResizeEdge get resizeEdge {
    switch (edge) {
      case ResizeZoneEdge.left: return ResizeEdge.left;
      case ResizeZoneEdge.right: return ResizeEdge.right;
      case ResizeZoneEdge.top: return ResizeEdge.top;
      case ResizeZoneEdge.bottom: return ResizeEdge.bottom;
      case ResizeZoneEdge.topLeft: return ResizeEdge.topLeft;
      case ResizeZoneEdge.topRight: return ResizeEdge.topRight;
      case ResizeZoneEdge.bottomLeft: return ResizeEdge.bottomLeft;
      case ResizeZoneEdge.bottomRight: return ResizeEdge.bottomRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    Alignment alignment;
    double? width;
    double? height;

    switch (edge) {
      case ResizeZoneEdge.left: alignment = Alignment.centerLeft; width = size; height = double.infinity; break;
      case ResizeZoneEdge.right: alignment = Alignment.centerRight; width = size; height = double.infinity; break;
      case ResizeZoneEdge.top: alignment = Alignment.topCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.bottom: alignment = Alignment.bottomCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.topLeft: alignment = Alignment.topLeft; width = size; height = size; break;
      case ResizeZoneEdge.topRight: alignment = Alignment.topRight; width = size; height = size; break;
      case ResizeZoneEdge.bottomLeft: alignment = Alignment.bottomLeft; width = size; height = size; break;
      case ResizeZoneEdge.bottomRight: alignment = Alignment.bottomRight; width = size; height = size; break;
    }

    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(resizeEdge),
          child: SizedBox(width: width, height: height),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 700),
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const FyrStoreApp());
}

class FyrStoreApp extends StatelessWidget {
  const FyrStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: FyrTheme.themeMode,
          theme: ThemeData.light().copyWith(
            useMaterial3: false,
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: const Color(0xFFF0F0F0),
            colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: false,
            scaffoldBackgroundColor: const Color(0xFF2A282C),
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor),
          ),
          home: const FyrStoreHome(),
        );
      },
    );
  }
}

class FyrStoreHome extends StatefulWidget {
  const FyrStoreHome({super.key});

  @override
  State<FyrStoreHome> createState() => _FyrStoreHomeState();
}

class _FyrStoreHomeState extends State<FyrStoreHome> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String _selectedCategory = 'Recommended';
  bool _isSearching = false;

  final Map<String, List<Map<String, String>>> defaultApps = {
    'Recommended': [
      {'name': 'firefox', 'description': 'Standalone web browser from mozilla.org', 'source': 'Arch', 'url': 'https://www.mozilla.org/firefox/'},
      {'name': 'visual-studio-code-bin', 'description': 'Visual Studio Code (vscode): Editor for building and debugging modern web and cloud applications', 'source': 'AUR', 'url': 'https://code.visualstudio.com/'},
      {'name': 'vlc', 'description': 'Multi-platform MPEG, VCD/DVD, and DivX player', 'source': 'Arch', 'url': 'https://www.videolan.org/'},
      {'name': 'discord', 'description': 'All-in-one voice and text chat for gamers', 'source': 'Arch', 'url': 'https://discord.com/'},
      {'name': 'steam', 'description': 'Valve distribution utility', 'source': 'Arch', 'url': 'https://store.steampowered.com/'},
      {'name': 'spotify', 'description': 'A proprietary music streaming service', 'source': 'AUR', 'url': 'https://www.spotify.com/'},
    ],
    'Web Browsers': [
      {'name': 'firefox', 'description': 'Standalone web browser from mozilla.org', 'source': 'Arch', 'url': 'https://www.mozilla.org/firefox/'},
      {'name': 'chromium', 'description': 'A web browser built for speed, simplicity, and security', 'source': 'Arch', 'url': 'https://www.chromium.org/Home'},
      {'name': 'brave-bin', 'description': 'Web browser that blocks ads and trackers by default', 'source': 'AUR', 'url': 'https://brave.com/'},
      {'name': 'google-chrome', 'description': 'The popular web browser by Google', 'source': 'AUR', 'url': 'https://www.google.com/chrome/'},
    ],
    'Development': [
      {'name': 'visual-studio-code-bin', 'description': 'Visual Studio Code', 'source': 'AUR', 'url': 'https://code.visualstudio.com/'},
      {'name': 'intellij-idea-community-edition', 'description': 'IntelliJ IDEA Community Edition', 'source': 'Arch', 'url': 'https://www.jetbrains.com/idea/'},
      {'name': 'neovim', 'description': 'Fork of Vim aiming to improve user experience, plugins, and GUIs', 'source': 'Arch', 'url': 'https://neovim.io/'},
      {'name': 'git', 'description': 'the fast distributed version control system', 'source': 'Arch', 'url': 'https://git-scm.com/'},
      {'name': 'docker', 'description': 'Pack, ship and run any application as a lightweight container', 'source': 'Arch', 'url': 'https://www.docker.com/'},
      {'name': 'postman-bin', 'description': 'Build, test, and document your APIs faster', 'source': 'AUR', 'url': 'https://www.postman.com/'},
    ],
    'Multimedia': [
      {'name': 'vlc', 'description': 'Multi-platform MPEG, VCD/DVD, and DivX player', 'source': 'Arch', 'url': 'https://www.videolan.org/'},
      {'name': 'spotify', 'description': 'A proprietary music streaming service', 'source': 'AUR', 'url': 'https://www.spotify.com/'},
      {'name': 'obs-studio', 'description': 'Free and open source software for video recording and live streaming', 'source': 'Arch', 'url': 'https://obsproject.com/'},
      {'name': 'gimp', 'description': 'GNU Image Manipulation Program', 'source': 'Arch', 'url': 'https://www.gimp.org/'},
      {'name': 'blender', 'description': 'A fully integrated 3D graphics creation suite', 'source': 'Arch', 'url': 'https://www.blender.org/'},
    ],
    'System': [
      {'name': 'htop', 'description': 'Interactive process viewer', 'source': 'Arch', 'url': 'https://htop.dev/'},
      {'name': 'neofetch', 'description': 'A CLI system information tool written in BASH that supports displaying images.', 'source': 'Arch', 'url': 'https://github.com/dylanaraps/neofetch'},
      {'name': 'timeshift', 'description': 'A system restore utility for Linux', 'source': 'Arch', 'url': 'https://github.com/linuxmint/timeshift'},
      {'name': 'alacritty', 'description': 'A cross-platform, GPU-accelerated terminal emulator', 'source': 'Arch', 'url': 'https://alacritty.org/'},
      {'name': 'gparted', 'description': 'A Partition Magic clone, frontend to GNU Parted', 'source': 'Arch', 'url': 'https://gparted.org/'},
    ],
    'Games': [
      {'name': 'steam', 'description': 'Valve distribution utility', 'source': 'Arch', 'url': 'https://store.steampowered.com/'},
      {'name': 'lutris', 'description': 'Open gaming platform for Linux', 'source': 'Arch', 'url': 'https://lutris.net/'},
      {'name': 'heroic-games-launcher-bin', 'description': 'An Open Source Epic Games and GOG Launcher', 'source': 'AUR', 'url': 'https://heroicgameslauncher.com/'},
      {'name': 'minecraft-launcher', 'description': 'Official Minecraft Launcher', 'source': 'AUR', 'url': 'https://www.minecraft.net/'},
    ],
    'Office': [
      {'name': 'libreoffice-fresh', 'description': 'LibreOffice branch which contains new features and program enhancements', 'source': 'Arch', 'url': 'https://www.libreoffice.org/'},
      {'name': 'onlyoffice-bin', 'description': 'Office suite that combines text, spreadsheet and presentation editors', 'source': 'AUR', 'url': 'https://www.onlyoffice.com/'},
      {'name': 'obsidian', 'description': 'A powerful knowledge base that works on top of a local folder of plain text Markdown files', 'source': 'Arch', 'url': 'https://obsidian.md/'},
    ]
  };

  final Map<String, IconData> categoryIcons = {
    'Recommended': Icons.star,
    'Web Browsers': Icons.language,
    'Development': Icons.code,
    'Multimedia': Icons.music_video,
    'System': Icons.settings_system_daydream,
    'Games': Icons.sports_esports,
    'Office': Icons.work,
  };

  Future<void> _searchApps(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearching = true;
      _searchResults = [];
    });

    List<Map<String, dynamic>> temp = [];

    // Pacman search
    try {
      var pr = await Process.run('pacman', ['-Ss', '^$query']);
      var lines = pr.stdout.toString().split('\n');
      for (int i = 0; i < lines.length - 1; i++) {
        if (lines[i].startsWith('core/') || lines[i].startsWith('extra/') || lines[i].startsWith('community/') || lines[i].startsWith('multilib/')) {
          var parts = lines[i].split(' ');
          var name = parts[0].split('/').last;
          var desc = i + 1 < lines.length ? lines[i + 1].trim() : '';
          temp.add({
            'name': name,
            'description': desc,
            'source': 'Arch',
          });
        }
      }
    } catch (e) {
      debugPrint("Pacman error: $e");
    }

    // AUR search
    try {
      var response = await http.get(Uri.parse('https://aur.archlinux.org/rpc/v5/search/$query'));
      var json = jsonDecode(response.body);
      if (json['results'] != null) {
        for (var item in json['results']) {
          temp.add({
            'name': item['Name'],
            'description': item['Description'] ?? '',
            'source': 'AUR',
          });
        }
      }
    } catch (e) {
      debugPrint("AUR error: $e");
    }

    if (mounted) {
      setState(() {
        _searchResults = temp;
        _isLoading = false;
      });
    }
  }

  void _installApp(String appName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => InstallDialog(appName: appName),
    );
  }

  Widget _buildAppCard(Map<String, dynamic> item) {
    bool isAUR = item['source'] == 'AUR';
    String url = item['url'] ?? '';
    String host = '';
    try {
      if (url.isNotEmpty) host = Uri.parse(url).host;
    } catch(e) {}

    Widget iconWidget;
    if (host.isNotEmpty) {
      iconWidget = Image.network(
        'https://icon.horse/icon/$host',
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) => Icon(
          isAUR ? Icons.cloud_download : Icons.computer,
          color: isAUR ? Colors.blueAccent : Colors.green,
          size: 28,
        ),
      );
    } else {
      iconWidget = Icon(
        isAUR ? Icons.cloud_download : Icons.computer,
        color: isAUR ? Colors.blueAccent : Colors.green,
        size: 28,
      );
    }

    return Card(
      elevation: 0,
      color: FyrTheme.isDark ? const Color(0xFF3B393D) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isAUR ? Colors.blueAccent.withOpacity(0.2) : Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: iconWidget),
        ),
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            item['description'],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => _installApp(item['name']),
          child: const Text('Install', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResizableWindow(
        child: Column(
          children: [
            CustomTitleBar(),
            Expanded(
              child: Row(
                children: [
                  // Sidebar
                  Container(
                    width: 220,
                    color: FyrTheme.isDark ? const Color(0xFF222124) : const Color(0xFFE5E7EB),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
                          child: Text(
                            'Categories',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: defaultApps.keys.length,
                            itemBuilder: (context, index) {
                              String category = defaultApps.keys.elementAt(index);
                              bool isSelected = !_isSearching && _selectedCategory == category;
                              return ListTile(
                                leading: Icon(
                                  categoryIcons[category],
                                  color: isSelected ? FyrTheme.accentColor : Colors.grey,
                                ),
                                title: Text(
                                  category,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? FyrTheme.accentColor : (FyrTheme.isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                                selected: isSelected,
                                selectedTileColor: FyrTheme.accentColor.withOpacity(0.1),
                                onTap: () {
                                  setState(() {
                                    _isSearching = false;
                                    _selectedCategory = category;
                                    _searchController.clear();
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Main Content
                  Expanded(
                    child: Column(
                      children: [
                        // Search Bar
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search for apps (Arch/AUR)...',
                              filled: true,
                              fillColor: FyrTheme.isDark ? const Color(0xFF3B393D) : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isNotEmpty ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _isSearching = false;
                                  });
                                },
                              ) : null,
                            ),
                            onChanged: (val) {
                              setState(() {}); // Update suffix icon
                            },
                            onSubmitted: _searchApps,
                          ),
                        ),
                        // Content Area
                        Expanded(
                          child: _isSearching
                              ? (_isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : _searchResults.isEmpty
                                      ? const Center(child: Text('No applications found.'))
                                      : ListView.builder(
                                          itemCount: _searchResults.length,
                                          itemBuilder: (context, index) => _buildAppCard(_searchResults[index]),
                                        ))
                              : ListView.builder(
                                  itemCount: defaultApps[_selectedCategory]!.length,
                                  itemBuilder: (context, index) => _buildAppCard(defaultApps[_selectedCategory]![index]),
                                ),
                        ),
                      ],
                    ),
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

class CustomTitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () {
        Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']);
      },
      child: Container(
        height: 45,
        color: FyrTheme.isDark ? const Color.fromARGB(255, 0, 0, 0) : const Color(0xFFeff1f5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Row(
              children: [
                _WindowButton(
                  color: Colors.red.shade300,
                  onPressed: () => windowManager.close(),
                ),
                const SizedBox(width: 8),
                _WindowButton(
                  color: Colors.amber.shade300,
                  onPressed: () {
                    Process.run('swaymsg', ['[pid="$pid"] move scratchpad']);
                  },
                ),
                const SizedBox(width: 8),
                _WindowButton(
                  color: Colors.green.shade300,
                  onPressed: () {
                    Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']);
                  },
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Text(
                  'FyrStore',
                  style: TextStyle(
                    color: FyrTheme.isDark ? const Color(0xFFcdd6f4) : const Color(0xFF4c4f69),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 60),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final Color color;
  final VoidCallback onPressed;

  const _WindowButton({required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class InstallDialog extends StatefulWidget {
  final String appName;
  const InstallDialog({super.key, required this.appName});

  @override
  State<InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<InstallDialog> {
  late Terminal terminal;
  late TerminalController terminalController;
  late Pty pty;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    terminalController = TerminalController();
    
    String cmd = '''
if ! command -v yay &> /dev/null; then
  echo "AUR helper 'yay' not found. Installing yay automatically..."
  sudo pacman -S --noconfirm base-devel git
  rm -rf /tmp/yay-bin
  git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  cd /tmp/yay-bin
  makepkg -si --noconfirm
fi
echo "Installing \${APP}..."
yay -S --noconfirm "\${APP}"
echo ""
echo "Installation process finished. You can close this dialog."
''';

    pty = Pty.start('bash', arguments: ['-c', cmd], environment: {'TERM': 'xterm-256color', 'APP': widget.appName, ...Platform.environment});

    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
          if (mounted) terminal.write(data);
        });

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };
    
    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }

  @override
  void dispose() {
    pty.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.isDark ? const Color(0xFF2A282C) : Colors.white,
      title: Text('Installing ${widget.appName}'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: TerminalView(
          terminal,
          controller: terminalController,
          autofocus: true,
          theme: FyrTheme.isDark ? TerminalThemes.defaultTheme : TerminalThemes.whiteOnBlack,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: FyrTheme.accentColor)),
        ),
      ],
    );
  }
}
