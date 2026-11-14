import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    String arg = args.first.trim();
    if (arg.startsWith('file://')) {
      try {
        arg = Uri.parse(arg).toFilePath();
      } catch (_) {
        arg = arg.substring(7);
      }
    }
    try {
      arg = Uri.decodeFull(arg);
    } catch (_) {}
    initialFile = arg;
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
  String? _currentFilePath;

  // Subtitle state
  List<SubtitleTrack> _subtitleTracks = [];
  SubtitleTrack _selectedSubtitleTrack = SubtitleTrack.auto();
  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 26.0;
  double _subtitleDelay = 0.0; // Seconds offset (mpv sub-delay)

  StreamSubscription? _tracksSubscription;
  StreamSubscription? _trackSubscription;

  @override
  void initState() {
    super.initState();

    _tracksSubscription = player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() {
          _subtitleTracks = tracks.subtitle;
        });
      }
    });

    _trackSubscription = player.stream.track.listen((track) {
      if (mounted) {
        setState(() {
          _selectedSubtitleTrack = track.subtitle;
          _subtitlesEnabled = track.subtitle.id != 'no';
        });
      }
    });

    if (widget.initialFile != null) {
      _playFile(widget.initialFile!);
    }
  }

  @override
  void dispose() {
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  void _playFile(String path) {
    setState(() {
      _currentFilePath = path;
      _currentFileName = p.basename(path);
      _subtitleDelay = 0.0;
    });
    player.open(Media(path));
    _autoDetectSubtitles(path);
  }

  void _autoDetectSubtitles(String videoPath) {
    try {
      final videoFile = File(videoPath);
      final dir = videoFile.parent;
      final baseName = p.basenameWithoutExtension(videoPath);
      if (dir.existsSync()) {
        final subExtensions = ['.srt', '.vtt', '.ass', '.ssa', '.sub'];
        for (final entity in dir.listSync()) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (subExtensions.contains(ext)) {
              final fileName = p.basenameWithoutExtension(entity.path);
              if (fileName == baseName ||
                  fileName.startsWith('$baseName.') ||
                  fileName.startsWith('$baseName-') ||
                  fileName.startsWith('$baseName _')) {
                final label = fileName == baseName
                    ? 'External (${ext.replaceFirst('.', '').toUpperCase()})'
                    : fileName.substring(baseName.length + 1);
                final track = SubtitleTrack.uri(entity.path, title: label);
                player.setSubtitleTrack(track);
                break;
              }
            }
          }
        }
      }
    } catch (_) {}
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
            : (home.isNotEmpty && Directory(p.join(home, 'Videos')).existsSync()
                ? p.join(home, 'Videos')
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

  Future<void> _openFilePicker() async {
    final startDir = _currentFilePath != null ? p.dirname(_currentFilePath!) : null;
    final picked = await _pickFile(
      title: 'Open Video',
      initialDirectory: startDir,
      type: FileType.video,
    );

    if (picked != null) {
      _playFile(picked);
    }
  }

  Future<void> _pickSubtitleFile() async {
    final startDir = _currentFilePath != null ? p.dirname(_currentFilePath!) : null;
    final subPath = await _pickFile(
      title: 'Select Subtitles',
      initialDirectory: startDir,
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa', 'sub'],
    );
    if (subPath != null) {
      final track = SubtitleTrack.uri(subPath, title: p.basename(subPath));
      await player.setSubtitleTrack(track);
      setState(() {
        _selectedSubtitleTrack = track;
        _subtitlesEnabled = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded subtitle: ${p.basename(subPath)}'),
            backgroundColor: FyrTheme.accentColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleSubtitles() async {
    if (_subtitlesEnabled && _selectedSubtitleTrack.id != 'no') {
      await player.setSubtitleTrack(SubtitleTrack.no());
      setState(() {
        _subtitlesEnabled = false;
        _selectedSubtitleTrack = SubtitleTrack.no();
      });
    } else {
      final target = _subtitleTracks.firstWhere(
        (t) => t.id != 'no',
        orElse: () => SubtitleTrack.auto(),
      );
      await player.setSubtitleTrack(target);
      setState(() {
        _subtitlesEnabled = true;
        _selectedSubtitleTrack = target;
      });
    }
  }

  Future<void> _adjustSubtitleDelay(double delta) async {
    final newDelay = double.parse((_subtitleDelay + delta).toStringAsFixed(2));
    setState(() {
      _subtitleDelay = newDelay;
    });
    try {
      await (player.platform as dynamic)?.setProperty('sub-delay', '$_subtitleDelay');
    } catch (_) {}
  }

  Future<void> _resetSubtitleDelay() async {
    setState(() {
      _subtitleDelay = 0.0;
    });
    try {
      await (player.platform as dynamic)?.setProperty('sub-delay', '0.0');
    } catch (_) {}
  }

  String _formatTrackTitle(SubtitleTrack track) {
    if (track.id == 'no') return 'Off';
    if (track.id == 'auto') return 'Auto (Default)';
    final parts = <String>[];
    if (track.title != null && track.title!.trim().isNotEmpty) {
      parts.add(track.title!.trim());
    }
    if (track.language != null && track.language!.trim().isNotEmpty) {
      parts.add('(${track.language!.trim()})');
    }
    if (parts.isEmpty) {
      parts.add('Subtitle Track #${track.id}');
    }
    return parts.join(' ');
  }

  void _showSubtitlesDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: FyrTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
              ),
              title: Row(
                children: [
                  Icon(Icons.subtitles, color: FyrTheme.accentColor),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subtitle Settings',
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (_currentFilePath != null)
                        Text(
                          _currentFileName ?? '',
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtitle master switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Enable Subtitles',
                          style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _subtitlesEnabled ? 'Subtitles are showing' : 'Subtitles are turned off',
                          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                        ),
                        value: _subtitlesEnabled && _selectedSubtitleTrack.id != 'no',
                        activeColor: FyrTheme.accentColor,
                        onChanged: (val) async {
                          await _toggleSubtitles();
                          setDialogState(() {});
                          setState(() {});
                        },
                      ),
                      const Divider(height: 24),

                      // Tracks Section
                      Text(
                        'Select Track',
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: FyrTheme.isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            RadioListTile<String>(
                              dense: true,
                              title: const Text('Off'),
                              value: 'no',
                              groupValue: _selectedSubtitleTrack.id,
                              activeColor: FyrTheme.accentColor,
                              onChanged: (val) async {
                                final track = SubtitleTrack.no();
                                await player.setSubtitleTrack(track);
                                setDialogState(() {
                                  _selectedSubtitleTrack = track;
                                  _subtitlesEnabled = false;
                                });
                                setState(() {});
                              },
                            ),
                            RadioListTile<String>(
                              dense: true,
                              title: const Text('Auto'),
                              value: 'auto',
                              groupValue: _selectedSubtitleTrack.id,
                              activeColor: FyrTheme.accentColor,
                              onChanged: (val) async {
                                final track = SubtitleTrack.auto();
                                await player.setSubtitleTrack(track);
                                setDialogState(() {
                                  _selectedSubtitleTrack = track;
                                  _subtitlesEnabled = true;
                                });
                                setState(() {});
                              },
                            ),
                            ..._subtitleTracks
                                .where((t) => t.id != 'no' && t.id != 'auto')
                                .map((track) {
                              return RadioListTile<String>(
                                dense: true,
                                title: Text(
                                  _formatTrackTitle(track),
                                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                                ),
                                value: track.id,
                                groupValue: _selectedSubtitleTrack.id,
                                activeColor: FyrTheme.accentColor,
                                onChanged: (val) async {
                                  await player.setSubtitleTrack(track);
                                  setDialogState(() {
                                    _selectedSubtitleTrack = track;
                                    _subtitlesEnabled = true;
                                  });
                                  setState(() {});
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Load External Subtitle File Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FyrTheme.textColor,
                          side: BorderSide(color: FyrTheme.accentColor.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(double.infinity, 38),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _pickSubtitleFile();
                        },
                        icon: const Icon(Icons.file_open, size: 18),
                        label: const Text('Load External Subtitle File (.srt, .vtt, .ass)...'),
                      ),
                      const Divider(height: 24),

                      // Subtitle Sync / Delay
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Audio Sync Delay',
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${_subtitleDelay >= 0 ? '+' : ''}${_subtitleDelay.toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: _subtitleDelay != 0.0 ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildDelayButton('-0.5s', () async {
                            await _adjustSubtitleDelay(-0.5);
                            setDialogState(() {});
                          }),
                          _buildDelayButton('-0.1s', () async {
                            await _adjustSubtitleDelay(-0.1);
                            setDialogState(() {});
                          }),
                          _buildDelayButton('Reset', () async {
                            await _resetSubtitleDelay();
                            setDialogState(() {});
                          }),
                          _buildDelayButton('+0.1s', () async {
                            await _adjustSubtitleDelay(0.1);
                            setDialogState(() {});
                          }),
                          _buildDelayButton('+0.5s', () async {
                            await _adjustSubtitleDelay(0.5);
                            setDialogState(() {});
                          }),
                        ],
                      ),
                      const Divider(height: 24),

                      // Subtitle Font Size
                      Text(
                        'Font Size',
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildSizeChip('Small', 20.0, setDialogState),
                          const SizedBox(width: 8),
                          _buildSizeChip('Medium', 26.0, setDialogState),
                          const SizedBox(width: 8),
                          _buildSizeChip('Large', 34.0, setDialogState),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Done', style: TextStyle(color: FyrTheme.accentColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDelayButton(String text, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: BorderSide(color: FyrTheme.dividerColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onPressed,
        child: Text(text, style: TextStyle(color: FyrTheme.textColor, fontSize: 12)),
      ),
    );
  }

  Widget _buildSizeChip(String label, double size, StateSetter setDialogState) {
    final isSelected = _subtitleFontSize == size;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: FyrTheme.accentColor,
      backgroundColor: FyrTheme.isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : FyrTheme.textColor,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          setDialogState(() {
            _subtitleFontSize = size;
          });
          setState(() {
            _subtitleFontSize = size;
          });
        }
      },
    );
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
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyC) {
            _toggleSubtitles();
          } else if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
            _adjustSubtitleDelay(-0.1);
          } else if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
            _adjustSubtitleDelay(0.1);
          } else if (event.logicalKey == LogicalKeyboardKey.keyS &&
              HardwareKeyboard.instance.isMetaPressed) {
            _showSubtitlesDialog();
          }
        }
      },
      child: Scaffold(
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
                    // Subtitles button
                    IconButton(
                      icon: Icon(
                        _subtitlesEnabled && _selectedSubtitleTrack.id != 'no'
                            ? Icons.subtitles
                            : Icons.subtitles_off_outlined,
                        color: _subtitlesEnabled && _selectedSubtitleTrack.id != 'no'
                            ? FyrTheme.accentColor
                            : FyrTheme.textColor.withOpacity(0.6),
                      ),
                      onPressed: _showSubtitlesDialog,
                      tooltip: 'Subtitles & Captions',
                    ),
                    const SizedBox(width: 4),
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
                      controls: (videoState) => _FyrVideoControls(
                        videoState: videoState,
                        player: player,
                        subtitlesEnabled: _subtitlesEnabled && _selectedSubtitleTrack.id != 'no',
                        onOpenSubtitles: _showSubtitlesDialog,
                      ),
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: _subtitlesEnabled && _selectedSubtitleTrack.id != 'no',
                        style: TextStyle(
                          height: 1.3,
                          fontSize: _subtitleFontSize,
                          color: Colors.white,
                          backgroundColor: Colors.black.withOpacity(0.65),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          shadows: const [
                            Shadow(blurRadius: 3.0, color: Colors.black, offset: Offset(1.0, 1.0)),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 88.0),
                      ),
                    ),
                    if (_currentFileName == null)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.video_library,
                              size: 64,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 16),
                            const Text(
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
      ),
    );
  }
}

class _FyrVideoControls extends StatefulWidget {
  final VideoState videoState;
  final Player player;
  final bool subtitlesEnabled;
  final VoidCallback onOpenSubtitles;

  const _FyrVideoControls({
    required this.videoState,
    required this.player,
    required this.subtitlesEnabled,
    required this.onOpenSubtitles,
  });

  @override
  State<_FyrVideoControls> createState() => _FyrVideoControlsState();
}

class _FyrVideoControlsState extends State<_FyrVideoControls> {
  bool _visible = false;
  bool _hoveringBottomControls = false;
  bool _seeking = false;
  double? _dragValue;
  Timer? _hideTimer;

  late bool _playing = widget.player.state.playing;
  late Duration _position = widget.player.state.position;
  late Duration _duration = widget.player.state.duration;
  late double _volume = widget.player.state.volume;
  double _lastNonZeroVolume = 100.0;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      widget.player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }),
      widget.player.stream.position.listen((v) {
        if (mounted && !_seeking) setState(() => _position = v);
      }),
      widget.player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }),
      widget.player.stream.volume.listen((v) {
        if (mounted) {
          setState(() {
            _volume = v;
            if (v > 0) _lastNonZeroVolume = v;
          });
        }
      }),
    ]);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _showControlsAndScheduleHide() {
    if (!_visible) {
      setState(() => _visible = true);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && !_hoveringBottomControls && !_seeking) {
        setState(() => _visible = false);
      }
    });
  }

  void _onMouseExitWindow() {
    _hideTimer?.cancel();
    if (!_seeking && mounted) {
      setState(() {
        _hoveringBottomControls = false;
        _visible = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds <= 0) return '0:00';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = (_seeking && _dragValue != null)
        ? _dragValue!
        : _position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    const iconShadows = [
      Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
    ];

    return MouseRegion(
      cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      onEnter: (_) => _showControlsAndScheduleHide(),
      onHover: (_) => _showControlsAndScheduleHide(),
      onExit: (_) => _onMouseExitWindow(),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
            widget.player.setVolume((_volume + delta).clamp(0.0, 100.0));
            _showControlsAndScheduleHide();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video surface tap/double-tap area
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                widget.player.playOrPause();
                _showControlsAndScheduleHide();
              },
              onDoubleTap: () {
                widget.videoState.toggleFullscreen();
              },
              child: const SizedBox.expand(),
            ),
            // Hover-fading transparent bottom controls with generous padding
            Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                ignoring: !_visible,
                child: AnimatedOpacity(
                  opacity: _visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: MouseRegion(
                    onEnter: (_) {
                      _hoveringBottomControls = true;
                      _hideTimer?.cancel();
                      if (!_visible) setState(() => _visible = true);
                    },
                    onHover: (_) {
                      _hoveringBottomControls = true;
                      _hideTimer?.cancel();
                    },
                    onExit: (_) {
                      _hoveringBottomControls = false;
                      _showControlsAndScheduleHide();
                    },
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.fromLTRB(28.0, 12.0, 28.0, 22.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Scrubber / Seek bar
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4.0,
                              activeTrackColor: FyrTheme.accentColor,
                              inactiveTrackColor: Colors.white.withOpacity(0.32),
                              thumbColor: Colors.white,
                              overlayColor: FyrTheme.accentColor.withOpacity(0.22),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                            ),
                            child: Slider(
                              value: maxMs > 0 ? currentMs.clamp(0.0, maxMs) : 0.0,
                              min: 0.0,
                              max: maxMs > 0 ? maxMs : 1.0,
                              onChangeStart: (val) {
                                _hideTimer?.cancel();
                                setState(() {
                                  _seeking = true;
                                  _dragValue = val;
                                });
                              },
                              onChanged: (val) {
                                setState(() {
                                  _dragValue = val;
                                });
                              },
                              onChangeEnd: (val) async {
                                final target = Duration(milliseconds: val.round());
                                await widget.player.seek(target);
                                if (mounted) {
                                  setState(() {
                                    _position = target;
                                    _seeking = false;
                                    _dragValue = null;
                                  });
                                  _showControlsAndScheduleHide();
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Play button and controls row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => widget.player.playOrPause(),
                                  tooltip: _playing ? 'Pause' : 'Play',
                                  icon: Icon(
                                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 30,
                                    shadows: iconShadows,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: () {
                                    if (_volume > 0) {
                                      _lastNonZeroVolume = _volume;
                                      widget.player.setVolume(0);
                                    } else {
                                      widget.player.setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 100.0);
                                    }
                                  },
                                  tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                                  icon: Icon(
                                    _volume == 0
                                        ? Icons.volume_off_rounded
                                        : (_volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                                    color: Colors.white,
                                    size: 22,
                                    shadows: iconShadows,
                                  ),
                                ),
                                SizedBox(
                                  width: 88,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3.0,
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white.withOpacity(0.3),
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                                    ),
                                    child: Slider(
                                      value: _volume.clamp(0.0, 100.0),
                                      min: 0.0,
                                      max: 100.0,
                                      onChanged: (v) => widget.player.setVolume(v),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${_formatDuration(Duration(milliseconds: currentMs.round()))} / ${_formatDuration(_duration)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    shadows: iconShadows,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: widget.onOpenSubtitles,
                                  tooltip: 'Subtitles & Captions',
                                  icon: Icon(
                                    widget.subtitlesEnabled ? Icons.subtitles : Icons.subtitles_off_outlined,
                                    color: widget.subtitlesEnabled ? FyrTheme.accentColor : Colors.white,
                                    size: 22,
                                    shadows: iconShadows,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: () => widget.videoState.toggleFullscreen(),
                                  tooltip: 'Toggle Fullscreen',
                                  icon: Icon(
                                    widget.videoState.isFullscreen()
                                        ? Icons.fullscreen_exit_rounded
                                        : Icons.fullscreen_rounded,
                                    color: Colors.white,
                                    size: 26,
                                    shadows: iconShadows,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
