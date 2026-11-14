import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';

void main(List<String> args) async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
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

  runApp(FyrPhotosApp(initialFile: initialFile));
}

class Photo {
  final String path;
  final String album;
  final DateTime date;

  Photo({required this.path, required this.album, required this.date});

  Map<String, dynamic> toJson() => {
    'path': path,
    'album': album,
    'date': date.toIso8601String(),
  };

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
    path: json['path'],
    album: json['album'] ?? 'Unknown',
    date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
  );
}

Future<void> setPhotoAsWallpaper(BuildContext context, String imagePath) async {
  if (imagePath.isEmpty) return;
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wallpaper set to ${p.basename(imagePath)}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to set wallpaper: $e')),
      );
    }
  }
}

class FyrPhotosApp extends StatelessWidget {
  final String? initialFile;
  const FyrPhotosApp({super.key, this.initialFile});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FyrPhotos',
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
        home: initialFile != null 
          ? SinglePhotoViewer(filePath: initialFile!) 
          : LibraryScreen(),
      ),
    );
  }
}

class SinglePhotoViewer extends StatelessWidget {
  final String filePath;
  const SinglePhotoViewer({super.key, required this.filePath});

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14, height: 14,
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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onSecondaryTapDown: (details) async {
              final value = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem<String>(
                    value: 'wallpaper',
                    child: Row(
                      children: [
                        Icon(Icons.wallpaper, size: 18),
                        SizedBox(width: 10),
                        Text('Set as Wallpaper'),
                      ],
                    ),
                  ),
                ],
              );
              if (value == 'wallpaper' && context.mounted) {
                await setPhotoAsWallpaper(context, filePath);
              }
            },
            child: PhotoView(
              imageProvider: FileImage(File(filePath)),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              backgroundDecoration: BoxDecoration(color: Colors.black),
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: DragToMoveArea(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  )
                ),
                child: Row(
                  children: [
                    _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                    const SizedBox(width: 8),
                    _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                    const SizedBox(width: 8),
                    _buildTrafficLight(Colors.greenAccent, () async {
                      if (await windowManager.isMaximized()) windowManager.unmaximize();
                      else windowManager.maximize();
                    }),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Text(
                        p.basename(filePath),
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setPhotoAsWallpaper(context, filePath),
                      icon: const Icon(Icons.wallpaper, color: Colors.white, size: 18),
                      label: const Text(
                        'Set as Wallpaper',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Photo> _photos = [];
  bool _loading = true;
  String _currentView = 'All Photos';
  String? _selectedAlbum;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    setState(() => _loading = true);
    final file = File('${Platform.environment['HOME']}/.config/fyr/fyrphotos.json');
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as List;
        _photos = data.map((e) => Photo.fromJson(e)).toList();
      } catch (_) {}
    }
    _photos.sort((a, b) => b.date.compareTo(a.date));
    setState(() => _loading = false);
  }

  Future<void> _saveLibrary() async {
    final dir = Directory('${Platform.environment['HOME']}/.config/fyr');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/fyrphotos.json');
    final data = _photos.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<String?> _pickDirectory({String? title, String? initialDirectory}) async {
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
            : (home.isNotEmpty && Directory(p.join(home, 'Pictures')).existsSync()
                ? p.join(home, 'Pictures')
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
            if (Directory(picked).existsSync()) {
              return picked;
            } else if (File(picked).existsSync()) {
              return p.dirname(picked);
            }
          }
        }
        return null;
      } catch (_) {}
    }

    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: title,
        initialDirectory: initialDirectory,
      );
    } catch (_) {}

    return null;
  }

  Future<void> _importFolder() async {
    final home = Platform.environment['HOME'] ?? '';
    final defaultDir = home.isNotEmpty && Directory(p.join(home, 'Pictures')).existsSync()
        ? p.join(home, 'Pictures')
        : null;
    String? folder = await _pickDirectory(
      title: 'Select Photos Folder',
      initialDirectory: defaultDir,
    );
    if (folder == null) return;

    setState(() => _loading = true);
    final dir = Directory(folder);
    final files = dir.listSync(recursive: true);
    for (var f in files) {
      if (f is File && (f.path.toLowerCase().endsWith('.jpg') || f.path.toLowerCase().endsWith('.jpeg') || f.path.toLowerCase().endsWith('.png') || f.path.toLowerCase().endsWith('.webp'))) {
        if (!_photos.any((p) => p.path == f.path)) {
          final stat = f.statSync();
          final album = p.basename(p.dirname(f.path));
          _photos.add(Photo(path: f.path, album: album, date: stat.modified));
        }
      }
    }
    _photos.sort((a, b) => b.date.compareTo(a.date));
    await _saveLibrary();
    setState(() => _loading = false);
  }

  void _openGallery(int initialIndex, List<Photo> photosList) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => GalleryScreen(photos: photosList, initialIndex: initialIndex),
    ));
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14, height: 14,
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
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            color: FyrTheme.sidebarColor,
            child: Column(
              children: [
                DragToMoveArea(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 20),
                    child: Row(
                      children: [
                        _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.greenAccent, () async {
                          if (await windowManager.isMaximized()) windowManager.unmaximize();
                          else windowManager.maximize();
                        }),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                    children: [
                      _buildSidebarItem('All Photos', Icons.photo_library),
                      _buildSidebarItem('Albums', Icons.photo_album),
                      const Divider(),
                      ListTile(
                        leading: Icon(Icons.add_a_photo, color: FyrTheme.accentColor),
                        title: Text('Import Folder', style: TextStyle(color: FyrTheme.textColor)),
                        onTap: _importFolder,
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Main Area
          Expanded(
            child: Container(
              color: FyrTheme.bgColor,
              child: Column(
                children: [
                  DragToMoveArea(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _selectedAlbum != null
                        ? Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back, color: FyrTheme.textColor),
                                onPressed: () => setState(() => _selectedAlbum = null),
                              ),
                              Text(_selectedAlbum!, style: TextStyle(color: FyrTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          )
                        : null,
                    ),
                  ),
                  Expanded(
                    child: _loading 
                      ? Center(child: CircularProgressIndicator()) 
                      : _buildMainContent(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String title, IconData icon) {
    final isSelected = _currentView == title;
    final onAccentColor = FyrTheme.getContrastingColor(FyrTheme.accentColor);
    return ListTile(
      leading: Icon(icon, color: isSelected ? onAccentColor : FyrTheme.textColor),
      title: Text(title, style: TextStyle(color: isSelected ? onAccentColor : FyrTheme.textColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: isSelected ? FyrTheme.accentColor : Colors.transparent,
      onTap: () => setState(() => _currentView = title),
    );
  }

  Widget _buildMainContent() {
    if (_photos.isEmpty) {
      return Center(child: Text('No photos found. Import a folder.', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 18)));
    }

    if (_currentView == 'All Photos' || _selectedAlbum != null) {
      final photosToShow = _selectedAlbum != null 
        ? _photos.where((p) => p.album == _selectedAlbum).toList()
        : _photos;

      return GridView.builder(
        padding: EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: photosToShow.length,
        itemBuilder: (context, index) {
          final photoPath = photosToShow[index].path;
          return GestureDetector(
            onTap: () => _openGallery(index, photosToShow),
            onSecondaryTapDown: (details) async {
              final action = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem<String>(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.photo, size: 18),
                        SizedBox(width: 10),
                        Text('View Photo'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'wallpaper',
                    child: Row(
                      children: [
                        Icon(Icons.wallpaper, size: 18),
                        SizedBox(width: 10),
                        Text('Set as Wallpaper'),
                      ],
                    ),
                  ),
                ],
              );
              if (action == 'view') {
                _openGallery(index, photosToShow);
              } else if (action == 'wallpaper' && context.mounted) {
                await setPhotoAsWallpaper(context, photoPath);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: ResizeImage(FileImage(File(photoPath)), width: 300),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      );
    } else {
      final albums = _photos.map((e) => e.album).toSet().toList();
      return GridView.builder(
        padding: EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.9, crossAxisSpacing: 16, mainAxisSpacing: 16),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final albumPhotos = _photos.where((p) => p.album == albums[index]).toList();
          return GestureDetector(
            onTap: () => setState(() => _selectedAlbum = albums[index]),
            child: Card(
              color: FyrTheme.cardColor,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: albumPhotos.isNotEmpty 
                      ? Image(
                          image: ResizeImage(FileImage(File(albumPhotos.first.path)), width: 400),
                          fit: BoxFit.cover,
                        )
                      : Container(color: Colors.black12),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(albums[index], style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold), maxLines: 1),
                        Text('${albumPhotos.length} photos', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
}

class GalleryScreen extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;

  const GalleryScreen({super.key, required this.photos, required this.initialIndex});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPhotoPath = widget.photos.isNotEmpty
        ? widget.photos[_currentIndex.clamp(0, widget.photos.length - 1)].path
        : '';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onSecondaryTapDown: (details) async {
              if (currentPhotoPath.isEmpty) return;
              final value = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem<String>(
                    value: 'wallpaper',
                    child: Row(
                      children: [
                        Icon(Icons.wallpaper, size: 18),
                        SizedBox(width: 10),
                        Text('Set as Wallpaper'),
                      ],
                    ),
                  ),
                ],
              );
              if (value == 'wallpaper' && context.mounted) {
                await setPhotoAsWallpaper(context, currentPhotoPath);
              }
            },
            child: PhotoViewGallery.builder(
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              builder: (context, index) {
                return PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(File(widget.photos[index].path)),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                );
              },
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: BoxDecoration(color: Colors.black),
              pageController: _pageController,
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: DragToMoveArea(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  )
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    if (currentPhotoPath.isNotEmpty)
                      Expanded(
                        child: Text(
                          p.basename(currentPhotoPath),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    if (currentPhotoPath.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setPhotoAsWallpaper(context, currentPhotoPath),
                        icon: const Icon(Icons.wallpaper, color: Colors.white, size: 18),
                        label: const Text(
                          'Set as Wallpaper',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.15),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
