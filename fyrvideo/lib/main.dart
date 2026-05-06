import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';

void main(List<String> args) async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  String? initialFile;
  if (args.isNotEmpty) {
    initialFile = args.first;
  }

  runApp(FyrVideoApp(initialFile: initialFile));
}

class FyrVideoApp extends StatelessWidget {
  final String? initialFile;
  const FyrVideoApp({super.key, this.initialFile});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FyrVideo',
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
        home: VideoPlayerScreen(initialFile: initialFile),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String? initialFile;
  const VideoPlayerScreen({super.key, this.initialFile});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  String? _currentFileName;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _playFile(widget.initialFile!);
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _playFile(String path) {
    setState(() {
      _currentFileName = p.basename(path);
    });
    player.open(Media(path));
  }

  Future<void> _openFilePicker() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      _playFile(result.files.single.path!);
    }
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FyrTheme.bgColor,
      body: Column(
        children: [
          DragToMoveArea(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                  const SizedBox(width: 8),
                  _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                  const SizedBox(width: 8),
                  _buildTrafficLight(Colors.greenAccent, () async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  }),
                  const SizedBox(width: 24),
                  Icon(Icons.movie, color: FyrTheme.textColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentFileName ?? 'FyrVideo',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.folder_open, color: FyrTheme.textColor),
                    onPressed: _openFilePicker,
                    tooltip: 'Open Video',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    controller: controller,
                    controls: MaterialVideoControls,
                  ),
                  if (_currentFileName == null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.video_library,
                            size: 64,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No video loaded',
                            style: TextStyle(color: Colors.white54, fontSize: 18),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _openFilePicker,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Open File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FyrTheme.accentColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
