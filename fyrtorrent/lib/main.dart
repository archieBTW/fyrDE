import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';
import 'services/torrent_service.dart';

void main(List<String> args) async {
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
    await windowManager.show();
    await windowManager.focus();
  });

  final torrentService = TorrentService();
  await torrentService.init();

  // Logging for debugging
  final logDir = Directory(
    p.join(Platform.environment['HOME'] ?? '', '.config', 'fyrtorrent'),
  );
  if (!logDir.existsSync()) logDir.createSync(recursive: true);
  final logFile = File(p.join(logDir.path, 'fyrtorrent.log'));
  await logFile.writeAsString(
    'Launched with args: $args\n',
    mode: FileMode.append,
  );

  // Handle CLI arguments
  if (args.isNotEmpty) {
    for (var arg in args) {
      final cleanArg = arg.replaceAll('"', '').replaceAll("'", "");
      if (cleanArg.startsWith('magnet:')) {
        await logFile.writeAsString(
          'Handling magnet: $cleanArg\n',
          mode: FileMode.append,
        );
        torrentService.addTorrentFromMagnet(cleanArg);
      } else if (cleanArg.endsWith('.torrent')) {
        await logFile.writeAsString(
          'Handling torrent file: $cleanArg\n',
          mode: FileMode.append,
        );
        torrentService.addTorrentFromFile(cleanArg);
      }
    }
  }

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

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  void _addTorrent(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
    );

    if (result != null && result.files.single.path != null) {
      // ignore: use_build_context_synchronously
      Provider.of<TorrentService>(
        context,
        listen: false,
      ).addTorrentFromFile(result.files.single.path!);
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
          // Background Glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FyrTheme.accentColor.withOpacity(0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(),
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
                        () => windowManager.close(),
                      ),
                      const SizedBox(width: 8),
                      _buildTrafficLight(
                        Colors.amberAccent,
                        () => windowManager.minimize(),
                      ),
                      const SizedBox(width: 8),
                      _buildTrafficLight(
                        Colors.greenAccent,
                        () => windowManager.maximize(),
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

  Widget _buildActionButton() {
    if (item.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Seeding',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
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
        ),
        const SizedBox(width: 8),
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
          onPressed: () {
            TorrentService().removeTorrent(item);
          },
        ),
      ],
    );
  }
}
