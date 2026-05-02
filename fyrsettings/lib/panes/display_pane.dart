import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fyr_theme.dart';

class DisplayPane extends StatefulWidget {
  const DisplayPane({super.key});

  @override
  State<DisplayPane> createState() => _DisplayPaneState();
}

class _DisplayPaneState extends State<DisplayPane> {
  List<dynamic> _outputs = [];
  bool _loading = false;
  String _bgPath = '';
  String _selectedBgPath = '';
  String _primaryOutput = '';
  List<String> _defaultBackgrounds = [];
  final ScrollController _bgScrollController = ScrollController();

  @override
  void dispose() {
    _bgScrollController.dispose();
    super.dispose();
  }

  void _scrollBackgrounds(bool right) {
    if (_bgScrollController.hasClients) {
      final offset = right
          ? _bgScrollController.offset + 400
          : _bgScrollController.offset - 400;
      _bgScrollController.animateTo(
        offset.clamp(0.0, _bgScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDisplays();
    _loadSettings();
    _loadDefaultBackgrounds();
  }

  Future<void> _loadDefaultBackgrounds() async {
    List<String> bgs = [];
    final dirs = [
      '/usr/share/backgrounds/gnome',
      '/usr/share/backgrounds/sway',
      '/usr/share/backgrounds',
    ];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final entities = await dir.list(recursive: true).toList();
        for (final file in entities) {
          if (file is File) {
            final path = file.path.toLowerCase();
            if (path.endsWith('.png') ||
                path.endsWith('.jpg') ||
                path.endsWith('.jpeg')) {
              bgs.add(file.path);
            }
          }
        }
      }
    }
    setState(() {
      _defaultBackgrounds = bgs.toSet().toList();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgPath = prefs.getString('bg_path') ?? '';
      _selectedBgPath = _bgPath;
      _primaryOutput = prefs.getString('primary_output') ?? '';
    });
  }

  Future<void> _pickBackground() async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Select Background Image',
      ]);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) {
          _applyBackground(path);
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _applyBackground(String path) async {
    if (path.isEmpty) return;
    setState(() {
      _bgPath = path;
      _selectedBgPath = path;
    });
    try {
      await Process.run('swaymsg', ['output', '*', 'bg', path, 'fill']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bg_path', path);

      final configFile = File(
        '${Platform.environment['HOME']}/.config/sway/config',
      );
      if (await configFile.exists()) {
        final lines = await configFile.readAsLines();
        final newLines = lines.map((line) {
          if (line.startsWith('output * bg') ||
              line.startsWith('output * bg ')) {
            return 'output * bg $path fill';
          }
          return line;
        }).toList();
        if (!newLines.any((line) => line.startsWith('output * bg'))) {
          newLines.insert(0, 'output * bg $path fill');
        }
        await configFile.writeAsString('${newLines.join('\n')}\n');
      }
    } catch (e) {}
  }

  Future<void> _setPrimaryOutput(String name) async {
    setState(() => _primaryOutput = name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primary_output', name);

    for (final app in ['fyrtaskbar', 'fyrdock']) {
      await Process.run('swaymsg', ['[app_id="$app"]', 'move', 'output', name]);
    }

    final configFile = File(
      '${Platform.environment['HOME']}/.config/sway/config',
    );
    if (await configFile.exists()) {
      var lines = await configFile.readAsLines();
      bool inBlock = false;
      var newLines = <String>[];
      for (var line in lines) {
        if (line == '# PRIMARY OUTPUT SETTINGS') {
          inBlock = true;
          continue;
        }
        if (line == '# END PRIMARY OUTPUT SETTINGS') {
          inBlock = false;
          continue;
        }
        if (!inBlock) {
          newLines.add(line);
        }
      }
      newLines.add('# PRIMARY OUTPUT SETTINGS');
      newLines.add('assign [app_id="fyrtaskbar"] output $name');
      newLines.add('assign [app_id="fyrdock"] output $name');
      newLines.add('# END PRIMARY OUTPUT SETTINGS');
      await configFile.writeAsString('${newLines.join('\n')}\n');
    }
  }

  Future<void> _updateWorkspaceBindings() async {
    if (_outputs.isEmpty) return;

    List<String> workspaceCmds = [];
    for (int w = 1; w <= 9; w++) {
      int monitorIndex = (w - 1) % _outputs.length;
      String outputName = _outputs[monitorIndex]['name'];
      workspaceCmds.add('workspace $w output $outputName');
      await Process.run('swaymsg', ['workspace', '$w', 'output', outputName]);
    }

    final configFile = File(
      '${Platform.environment['HOME']}/.config/sway/config',
    );
    if (await configFile.exists()) {
      var lines = await configFile.readAsLines();
      bool inBlock = false;
      var newLines = <String>[];
      for (var line in lines) {
        if (line == '# WORKSPACE BINDINGS') {
          inBlock = true;
          continue;
        }
        if (line == '# END WORKSPACE BINDINGS') {
          inBlock = false;
          continue;
        }
        if (!inBlock) {
          newLines.add(line);
        }
      }
      newLines.add('# WORKSPACE BINDINGS');
      newLines.addAll(workspaceCmds);
      newLines.add('# END WORKSPACE BINDINGS');
      await configFile.writeAsString('${newLines.join('\n')}\n');
    }
  }

  Future<void> _loadDisplays() async {
    if (_outputs.isEmpty) setState(() => _loading = true);
    try {
      final result = await Process.run('swaymsg', ['-t', 'get_outputs']);
      if (result.exitCode == 0) {
        final List<dynamic> outputs = jsonDecode(result.stdout);
        outputs.sort(
          (a, b) => (a['rect']['x'] as int).compareTo(b['rect']['x'] as int),
        );
        setState(() {
          _outputs = outputs;
          if (_primaryOutput.isEmpty && outputs.isNotEmpty) {
            _primaryOutput = outputs.first['name'];
          }
        });
        await _updateWorkspaceBindings();
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    setState(() {
      final item = _outputs.removeAt(oldIndex);
      _outputs.insert(newIndex, item);
    });
    _applyMonitorArrangement();
  }

  Future<void> _applyMonitorArrangement() async {
    int currentX = 0;
    for (final out in _outputs) {
      final name = out['name'] ?? 'Unknown';
      final rect = out['rect'] ?? {};
      final width = rect['width'] ?? 1920;
      await Process.run('swaymsg', ['output', name, 'pos', '$currentX', '0']);
      currentX += width as int;
    }
    _loadDisplays();
  }

  Future<void> _changeResolution(
    String outputName,
    String width,
    String height,
  ) async {
    try {
      await Process.run('swaymsg', [
        'output',
        outputName,
        'resolution',
        '${width}x$height',
      ]);
      _loadDisplays();
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _mirrorDisplay(String outputName) async {
    if (_primaryOutput.isEmpty || _primaryOutput == outputName) return;
    try {
      final primary = _outputs.firstWhere(
        (o) => o['name'] == _primaryOutput,
        orElse: () => null,
      );
      if (primary != null) {
        final rect = primary['rect'];
        await Process.run('swaymsg', [
          'output',
          outputName,
          'pos',
          '${rect['x']}',
          '${rect['y']}',
        ]);
        _loadDisplays();
      }
    } catch (e) {}
  }

  void _showResolutionDialog(String outputName, int currentW, int currentH) {
    final wController = TextEditingController(text: currentW.toString());
    final hController = TextEditingController(text: currentH.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FyrTheme.cardColor,
          title: Text(
            'Resolution for $outputName',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: wController,
                  decoration: InputDecoration(
                    labelText: 'Width',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('x', style: TextStyle(color: FyrTheme.textColor)),
              ),
              Expanded(
                child: TextField(
                  controller: hController,
                  decoration: InputDecoration(
                    labelText: 'Height',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                _changeResolution(
                  outputName,
                  wController.text,
                  hController.text,
                );
                Navigator.pop(context);
              },
              child: Text(
                'Apply',
                style: TextStyle(color: FyrTheme.accentColor),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Displays & Appearance',
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Theme Mode',
                    style: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => FyrTheme.setThemeMode(ThemeMode.light),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: !FyrTheme.isDark
                                ? FyrTheme.accentColor
                                : FyrTheme.cardColor,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                            border: Border.all(color: FyrTheme.accentColor),
                          ),
                          child: Text(
                            'Light',
                            style: TextStyle(
                              color: !FyrTheme.isDark
                                  ? Colors.white
                                  : FyrTheme.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => FyrTheme.setThemeMode(ThemeMode.dark),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: FyrTheme.isDark
                                ? FyrTheme.accentColor
                                : FyrTheme.cardColor,
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                            border: Border.all(color: FyrTheme.accentColor),
                          ),
                          child: Text(
                            'Dark',
                            style: TextStyle(
                              color: FyrTheme.isDark
                                  ? Colors.white
                                  : FyrTheme.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accent Color',
                    style: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: FyrTheme.customColors.map((color) {
                      return GestureDetector(
                        onTap: () {
                          FyrTheme.setAccentColor(color);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: FyrTheme.accentColorNotifier.value == color
                                  ? FyrTheme.textColor
                                  : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Desktop Background',
                    style: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  if (_selectedBgPath.isNotEmpty)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 360),
                        margin: EdgeInsets.only(bottom: 16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: FyrTheme.accentColor,
                                width: 2,
                              ),
                              image: DecorationImage(
                                image: FileImage(File(_selectedBgPath)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_defaultBackgrounds.isNotEmpty) ...[
                    SizedBox(height: 24),
                    Text(
                      'Default Backgrounds',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.chevron_left,
                              color: FyrTheme.textColor,
                              size: 32,
                            ),
                            onPressed: () => _scrollBackgrounds(false),
                          ),
                          Expanded(
                            child: GridView.builder(
                              controller: _bgScrollController,
                              scrollDirection: Axis.horizontal,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisExtent: 260,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                  ),
                              itemCount: _defaultBackgrounds.length,
                              itemBuilder: (context, index) {
                                final path = _defaultBackgrounds[index];
                                final isSelected = path == _selectedBgPath;
                                return GestureDetector(
                                  onTap: () => _applyBackground(path),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? FyrTheme.accentColor
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(File(path)),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.chevron_right,
                              color: FyrTheme.textColor,
                              size: 32,
                            ),
                            onPressed: () => _scrollBackgrounds(true),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.folder_open, color: FyrTheme.textColor),
                      label: Text(
                        'Browse Files...',
                        style: TextStyle(color: FyrTheme.textColor),
                      ),
                      onPressed: _pickBackground,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FyrTheme.cardColor,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 24),
          Text(
            'Monitors (Drag to Arrange)',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),

          if (_loading && _outputs.isEmpty)
            Center(child: CircularProgressIndicator())
          else if (_outputs.isEmpty)
            Center(
              child: Text(
                'No displays found',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            )
          else ...[
            SizedBox(
              height: 120,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                onReorder: _onReorder,
                itemCount: _outputs.length,
                itemBuilder: (context, index) {
                  final out = _outputs[index];
                  final name = out['name'] ?? 'Unknown';
                  return Container(
                    key: ValueKey(name),
                    margin: EdgeInsets.only(right: 16),
                    width: 160,
                    decoration: BoxDecoration(
                      color: FyrTheme.accentColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: FyrTheme.accentColor, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.monitor,
                            color: FyrTheme.textColor,
                            size: 32,
                          ),
                          SizedBox(height: 8),
                          Text(
                            name,
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _outputs.length,
              itemBuilder: (context, index) {
                final out = _outputs[index];
                final name = out['name'] ?? 'Unknown';
                final make = out['make'] ?? 'Unknown';
                final model = out['model'] ?? 'Unknown';
                final rect = out['rect'] ?? {};
                final width = rect['width'] ?? 0;
                final height = rect['height'] ?? 0;
                final scale = out['scale'] ?? 1.0;
                final active = out['active'] == true;
                final isPrimary = _primaryOutput == name;

                return Card(
                  color: FyrTheme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.monitor,
                              color: FyrTheme.accentColor,
                              size: 40,
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$make $model',
                                    style: TextStyle(
                                      color: FyrTheme.textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: FyrTheme.textColorMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (active)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Set as Primary (Fyr Stack)',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 16,
                              ),
                            ),
                            Radio<String>(
                              value: name,
                              groupValue: _primaryOutput,
                              activeColor: FyrTheme.accentColor,
                              onChanged: (String? value) {
                                if (value != null) _setPrimaryOutput(value);
                              },
                            ),
                          ],
                        ),
                        if (!isPrimary) ...[
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Mirror Primary Display',
                                style: TextStyle(
                                  color: FyrTheme.textColorMuted,
                                  fontSize: 16,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _mirrorDisplay(name),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: FyrTheme.cardColor,
                                ),
                                child: Text(
                                  'Mirror',
                                  style: TextStyle(color: FyrTheme.textColor),
                                ),
                              ),
                            ],
                          ),
                        ],
                        SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Resolution',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 16,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${width}x$height',
                                  style: TextStyle(
                                    color: FyrTheme.textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(width: 16),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    color: FyrTheme.textColorMuted,
                                    size: 20,
                                  ),
                                  onPressed: () => _showResolutionDialog(
                                    name,
                                    width,
                                    height,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        _buildProp('Scale', '${scale}x'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProp(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
        ),
        Text(
          value,
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
