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
  String _primaryOutput = '';

  @override
  void initState() {
    super.initState();
    _loadDisplays();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _primaryOutput = prefs.getString('primary_output') ?? '';
    });
  }

  Future<void> _setPrimaryOutput(String name) async {
    setState(() => _primaryOutput = name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primary_output', name);

    // Save to ~/.config/fyr/primary_display for fast lookup across Fyr apps
    try {
      final primaryFile = File('${Platform.environment['HOME']}/.config/fyr/primary_display');
      await primaryFile.parent.create(recursive: true);
      await primaryFile.writeAsString(name);
    } catch (_) {}

    final content = StringBuffer()
      ..writeln('# PRIMARY OUTPUT SETTINGS')
      ..writeln('assign [app_id="fyrtaskbar"] output $name')
      ..writeln('assign [app_id="fyrdock"] output $name')
      ..writeln('# END PRIMARY OUTPUT SETTINGS');
    await SwayConfD.removeLegacyMarkerBlock(
      '# PRIMARY OUTPUT SETTINGS',
      '# END PRIMARY OUTPUT SETTINGS',
    );
    await SwayConfD.writeDropIn(
      '20-primary-output.conf',
      content.toString(),
      reload: false,
    );

    await _updateWorkspaceBindings();
    await _restartDesktopStack(name);
  }

  Future<void> _restartDesktopStack(String outputName) async {
    try {
      // 1. Move existing floating/sticky windows to the new output in Sway
      await Process.run('swaymsg', ['[app_id="fyrtaskbar"]', 'move', 'to', 'output', outputName]);
      await Process.run('swaymsg', ['[app_id="fyrtaskbar"]', 'move', 'position', '0', '0']);
      await Process.run('swaymsg', ['[app_id="fyrdock"]', 'move', 'to', 'output', outputName]);

      // 2. Reload Sway config so output assignments and workspace bindings take effect immediately
      await Process.run('swaymsg', ['reload']);

      // 3. Restart fyrtaskbar (bar + desktop layer) and fyrdock so layer-shell
      // surfaces immediately bind to the new primary output across all monitors
      await Process.run('sh', [
        '-c',
        'pkill -x fyrtaskbar 2>/dev/null; pkill -x fyrdock 2>/dev/null; sleep 0.2; '
        '(/opt/fyrtaskbar/fyrtaskbar >/dev/null 2>&1 &); '
        '(/opt/fyrtaskbar/fyrtaskbar --desktop >/dev/null 2>&1 &); '
        '(/opt/fyrdock/fyrdock >/dev/null 2>&1 &); '
        'if pgrep -x fyrdesktop >/dev/null 2>&1; then pkill -x fyrdesktop; (/opt/fyrdesktop/fyrdesktop >/dev/null 2>&1 &); fi'
      ]);
    } catch (e) {
      debugPrint('Error restarting desktop stack: $e');
    }
  }

  Future<void> _updateSwayConfigDisplays() async {
    if (_outputs.isEmpty) return;

    final outputCmds = <String>[];
    for (final out in _outputs) {
      final name = out['name'] ?? 'Unknown';
      final rect = out['rect'] ?? {};
      final w = rect['width'] ?? 1920;
      final h = rect['height'] ?? 1080;
      final x = rect['x'] ?? 0;
      final y = rect['y'] ?? 0;
      outputCmds.add('output $name resolution ${w}x$h position $x $y');
    }

    final content = StringBuffer()
      ..writeln('# DISPLAY OUTPUT SETTINGS')
      ..writeAll(outputCmds.map((c) => '$c\n'))
      ..writeln('# END DISPLAY OUTPUT SETTINGS');

    await SwayConfD.removeLegacyMarkerBlock(
      '# DISPLAY OUTPUT SETTINGS',
      '# END DISPLAY OUTPUT SETTINGS',
    );
    await SwayConfD.writeDropIn(
      '22-displays.conf',
      content.toString(),
      reload: false,
    );
  }

  Future<void> _updateWorkspaceBindings() async {
    if (_outputs.isEmpty) return;

    final workspaceCmds = <String>[];
    for (var w = 1; w <= 9; w++) {
      final monitorIndex = (w - 1) % _outputs.length;
      final outputName = _outputs[monitorIndex]['name'];
      workspaceCmds.add('workspace $w output $outputName');
      await Process.run('swaymsg', ['workspace', '$w', 'output', outputName]);
    }

    final content = StringBuffer()
      ..writeln('# WORKSPACE BINDINGS')
      ..writeAll(workspaceCmds.map((c) => '$c\n'))
      ..writeln('# END WORKSPACE BINDINGS');

    await SwayConfD.removeLegacyMarkerBlock(
      '# WORKSPACE BINDINGS',
      '# END WORKSPACE BINDINGS',
    );
    await SwayConfD.writeDropIn(
      '21-workspaces.conf',
      content.toString(),
      reload: false,
    );
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
        await _updateSwayConfigDisplays();
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
    await _updateSwayConfigDisplays();
    await Process.run('swaymsg', ['reload']);
    if (_primaryOutput.isNotEmpty) {
      await _restartDesktopStack(_primaryOutput);
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
      await _updateSwayConfigDisplays();
      await Process.run('swaymsg', ['reload']);
      if (_primaryOutput == outputName || _primaryOutput.isEmpty) {
        await _restartDesktopStack(_primaryOutput.isNotEmpty ? _primaryOutput : outputName);
      }
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
        await _updateSwayConfigDisplays();
        await Process.run('swaymsg', ['reload']);
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
                    side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
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
