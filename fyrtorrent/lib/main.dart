import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';
import 'services/torrent_service.dart';

ServerSocket? _instanceServer;

String _instanceSocketPath() {
  final home = Platform.environment['HOME'] ?? '';
  final dir = Directory(p.join(home, '.config', 'fyrtorrent'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return p.join(dir.path, 'instance.sock');
}

/// If another fyrtorrent instance is already running, forward CLI args to it
/// and return true so this process can exit immediately instead of fighting
/// over the same download files and ports.
Future<bool> _tryForwardToExistingInstance(List<String> args) async {
  final sockPath = _instanceSocketPath();
  if (!File(sockPath).existsSync()) return false;
  try {
    final socket = await Socket.connect(
      InternetAddress(sockPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(milliseconds: 500),
    );
    socket.write('${jsonEncode({'args': args})}\n');
    await socket.flush();
    await socket.close();
    return true;
  } catch (_) {
    // Stale socket from a previous crashed process — clean it up.
    try {
      File(sockPath).deleteSync();
    } catch (_) {}
    return false;
  }
}

Future<void> _startInstanceServer(TorrentService torrentService) async {
  final sockPath = _instanceSocketPath();
  try {
    if (File(sockPath).existsSync()) {
      File(sockPath).deleteSync();
    }
    _instanceServer = await ServerSocket.bind(
      InternetAddress(sockPath, type: InternetAddressType.unix),
      0,
    );
    _instanceServer!.listen((Socket client) {
      final buffer = StringBuffer();
      client.listen(
        (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
        onDone: () {
          client.destroy();
          final raw = buffer.toString().trim();
          if (raw.isEmpty) return;
          try {
            final payload = jsonDecode(raw);
            if (payload is Map && payload['args'] is List) {
              final incomingArgs =
                  payload['args'].map<String>((e) => e.toString()).toList();
              if (incomingArgs.isNotEmpty) {
                unawaited(torrentService.handleCliArgs(incomingArgs));
              }
            }
          } catch (_) {}
          unawaited(windowManager.show().then((_) => windowManager.focus()));
        },
        onError: (_) => client.destroy(),
      );
    });
  } catch (e) {
    debugPrint('Could not bind single-instance socket: $e');
  }
}

Future<void> _cleanupInstanceServer() async {
  try {
    await _instanceServer?.close();
  } catch (_) {}
  _instanceServer = null;
  try {
    final sockFile = File(_instanceSocketPath());
    if (sockFile.existsSync()) {
      sockFile.deleteSync();
    }
  } catch (_) {}
}

void main(List<String> args) async {
  // Forward magnet links / .torrent files to an already-running instance first.
  if (await _tryForwardToExistingInstance(args)) {
    exit(0);
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  FyrTheme.initialize();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 500),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  final torrentService = TorrentService();
  unawaited(_startInstanceServer(torrentService));
  // Render UI immediately; load persisted torrents and CLI args asynchronously.
  unawaited(torrentService.init(initialArgs: args));

  runApp(
    ChangeNotifierProvider.value(
      value: torrentService,
      child: const FyrTorrentApp(),
    ),
  );
}

class FyrTorrentApp extends StatelessWidget {
  const FyrTorrentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: FyrTheme.themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrTorrent',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: FyrTheme.accentColor,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: Colors.black,
            useMaterial3: true,
          ),
          themeMode: themeMode,
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await _shutdownAndClose();
  }

  Future<void> _shutdownAndClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await Future.wait([
        TorrentService().disposeAll(),
        _cleanupInstanceServer(),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<String?> _pickFile({
    String? title,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final home = Platform.environment['HOME'] ?? '';
    final fyrfilesCandidates = [
      if (home.isNotEmpty) p.join(home, '.local/bin/fyrfiles'),
      if (home.isNotEmpty) p.join(home, '.local/share/fyrDE/fyrfiles/fyrfiles'),
      '/usr/local/bin/fyrfiles',
      '/usr/bin/fyrfiles',
    ];

    String? fyrfilesPath;
    for (final c in fyrfilesCandidates) {
      if (File(c).existsSync()) {
        fyrfilesPath = c;
        break;
      }
    }

    if (fyrfilesPath != null) {
      try {
        final startDir = (initialDirectory != null && Directory(initialDirectory).existsSync())
            ? initialDirectory
            : (home.isNotEmpty && Directory(p.join(home, 'Downloads')).existsSync()
                ? p.join(home, 'Downloads')
                : (home.isNotEmpty ? home : '.'));

        final args = <String>['--picker'];
        if (title != null && title.isNotEmpty) {
          args.add('--title=$title');
        }
        args.add(startDir);

        final res = await Process.run(fyrfilesPath, args);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            final picked = out.split('\n').first.trim();
            if (File(picked).existsSync()) {
              return picked;
            }
          }
        }
        return null;
      } catch (_) {}
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: title,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        return result.files.single.path;
      }
    } catch (_) {}

    return null;
  }

  void _addTorrent(BuildContext context) async {
    final home = Platform.environment['HOME'] ?? '';
    final downloadsDir = home.isNotEmpty ? p.join(home, 'Downloads') : null;
    final path = await _pickFile(
      title: 'Select Torrent File',
      initialDirectory: downloadsDir,
      type: FileType.custom,
      allowedExtensions: ['torrent'],
    );

    if (path != null && context.mounted) {
      // ignore: use_build_context_synchronously
      Provider.of<TorrentService>(
        context,
        listen: false,
      ).addTorrentFromFile(path);
    }
  }

  void _addMagnet(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor.withOpacity(0.9),
        title: Text(
          'Add Magnet Link',
          style: TextStyle(color: FyrTheme.textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FyrTheme.textColor),
          decoration: InputDecoration(
            hintText: 'magnet:?xt=urn:btih:...',
            hintStyle: TextStyle(color: FyrTheme.textColorMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FyrTheme.accentColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Provider.of<TorrentService>(
                  context,
                  listen: false,
                ).addTorrentFromMagnet(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final torrentService = Provider.of<TorrentService>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background Glow (lightweight RadialGradient instead of sigma=100 BackdropFilter)
          Positioned(
            top: -150,
            right: -150,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        FyrTheme.accentColor.withOpacity(0.18),
                        FyrTheme.accentColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          Column(
            children: [
              // Header
              GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  // height: 48, // Defined height for consistent drag area
                  color: Colors.transparent, // Ensure it catches hits
                  child: Row(
                    children: [
                      // Traffic Lights
                      _buildTrafficLight(
                        Colors.redAccent,
                        () => _shutdownAndClose(),
                      ),
                      const SizedBox(width: 8),
                      _buildTrafficLight(
                        Colors.amberAccent,
                        () => windowManager.minimize(),
                      ),
                      const SizedBox(width: 8),
                      _buildTrafficLight(
                        Colors.greenAccent,
                        () async {
                          if (await windowManager.isMaximized()) {
                            await windowManager.unmaximize();
                          } else {
                            await windowManager.maximize();
                          }
                        },
                      ),

                      const Spacer(),

                      IconButton(
                        icon: Icon(
                          Icons.link,
                          color: FyrTheme.accentColor,
                          size: 20,
                        ),
                        onPressed: () => _addMagnet(context),
                        tooltip: 'Add Magnet Link',
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: () => _addTorrent(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text(
                            'Add Torrent',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FyrTheme.accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Torrent List
              Expanded(
                child: Column(
                  children: [
                    if (torrentService.pendingMagnets.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fetching Metadata...',
                              style: TextStyle(
                                color: FyrTheme.accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...torrentService.pendingMagnets.map(
                              (hash) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: FyrTheme.cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: FyrTheme.accentColor.withOpacity(
                                      0.2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: FyrTheme.accentColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Magnet: ${hash.substring(0, 8)}...',
                                        style: TextStyle(
                                          color: FyrTheme.textColorMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Divider(color: FyrTheme.dividerColor),
                          ],
                        ),
                      ),

                    Expanded(
                      child:
                          torrentService.items.isEmpty &&
                              torrentService.pendingMagnets.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_download_outlined,
                                    size: 48,
                                    color: FyrTheme.textColorMuted.withOpacity(
                                      0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No active torrents',
                                    style: TextStyle(
                                      color: FyrTheme.textColorMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: torrentService.items.length,
                              itemBuilder: (context, index) {
                                return TorrentListItem(
                                  item: torrentService.items[index],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // Bottom Bar / IP
              if (torrentService.publicIp != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    border: Border(
                      top: BorderSide(
                        color: FyrTheme.dividerColor.withOpacity(0.1),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.public,
                        size: 12,
                        color: FyrTheme.textColorMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Your IP: ${torrentService.publicIp}',
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }
}

class TorrentListItem extends StatelessWidget {
  final TorrentItem item;
  const TorrentListItem({super.key, required this.item});

  String _formatSpeed(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(1)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: item,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: FyrTheme.accentColor.withOpacity(
                item.isCompleted ? 0.3 : 0.1,
              ),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildActionButton(),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: FyrTheme.accentColor.withOpacity(0.1),
                  color: item.isCompleted
                      ? Colors.greenAccent
                      : FyrTheme.accentColor,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: 14,
                        color: FyrTheme.accentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatSpeed(item.downloadSpeed),
                        style: TextStyle(
                          fontSize: 12,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.arrow_upward,
                        size: 14,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatSpeed(item.uploadSpeed),
                        style: TextStyle(
                          fontSize: 12,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.people, size: 14, color: FyrTheme.accentColor),
                      const SizedBox(width: 4),
                      Text(
                        '${item.seeders} S / ${item.leechers} L',
                        style: TextStyle(
                          fontSize: 12,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(item.progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: item.isCompleted
                          ? Colors.greenAccent
                          : FyrTheme.textColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRemoveButton() {
    return IconButton(
      constraints: const BoxConstraints(),
      padding: EdgeInsets.zero,
      tooltip: 'Remove torrent',
      icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
      onPressed: () {
        TorrentService().removeTorrent(item);
      },
    );
  }

  Widget _buildPauseButton() {
    return IconButton(
      constraints: const BoxConstraints(),
      padding: EdgeInsets.zero,
      tooltip: item.isCompleted
          ? (item.isPaused ? 'Resume seeding' : 'Pause seeding')
          : (item.isPaused ? 'Resume' : 'Pause'),
      icon: Icon(
        item.isPaused ? Icons.play_arrow : Icons.pause,
        size: 20,
        color: FyrTheme.textColorMuted,
      ),
      onPressed: () {
        if (item.isPaused) {
          item.resume();
        } else {
          item.pause();
        }
      },
    );
  }

  Widget _buildActionButton() {
    if (item.isCompleted) {
      final badgeColor = item.isPaused ? Colors.amberAccent : Colors.greenAccent;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item.isPaused ? 'Paused' : 'Seeding',
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildPauseButton(),
          const SizedBox(width: 8),
          _buildRemoveButton(),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPauseButton(),
        const SizedBox(width: 8),
        _buildRemoveButton(),
      ],
    );
  }
}
