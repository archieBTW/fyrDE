import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    for (final app in ['fyrtaskbar', 'fyrdock', 'fyrsearch', 'fyroverview']) {
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
      newLines.add('assign [app_id="(?i).*fyrsearch.*"] output $name');
      newLines.add('assign [app_id="fyroverview"] output $name');
      newLines.add('# END PRIMARY OUTPUT SETTINGS');
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
          backgroundColor: const Color(0xFF2E2E2E),
          title: Text(
            'Resolution for $outputName',
            style: const TextStyle(color: Colors.white),
          ),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: wController,
                  decoration: const InputDecoration(
                    labelText: 'Width',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('x', style: TextStyle(color: Colors.white)),
              ),
              Expanded(
                child: TextField(
                  controller: hController,
                  decoration: const InputDecoration(
                    labelText: 'Height',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
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
              child: const Text(
                'Apply',
                style: TextStyle(color: Colors.purpleAccent),
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
          const Text(
            'Displays & Appearance',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          Card(
            color: Colors.white.withOpacity(0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Desktop Background',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedBgPath.isNotEmpty)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 360),
                        margin: const EdgeInsets.only(bottom: 16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.purpleAccent,
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
                    const SizedBox(height: 24),
                    const Text(
                      'Default Backgrounds',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
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
                                            ? Colors.purpleAccent
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
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () => _scrollBackgrounds(true),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open, color: Colors.white),
                      label: const Text(
                        'Browse Files...',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: _pickBackground,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(
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

          const SizedBox(height: 24),
          const Text(
            'Monitors (Drag to Arrange)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          if (_loading && _outputs.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_outputs.isEmpty)
            const Center(
              child: Text(
                'No displays found',
                style: TextStyle(color: Colors.white70),
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
                    margin: const EdgeInsets.only(right: 16),
                    width: 160,
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purpleAccent, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.monitor,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
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
            const SizedBox(height: 24),
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
                  color: Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.monitor,
                              color: Colors.purpleAccent,
                              size: 40,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$make $model',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (active)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Set as Primary (Fyr Stack)',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            Radio<String>(
                              value: name,
                              groupValue: _primaryOutput,
                              activeColor: Colors.purpleAccent,
                              onChanged: (String? value) {
                                if (value != null) _setPrimaryOutput(value);
                              },
                            ),
                          ],
                        ),
                        if (!isPrimary) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Mirror Primary Display',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _mirrorDisplay(name),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white12,
                                ),
                                child: const Text(
                                  'Mirror',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Resolution',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${width}x$height',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white54,
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
                        const SizedBox(height: 12),
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
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
