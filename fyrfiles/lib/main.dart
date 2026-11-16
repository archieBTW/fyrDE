// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'fyr_theme.dart';
import 's3_service.dart';

const dragChannel = MethodChannel('fyr_files/drag');

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

bool isPicker = false;
bool isSavePicker = false;
bool isDirectoryPicker = false;
bool isMultiplePicker = false;
String? initialDirectoryPath;
String? initialSelectedPath;
String? pickerTitle;

void _parsePickerPath(String raw) {
  String arg = raw.trim();
  if (arg.isEmpty) return;

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

  final home = Platform.environment['HOME'] ?? '';
  if (arg == '~' && home.isNotEmpty) {
    arg = home;
  } else if (arg.startsWith('~/') && home.isNotEmpty) {
    arg = p.join(home, arg.substring(2));
  }

  final d = Directory(arg);
  final f = File(arg);
  if (d.existsSync()) {
    initialDirectoryPath = d.absolute.path;
  } else if (f.existsSync()) {
    initialDirectoryPath = f.parent.absolute.path;
    initialSelectedPath = f.absolute.path;
  } else {
    final parent = Directory(p.dirname(arg));
    if (parent.existsSync()) {
      initialDirectoryPath = parent.absolute.path;
      initialSelectedPath = p.join(parent.absolute.path, p.basename(arg));
    }
  }
}

void main(List<String> args) async {
  if (args.any((a) =>
      a == '--picker' ||
      a.startsWith('--picker=') ||
      a == '--file-selection' ||
      a == '--save' ||
      a == '--directory')) {
    isPicker = true;
  }
  for (int i = 0; i < args.length; i++) {
    final rawArg = args[i];
    if (rawArg == '--picker' || rawArg == '--file-selection') continue;
    if (rawArg == '--save' || rawArg == '--getsavefilename') {
      isSavePicker = true;
      continue;
    }
    if (rawArg == '--directory' || rawArg == '--getexistingdirectory') {
      isDirectoryPicker = true;
      continue;
    }
    if (rawArg == '--multiple') {
      isMultiplePicker = true;
      continue;
    }
    if (rawArg.startsWith('--picker=')) {
      final pStr = rawArg.substring('--picker='.length).trim();
      if (pStr.isNotEmpty) _parsePickerPath(pStr);
      continue;
    }
    if (rawArg.startsWith('--filename=')) {
      final fStr = rawArg.substring('--filename='.length).trim();
      if (fStr.isNotEmpty) _parsePickerPath(fStr);
      continue;
    }
    if (rawArg == '--filename' && i + 1 < args.length) {
      _parsePickerPath(args[++i].trim());
      continue;
    }
    if (rawArg.startsWith('--title=')) {
      pickerTitle = rawArg.substring('--title='.length).trim();
      continue;
    }
    if (rawArg == '--title' && i + 1 < args.length) {
      pickerTitle = args[++i].trim();
      continue;
    }
    if (rawArg.startsWith('-')) continue;

    _parsePickerPath(rawArg.trim());
  }
  // If invoked as a picker with a specific file path (e.g. from SaveFile portal),
  // enable save mode unless explicitly in directory picker mode.
  if (isPicker && !isDirectoryPicker && initialSelectedPath != null) {
    isSavePicker = true;
  }
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    size: const Size(800, 600),
    center: true,
    title: isPicker
        ? (pickerTitle ?? (isSavePicker ? 'Save File' : (isDirectoryPicker ? 'Select Folder' : 'Open File')))
        : 'fyrfiles',
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const FyrFilesApp());
}

Widget getDotColor(Color color) {
  return Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
    ),
  );
}

List<Map<String, dynamic>> customTags = [
  {'id': 'purple', 'name': 'Creativity', 'colorValue': Colors.purple.value},
  {'id': 'green', 'name': 'Important', 'colorValue': Colors.green.value},
  {'id': 'blue', 'name': 'Development', 'colorValue': Colors.blue.value},
];
List<String> customPins = [];

Widget getDotByTag(String tag) {
  var t = customTags.firstWhere((element) => element['id'] == tag, orElse: () => <String, dynamic>{});
  if (t.isNotEmpty) {
    return getDotColor(Color(t['colorValue']));
  }
  return getDotColor(Colors.transparent);
}

Future<void> saveCustomTags() async {
  String homePath = Platform.environment['HOME'] ?? '/home/';
  if (Platform.isAndroid) {
    homePath = (await getApplicationDocumentsDirectory()).path;
  }
  String customTagsPath = p.join(homePath, '.fyr/files/tags_config.json');
  File file = File(customTagsPath);
  if (!file.existsSync()) file.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(customTags));
}

Future<void> saveCustomPins() async {
  String homePath = Platform.environment['HOME'] ?? '/home/';
  if (Platform.isAndroid) {
    homePath = (await getApplicationDocumentsDirectory()).path;
  }
  String pinsPath = p.join(homePath, '.fyr/files/pins.json');
  File file = File(pinsPath);
  if (!file.existsSync()) file.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(customPins));
}

class FileInfo {
  String filePath;
  String? tag;

  FileInfo({required this.filePath, this.tag});

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'tag': tag,
    };
  }

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      filePath: json['filePath'] as String,
      tag: json['tag'] as String?,
    );
  }
}

class TransferProgress {
  final String id;
  final String label;
  double progress;
  bool isCompleted;
  bool isError;
  String? errorMessage;

  TransferProgress({
    required this.id,
    required this.label,
    this.progress = 0.0,
    this.isCompleted = false,
    this.isError = false,
    this.errorMessage,
  });
}



class MousePanGestureRecognizer extends PanGestureRecognizer {
  MousePanGestureRecognizer({super.allowedButtonsFilter});

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    // Do nothing to prevent intercepting trackpad scrolling
  }
}

class FyrFilesApp extends StatelessWidget {
  const FyrFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (_, __) {
        return MaterialApp(
          theme: ThemeData.light(useMaterial3: true).copyWith(
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: FyrTheme.bgColor,
            colorScheme: ColorScheme.light(
              primary: FyrTheme.accentColor,
              surface: FyrTheme.surfaceColor,
            ),
            dividerColor: FyrTheme.dividerColor,
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: ColorScheme.dark(
              primary: FyrTheme.accentColor,
              surface: const Color(0xFF1E1E1E),
            ),
            dividerColor: FyrTheme.dividerColor,
          ),
          themeMode: FyrTheme.themeMode,
          home: const FyrFiles(),
        );
      },
    );
  }
}

class FyrFiles extends StatefulWidget {
  const FyrFiles({super.key});

  @override
  State<FyrFiles> createState() => _FyrFilesState();
}

class _FyrFilesState extends State<FyrFiles> with WindowListener {
  late List<FileSystemEntity> files;
  late Directory currentDir = Directory.current;
  FileSystemEntity? copiedEntity;
  bool isFileContextMenuShown = false;
  bool showHiddenFiles = false;
  bool isSidebarCollapsed = false;
  List<FileInfo> fileInfoList = [];
  late String tagsFilePath;
  String? selectedTag;
  Set<String> selectedPaths = {};
  Offset? dragStart;
  Offset? dragCurrent;
  PointerDeviceKind? _lastPointerDeviceKind;
  int _lastPointerButtons = 0;
  bool isListView = false;
  String sortBy = 'name'; // 'name', 'date', 'size'
  bool sortAscending = true;
  int? _lastSelectedIndex;
  final ScrollController _scrollController = ScrollController();
  String? previewImagePath;
  final FocusNode _mainFocusNode = FocusNode();
  late final TextEditingController _saveFileNameController = TextEditingController(
    text: initialSelectedPath != null
        ? p.basename(initialSelectedPath!)
        : (isSavePicker ? 'untitled' : ''),
  );
  S3Config s3config = S3Config.empty();
  List<TransferProgress> activeTransfers = [];

  Future<void> _confirmPickerSelection() async {
    String output;
    if (isSavePicker) {
      String targetDir = currentDir.path;
      if (selectedPaths.length == 1) {
        final single = selectedPaths.first;
        if (FileSystemEntity.isDirectorySync(single) && p.dirname(single) == currentDir.path) {
          targetDir = single;
        }
      }
      String fileName = _saveFileNameController.text.trim();
      if (fileName.isEmpty && initialSelectedPath != null) {
        fileName = p.basename(initialSelectedPath!);
      }
      if (fileName.isEmpty) {
        fileName = 'download';
      }
      output = p.join(targetDir, fileName);

      // Clean up xdg-desktop-portal-termfilechooser dummy help file if user chose a different location
      if (initialSelectedPath != null && initialSelectedPath != output) {
        try {
          final initFile = File(initialSelectedPath!);
          if (initFile.existsSync() && initFile.lengthSync() < 1024) {
            final head = initFile.readAsStringSync();
            if (head.contains('xdg-desktop-portal-termfilechooser')) {
              initFile.deleteSync();
            }
          }
        } catch (_) {}
      }
    } else if (isDirectoryPicker) {
      if (selectedPaths.length == 1 && FileSystemEntity.isDirectorySync(selectedPaths.first)) {
        output = selectedPaths.first;
      } else {
        output = currentDir.path;
      }
    } else {
      final validSelected = selectedPaths.where((s) => File(s).existsSync() || Directory(s).existsSync()).toList();
      output = validSelected.isNotEmpty ? validSelected.join('\n') : currentDir.path;
    }
    stdout.writeln(output);
    await stdout.flush();
    exit(0);
  }

  void _updateSelection() {
    if (dragStart == null || dragCurrent == null) return;
    
    Rect selectionRect = Rect.fromPoints(dragStart!, dragCurrent!);
    double sidebarWidth = isSidebarCollapsed ? 64.0 : 200.0;
    double availableWidth = MediaQuery.of(context).size.width - sidebarWidth;
    
    Set<String> newSelection = {};
    
    if (isListView) {
      for (int i = 0; i < files.length; i++) {
        double y = i * 50.0 - _scrollController.offset;
        Rect itemRect = Rect.fromLTWH(0, y, availableWidth, 50.0);
        if (selectionRect.overlaps(itemRect)) {
          newSelection.add(files[i].path);
        }
      }
    } else {
      double itemWidth = availableWidth / (availableWidth / 120).floor();
      int crossAxisCount = (availableWidth / 120).floor();
      
      for (int i = 0; i < files.length; i++) {
        int row = i ~/ crossAxisCount;
        int col = i % crossAxisCount;
        
        double x = col * itemWidth;
        double y = row * itemWidth - _scrollController.offset;
        
        Rect itemRect = Rect.fromLTWH(x, y, itemWidth, itemWidth);
        if (selectionRect.overlaps(itemRect)) {
          newSelection.add(files[i].path);
        }
      }
    }
    
    setState(() {
      selectedPaths = newSelection;
    });
  }

  void _sortFiles() {
    files.sort((a, b) {
      // Directories always come first
      bool isDirA = FileSystemEntity.isDirectorySync(a.path);
      bool isDirB = FileSystemEntity.isDirectorySync(b.path);
      if (isDirA != isDirB) return isDirA ? -1 : 1;

      int comparison;
      try {
        switch (sortBy) {
          case 'date':
            comparison = a.statSync().modified.compareTo(b.statSync().modified);
            break;
          case 'size':
            comparison = a.statSync().size.compareTo(b.statSync().size);
            break;
          case 'name':
          default:
            comparison = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
            break;
        }
      } catch (e) {
        comparison = 0;
      }
      return sortAscending ? comparison : -comparison;
    });
  }

  Stream<List<FileSystemEntity>> watchDirectory() async* {
    List<FileSystemEntity> previousFiles = [];
    bool isFirstRun = true;

    while (true) {
      final currentFiles = selectedTag == null
          ? currentDir.listSync()
          : fileInfoList
              .where((info) => info.tag == selectedTag)
              .map((info) => FileSystemEntity.isDirectorySync(info.filePath)
                  ? Directory(info.filePath)
                  : File(info.filePath))
              .toList();

      final filteredFiles = showHiddenFiles
          ? currentFiles
          : currentFiles
              .where((file) => !p.basename(file.path).startsWith('.'))
              .toList();

      if (isFirstRun || !listEquals(previousFiles, filteredFiles)) {
        yield filteredFiles;
        previousFiles = filteredFiles;
        isFirstRun = false;
      }

      await Future.delayed(const Duration(seconds: 1));
    }
  }

  bool isAndroid() {
    return Platform.isAndroid;
  }

  bool _isArchive(String path) {
    final extensions = ['.zip', '.7z', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.tbz2', '.txz'];
    return extensions.any((ext) => path.toLowerCase().endsWith(ext));
  }

  bool _isImageFile(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return false;
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif');
  }

  Future<void> _setAsWallpaper(String imagePath) async {
    try {
      await Process.run('swaymsg', ['output', '*', 'bg', imagePath, 'fill']);
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        final configFile = File('$home/.config/sway/config');
        if (await configFile.exists()) {
          final lines = await configFile.readAsLines();
          final newLines = lines.map((line) {
            if (line.startsWith('output * bg')) {
              return 'output * bg "$imagePath" fill';
            }
            return line;
          }).toList();
          if (!newLines.any((line) => line.startsWith('output * bg'))) {
            newLines.insert(0, 'output * bg "$imagePath" fill');
          }
          final tempFile = File('${configFile.path}.tmp');
          await tempFile.writeAsString('${newLines.join('\n')}\n');
          await tempFile.rename(configFile.path);
        }

        bool pullColorFromBg = true;
        final prefsFile = File(
          '$home/.local/share/fyrsettings/shared_preferences.json',
        );
        try {
          Map<String, dynamic> prefsMap = {};
          if (await prefsFile.exists()) {
            prefsMap = jsonDecode(await prefsFile.readAsString());
            if (prefsMap['flutter.pull_color_from_bg'] is bool) {
              pullColorFromBg = prefsMap['flutter.pull_color_from_bg'];
            }
          } else {
            await prefsFile.parent.create(recursive: true);
          }
          prefsMap['flutter.bg_path'] = imagePath;
          await prefsFile.writeAsString(jsonEncode(prefsMap));
        } catch (_) {}

        if (pullColorFromBg) {
          try {
            final colorScheme = await ColorScheme.fromImageProvider(
              provider: FileImage(File(imagePath)),
            );
            await FyrTheme.setAccentColor(colorScheme.primary);
          } catch (_) {}
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallpaper set to ${p.basename(imagePath)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set wallpaper: $e')),
        );
      }
    }
  }

  void _openAppearanceSettings() {
    final home = Platform.environment['HOME'] ?? '';
    final bin = (home.isNotEmpty && File('$home/.local/bin/fyrsettings').existsSync())
        ? '$home/.local/bin/fyrsettings'
        : 'fyrsettings';
    Process.start(bin, ['--appearance'], mode: ProcessStartMode.detached);
  }

  Future<void> _extractArchive(String path) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Extracting ${p.basename(path)}...')),
    );
    
    try {
      ProcessResult pr;
      if (path.toLowerCase().endsWith('.zip')) {
        pr = await Process.run('unzip', [path, '-d', currentDir.path]);
      } else if (path.toLowerCase().endsWith('.tar.gz') || path.toLowerCase().endsWith('.tgz')) {
        pr = await Process.run('tar', ['-xzf', path, '-C', currentDir.path]);
      } else if (path.toLowerCase().endsWith('.tar.xz') || path.toLowerCase().endsWith('.txz')) {
        pr = await Process.run('tar', ['-xJf', path, '-C', currentDir.path]);
      } else if (path.toLowerCase().endsWith('.tar')) {
        pr = await Process.run('tar', ['-xf', path, '-C', currentDir.path]);
      } else {
        pr = await Process.run('7z', ['x', path, '-o${currentDir.path}', '-y']);
      }

      if (!mounted) return;

      if (pr.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Extraction complete')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extraction failed: ${pr.stderr}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleCompress(List<String> paths) async {
    if (paths.isEmpty) return;

    String baseDefaultName = paths.length == 1 
        ? p.basename(paths[0]) 
        : p.basename(currentDir.path);
    
    TextEditingController nameController = TextEditingController(text: baseDefaultName);
    String selectedFormat = '.zip';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Compress Files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Archive Name'),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedFormat,
                items: ['.zip', '.7z', '.tar.gz', '.tar.xz'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedFormat = value;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'name': nameController.text,
                  'format': selectedFormat,
                });
              },
              child: const Text('Compress'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;

    String archiveName = result['name']!;
    String format = result['format']!;
    if (!archiveName.toLowerCase().endsWith(format.toLowerCase())) {
      archiveName += format;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Compressing to $archiveName...')),
    );

    final outputPath = p.join(currentDir.path, archiveName);
      
      try {
        ProcessResult pr;
        if (format == '.zip') {
          pr = await Process.run('zip', ['-r', outputPath, ...paths.map((e) => p.relative(e, from: currentDir.path))]);
        } else if (format == '.tar.gz') {
          pr = await Process.run('tar', ['-czf', outputPath, ...paths.map((e) => p.relative(e, from: currentDir.path))]);
        } else if (format == '.tar.xz') {
          pr = await Process.run('tar', ['-cJf', outputPath, ...paths.map((e) => p.relative(e, from: currentDir.path))]);
        } else {
          pr = await Process.run('7z', ['a', outputPath, ...paths]);
        }

        if (!mounted) return;

        if (pr.exitCode == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compression complete')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compression failed: ${pr.stderr}')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
  }

  Future<Directory> getHomeDirectoryByPlatform() async {
    if (isAndroid()) {
      final directory = await getApplicationDocumentsDirectory();
      return directory;
    } else {
      return Directory(Platform.environment['HOME'] ?? '/home/');
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _mainFocusNode.dispose();
    _saveFileNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);

    getHomeDirectoryByPlatform().then((Directory dir) async {
      final homePath = dir.path;
      final targetDir = (initialDirectoryPath != null && Directory(initialDirectoryPath!).existsSync())
          ? Directory(initialDirectoryPath!)
          : dir;
      setState(() {
        currentDir = targetDir;
        tagsFilePath = p.join(homePath, '.fyr/files/tags.json');
        if (initialSelectedPath != null) {
          selectedPaths.add(initialSelectedPath!);
        }
      });

      String customTagsPath = p.join(homePath, '.fyr/files/tags_config.json');
      String pinsPath = p.join(homePath, '.fyr/files/pins.json');
      
      if (File(customTagsPath).existsSync()) {
        try {
          customTags = List<Map<String, dynamic>>.from(jsonDecode(File(customTagsPath).readAsStringSync()));
        } catch(e) {}
      }
      
      if (File(pinsPath).existsSync()) {
        try {
          customPins = List<String>.from(jsonDecode(File(pinsPath).readAsStringSync()));
        } catch(e) {}
      }

      try {
        await checkAndCreateFile();
        final loadedFileInfo = await readTagsFromFile(tagsFilePath);
        final loadedS3Config = await S3Service.loadConfig();
        setState(() {
          fileInfoList = loadedFileInfo;
          s3config = loadedS3Config;
          files = currentDir.listSync();
          if (initialSelectedPath != null && files.any((f) => f.path == initialSelectedPath)) {
            _lastSelectedIndex = files.indexWhere((f) => f.path == initialSelectedPath);
          }
        });
        if (s3config.enabled) {
          try {
            await S3Service.mount(s3config);
          } catch (e) {
            stderr.writeln("Failed to mount S3 on startup: $e");
          }
        }
      } catch (err) {
        stderr.writeln(err);
        setState(() {
          fileInfoList = [];
          files = currentDir.listSync();
        });
      }
    });
  }

  String displayText(
      Directory dir, Directory currentDir, bool isColorFiltered) {
    if (isColorFiltered) {
      return '';
    }

    if (dir.path == '/' && dir != currentDir) {
      return 'root > ';
    } else if (dir.path == '/' && dir == currentDir) {
      return 'root';
    } else if (dir != currentDir) {
      return '${dir.path.split('/').last} > ';
    } else {
      return dir.path.split('/').last;
    }
  }

  double getToolbarPadding() {
    if (Platform.isAndroid) {
      return 42.0;
    } else if (Platform.isLinux) {
      return 0.0;
    } else {
      return 0.0;
    }
  }

  String formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return "${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}";
  }

  Map<String, dynamic> fileStatToMap(FileStat fileStat, String filePath) {
    return {
      'filename': filePath.split('/').last,
      'mode': fileStat.mode.toString(),
      'modified': fileStat.modified.toString(),
      'accessed': fileStat.accessed.toString(),
      'changed': fileStat.changed.toString(),
      'size': formatBytes(fileStat.size, 2),
      'type': fileStat.type.toString(),
    };
  }

  Map<String, dynamic> dirStatToMap(FileStat dirStat, String dirPath) {
    return {
      'directory': dirPath,
      'mode': dirStat.mode.toString(),
      'modified': dirStat.modified.toString(),
      'accessed': dirStat.accessed.toString(),
      'changed': dirStat.changed.toString(),
      'type': dirStat.type.toString(),
    };
  }

  Future<void> checkAndCreateFile() async {
    try {
      final file = File(tagsFilePath);
      await file.parent.create(recursive: true);

      if (await file.exists()) {
        stderr.writeln("File exists.");
      } else {
        stderr.writeln("File does not exist. Creating file.");

        List<dynamic> initialData = [];

        await file.writeAsString(jsonEncode(initialData));
      }
    } catch (e) {
      stderr.writeln("An error occurred: $e");
    }
  }

  void openDirectory(Directory directory) {
    setState(() {
      selectedTag = null;
      currentDir = directory;
      files = directory.listSync().where((file) {
        String fileName = p.basename(file.path);
        return showHiddenFiles || !fileName.startsWith('.');
      }).toList();
      _sortFiles();
      selectedPaths.clear();
      _lastSelectedIndex = null;
    });
  }

  bool hasChildDirectories(Directory directory) {
    var entities = directory.listSync(followLinks: false);
    return entities.any((entity) => entity is Directory);
  }

  Future<void> createFile(Directory directory, String fileName) async {
    final newFile = File('${directory.path}/$fileName');
    await newFile.create();
  }

  Future<void> createDir(Directory directory, String newDirName) async {
    final newDir = Directory('${directory.path}/$newDirName');
    await newDir.create();
  }

  List<Directory> getParentDirectories(Directory currDir) {
    List<Directory> parents = [];
    Directory? dir = currDir;
    while (dir?.path != dir?.parent.path) {
      if (dir != null) {
        parents.add(dir);
      }
      dir = dir?.parent;
    }
    if (dir != null && dir.path == dir.parent.path) {
      parents.add(dir);
    }
    return parents.reversed.toList();
  }

  List<String> _extractPathsFromClipboard(String? text) {
    if (text == null || text.trim().isEmpty) return [];
    List<String> results = [];
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Handle file:// URIs (e.g. from nautilus, dolphin, browsers)
      if (line.startsWith('file://')) {
        try {
          line = Uri.parse(line).toFilePath();
        } catch (_) {
          line = line.replaceFirst(RegExp(r'^file://+'), '/');
        }
      }

      // Strip wrapping quotes
      if ((line.startsWith('"') && line.endsWith('"')) || (line.startsWith("'") && line.endsWith("'"))) {
        line = line.substring(1, line.length - 1);
      }

      line = line.trim();
      if (line.isNotEmpty) {
        results.add(line);
      }
    }
    return results;
  }

  Future<bool> isClipboardDataAvailable() async {
    try {
      ClipboardData? clipboardData = await Clipboard.getData('text/plain');
      final paths = _extractPathsFromClipboard(clipboardData?.text);
      if (paths.isEmpty) return false;

      for (final p in paths) {
        try {
          if (FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return false;
  }

  Widget _buildDragFeedback(List<String> paths) {
    final count = paths.length;
    final first = paths.first;
    final isDir = Directory(first).existsSync();
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FyrTheme.accentColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              count > 1 ? Icons.copy_all : (isDir ? Icons.folder : Icons.insert_drive_file),
              color: FyrTheme.accentColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                count > 1 ? '$count items' : p.basename(first),
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveItemsToDirectory(List<String> sourcePaths, String destinationDirPath) async {
    if (sourcePaths.isEmpty || destinationDirPath.isEmpty) return;

    final destDir = Directory(destinationDirPath);
    if (!destDir.existsSync()) {
      try {
        destDir.createSync(recursive: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot create destination directory: $e'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
    }

    final isTrash = destinationDirPath.contains('Trash/files');
    int movedCount = 0;
    List<String> failed = [];

    for (final src in sourcePaths) {
      if (!File(src).existsSync() && !Directory(src).existsSync()) continue;

      // Skip moving into parent if already there
      if (p.dirname(src) == destinationDirPath) continue;

      // Don't move directory into itself or child
      if (src == destinationDirPath || destinationDirPath.startsWith('$src/')) continue;

      if (isTrash) {
        try {
          final res = Process.runSync('gio', ['trash', src]);
          if (res.exitCode == 0) {
            movedCount++;
            continue;
          }
        } catch (_) {}
      }

      final fileName = p.basename(src);
      String targetPath = p.join(destinationDirPath, fileName);

      // Handle collision
      if (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
        final ext = p.extension(fileName);
        final base = p.basenameWithoutExtension(fileName);
        int counter = 1;
        while (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
          targetPath = p.join(destinationDirPath, '$base ($counter)$ext');
          counter++;
        }
      }

      try {
        if (FileSystemEntity.isDirectorySync(src)) {
          try {
            Directory(src).renameSync(targetPath);
          } catch (_) {
            final transferId = DateTime.now().millisecondsSinceEpoch.toString();
            await _copyDirectoryWithProgress(Directory(src), targetPath, transferId);
            Directory(src).deleteSync(recursive: true);
          }
        } else {
          try {
            File(src).renameSync(targetPath);
          } catch (_) {
            File(src).copySync(targetPath);
            File(src).deleteSync();
          }
        }

        // Update tag if any
        final tagIndex = fileInfoList.indexWhere((info) => info.filePath == src);
        if (tagIndex != -1) {
          fileInfoList[tagIndex].filePath = targetPath;
          await writeTagsToFile(fileInfoList, tagsFilePath);
        }

        movedCount++;
      } catch (e) {
        failed.add(fileName);
      }
    }

    if (mounted) {
      setState(() {
        selectedPaths.removeWhere((p) => sourcePaths.contains(p));
      });
      openDirectory(currentDir);

      if (failed.isEmpty && movedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isTrash
                ? 'Moved $movedCount item(s) to Trash'
                : 'Moved $movedCount item(s) to ${p.basename(destinationDirPath)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (failed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move ${failed.join(", ")}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String formatPath(String path) {
    List<String> segments = path.split('/');
    return segments.where((seg) => seg.isNotEmpty).join(' > ');
  }

  Future<void> _copyFileWithProgress(File source, String targetPath, String transferId) async {
    final totalSize = await source.length();
    int copiedSize = 0;
    
    final IOSink sink = File(targetPath).openWrite();
    final Stream<List<int>> stream = source.openRead();
    
    await for (final List<int> chunk in stream) {
      sink.add(chunk);
      copiedSize += chunk.length;
      setState(() {
        final transfer = activeTransfers.firstWhere((t) => t.id == transferId);
        transfer.progress = copiedSize / totalSize;
      });
    }
    
    await sink.close();
  }

  Future<void> _copyToS3WithProgress(String sourcePath, String targetPath, String transferId) async {
    // If it's a directory, we need the parent path for rclone copy
    bool isDir = FileSystemEntity.isDirectorySync(sourcePath);
    String rcloneCommand = isDir ? 'copy' : 'copyto';
    
    // For rclone, we need the path relative to the bucket
    // If targetPath is /home/archie/.fyr/mounts/s3/folder/file.txt
    // and mountPath is /home/archie/.fyr/mounts/s3
    // s3Path should be folder/file.txt
    String s3Path = S3Service.getRelativePath(targetPath);

    final process = await Process.start('rclone', [
      rcloneCommand,
      sourcePath,
      '${s3config.remoteName}:${s3config.bucket}/$s3Path',
      '--progress',
      '--stats', '1s',
      '--stats-one-line',
    ]);

    String lastStderr = '';

    void parseProgress(String data) {
      // Handle both \n and \r as line delimiters
      final lines = data.split(RegExp(r'[\n\r]'));
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        // Regex to find percentage: looks for a number followed by %
        // Works for " 50%", "[50%]", "Transferred: 50%" etc.
        final match = RegExp(r'(\d+)%').firstMatch(line);
        if (match != null) {
          final progress = int.parse(match.group(1)!) / 100.0;
          if (mounted) {
            setState(() {
              final transferIndex = activeTransfers.indexWhere((t) => t.id == transferId);
              if (transferIndex != -1) {
                // Ensure progress only moves forward or stays at 100%
                if (progress > activeTransfers[transferIndex].progress) {
                  activeTransfers[transferIndex].progress = progress;
                }
              }
            });
          }
        }
      }
    }

    process.stdout.transform(utf8.decoder).listen(parseProgress);
    process.stderr.transform(utf8.decoder).listen((data) {
      lastStderr += data;
      parseProgress(data);
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('Rclone failed ($exitCode): ${lastStderr.split('\n').last}');
    }
  }

  Future<void> _copyDirectoryWithProgress(Directory source, String targetPath, String transferId) async {
    final entities = source.listSync(recursive: true);
    final totalEntities = entities.length;
    int processedEntities = 0;

    await Directory(targetPath).create(recursive: true);

    for (final entity in entities) {
      final relativePath = p.relative(entity.path, from: source.path);
      final newPath = p.join(targetPath, relativePath);

      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await Directory(newPath).create(recursive: true);
      }
      
      processedEntities++;
      setState(() {
        final transfer = activeTransfers.firstWhere((t) => t.id == transferId);
        transfer.progress = processedEntities / totalEntities;
      });
    }
  }

  Future<void> pasteFile(Directory targetDir) async {
    try {
      ClipboardData? data = await Clipboard.getData('text/plain');
      final paths = _extractPathsFromClipboard(data?.text);
      if (paths.isEmpty) return;
      
      for (String path in paths) {
        if (!File(path).existsSync() && !Directory(path).existsSync()) continue;
        
        final transferId = DateTime.now().millisecondsSinceEpoch.toString() + path;
        final fileName = p.basename(path);
        
        setState(() {
          activeTransfers.add(TransferProgress(
            id: transferId,
            label: 'Copying $fileName',
          ));
        });

        try {
          final isS3 = path.startsWith(S3Service.mountPath) || targetDir.path.startsWith(S3Service.mountPath);
          String targetPath = p.join(targetDir.path, fileName);

          // Handle collision when copying into same folder
          if (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
            final ext = p.extension(fileName);
            final base = p.basenameWithoutExtension(fileName);
            int counter = 1;
            while (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
              targetPath = p.join(targetDir.path, '$base (copy $counter)$ext');
              counter++;
            }
          }

          if (isS3) {
            await _copyToS3WithProgress(path, targetPath, transferId);
          } else {
            if (FileSystemEntity.isFileSync(path)) {
              await _copyFileWithProgress(File(path), targetPath, transferId);
            } else if (FileSystemEntity.isDirectorySync(path)) {
              await _copyDirectoryWithProgress(Directory(path), targetPath, transferId);
            }
          }
          
          setState(() {
            final idx = activeTransfers.indexWhere((t) => t.id == transferId);
            if (idx != -1) activeTransfers[idx].isCompleted = true;
          });
          
          // Remove from list after a short delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                activeTransfers.removeWhere((t) => t.id == transferId);
              });
            }
          });
        } catch (e) {
          if (mounted) {
            setState(() {
              final idx = activeTransfers.indexWhere((t) => t.id == transferId);
              if (idx != -1) {
                activeTransfers[idx].isError = true;
                activeTransfers[idx].errorMessage = e.toString();
              }
            });
          }
        }
      }
      openDirectory(targetDir);
    } catch (err) {
      stderr.writeln(err);
    }
  }

  Future<void> writeTagsToFile(
      List<FileInfo> fileInfos, String filePath) async {
    final json = jsonEncode(fileInfos.map((e) => e.toJson()).toList());
    final file = File(filePath);
    await file.writeAsString(json);
  }

  Future<List<FileInfo>> readTagsFromFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      final json = await file.readAsString();
      if (json.trim() == '{}') {
        return [];
      }
      final list = jsonDecode(json) as List;
      return list
          .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  void showPropertiesDialog(
      BuildContext context, Map<String, dynamic> properties) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("File Properties"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: properties.entries.map((entry) {
                return Text('${entry.key}: ${entry.value}');
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebarItem(IconData icon, String label, VoidCallback onTap, {VoidCallback? onUnpin, String? targetPath}) {
    Widget item;
    if (isSidebarCollapsed) {
      item = Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Icon(icon, size: 24, color: FyrTheme.accentColor),
          ),
        ),
      );
    } else {
      item = ListTile(
        leading: Icon(icon, size: 20, color: FyrTheme.accentColor),
        title: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
        dense: true,
        onTap: onTap,
        trailing: onUnpin != null ? IconButton(
          icon: const Icon(Icons.close, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: onUnpin,
        ) : null,
      );
    }

    if (targetPath != null) {
      return DragTarget<List<String>>(
        onWillAcceptWithDetails: (details) {
          final dropped = details.data;
          if (dropped.contains(targetPath)) return false;
          for (final p in dropped) {
            if (targetPath.startsWith(p)) return false;
          }
          return true;
        },
        onAcceptWithDetails: (details) async {
          await _moveItemsToDirectory(details.data, targetPath);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: isHovered ? FyrTheme.accentColor.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isHovered ? Border.all(color: FyrTheme.accentColor, width: 1.5) : null,
            ),
            child: item,
          );
        },
      );
    }

    return item;
  }

  void _showSettingsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: FyrTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: TabBar(
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: "Tags"),
                Tab(text: "S3 Storage"),
              ],
              labelColor: FyrTheme.accentColor,
              unselectedLabelColor: FyrTheme.textColorMuted,
              indicatorColor: FyrTheme.accentColor,
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: TabBarView(
                children: [
                  _buildTagsSettingsTab(context),
                  _buildS3SettingsTab(context),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildTagsSettingsTab(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setStateModal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: customTags.length,
                itemBuilder: (context, index) {
                  var tag = customTags[index];
                  return ListTile(
                    leading: getDotColor(Color(tag['colorValue'])),
                    title: Text(tag['name'], style: TextStyle(color: FyrTheme.textColor)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.red.shade300),
                      onPressed: () {
                        setStateModal(() {
                          customTags.removeAt(index);
                        });
                        setState(() {});
                        saveCustomTags();
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
              onPressed: () {
                TextEditingController nameController = TextEditingController();
                Color selectedColor = Colors.red;
                showDialog(
                  context: context,
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, setStateAdd) {
                        return AlertDialog(
                          backgroundColor: FyrTheme.surfaceColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Add Tag'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: nameController,
                                style: TextStyle(color: FyrTheme.textColor),
                                decoration: const InputDecoration(labelText: 'Tag Name'),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                                  Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                                  Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                                  Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                                  Colors.brown, Colors.grey, Colors.blueGrey,
                                ].map((color) => GestureDetector(
                                  onTap: () {
                                    setStateAdd(() {
                                      selectedColor = color;
                                    });
                                  },
                                  child: Container(
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selectedColor == color ? Colors.white : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                )).toList(),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (nameController.text.isNotEmpty) {
                                  setStateModal(() {
                                    customTags.add({
                                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                      'name': nameController.text,
                                      'colorValue': selectedColor.value,
                                    });
                                  });
                                  setState(() {});
                                  saveCustomTags();
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text('Add'),
                            ),
                          ],
                        );
                      }
                    );
                  }
                );
              },
              child: const Text("Add New Tag"),
            )
          ],
        );
      }
    );
  }

  Widget _buildS3SettingsTab(BuildContext context) {
    TextEditingController endpointController = TextEditingController(text: s3config.endpoint);
    TextEditingController accessKeyController = TextEditingController(text: s3config.accessKey);
    TextEditingController secretKeyController = TextEditingController(text: s3config.secretKey);
    TextEditingController regionController = TextEditingController(text: s3config.region);
    TextEditingController bucketController = TextEditingController(text: s3config.bucket);
    bool enabled = s3config.enabled;

    return StatefulBuilder(
      builder: (context, setStateS3) {
        return SingleChildScrollView(
          child: Column(
            children: [
              SwitchListTile(
                title: Text("Enable S3 Sync", style: TextStyle(color: FyrTheme.textColor)),
                value: enabled,
                onChanged: (val) {
                  setStateS3(() {
                    enabled = val;
                  });
                },
                activeColor: FyrTheme.accentColor,
              ),
              TextField(
                controller: endpointController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: const InputDecoration(labelText: 'Endpoint (e.g. s3.amazonaws.com)'),
              ),
              TextField(
                controller: accessKeyController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: const InputDecoration(labelText: 'Access Key ID'),
              ),
              TextField(
                controller: secretKeyController,
                style: TextStyle(color: FyrTheme.textColor),
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Secret Access Key'),
              ),
              TextField(
                controller: regionController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: const InputDecoration(labelText: 'Region'),
              ),
              TextField(
                controller: bucketController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: const InputDecoration(labelText: 'Bucket Name'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
                onPressed: () async {
                  S3Config newConfig = S3Config(
                    remoteName: 's3',
                    endpoint: endpointController.text,
                    accessKey: accessKeyController.text,
                    secretKey: secretKeyController.text,
                    region: regionController.text,
                    bucket: bucketController.text,
                    enabled: enabled,
                  );
                  
                  try {
                    await S3Service.saveConfig(newConfig);
                    if (newConfig.enabled) {
                      await S3Service.updateRcloneConfig(newConfig);
                      await S3Service.mount(newConfig);
                    } else {
                      await S3Service.unmount();
                    }
                    setState(() {
                      s3config = newConfig;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("S3 Settings Saved and Applied")),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                },
                child: const Text("Save and Apply"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileItem(FileSystemEntity file, int index, bool isList) {
    var isDir = FileSystemEntity.isDirectorySync(file.path);
    FileInfo? currentFileInfo = fileInfoList.firstWhere(
      (info) => info.filePath == file.path,
      orElse: () => FileInfo(filePath: file.path),
    );
    bool isSelected = selectedPaths.contains(file.path);

    Widget content;
    if (isList) {
      content = Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: isSelected ? FyrTheme.accentColor.withOpacity(0.3) : Colors.transparent,
        child: Row(
          children: [
            (!isDir && (file.path.toLowerCase().endsWith('.png') || file.path.toLowerCase().endsWith('.jpg') || file.path.toLowerCase().endsWith('.jpeg') || file.path.toLowerCase().endsWith('.gif') || file.path.toLowerCase().endsWith('.webp')))
                ? Image.file(File(file.path), width: 32, height: 32, fit: BoxFit.cover)
                : Icon(isDir ? Icons.folder : Icons.file_copy, size: 32, color: FyrTheme.accentColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                p.basename(file.path),
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (currentFileInfo.tag != null)
              getDotByTag(currentFileInfo.tag!),
          ],
        ),
      );
    } else {
      content = Container(
        color: isSelected ? FyrTheme.accentColor.withOpacity(0.3) : Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                (!isDir && (file.path.toLowerCase().endsWith('.png') || file.path.toLowerCase().endsWith('.jpg') || file.path.toLowerCase().endsWith('.jpeg') || file.path.toLowerCase().endsWith('.gif') || file.path.toLowerCase().endsWith('.webp')))
                    ? Image.file(File(file.path), width: 48, height: 48, fit: BoxFit.cover)
                    : Icon(isDir ? Icons.folder : Icons.file_copy, size: 48, color: FyrTheme.accentColor),
                Text(
                  p.basename(file.path),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            if (currentFileInfo.tag != null)
              Positioned(top: 24, left: 24, child: getDotByTag(currentFileInfo.tag!)),
          ],
        ),
      );
    }

    final dragPayload = isSelected && selectedPaths.contains(file.path)
        ? selectedPaths.toList()
        : [file.path];

    Widget itemWidget = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (TapGestureRecognizer instance) {
            instance.onTap = () {
              bool isControlPressed = HardwareKeyboard.instance.isControlPressed;
              bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
              setState(() {
                if (isControlPressed) {
                  if (selectedPaths.contains(file.path)) {
                    selectedPaths.remove(file.path);
                  } else {
                    selectedPaths.add(file.path);
                    _lastSelectedIndex = index;
                  }
                } else if (isShiftPressed && _lastSelectedIndex != null) {
                  int start = min(_lastSelectedIndex!, index);
                  int end = max(_lastSelectedIndex!, index);
                  for (int i = start; i <= end; i++) {
                    selectedPaths.add(files[i].path);
                  }
                } else {
                  selectedPaths.clear();
                  selectedPaths.add(file.path);
                  _lastSelectedIndex = index;
                  if (isSavePicker && !isDir) {
                    _saveFileNameController.text = p.basename(file.path);
                  }
                }
              });
            };
          },
        ),
        DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
          () => DoubleTapGestureRecognizer(),
          (DoubleTapGestureRecognizer instance) {
            instance.onDoubleTap = () async {
              if (isDir) {
                openDirectory(file as Directory);
              } else {
                var filePath = file.path;
                if (isPicker) {
                  if (isSavePicker) {
                    _saveFileNameController.text = p.basename(filePath);
                    selectedPaths
                      ..clear()
                      ..add(filePath);
                    await _confirmPickerSelection();
                  } else {
                    stdout.writeln(filePath);
                    await stdout.flush();
                    exit(0);
                  }
                }
                await _openFileOrLaunch(filePath);
              }
            };
          },
        ),
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(),
          (LongPressGestureRecognizer instance) {
            instance.onLongPressStart = (details) {
              isFileContextMenuShown = true;
              openIconContextMenu(context, details, file).then((value) => isFileContextMenuShown = false);
            };
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) {
          if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
            isFileContextMenuShown = true;
            openIconContextMenuRightClick(context, event, file).then((value) => isFileContextMenuShown = false);
          }
        },
        child: content,
      ),
    );

    Widget draggableItem = Draggable<List<String>>(
      data: dragPayload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        if (!selectedPaths.contains(file.path)) {
          setState(() {
            selectedPaths.clear();
            selectedPaths.add(file.path);
            _lastSelectedIndex = index;
          });
        }
      },
      feedback: _buildDragFeedback(dragPayload),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: itemWidget,
      ),
      child: itemWidget,
    );

    if (isDir) {
      return DragTarget<List<String>>(
        onWillAcceptWithDetails: (details) {
          final dropped = details.data;
          if (dropped.contains(file.path)) return false;
          for (final p in dropped) {
            if (file.path.startsWith(p)) return false;
          }
          return true;
        },
        onAcceptWithDetails: (details) async {
          await _moveItemsToDirectory(details.data, file.path);
        },
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: FyrTheme.accentColor, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: FyrTheme.accentColor.withOpacity(0.18),
              ),
              child: draggableItem,
            );
          }
          return draggableItem;
        },
      );
    }

    return draggableItem;
  }

  @override
  void onWindowClose() async {
    bool hasActiveTransfers = activeTransfers.any((t) => !t.isCompleted && !t.isError);
    if (hasActiveTransfers) {
      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text('Active Transfers', style: TextStyle(color: FyrTheme.textColor)),
          content: Text(
            'There are active file transfers in progress. Are you sure you want to exit?',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400, foregroundColor: Colors.white),
              child: const Text('Exit'),
            ),
          ],
        ),
      ) ?? false;
      if (confirm) {
        exit(isPicker ? 1 : 0);
      }
    } else {
      exit(isPicker ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    Stream<List<FileSystemEntity>> fileStream = watchDirectory();

    return RawKeyboardListener(
      focusNode: _mainFocusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) {
          // If a text field is focused, don't trigger global shortcuts
          if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
              event.logicalKey == LogicalKeyboardKey.controlRight) {
          } else if (event.logicalKey == LogicalKeyboardKey.keyA && event.isControlPressed) {
            setState(() {
              selectedPaths = files.map((e) => e.path).toSet();
            });
          } else if (event.logicalKey == LogicalKeyboardKey.keyH &&
              event.isControlPressed) {
            setState(() {
              showHiddenFiles = !showHiddenFiles;
              if (selectedTag == null) {
                openDirectory(currentDir);
              }
            });
          } else if (event.logicalKey == LogicalKeyboardKey.space) {
            if (previewImagePath != null) {
              setState(() {
                previewImagePath = null;
              });
            } else if (selectedPaths.length == 1) {
              String path = selectedPaths.first;
              String lower = path.toLowerCase();
              if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
                setState(() {
                  previewImagePath = path;
                });
              }
            }
          } else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
            if (selectedPaths.isNotEmpty) {
              for (String path in selectedPaths.toList()) {
                try {
                  var result = Process.runSync('gio', ['trash', path]);
                  if (result.exitCode != 0) {
                    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                        ? Directory(path).deleteSync(recursive: true)
                        : File(path).deleteSync();
                  }
                } catch (e) {
                  FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                      ? Directory(path).deleteSync(recursive: true)
                      : File(path).deleteSync();
                }
              }
              setState(() {
                selectedPaths.clear();
              });
            }
          } else if (event.logicalKey == LogicalKeyboardKey.keyC && event.isControlPressed) {
            if (selectedPaths.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: selectedPaths.join('\n')));
            }
          } else if (event.logicalKey == LogicalKeyboardKey.keyV && event.isControlPressed) {
            pasteFile(currentDir);
          }
        }
      },
      child: ResizableWindow(
        child: Scaffold(
          backgroundColor: FyrTheme.bgColor,
          appBar: null,
          body: Stack(
            children: [
              Column(
                children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) {
                    windowManager.startDragging();
                  },
                  onDoubleTap: _toggleMaximize,
                  child: Container(
                    height: 55 + getToolbarPadding(),
                    padding: EdgeInsets.only(top: getToolbarPadding(), left: 16, right: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => windowManager.close(),
                          child: Icon(Icons.circle, color: Colors.red.shade300, size: 16),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            Process.run('swaymsg', ['[pid="$pid"] move scratchpad']);
                          },
                          child: Icon(Icons.circle, color: Colors.amber.shade300, size: 16),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _toggleMaximize,
                          child: Icon(Icons.circle, color: Colors.green.shade300, size: 16),
                        ),
                        const SizedBox(width: 24),
                        if (currentDir.path != currentDir.parent.path)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              if (selectedTag != null) {
                                setState(() {
                                  selectedTag = null;
                                });
                              } else {
                                openDirectory(currentDir.parent);
                              }
                            },
                            iconSize: 24.0,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        if (currentDir.path != currentDir.parent.path)
                          const SizedBox(width: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: getParentDirectories(currentDir).map((dir) {
                                final isCurrent = dir.path == currentDir.path;
                                final text = displayText(dir, currentDir, selectedTag != null);
                                if (text.isEmpty) return const SizedBox();

                                Widget crumb = InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () {
                                    selectedTag = null;
                                    openDirectory(dir);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        color: isCurrent ? FyrTheme.accentColor : FyrTheme.textColor,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                );

                                if (!isCurrent) {
                                  return DragTarget<List<String>>(
                                    onWillAcceptWithDetails: (details) {
                                      final dropped = details.data;
                                      if (dropped.contains(dir.path)) return false;
                                      for (final p in dropped) {
                                        if (dir.path.startsWith(p)) return false;
                                      }
                                      return true;
                                    },
                                    onAcceptWithDetails: (details) async {
                                      await _moveItemsToDirectory(details.data, dir.path);
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      final isHovered = candidateData.isNotEmpty;
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: isHovered ? FyrTheme.accentColor.withOpacity(0.25) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(4),
                                          border: isHovered ? Border.all(color: FyrTheme.accentColor, width: 1.5) : null,
                                        ),
                                        child: crumb,
                                      );
                                    },
                                  );
                                }
                                return crumb;
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.search, size: 20),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Search'),
                                content: const TextField(
                                  decoration: InputDecoration(hintText: "Search files..."),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        const Text('Filter:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Theme(
                          data: Theme.of(context).copyWith(
                            focusColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            splashColor: Colors.transparent,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: FyrTheme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                                value: selectedTag,
                                icon: const Icon(Icons.arrow_drop_down, size: 20),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('All Files'),
                                  ),
                                  ...customTags.map((tag) => DropdownMenuItem(
                                        value: tag['id'],
                                        child: Row(children: [getDotColor(Color(tag['colorValue'])), const SizedBox(width: 8), Text(tag['name'])]),
                                      ))
                                ],
                                onChanged: (String? newValue) {
                                  setState(() {
                                    selectedTag = newValue;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.settings, size: 20),
                          onPressed: () {
                            _showSettingsModal(context);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(isListView ? Icons.grid_view : Icons.list, size: 20),
                          onPressed: () {
                            setState(() {
                              isListView = !isListView;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.sort, size: 20),
                          onSelected: (String value) {
                            setState(() {
                              if (sortBy == value) {
                                sortAscending = !sortAscending;
                              } else {
                                sortBy = value;
                                sortAscending = true;
                              }
                              _sortFiles();
                            });
                          },
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(value: 'name', child: Text('Sort by Name')),
                            const PopupMenuItem<String>(value: 'date', child: Text('Sort by Date')),
                            const PopupMenuItem<String>(value: 'size', child: Text('Sort by Size')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: isSidebarCollapsed ? 64 : 200,
                        color: FyrTheme.sidebarColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
                              child: IconButton(
                                icon: Icon(isSidebarCollapsed ? Icons.menu : Icons.menu_open, color: FyrTheme.accentColor),
                                onPressed: () {
                                  setState(() {
                                    isSidebarCollapsed = !isSidebarCollapsed;
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final userHome = Platform.environment['HOME'] ?? '/home/archer';
                                  return ListView(
                                    padding: EdgeInsets.zero,
                                    children: [
                                      _buildSidebarItem(Icons.home, 'Home', () => getHomeDirectoryByPlatform().then((d) => openDirectory(d)), targetPath: userHome),
                                      _buildSidebarItem(Icons.desktop_mac, 'Desktop', () => getHomeDirectoryByPlatform().then((d) => openDirectory(Directory(p.join(d.path, 'Desktop')))), targetPath: p.join(userHome, 'Desktop')),
                                      _buildSidebarItem(Icons.library_music, 'Music', () => getHomeDirectoryByPlatform().then((d) => openDirectory(Directory(p.join(d.path, 'Music')))), targetPath: p.join(userHome, 'Music')),
                                      _buildSidebarItem(Icons.photo_library, 'Pictures', () => getHomeDirectoryByPlatform().then((d) => openDirectory(Directory(p.join(d.path, 'Pictures')))), targetPath: p.join(userHome, 'Pictures')),
                                      _buildSidebarItem(Icons.file_download, 'Downloads', () => getHomeDirectoryByPlatform().then((d) => openDirectory(Directory(p.join(d.path, 'Downloads')))), targetPath: p.join(userHome, 'Downloads')),
                                      _buildSidebarItem(Icons.delete, 'Trash', () => getHomeDirectoryByPlatform().then((d) => openDirectory(Directory(p.join(d.path, '.local/share/Trash/files')))), targetPath: p.join(userHome, '.local/share/Trash/files')),
                                      _buildSidebarItem(Icons.computer, 'My Computer', () => openDirectory(Directory('/')), targetPath: '/'),
                                      if (s3config.enabled)
                                        _buildSidebarItem(Icons.cloud, 'S3 Storage', () => openDirectory(Directory(S3Service.mountPath)), targetPath: S3Service.mountPath),
                                      const SizedBox(height: 8),
                                      if (!isSidebarCollapsed)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                          child: Text("Custom Pins", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ...customPins.map((pin) => _buildSidebarItem(Icons.folder, p.basename(pin), () => openDirectory(Directory(pin)), targetPath: pin, onUnpin: () {
                                        setState(() {
                                          customPins.remove(pin);
                                        });
                                        saveCustomPins();
                                      })),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<List<FileSystemEntity>>(
                          stream: fileStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              files = snapshot.data as List<FileSystemEntity>;
    double sidebarWidth = isSidebarCollapsed ? 64.0 : 200.0;
    return DropTarget(
      onDragDone: (details) async {
        for (var file in details.files) {
          final sourcePath = file.path;
          final fileName = p.basename(sourcePath);
          final targetPath = p.join(currentDir.path, fileName);
          
          final transferId = DateTime.now().millisecondsSinceEpoch.toString() + sourcePath;
          
          setState(() {
            activeTransfers.add(TransferProgress(
              id: transferId,
              label: 'Uploading $fileName',
            ));
          });

          try {
            final isS3 = sourcePath.startsWith(S3Service.mountPath) || targetPath.startsWith(S3Service.mountPath);

            if (isS3) {
              await _copyToS3WithProgress(sourcePath, targetPath, transferId);
            } else {
              if (FileSystemEntity.isFileSync(sourcePath)) {
                await _copyFileWithProgress(File(sourcePath), targetPath, transferId);
              } else if (FileSystemEntity.isDirectorySync(sourcePath)) {
                await _copyDirectoryWithProgress(Directory(sourcePath), targetPath, transferId);
              }
            }
            
            setState(() {
              activeTransfers.firstWhere((t) => t.id == transferId).isCompleted = true;
            });
            
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  activeTransfers.removeWhere((t) => t.id == transferId);
                });
              }
            });
          } catch (e) {
            setState(() {
              final t = activeTransfers.firstWhere((t) => t.id == transferId);
              t.isError = true;
              t.errorMessage = e.toString();
            });
          }
        }
        setState(() {});
      },
      child: Listener(
        onPointerDown: (event) {
          _lastPointerDeviceKind = event.kind;
          _lastPointerButtons = event.buttons;
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            MousePanGestureRecognizer: GestureRecognizerFactoryWithHandlers<MousePanGestureRecognizer>(
              () => MousePanGestureRecognizer(allowedButtonsFilter: (int buttons) => buttons == kPrimaryButton),
              (MousePanGestureRecognizer instance) {
                instance
                  ..onStart = (details) {
                    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed) return;
                    setState(() {
                      dragStart = details.localPosition;
                      dragCurrent = details.localPosition;
                      selectedPaths.clear();
                      _lastSelectedIndex = null;
                    });
                  }
                  ..onUpdate = (details) {
                    setState(() {
                      dragCurrent = details.localPosition;
                    });
                    _updateSelection();
                  }
                  ..onEnd = (details) {
                    setState(() {
                      dragStart = null;
                      dragCurrent = null;
                    });
                  };
              },
            ),
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (TapGestureRecognizer instance) {
                instance
                  ..onTap = () {
                    setState(() {
                      selectedPaths.clear();
                      _lastSelectedIndex = null;
                    });
                  }
                  ..onSecondaryTapDown = (details) async {
                    if (!isFileContextMenuShown) {
                      await openBodyContextMenuRightClickTap(context, details.globalPosition);
                    }
                  };
              },
            ),
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(),
              (LongPressGestureRecognizer instance) {
                instance.onLongPressStart = (details) async {
                  await openBodyContextMenu(context, details);
                };
              },
            ),
          },
          child: Stack(
            children: [
              Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: isListView 
                          ? ListView.builder(
                              controller: _scrollController,
                              itemCount: files.length,
                              itemBuilder: (context, index) => _buildFileItem(files[index], index, true),
                            )
                          : GridView.builder(
                              controller: _scrollController,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: ((width - sidebarWidth) / 120).floor().clamp(1, 100)),
                              itemCount: files.length,
                              itemBuilder: (context, index) => _buildFileItem(files[index], index, false),
                            ),
                        ),
                      ),
                      if (dragStart != null && dragCurrent != null)
                        Positioned(
                          left: min(dragStart!.dx, dragCurrent!.dx),
                          top: min(dragStart!.dy, dragCurrent!.dy),
                          width: (dragCurrent!.dx - dragStart!.dx).abs(),
                          height: (dragCurrent!.dy - dragStart!.dy).abs(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: FyrTheme.accentColor.withOpacity(0.3),
                              border: Border.all(color: FyrTheme.accentColor, width: 1),
                            ),
                          ),
                        ),
                      if (activeTransfers.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: FyrTheme.surfaceColor.withOpacity(0.9),
                              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: activeTransfers.take(3).map((t) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t.label,
                                            style: const TextStyle(fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (t.isCompleted)
                                          const Icon(Icons.check_circle, size: 14, color: Colors.green)
                                        else if (t.isError)
                                          const Icon(Icons.error, size: 14, color: Colors.red)
                                        else
                                          Text(
                                            '${(t.progress * 100).toStringAsFixed(0)}%',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    LinearProgressIndicator(
                                      value: t.progress,
                                      minHeight: 2,
                                      backgroundColor: FyrTheme.dividerColor,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        t.isError ? Colors.red : (t.isCompleted ? Colors.green : FyrTheme.accentColor)
                                      ),
                                    ),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
    );
            }
            return const CircularProgressIndicator();
          },
        ),
                ),
                    ],
                  ),
                ),
                if (isPicker)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: FyrTheme.bgColor,
                      border: Border(
                        top: BorderSide(
                          color: FyrTheme.accentColor.withOpacity(0.2),
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (pickerTitle != null && pickerTitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, right: 12.0),
                            child: Text(
                              pickerTitle!,
                              style: TextStyle(
                                color: FyrTheme.textColor.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (isSavePicker) ...[
                          Text(
                            'File name:',
                            style: TextStyle(
                              color: FyrTheme.textColor.withOpacity(0.75),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _saveFileNameController,
                                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                                onSubmitted: (_) => _confirmPickerSelection(),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  filled: true,
                                  fillColor: FyrTheme.surfaceColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: FyrTheme.accentColor, width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ] else
                          const Spacer(),
                        TextButton(
                          onPressed: () => exit(1),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: FyrTheme.textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FyrTheme.accentColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _confirmPickerSelection,
                          child: Text(isSavePicker ? 'Save' : 'Select'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        if (previewImagePath != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      previewImagePath = null;
                    });
                  },
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    child: Center(
                      child: Image.file(File(previewImagePath!)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }



  Future<void> _showRenameDialog(BuildContext context, FileSystemEntity file) async {
    String fileName = p.basename(file.path);
    int lastDotIndex = fileName.lastIndexOf('.');
    int selectionEnd = (lastDotIndex <= 0) ? fileName.length : lastDotIndex;

    TextEditingController renameController = TextEditingController(text: fileName);
    renameController.selection = TextSelection(baseOffset: 0, extentOffset: selectionEnd);

    void doRename() {
      String newName = renameController.text;
      if (newName.isNotEmpty && newName != fileName) {
        String newPath = p.join(p.dirname(file.path), newName);
        try {
          file.renameSync(newPath);
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error renaming: $e')),
          );
        }
      }
      Navigator.pop(context);
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: renameController,
          autofocus: true,
          onSubmitted: (_) => doRename(),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: doRename,
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<dynamic> openIconContextMenuRightClick(
      BuildContext context, PointerDownEvent event, FileSystemEntity file) {
    final currentFileInfo = fileInfoList.firstWhere(
      (info) => info.filePath == file.path,
      orElse: () => FileInfo(filePath: file.path),
    );
    final hasActiveTag = currentFileInfo.tag != null && currentFileInfo.tag!.isNotEmpty;
    final targetPaths = selectedPaths.contains(file.path) && selectedPaths.length > 1
        ? selectedPaths.toList()
        : [file.path];

    return showMenu(
      context: context,
      position: RelativeRect.fromLTRB(event.position.dx, event.position.dy,
          event.position.dx, event.position.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              String paths = selectedPaths.contains(file.path) && selectedPaths.length > 1 
                  ? selectedPaths.join('\n') 
                  : file.path;
              Clipboard.setData(ClipboardData(text: paths));
              Navigator.pop(context);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(context);
              await _showRenameDialog(context, file);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              List<String> toDelete = selectedPaths.contains(file.path) && selectedPaths.length > 1 
                  ? selectedPaths.toList() 
                  : [file.path];
              for (String path in toDelete) {
                try {
                  var result = Process.runSync('gio', ['trash', path]);
                  if (result.exitCode != 0) {
                    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                        ? Directory(path).deleteSync(recursive: true)
                        : File(path).deleteSync();
                  }
                } catch (e) {
                  FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                      ? Directory(path).deleteSync(recursive: true)
                      : File(path).deleteSync();
                }
              }
              setState(() {
                selectedPaths.clear();
              });
              Navigator.pop(context);
            },
          ),
        ),
        if (file.path.endsWith('.desktop'))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Launch Application'),
              onTap: () {
                Navigator.pop(context);
                _launchDesktopFile(file.path);
              },
            ),
          ),
        if (!FileSystemEntity.isDirectorySync(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open With...'),
              onTap: () {
                Navigator.pop(context);
                _showOpenWithDialog(context, file.path);
              },
            ),
          ),
        if (_isImageFile(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.wallpaper),
              title: const Text('Set as Wallpaper'),
              onTap: () {
                Navigator.pop(context);
                _setAsWallpaper(file.path);
              },
            ),
          ),
        if (_isArchive(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.unarchive),
              title: const Text('Extract Here'),
              onTap: () {
                Navigator.pop(context);
                _extractArchive(file.path);
              },
            ),
          ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.archive),
            title: const Text('Compress...'),
            onTap: () {
              Navigator.pop(context);
              List<String> toCompress = selectedPaths.contains(file.path) 
                  ? selectedPaths.toList() 
                  : [file.path];
              _handleCompress(toCompress);
            },
          ),
        ),
        PopupMenuItem(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Properties'),
                onTap: () {
                  Navigator.pop(context);
                  var fileStat = file.statSync();
                  var properties = fileStatToMap(fileStat, file.path);
                  showPropertiesDialog(context, properties);
                },
              ),
              if (FileSystemEntity.isDirectorySync(file.path) && !customPins.contains(file.path))
                ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: const Text('Pin to Sidebar'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      customPins.add(file.path);
                    });
                    saveCustomPins();
                  },
                ),
            ],
          ),
        ),
        if (hasActiveTag)
          PopupMenuItem(
            onTap: () async {
              setState(() {
                for (final tp in targetPaths) {
                  fileInfoList.removeWhere((info) => info.filePath == tp);
                }
              });
              await writeTagsToFile(fileInfoList, tagsFilePath);
            },
            child: Row(
              children: [
                Icon(Icons.label_off_outlined, color: Colors.red.shade300, size: 18),
                const SizedBox(width: 8),
                Text('Remove Tag', style: TextStyle(color: Colors.red.shade300)),
              ],
            ),
          ),
        ...customTags.map((tag) {
          final currentFileInfo = fileInfoList.firstWhere(
            (info) => info.filePath == file.path,
            orElse: () => FileInfo(filePath: file.path),
          );
          final isTagApplied = currentFileInfo.tag == tag['id'];
          final targetPaths = selectedPaths.contains(file.path) && selectedPaths.length > 1
              ? selectedPaths.toList()
              : [file.path];

          return PopupMenuItem(
            onTap: () async {
              setState(() {
                if (isTagApplied) {
                  for (final tp in targetPaths) {
                    fileInfoList.removeWhere((info) => info.filePath == tp);
                  }
                } else {
                  for (final tp in targetPaths) {
                    fileInfoList.removeWhere((info) => info.filePath == tp);
                    fileInfoList.add(FileInfo(filePath: tp, tag: tag['id']));
                  }
                }
              });
              await writeTagsToFile(fileInfoList, tagsFilePath);
            },
            child: Row(
              children: [
                getDotColor(Color(tag['colorValue'])),
                const SizedBox(width: 8),
                Expanded(child: Text(tag['name'])),
                if (isTagApplied)
                  Icon(Icons.check, size: 16, color: FyrTheme.accentColor),
              ],
            ),
          );
        }),
      ],
    );
  }

  openBodyContextMenuRightClickTap(BuildContext context, Offset position) async {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.create),
            title: const Text('Create File'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) {
                  TextEditingController fileNameController =
                      TextEditingController();
                  return AlertDialog(
                    title: const Text('Enter File Name'),
                    content: TextField(
                      controller: fileNameController,
                      decoration: const InputDecoration(hintText: "File name"),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (fileNameController.text.isNotEmpty) {
                            await createFile(
                                currentDir, fileNameController.text);
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Create'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.create),
            title: const Text('Create Directory'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) {
                  TextEditingController dirNameController =
                      TextEditingController();
                  return AlertDialog(
                    title: const Text('Enter Directory Name'),
                    content: TextField(
                      controller: dirNameController,
                      decoration:
                          const InputDecoration(hintText: "Directory name"),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (dirNameController.text.isNotEmpty) {
                            await createDir(currentDir, dirNameController.text);
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Create'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        PopupMenuItem(
          enabled: await isClipboardDataAvailable(),
          child: ListTile(
            leading: const Icon(Icons.paste),
            title: const Text('Paste'),
            onTap: () async {
              await pasteFile(currentDir);
              Navigator.pop(context);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Properties'),
            onTap: () {
              Navigator.pop(context);
              var dirStat = currentDir.statSync();
              var properties = dirStatToMap(dirStat, currentDir.path);
              showPropertiesDialog(context, properties);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Open in Terminal'),
            onTap: () {
              Navigator.pop(context);
              Process.run('fyrterm', [], workingDirectory: currentDir.path);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Change Wallpaper / Appearance'),
            onTap: () {
              Navigator.pop(context);
              _openAppearanceSettings();
            },
          ),
        ),
      ],
    );
  }

  openBodyContextMenu(
      BuildContext context, LongPressStartDetails details) async {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.create),
            title: const Text('Create File'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) {
                  TextEditingController fileNameController =
                      TextEditingController();
                  return AlertDialog(
                    title: const Text('Enter File Name'),
                    content: TextField(
                      controller: fileNameController,
                      decoration: const InputDecoration(hintText: "File name"),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (fileNameController.text.isNotEmpty) {
                            await createFile(
                                currentDir, fileNameController.text);
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Create'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.create),
            title: const Text('Create Directory'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) {
                  TextEditingController dirNameController =
                      TextEditingController();
                  return AlertDialog(
                    title: const Text('Enter Directory Name'),
                    content: TextField(
                      controller: dirNameController,
                      decoration:
                          const InputDecoration(hintText: "Directory name"),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (dirNameController.text.isNotEmpty) {
                            await createDir(currentDir, dirNameController.text);
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Create'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        PopupMenuItem(
          enabled: await isClipboardDataAvailable(),
          child: ListTile(
            leading: const Icon(Icons.paste),
            title: const Text('Paste'),
            onTap: () async {
              await pasteFile(currentDir);
              Navigator.pop(context);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Properties'),
            onTap: () {
              Navigator.pop(context);
              var dirStat = currentDir.statSync();
              var properties = dirStatToMap(dirStat, currentDir.path);
              showPropertiesDialog(context, properties);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Open in Terminal'),
            onTap: () {
              Navigator.pop(context);
              Process.run('fyrterm', [], workingDirectory: currentDir.path);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Change Wallpaper / Appearance'),
            onTap: () {
              Navigator.pop(context);
              _openAppearanceSettings();
            },
          ),
        ),
      ],
    );
  }

  Future<dynamic> openIconContextMenu(BuildContext context,
      LongPressStartDetails event, FileSystemEntity file) {
    final currentFileInfo = fileInfoList.firstWhere(
      (info) => info.filePath == file.path,
      orElse: () => FileInfo(filePath: file.path),
    );
    final hasActiveTag = currentFileInfo.tag != null && currentFileInfo.tag!.isNotEmpty;
    final targetPaths = selectedPaths.contains(file.path) && selectedPaths.length > 1
        ? selectedPaths.toList()
        : [file.path];

    return showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          event.globalPosition.dx,
          event.globalPosition.dy,
          event.globalPosition.dx,
          event.globalPosition.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              String paths = selectedPaths.contains(file.path) && selectedPaths.length > 1 
                  ? selectedPaths.join('\n') 
                  : file.path;
              Clipboard.setData(ClipboardData(text: paths));
              Navigator.pop(context);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(context);
              await _showRenameDialog(context, file);
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              List<String> toDelete = selectedPaths.contains(file.path) && selectedPaths.length > 1 
                  ? selectedPaths.toList() 
                  : [file.path];
              for (String path in toDelete) {
                try {
                  var result = Process.runSync('gio', ['trash', path]);
                  if (result.exitCode != 0) {
                    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                        ? Directory(path).deleteSync(recursive: true)
                        : File(path).deleteSync();
                  }
                } catch (e) {
                  FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
                      ? Directory(path).deleteSync(recursive: true)
                      : File(path).deleteSync();
                }
              }
              setState(() {
                selectedPaths.clear();
              });
              Navigator.pop(context);
            },
          ),
        ),
        if (file.path.endsWith('.desktop'))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Launch Application'),
              onTap: () {
                Navigator.pop(context);
                _launchDesktopFile(file.path);
              },
            ),
          ),
        if (!FileSystemEntity.isDirectorySync(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open With...'),
              onTap: () {
                Navigator.pop(context);
                _showOpenWithDialog(context, file.path);
              },
            ),
          ),
        if (_isImageFile(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.wallpaper),
              title: const Text('Set as Wallpaper'),
              onTap: () {
                Navigator.pop(context);
                _setAsWallpaper(file.path);
              },
            ),
          ),
        if (_isArchive(file.path))
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.unarchive),
              title: const Text('Extract Here'),
              onTap: () {
                Navigator.pop(context);
                _extractArchive(file.path);
              },
            ),
          ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.archive),
            title: const Text('Compress...'),
            onTap: () {
              Navigator.pop(context);
              List<String> toCompress = selectedPaths.contains(file.path) 
                  ? selectedPaths.toList() 
                  : [file.path];
              _handleCompress(toCompress);
            },
          ),
        ),
        PopupMenuItem(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Properties'),
                onTap: () {
                  Navigator.pop(context);
                  var fileStat = file.statSync();
                  var properties = fileStatToMap(fileStat, file.path);
                  showPropertiesDialog(context, properties);
                },
              ),
              if (FileSystemEntity.isDirectorySync(file.path) && !customPins.contains(file.path))
                ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: const Text('Pin to Sidebar'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      customPins.add(file.path);
                    });
                    saveCustomPins();
                  },
                ),
            ],
          ),
        ),
        if (hasActiveTag)
          PopupMenuItem(
            onTap: () async {
              setState(() {
                for (final tp in targetPaths) {
                  fileInfoList.removeWhere((info) => info.filePath == tp);
                }
              });
              await writeTagsToFile(fileInfoList, tagsFilePath);
            },
            child: Row(
              children: [
                Icon(Icons.label_off_outlined, color: Colors.red.shade300, size: 18),
                const SizedBox(width: 8),
                Text('Remove Tag', style: TextStyle(color: Colors.red.shade300)),
              ],
            ),
          ),
        ...customTags.map((tag) {
          final currentFileInfo = fileInfoList.firstWhere(
            (info) => info.filePath == file.path,
            orElse: () => FileInfo(filePath: file.path),
          );
          final isTagApplied = currentFileInfo.tag == tag['id'];
          final targetPaths = selectedPaths.contains(file.path) && selectedPaths.length > 1
              ? selectedPaths.toList()
              : [file.path];

          return PopupMenuItem(
            onTap: () async {
              setState(() {
                if (isTagApplied) {
                  for (final tp in targetPaths) {
                    fileInfoList.removeWhere((info) => info.filePath == tp);
                  }
                } else {
                  for (final tp in targetPaths) {
                    fileInfoList.removeWhere((info) => info.filePath == tp);
                    fileInfoList.add(FileInfo(filePath: tp, tag: tag['id']));
                  }
                }
              });
              await writeTagsToFile(fileInfoList, tagsFilePath);
            },
            child: Row(
              children: [
                getDotColor(Color(tag['colorValue'])),
                const SizedBox(width: 8),
                Expanded(child: Text(tag['name'])),
                if (isTagApplied)
                  Icon(Icons.check, size: 16, color: FyrTheme.accentColor),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openFileOrLaunch(String filePath) async {
    if (filePath.endsWith('.desktop')) {
      await _launchDesktopFile(filePath);
      return;
    }
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        final stat = file.statSync();
        final isExecutable = (stat.mode & 0x49) != 0;
        if (isExecutable &&
            (filePath.endsWith('.sh') ||
                filePath.endsWith('.AppImage') ||
                !p.basename(filePath).contains('.'))) {
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          return;
        }
      } catch (_) {}
    }

    bool opened = false;
    try {
      await Process.start('gio', ['open', filePath], mode: ProcessStartMode.detached);
      opened = true;
    } catch (_) {}

    if (!opened) {
      try {
        await Process.start('xdg-open', [filePath], mode: ProcessStartMode.detached);
      } catch (e) {
        stderr.writeln('Could not open $filePath: $e');
      }
    }
  }

  Future<void> _launchDesktopFile(String desktopPath, [String? fileArg]) async {
    try {
      if (fileArg != null) {
        await Process.start('gio', ['launch', desktopPath, fileArg], mode: ProcessStartMode.detached);
      } else {
        await Process.start('gio', ['launch', desktopPath], mode: ProcessStartMode.detached);
      }
      return;
    } catch (_) {}

    try {
      final lines = await File(desktopPath).readAsLines();
      String? exec;
      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('Exec=')) {
          exec = trimmed.substring(5).trim();
          break;
        }
      }
      if (exec != null) {
        if (fileArg != null) {
          if (exec.contains('@@')) {
            exec = exec.replaceAll(RegExp(r'@@[uU]?\s+%[uUfF]\s+@@'), fileArg);
            exec = exec.replaceAll(RegExp(r'@@[uU]?'), '');
            exec = exec.replaceAll('@@', '');
          }
          if (exec.contains('%f') || exec.contains('%F') || exec.contains('%u') || exec.contains('%U')) {
            exec = exec
                .replaceAll('%f', fileArg)
                .replaceAll('%F', fileArg)
                .replaceAll('%u', fileArg)
                .replaceAll('%U', fileArg);
          } else {
            exec = '$exec "$fileArg"';
          }
        }
        exec = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').replaceAll('@@u', '').replaceAll('@@', '').trim();
        await Process.start('sh', ['-c', exec], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      stderr.writeln('Error launching $desktopPath: $e');
    }
  }

  Future<void> _showOpenWithDialog(BuildContext context, String filePath) async {
    final Set<String> searchPaths = {};
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      searchPaths.add('$home/.local/share/applications');
      searchPaths.add('$home/.local/share/flatpak/exports/share/applications');
    }
    final xdgDataDirs = Platform.environment['XDG_DATA_DIRS'];
    if (xdgDataDirs != null && xdgDataDirs.isNotEmpty) {
      for (var dir in xdgDataDirs.split(':')) {
        if (dir.trim().isNotEmpty) {
          searchPaths.add('${dir.trim()}/applications');
        }
      }
    }
    searchPaths.add('/usr/local/share/applications');
    searchPaths.add('/usr/share/applications');
    searchPaths.add('/var/lib/flatpak/exports/share/applications');
    searchPaths.add('/var/lib/snapd/desktop/applications');

    final Set<String> seenDesktopFiles = {};
    List<Map<String, String>> apps = [];

    for (var pth in searchPaths) {
      final dir = Directory(pth);
      if (await dir.exists()) {
        try {
          for (var file in dir.listSync()) {
            if (file.path.endsWith('.desktop')) {
              final desktopFile = file.path.split('/').last;
              if (seenDesktopFiles.contains(desktopFile)) continue;
              try {
                final content = await File(file.path).readAsString();
                String? name;
                String? exec;
                bool noDisplay = false;
                for (var line in content.split('\n')) {
                  final trimmed = line.trim();
                  if (trimmed.startsWith('Name=') && name == null) name = trimmed.substring(5).trim();
                  if (trimmed.startsWith('Exec=') && exec == null) exec = trimmed.substring(5).trim();
                  if (trimmed.toLowerCase() == 'nodisplay=true') noDisplay = true;
                }
                if (name != null && exec != null && !noDisplay) {
                  seenDesktopFiles.add(desktopFile);
                  apps.add({
                    'name': name,
                    'exec': exec,
                    'desktopPath': file.path,
                    'desktopFile': desktopFile,
                  });
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }
    apps.sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredApps = searchQuery.isEmpty
                ? apps
                : apps.where((a) => a['name']!.toLowerCase().contains(searchQuery.toLowerCase())).toList();

            return AlertDialog(
              backgroundColor: FyrTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
              ),
              title: Row(
                children: [
                  Icon(Icons.open_in_new, color: FyrTheme.accentColor),
                  const SizedBox(width: 12),
                  Text('Open With...', style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 440,
                height: 480,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search applications...',
                        hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                        prefixIcon: Icon(Icons.search, color: FyrTheme.accentColor),
                        filled: true,
                        fillColor: FyrTheme.isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      style: TextStyle(color: FyrTheme.textColor),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredApps.isEmpty
                          ? Center(
                              child: Text(
                                'No matching applications',
                                style: TextStyle(color: FyrTheme.textColorMuted),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredApps.length,
                              itemBuilder: (context, index) {
                                final app = filteredApps[index];
                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: FyrTheme.accentColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.apps, color: FyrTheme.accentColor, size: 20),
                                  ),
                                  title: Text(
                                    app['name']!,
                                    style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    app['desktopFile']!,
                                    style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                                  ),
                                  onTap: () async {
                                    Navigator.pop(dialogCtx);
                                    await _launchDesktopFile(app['desktopPath']!, filePath);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: TextStyle(color: FyrTheme.accentColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
