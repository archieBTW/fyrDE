import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
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

  runApp(FyrMusicApp(initialFile: initialFile));
}

enum VisualizerMode { classic, psychedelic }

class Song {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String? artworkPath;
  final int durationSeconds;

  Song({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    this.artworkPath,
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'genre': genre,
    'artworkPath': artworkPath,
    'durationSeconds': durationSeconds,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    path: json['path'],
    title: json['title'] ?? 'Unknown',
    artist: json['artist'] ?? 'Unknown Artist',
    album: json['album'] ?? 'Unknown Album',
    genre: json['genre'] ?? '',
    artworkPath: json['artworkPath'],
    durationSeconds: json['durationSeconds'] ?? 0,
  );
}

class FyrMusicApp extends StatelessWidget {
  final String? initialFile;
  const FyrMusicApp({super.key, this.initialFile});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FyrMusic',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        theme: ThemeData.light().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: FyrTheme.bgColor,
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: FyrTheme.surfaceColor,
          ),
        ),
        home: initialFile != null 
          ? SingleFilePlayer(filePath: initialFile!) 
          : LibraryScreen(),
      ),
    );
  }
}

class SingleFilePlayer extends StatefulWidget {
  final String filePath;
  const SingleFilePlayer({super.key, required this.filePath});

  @override
  State<SingleFilePlayer> createState() => _SingleFilePlayerState();
}

class _SingleFilePlayerState extends State<SingleFilePlayer> {
  late final Player player = Player();
  String _title = 'Loading...';
  String _artist = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  Song? _song;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    player.stream.position.listen((p) => setState(() => _position = p));
    player.stream.duration.listen((d) => setState(() => _duration = d));
    player.stream.playing.listen((p) => setState(() => _playing = p));

    final song = await _extractMetadata(widget.filePath);
    setState(() {
      _song = song;
      _title = song.title;
      _artist = song.artist;
    });

    player.open(Media(widget.filePath), play: true);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<Song> _extractMetadata(String path) async {
    try {
      final res = await Process.run('ffprobe', [
        '-v', 'quiet', '-print_format', 'json', '-show_format', path
      ]);
      final jsonOutput = jsonDecode(res.stdout.toString());
      final format = jsonOutput['format'];
      final tags = format['tags'] ?? {};

      return Song(
        path: path,
        title: tags['title'] ?? p.basenameWithoutExtension(path),
        artist: tags['artist'] ?? 'Unknown Artist',
        album: tags['album'] ?? 'Unknown Album',
        genre: tags['genre'] ?? '',
        durationSeconds: double.tryParse(format['duration']?.toString() ?? '0')?.round() ?? 0,
      );
    } catch (_) {
      return Song(
        path: path,
        title: p.basenameWithoutExtension(path),
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        genre: '',
      );
    }
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
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WinampVisualizer(isPlaying: _playing, height: 160, currentSong: _song),
                  SizedBox(height: 24),
                  Text(_title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: FyrTheme.textColor)),
                  Text(_artist, style: TextStyle(fontSize: 18, color: FyrTheme.textColorMuted)),
                  SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48.0),
                    child: Slider(
                      value: _position.inSeconds.toDouble(),
                      max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                      onChanged: (v) => player.seek(Duration(seconds: v.round())),
                      activeColor: FyrTheme.accentColor,
                    ),
                  ),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: FyrTheme.accentColor),
                    onPressed: () => player.playOrPause(),
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Song> _songs = [];
  bool _loading = true;
  String _currentView = 'Songs';
  String _searchQuery = '';
  String _sortBy = 'Title';
  String? _selectedArtist;
  String? _selectedAlbum;
  
  late final Player player = Player();
  Song? _currentSong;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    player.stream.position.listen((p) => setState(() => _position = p));
    player.stream.duration.listen((d) => setState(() => _duration = d));
    player.stream.playing.listen((p) => setState(() => _playing = p));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _showEditDialog(Song song) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    final albumController = TextEditingController(text: song.album);
    String? newArtworkPath = song.artworkPath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Track Info', style: TextStyle(color: FyrTheme.textColor)),
          backgroundColor: FyrTheme.isDark ? Color(0xFF1E1E1E) : Colors.white,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result != null) {
                      setDialogState(() => newArtworkPath = result.files.single.path);
                    }
                  },
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                      image: newArtworkPath != null 
                        ? DecorationImage(image: FileImage(File(newArtworkPath!)), fit: BoxFit.cover)
                        : null,
                    ),
                    child: newArtworkPath == null ? Icon(Icons.add_a_photo, size: 40, color: FyrTheme.textColorMuted) : null,
                  ),
                ),
                SizedBox(height: 24),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: FyrTheme.textColorMuted)),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
                TextField(
                  controller: artistController,
                  decoration: InputDecoration(labelText: 'Artist', labelStyle: TextStyle(color: FyrTheme.textColorMuted)),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
                TextField(
                  controller: albumController,
                  decoration: InputDecoration(labelText: 'Album', labelStyle: TextStyle(color: FyrTheme.textColorMuted)),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final updatedSong = Song(
                  path: song.path,
                  title: titleController.text,
                  artist: artistController.text,
                  album: albumController.text,
                  genre: song.genre,
                  artworkPath: newArtworkPath,
                  durationSeconds: song.durationSeconds,
                );
                
                setState(() {
                  int idx = _songs.indexWhere((s) => s.path == song.path);
                  if (idx != -1) _songs[idx] = updatedSong;
                  if (_currentSong?.path == song.path) _currentSong = updatedSong;
                });
                
                await _saveLibrary();
                _updateFileMetadata(updatedSong);
                Navigator.pop(context);
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateFileMetadata(Song song) async {
    try {
      final tempPath = '${song.path}.tmp';
      final res = await Process.run('ffmpeg', [
        '-i', song.path,
        '-metadata', 'title=${song.title}',
        '-metadata', 'artist=${song.artist}',
        '-metadata', 'album=${song.album}',
        '-codec', 'copy',
        '-y',
        tempPath
      ]);
      
      if (res.exitCode == 0) {
        await File(tempPath).rename(song.path);
      } else {
        stderr.writeln('FFmpeg error: ${res.stderr}');
      }
    } catch (e) {
      stderr.writeln('Failed to update file metadata: $e');
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _loading = true);
    final file = File('${Platform.environment['HOME']}/.config/fyr/fyrmusic.json');
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as List;
        _songs = data.map((e) => Song.fromJson(e)).toList();
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<void> _saveLibrary() async {
    final dir = Directory('${Platform.environment['HOME']}/.config/fyr');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/fyrmusic.json');
    final data = _songs.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<Song> _extractMetadata(String path) async {
    try {
      final res = await Process.run('ffprobe', [
        '-v', 'quiet', '-print_format', 'json', '-show_format', path
      ]);
      final jsonOutput = jsonDecode(res.stdout.toString());
      final format = jsonOutput['format'];
      final tags = format['tags'] ?? {};

      String? artworkPath;
      try {
        final cacheDir = Directory('${Platform.environment['HOME']}/.cache/fyr/music_artwork');
        if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
        
        final hash = path.hashCode.toString();
        final artPath = '${cacheDir.path}/$hash.jpg';
        
        // Try to extract cover art
        final artRes = await Process.run('ffmpeg', [
          '-i', path, '-an', '-vcodec', 'copy', '-y', artPath
        ]);
        
        if (artRes.exitCode == 0 && File(artPath).existsSync() && File(artPath).lengthSync() > 0) {
          artworkPath = artPath;
        }
      } catch (_) {}

      return Song(
        path: path,
        title: tags['title'] ?? p.basenameWithoutExtension(path),
        artist: tags['artist'] ?? 'Unknown Artist',
        album: tags['album'] ?? 'Unknown Album',
        genre: tags['genre'] ?? '',
        artworkPath: artworkPath,
        durationSeconds: double.tryParse(format['duration']?.toString() ?? '0')?.round() ?? 0,
      );
    } catch (_) {
      return Song(
        path: path,
        title: p.basenameWithoutExtension(path),
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        genre: '',
      );
    }
  }

  Future<void> _importFolder() async {
    String? folder = await FilePicker.platform.getDirectoryPath();
    if (folder == null) return;

    setState(() => _loading = true);
    final dir = Directory(folder);
    final files = dir.listSync(recursive: true);
    for (var f in files) {
      if (f is File && (f.path.endsWith('.mp3') || f.path.endsWith('.flac') || f.path.endsWith('.m4a') || f.path.endsWith('.wav'))) {
        if (!_songs.any((s) => s.path == f.path)) {
          final song = await _extractMetadata(f.path);
          _songs.add(song);
        }
      }
    }
    await _saveLibrary();
    setState(() => _loading = false);
  }

  void _playSong(Song song) {
    setState(() => _currentSong = song);
    player.open(Media(song.path), play: true);
  }

  void _showArtist(String artist) {
    setState(() {
      _currentView = 'Songs';
      _selectedArtist = artist;
      _selectedAlbum = null;
      _searchQuery = '';
    });
  }

  void _showAlbum(String album) {
    setState(() {
      _currentView = 'Songs';
      _selectedAlbum = album;
      _selectedArtist = null;
      _searchQuery = '';
    });
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
                          if (await windowManager.isMaximized()) {
                            windowManager.unmaximize();
                          } else {
                            windowManager.maximize();
                          }
                        }),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: Icon(Icons.search, color: FyrTheme.textColorMuted),
                      filled: true,
                      fillColor: FyrTheme.isDark ? Colors.white12 : Colors.black12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(color: FyrTheme.textColor),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _buildSidebarItem('Songs', Icons.music_note),
                      _buildSidebarItem('Albums', Icons.album),
                      _buildSidebarItem('Artists', Icons.person),
                      const Divider(),
                      ListTile(
                        leading: Icon(Icons.add, color: FyrTheme.accentColor),
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
                  DragToMoveArea(child: Container(height: 48)),
                  Expanded(
                    child: _loading 
                      ? Center(child: CircularProgressIndicator()) 
                      : _buildMainContent(),
                  ),
                  _buildBottomPlayer(),
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
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? FyrTheme.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          visualDensity: VisualDensity.compact,
          leading: Icon(
            icon, 
            color: isSelected ? onAccentColor : FyrTheme.textColor
          ),
          title: Text(
            title, 
            style: TextStyle(
              color: isSelected ? onAccentColor : FyrTheme.textColor, 
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
            )
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () => setState(() => _currentView = title),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    var filtered = _songs.where((s) {
      final matchesSearch = s.title.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                           s.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           s.genre.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesArtist = _selectedArtist == null || s.artist == _selectedArtist;
      final matchesAlbum = _selectedAlbum == null || s.album == _selectedAlbum;
      return matchesSearch && matchesArtist && matchesAlbum;
    }).toList();

    // Sorting
    switch (_sortBy) {
      case 'Title':
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'Artist':
        filtered.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case 'Album':
        filtered.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
        break;
      case 'Genre':
        filtered.sort((a, b) => a.genre.toLowerCase().compareTo(b.genre.toLowerCase()));
        break;
    }

    if (filtered.isEmpty && _searchQuery.isEmpty && _selectedArtist == null && _selectedAlbum == null) {
      return Center(child: Text('No music found. Import a folder.', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 18)));
    }

    return Column(
      children: [
        if (_selectedArtist != null || _selectedAlbum != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: FyrTheme.textColor),
                  onPressed: () => setState(() {
                    _selectedArtist = null;
                    _selectedAlbum = null;
                  }),
                ),
                Text(
                  _selectedArtist ?? _selectedAlbum!,
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        
        if (_currentView == 'Songs')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Sort by: ', style: TextStyle(color: FyrTheme.textColorMuted)),
                DropdownButton<String>(
                  value: _sortBy,
                  dropdownColor: FyrTheme.surfaceColor,
                  style: TextStyle(color: FyrTheme.textColor),
                  underline: SizedBox(),
                  items: ['Title', 'Artist', 'Album', 'Genre'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
                  },
                ),
              ],
            ),
          ),

        Expanded(
          child: _buildListOrGrid(filtered),
        ),
      ],
    );
  }

  Widget _buildListOrGrid(List<Song> filtered) {
    if (_currentView == 'Songs') {
      return ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final s = filtered[index];
          return GestureDetector(
            onSecondaryTapDown: (details) {
              showMenu(
                context: context,
                position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                items: [
                  PopupMenuItem(child: ListTile(leading: Icon(Icons.edit), title: Text('Edit Track')), onTap: () => Future.delayed(Duration.zero, () => _showEditDialog(s))),
                ],
              );
            },
            child: ListTile(
              leading: s.artworkPath != null 
                ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(File(s.artworkPath!), width: 40, height: 40, fit: BoxFit.cover))
                : Icon(Icons.music_note, color: FyrTheme.textColorMuted),
              title: Text(s.title, style: TextStyle(color: FyrTheme.textColor)),
              subtitle: Row(
                children: [
                  InkWell(
                    onTap: () => _showArtist(s.artist),
                    child: Text(s.artist, style: TextStyle(color: FyrTheme.accentColor, fontSize: 12)),
                  ),
                  Text(' • ', style: TextStyle(color: FyrTheme.textColorMuted)),
                  InkWell(
                    onTap: () => _showAlbum(s.album),
                    child: Text(s.album, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                  ),
                  if (s.genre.isNotEmpty) ...[
                    Text(' • ', style: TextStyle(color: FyrTheme.textColorMuted)),
                    Text(s.genre, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                  ],
                ],
              ),
              trailing: Text('${s.durationSeconds ~/ 60}:${(s.durationSeconds % 60).toString().padLeft(2, '0')}', style: TextStyle(color: FyrTheme.textColorMuted)),
              onTap: () => _playSong(s),
            ),
          );
        },
      );
    } else if (_currentView == 'Albums') {
      final albumMap = <String, List<Song>>{};
      for (var s in _songs) {
        albumMap.putIfAbsent(s.album, () => []).add(s);
      }
      final albums = albumMap.keys.toList()..sort();

      return GridView.builder(
        padding: EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.8, crossAxisSpacing: 16, mainAxisSpacing: 16),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final albumName = albums[index];
          final songs = albumMap[albumName]!;
          final firstWithArt = songs.firstWhere((s) => s.artworkPath != null, orElse: () => songs.first);

          return GestureDetector(
            onTap: () => _showAlbum(albumName),
            child: Card(
              color: FyrTheme.cardColor,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: firstWithArt.artworkPath != null
                      ? Image.file(File(firstWithArt.artworkPath!), fit: BoxFit.cover, width: double.infinity)
                      : Container(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.album, size: 64, color: FyrTheme.textColorMuted)),
                        ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(albumName, textAlign: TextAlign.center, style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      final artists = filtered.map((e) => e.artist).toSet().toList()..sort();
      return ListView.builder(
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return ListTile(
            leading: Icon(Icons.person, color: FyrTheme.textColorMuted),
            title: Text(artist, style: TextStyle(color: FyrTheme.textColor)),
            onTap: () => _showArtist(artist),
          );
        },
      );
    }
  }

  Widget _buildBottomPlayer() {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: FyrTheme.isDark ? Color(0xFF000000) : Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          if (_currentSong != null) ...[
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withOpacity(0.2), 
                borderRadius: BorderRadius.circular(8),
                image: _currentSong?.artworkPath != null 
                  ? DecorationImage(image: FileImage(File(_currentSong!.artworkPath!)), fit: BoxFit.cover)
                  : null,
              ),
              child: _currentSong?.artworkPath == null ? Icon(Icons.music_note, color: FyrTheme.accentColor) : null,
            ),
            SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_currentSong!.title, style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_currentSong!.artist, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  WinampVisualizer(isPlaying: _playing, height: 20, barCount: 20, currentSong: _currentSong),
                ],
              ),
            ),
          ] else Expanded(flex: 2, child: SizedBox()),
          
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: Icon(Icons.skip_previous, color: FyrTheme.textColor), onPressed: () {}),
                    IconButton(
                      iconSize: 40,
                      icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: FyrTheme.accentColor),
                      onPressed: () {
                        if (_currentSong != null) player.playOrPause();
                      },
                    ),
                    IconButton(icon: Icon(Icons.skip_next, color: FyrTheme.textColor), onPressed: () {}),
                  ],
                ),
                Row(
                  children: [
                    Text('${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _position.inSeconds.toDouble(),
                        max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                        onChanged: (v) => player.seek(Duration(seconds: v.round())),
                        activeColor: FyrTheme.accentColor,
                      ),
                    ),
                    Text('${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.volume_up, color: FyrTheme.textColorMuted),
                SizedBox(
                  width: 100,
                  child: Slider(
                    value: player.state.volume,
                    max: 100,
                    onChanged: (v) => player.setVolume(v),
                    activeColor: FyrTheme.accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WinampVisualizer extends StatefulWidget {
  final bool isPlaying;
  final double height;
  final int barCount;
  final VisualizerMode mode;
  final bool allowFullscreen;
  final Song? currentSong;

  const WinampVisualizer({
    super.key,
    required this.isPlaying,
    this.height = 100,
    this.barCount = 32,
    this.mode = VisualizerMode.classic,
    this.allowFullscreen = true,
    this.currentSong,
  });

  @override
  State<WinampVisualizer> createState() => _WinampVisualizerState();
}

class _WinampVisualizerState extends State<WinampVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _amplitudes = [];
  final List<double> _peaks = [];
  final math.Random _random = math.Random();
  double _hue = 0.0;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.barCount; i++) {
      _amplitudes.add(0.0);
      _peaks.add(0.0);
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_updateAmplitudes);
    
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(WinampVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.barCount != oldWidget.barCount) {
      _amplitudes.clear();
      _peaks.clear();
      for (int i = 0; i < widget.barCount; i++) {
        _amplitudes.add(0.0);
        _peaks.add(0.0);
      }
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  void _updateAmplitudes() {
    if (!mounted) return;
    setState(() {
      _hue = (_hue + 0.1) % 360; // Further slow down hue rotation
      for (int i = 0; i < widget.barCount; i++) {
        if (widget.isPlaying) {
          double target = _random.nextDouble();
          if (i < widget.barCount / 4) target *= 1.2;
          else if (i > widget.barCount * 0.75) target *= 0.6;
          
          // Very heavy dampening for a calm, safe look
          _amplitudes[i] = _amplitudes[i] * 0.96 + target * 0.04;
        } else {
          _amplitudes[i] *= 0.95;
        }

        if (_amplitudes[i] > _peaks[i]) {
          _peaks[i] = _amplitudes[i];
        } else {
          _peaks[i] = math.max(0.0, _peaks[i] - 0.01);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.allowFullscreen ? () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => FullscreenVisualizer(
            initialMode: widget.mode,
            currentSong: widget.currentSong,
            isPlaying: widget.isPlaying,
          ),
        ));
      } : null,
      child: MouseRegion(
        cursor: widget.allowFullscreen ? SystemMouseCursors.click : MouseCursor.defer,
        child: SizedBox(
          height: widget.height,
          child: CustomPaint(
            painter: widget.mode == VisualizerMode.classic 
              ? _VisualizerPainter(amplitudes: _amplitudes, peaks: _peaks)
              : _PsychedelicPainter(amplitudes: _amplitudes, hue: _hue),
            child: Container(),
          ),
        ),
      ),
    );
  }
}

class _PsychedelicPainter extends CustomPainter {
  final List<double> amplitudes;
  final double hue;

  _PsychedelicPainter({required this.amplitudes, required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final baseHue = HSVColor.fromColor(FyrTheme.accentColor).hue;

    for (int i = 0; i < 3; i++) {
      final h = (baseHue + math.sin(hue * 0.02 + i) * 30) % 360;
      paint.color = HSVColor.fromAHSV(0.8, h, 0.8, 1.0).toColor();
      
      final path = Path();
      path.moveTo(0, size.height / 2);
      
      for (int j = 0; j < amplitudes.length; j++) {
        final x = j * (size.width / (amplitudes.length - 1));
        final amp = amplitudes[j] * (size.height / 2);
        // Significantly slow down wave oscillation speed
        final y = size.height / 2 + math.sin(hue * 0.1 + j * 0.2 + i) * amp;
        
        if (j == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PsychedelicPainter oldDelegate) => true;
}

class _VisualizerPainter extends CustomPainter {
  final List<double> amplitudes;
  final List<double> peaks;

  _VisualizerPainter({required this.amplitudes, required this.peaks});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    final barWidth = size.width / amplitudes.length;
    final spacing = 2.0;
    final actualBarWidth = math.max(1.0, barWidth - spacing);
    
    final segmentHeight = 4.0;
    final segmentSpacing = 1.0;
    final totalSegmentHeight = segmentHeight + segmentSpacing;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * barWidth;
      final h = amplitudes[i] * size.height;
      final segments = (h / totalSegmentHeight).floor();

      for (int j = 0; j < (size.height / totalSegmentHeight).floor(); j++) {
        final y = size.height - (j + 1) * totalSegmentHeight;
        
        Color color;
        if (j > (size.height / totalSegmentHeight) * 0.8) {
          color = Colors.redAccent;
        } else if (j > (size.height / totalSegmentHeight) * 0.6) {
          color = Colors.orangeAccent;
        } else {
          color = FyrTheme.accentColor;
        }

        final paint = Paint()
          ..color = j < segments ? color : color.withOpacity(0.1)
          ..style = PaintingStyle.fill;

        canvas.drawRect(
          Rect.fromLTWH(x, y, actualBarWidth, segmentHeight),
          paint,
        );
      }

      final peakY = size.height - (peaks[i] * size.height);
      final peakPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(
        Rect.fromLTWH(x, peakY, actualBarWidth, 1),
        peakPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) => true;
}

class FullscreenVisualizer extends StatefulWidget {
  final VisualizerMode initialMode;
  final Song? currentSong;
  final bool isPlaying;

  const FullscreenVisualizer({
    super.key,
    required this.initialMode,
    this.currentSong,
    required this.isPlaying,
  });

  @override
  State<FullscreenVisualizer> createState() => _FullscreenVisualizerState();
}

class _FullscreenVisualizerState extends State<FullscreenVisualizer> {
  late VisualizerMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: WinampVisualizer(
              isPlaying: widget.isPlaying,
              height: MediaQuery.of(context).size.height * 0.6,
              barCount: _mode == VisualizerMode.classic ? 64 : 128,
              mode: _mode,
              allowFullscreen: false,
            ),
          ),
          Positioned(
            top: 40, left: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.currentSong?.title ?? 'Unknown Track', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                Text(widget.currentSong?.artist ?? 'Unknown Artist', style: const TextStyle(color: Colors.white70, fontSize: 24)),
              ],
            ),
          ),
          Positioned(
            bottom: 40, right: 40,
            child: Row(
              children: [
                _modeButton('Classic', VisualizerMode.classic),
                const SizedBox(width: 16),
                _modeButton('Psychedelic', VisualizerMode.psychedelic),
                const SizedBox(width: 40),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String label, VisualizerMode mode) {
    final isSelected = _mode == mode;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? FyrTheme.accentColor : Colors.white12,
        foregroundColor: Colors.white,
      ),
      onPressed: () => setState(() => _mode = mode),
      child: Text(label),
    );
  }
}
