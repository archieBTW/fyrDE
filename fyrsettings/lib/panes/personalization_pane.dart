import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fyr_theme.dart';

class PersonalizationPane extends StatefulWidget {
  const PersonalizationPane({super.key});

  @override
  State<PersonalizationPane> createState() => _PersonalizationPaneState();
}

class _PersonalizationPaneState extends State<PersonalizationPane> {
  String _bgPath = '';
  String _selectedBgPath = '';
  List<String> _defaultBackgrounds = [];
  final ScrollController _bgScrollController = ScrollController();
  bool _pullColorFromBg = true;

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
    _loadSettings();
    _loadDefaultBackgrounds();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgPath = prefs.getString('bg_path') ?? '';
      _selectedBgPath = _bgPath;
      _pullColorFromBg = prefs.getBool('pull_color_from_bg') ?? true;
    });
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
        final tempFile = File('${configFile.path}.tmp');
        await tempFile.writeAsString('${newLines.join('\n')}\n');
        await tempFile.rename(configFile.path);
      }

      if (_pullColorFromBg) {
        _extractAndApplyColorFromBg(path);
      }
    } catch (e) {}
  }

  Future<void> _extractAndApplyColorFromBg(String path) async {
    try {
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: FileImage(File(path)),
      );
      FyrTheme.setAccentColor(colorScheme.primary);
    } catch (e) {
      // Ignore extraction error
    }
  }

  void _onTogglePullColor(bool? value) async {
    if (value != null) {
      setState(() {
        _pullColorFromBg = value;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pull_color_from_bg', value);
      
      if (value && _selectedBgPath.isNotEmpty) {
        _extractAndApplyColorFromBg(_selectedBgPath);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personalization',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Accent Color',
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Pull from Background',
                            style: TextStyle(color: FyrTheme.textColorMuted),
                          ),
                          Switch(
                            value: _pullColorFromBg,
                            onChanged: _onTogglePullColor,
                            activeColor: FyrTheme.accentColor,
                          ),
                        ],
                      )
                    ],
                  ),
                  SizedBox(height: 16),
                  ValueListenableBuilder<Color>(
                    valueListenable: FyrTheme.accentColorNotifier,
                    builder: (context, color, child) {
                      return AbsorbPointer(
                        absorbing: _pullColorFromBg,
                        child: Opacity(
                          opacity: _pullColorFromBg ? 0.5 : 1.0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: FyrTheme.textColor, width: 2),
                                ),
                              ),
                              SizedBox(height: 16),
                              _buildColorSlider('Red', color.red, Colors.red, (val) {
                                FyrTheme.accentColorNotifier.value = Color.fromARGB(255, val.toInt(), color.green, color.blue);
                              }, (val) {
                                FyrTheme.setAccentColor(Color.fromARGB(255, val.toInt(), color.green, color.blue));
                              }),
                              _buildColorSlider('Green', color.green, Colors.green, (val) {
                                FyrTheme.accentColorNotifier.value = Color.fromARGB(255, color.red, val.toInt(), color.blue);
                              }, (val) {
                                FyrTheme.setAccentColor(Color.fromARGB(255, color.red, val.toInt(), color.blue));
                              }),
                              _buildColorSlider('Blue', color.blue, Colors.blue, (val) {
                                FyrTheme.accentColorNotifier.value = Color.fromARGB(255, color.red, color.green, val.toInt());
                              }, (val) {
                                FyrTheme.setAccentColor(Color.fromARGB(255, color.red, color.green, val.toInt()));
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSlider(String label, int value, Color activeColor, ValueChanged<double> onChanged, ValueChanged<double> onChangeEnd) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(color: FyrTheme.textColor),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: activeColor,
            inactiveColor: activeColor.withOpacity(0.3),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            style: TextStyle(color: FyrTheme.textColorMuted),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
