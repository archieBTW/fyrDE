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
    center: true,
    backgroundColor: Colors.transparent,
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
            useMaterial3: true,
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: true,
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
      {'name': 'firefox', 'friendlyName': 'Firefox Browser', 'description': 'Standalone web browser from mozilla.org', 'source': 'Arch', 'url': 'https://www.mozilla.org/firefox/'},
      {'name': 'visual-studio-code-bin', 'friendlyName': 'VS Code', 'description': 'Code Editor for building and debugging modern web and cloud applications', 'source': 'AUR', 'url': 'https://code.visualstudio.com/'},
      {'name': 'vlc', 'friendlyName': 'VLC Media Player', 'description': 'Multi-platform MPEG, VCD/DVD, and DivX player', 'source': 'Arch', 'url': 'https://www.videolan.org/'},
      {'name': 'discord', 'friendlyName': 'Discord', 'description': 'All-in-one voice and text chat for gamers', 'source': 'Arch', 'url': 'https://discord.com/'},
      {'name': 'steam', 'friendlyName': 'Steam', 'description': 'Valve distribution utility', 'source': 'Arch', 'url': 'https://store.steampowered.com/'},
      {'name': 'spotify', 'friendlyName': 'Spotify', 'description': 'A proprietary music streaming service', 'source': 'AUR', 'url': 'https://www.spotify.com/'},
    ],
    'Web Browsers': [
      {'name': 'firefox', 'friendlyName': 'Firefox', 'description': 'Standalone web browser from mozilla.org', 'source': 'Arch', 'url': 'https://www.mozilla.org/firefox/'},
      {'name': 'chromium', 'friendlyName': 'Chromium', 'description': 'A web browser built for speed, simplicity, and security', 'source': 'Arch', 'url': 'https://www.chromium.org/Home'},
      {'name': 'brave-bin', 'friendlyName': 'Brave', 'description': 'Web browser that blocks ads and trackers by default', 'source': 'AUR', 'url': 'https://brave.com/'},
      {'name': 'google-chrome', 'friendlyName': 'Google Chrome', 'description': 'The popular web browser by Google', 'source': 'AUR', 'url': 'https://www.google.com/chrome/'},
    ],
    'Development': [
      {'name': 'visual-studio-code-bin', 'friendlyName': 'VS Code', 'description': 'Visual Studio Code', 'source': 'AUR', 'url': 'https://code.visualstudio.com/'},
      {'name': 'intellij-idea-community-edition', 'friendlyName': 'IntelliJ IDEA', 'description': 'IntelliJ IDEA Community Edition', 'source': 'Arch', 'url': 'https://www.jetbrains.com/idea/'},
      {'name': 'neovim', 'friendlyName': 'Neovim', 'description': 'Fork of Vim aiming to improve user experience', 'source': 'Arch', 'url': 'https://neovim.io/'},
      {'name': 'git', 'friendlyName': 'Git', 'description': 'Distributed version control system', 'source': 'Arch', 'url': 'https://git-scm.com/'},
      {'name': 'docker', 'friendlyName': 'Docker', 'description': 'Pack, ship and run any application as a lightweight container', 'source': 'Arch', 'url': 'https://www.docker.com/'},
    ],
    'Multimedia': [
      {'name': 'vlc', 'friendlyName': 'VLC', 'description': 'Multi-platform player', 'source': 'Arch', 'url': 'https://www.videolan.org/'},
      {'name': 'spotify', 'friendlyName': 'Spotify', 'description': 'Music streaming service', 'source': 'AUR', 'url': 'https://www.spotify.com/'},
      {'name': 'obs-studio', 'friendlyName': 'OBS Studio', 'description': 'Video recording and live streaming', 'source': 'Arch', 'url': 'https://obsproject.com/'},
      {'name': 'gimp', 'friendlyName': 'GIMP', 'description': 'GNU Image Manipulation Program', 'source': 'Arch', 'url': 'https://www.gimp.org/'},
      {'name': 'blender', 'friendlyName': 'Blender', 'description': '3D graphics creation suite', 'source': 'Arch', 'url': 'https://www.blender.org/'},
    ],
    'System': [
      {'name': 'htop', 'friendlyName': 'Htop', 'description': 'Interactive process viewer', 'source': 'Arch', 'url': 'https://htop.dev/'},
      {'name': 'neofetch', 'friendlyName': 'Neofetch', 'description': 'CLI system information tool', 'source': 'Arch', 'url': 'https://github.com/dylanaraps/neofetch'},
      {'name': 'timeshift', 'friendlyName': 'Timeshift', 'description': 'System restore utility', 'source': 'Arch', 'url': 'https://github.com/linuxmint/timeshift'},
      {'name': 'alacritty', 'friendlyName': 'Alacritty', 'description': 'GPU-accelerated terminal emulator', 'source': 'Arch', 'url': 'https://alacritty.org/'},
    ],
    'Games': [
      {'name': 'steam', 'friendlyName': 'Steam', 'description': 'Valve distribution utility', 'source': 'Arch', 'url': 'https://store.steampowered.com/'},
      {'name': 'lutris', 'friendlyName': 'Lutris', 'description': 'Open gaming platform for Linux', 'source': 'Arch', 'url': 'https://lutris.net/'},
      {'name': 'heroic-games-launcher-bin', 'friendlyName': 'Heroic Launcher', 'description': 'Epic/GOG Launcher', 'source': 'AUR', 'url': 'https://heroicgameslauncher.com/'},
    ],
    'Office': [
      {'name': 'libreoffice-fresh', 'friendlyName': 'LibreOffice', 'description': 'LibreOffice branch with new features', 'source': 'Arch', 'url': 'https://www.libreoffice.org/'},
      {'name': 'onlyoffice-bin', 'friendlyName': 'ONLYOFFICE', 'description': 'Office suite for documents, spreadsheets, presentations', 'source': 'AUR', 'url': 'https://www.onlyoffice.com/'},
      {'name': 'obsidian', 'friendlyName': 'Obsidian', 'description': 'Powerful knowledge base on Markdown', 'source': 'Arch', 'url': 'https://obsidian.md/'},
    ]
  };

  final Map<String, IconData> categoryIcons = {
    'Recommended': Icons.star_rounded,
    'Web Browsers': Icons.language_rounded,
    'Development': Icons.code_rounded,
    'Multimedia': Icons.music_video_rounded,
    'System': Icons.settings_system_daydream_rounded,
    'Games': Icons.sports_esports_rounded,
    'Office': Icons.work_rounded,
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
            'friendlyName': name,
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
            'friendlyName': item['Name'],
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
          isAUR ? Icons.cloud_download_rounded : Icons.computer_rounded,
          color: isAUR ? Colors.blueAccent : FyrTheme.accentColor,
          size: 28,
        ),
      );
    } else {
      iconWidget = Icon(
        isAUR ? Icons.cloud_download_rounded : Icons.computer_rounded,
        color: isAUR ? Colors.blueAccent : FyrTheme.accentColor,
        size: 28,
      );
    }

    return Card(
      elevation: 0,
      color: FyrTheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: (isAUR ? Colors.blueAccent : FyrTheme.accentColor).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: iconWidget),
        ),
        title: Text(
          item['friendlyName'] ?? item['name'],
          style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['description'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
              const SizedBox(height: 4),
              Text(
                '${item['source']} Repository' + (item['friendlyName'] != item['name'] ? ' (${item['name']})' : ''),
                style: TextStyle(color: FyrTheme.accentColor.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
      backgroundColor: FyrTheme.bgColor,
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
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                          child: Text(
                            'CATEGORIES',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: FyrTheme.textColorMuted, letterSpacing: 1.2),
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
                                  color: isSelected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                                  size: 20,
                                ),
                                title: Text(
                                  category,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? FyrTheme.textColor : FyrTheme.textColorMuted,
                                    fontSize: 14,
                                  ),
                                ),
                                selected: isSelected,
                                selectedTileColor: FyrTheme.hoverColor,
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
                            style: TextStyle(color: FyrTheme.textColor),
                            decoration: InputDecoration(
                              hintText: 'Search for apps...',
                              hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                              filled: true,
                              fillColor: FyrTheme.cardColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: FyrTheme.dividerColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: FyrTheme.dividerColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: FyrTheme.accentColor),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                              prefixIcon: Icon(Icons.search_rounded, color: FyrTheme.accentColor),
                              suffixIcon: _searchController.text.isNotEmpty ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                color: FyrTheme.textColorMuted,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _isSearching = false;
                                  });
                                },
                              ) : null,
                            ),
                            onChanged: (val) {
                              setState(() {}); 
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
                                      ? Center(child: Text('No applications found.', style: TextStyle(color: FyrTheme.textColorMuted)))
                                      : ListView.builder(
                                          padding: const EdgeInsets.only(bottom: 24),
                                          itemCount: _searchResults.length,
                                          itemBuilder: (context, index) => _buildAppCard(_searchResults[index]),
                                        ))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 24),
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
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () {
        Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']);
      },
      child: Container(
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            InkWell(
              onTap: () => windowManager.close(),
              child: Icon(Icons.circle, color: Colors.red.shade300, size: 16),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => Process.run('swaymsg', ['[pid="$pid"] move scratchpad']),
              child: Icon(Icons.circle, color: Colors.amber.shade300, size: 16),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']),
              child: Icon(Icons.circle, color: Colors.green.shade300, size: 16),
            ),
            const SizedBox(width: 24),
            Text(
              'FyrStore',
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
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
      backgroundColor: const Color(0xFF2A282C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Installing ${widget.appName}', style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 700,
        height: 450,
        child: TerminalView(
          terminal,
          controller: terminalController,
          autofocus: true,
          theme: TerminalThemes.defaultTheme,
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
