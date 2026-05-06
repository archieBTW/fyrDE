import 'dart:io';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

class DesktopApp {
  final String name;
  final String exec;
  final String desktopFile;

  DesktopApp({required this.name, required this.exec, required this.desktopFile});
}

class DefaultAppsPane extends StatefulWidget {
  const DefaultAppsPane({super.key});

  @override
  State<DefaultAppsPane> createState() => _DefaultAppsPaneState();
}

class _DefaultAppsPaneState extends State<DefaultAppsPane> {
  String? _terminalDesktop;
  String? _videoDesktop;
  String? _musicDesktop;
  String? _photoDesktop;
  String? _browserDesktop;
  String? _fileManagerDesktop;
  List<DesktopApp> _installedApps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadInstalledApps() async {
    List<DesktopApp> apps = [];
    List<String> searchPaths = [
      '/usr/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];

    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            try {
              final content = await entity.readAsString();
              String? name;
              String? exec;
              bool noDisplay = false;

              for (var line in content.split('\n')) {
                if (line.startsWith('Name=') && name == null) {
                  name = line.substring(5);
                } else if (line.startsWith('Exec=') && exec == null) {
                  exec = line.substring(5);
                } else if (line.startsWith('NoDisplay=true')) {
                  noDisplay = true;
                }
              }

              if (name != null && exec != null && !noDisplay) {
                final desktopFile = entity.path.split('/').last;
                apps.add(DesktopApp(name: name, exec: exec, desktopFile: desktopFile));
              }
            } catch (e) {}
          }
        }
      }
    }

    apps.sort((a, b) => a.name.compareTo(b.name));
    setState(() {
      _installedApps = apps;
    });
  }

  Future<void> _loadDefaults() async {
    setState(() => _loading = true);
    await _loadInstalledApps();

    _terminalDesktop = await _queryDefault('x-scheme-handler/terminal') ?? 'fyrterm.desktop';
    _videoDesktop = await _queryDefault('video/mp4') ?? 'fyrvideo.desktop';
    _musicDesktop = await _queryDefault('audio/mpeg') ?? 'fyrmusic.desktop';
    _photoDesktop = await _queryDefault('image/jpeg') ?? 'fyrphotos.desktop';
    _browserDesktop = await _queryDefault('x-scheme-handler/https') ?? 'firefox.desktop';
    _fileManagerDesktop = await _queryDefault('inode/directory') ?? 'fyrfiles.desktop';

    setState(() => _loading = false);
  }

  Future<String?> _queryDefault(String mimeType) async {
    try {
      final res = await Process.run('xdg-mime', ['query', 'default', mimeType]);
      final output = res.stdout.toString().trim();
      return output.isNotEmpty ? output : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setDefault(String mimeType, String desktopFile) async {
    if (desktopFile.isEmpty) return;
    try {
      await Process.run('xdg-mime', ['default', desktopFile, mimeType]);
    } catch (_) {}
  }

  Future<void> _updateTerminal(String val) async {
    setState(() => _terminalDesktop = val);
    await _setDefault('x-scheme-handler/terminal', val);
  }

  Future<void> _updateVideo(String val) async {
    setState(() => _videoDesktop = val);
    final mimes = [
      'video/mp4', 'video/x-matroska', 'video/webm',
      'video/quicktime', 'video/x-msvideo', 'video/x-flv',
      'video/x-ms-wmv', 'video/mpeg'
    ];
    for (var m in mimes) {
      await _setDefault(m, val);
    }
  }

  Future<void> _updateMusic(String val) async {
    setState(() => _musicDesktop = val);
    final mimes = [
      'audio/mpeg', 'audio/x-wav', 'audio/flac', 'audio/ogg', 'audio/mp4'
    ];
    for (var m in mimes) {
      await _setDefault(m, val);
    }
  }

  Future<void> _updatePhoto(String val) async {
    setState(() => _photoDesktop = val);
    final mimes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/x-ms-bmp'
    ];
    for (var m in mimes) {
      await _setDefault(m, val);
    }
  }

  Future<void> _updateBrowser(String val) async {
    setState(() => _browserDesktop = val);
    final mimes = ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html'];
    for (var m in mimes) {
      await _setDefault(m, val);
    }
  }

  Future<void> _updateFileManager(String val) async {
    setState(() => _fileManagerDesktop = val);
    await _setDefault('inode/directory', val);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Default Apps',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: FyrTheme.textColor,
          ),
        ),
        SizedBox(height: 24),
        Card(
          color: FyrTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildDropdownRow('Terminal', _terminalDesktop ?? '', (v) => _updateTerminal(v)),
                SizedBox(height: 16),
                _buildDropdownRow('Video Player', _videoDesktop ?? '', (v) => _updateVideo(v)),
                SizedBox(height: 16),
                _buildDropdownRow('Music Player', _musicDesktop ?? '', (v) => _updateMusic(v)),
                SizedBox(height: 16),
                _buildDropdownRow('Photo Viewer', _photoDesktop ?? '', (v) => _updatePhoto(v)),
                SizedBox(height: 16),
                _buildDropdownRow('Web Browser', _browserDesktop ?? '', (v) => _updateBrowser(v)),
                SizedBox(height: 16),
                _buildDropdownRow('File Manager', _fileManagerDesktop ?? '', (v) => _updateFileManager(v)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownRow(String label, String value, ValueChanged<String> onChanged) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
          ),
        ),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: _installedApps.any((app) => app.desktopFile == value) ? value : null,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: FyrTheme.cardColor,
            style: TextStyle(color: FyrTheme.textColor, fontSize: 16),
            items: _installedApps.map((app) {
              return DropdownMenuItem<String>(
                value: app.desktopFile,
                child: Text(app.name, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                onChanged(val);
              }
            },
          ),
        ),
      ],
    );
  }
}
