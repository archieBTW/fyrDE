import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fyr_theme.dart';

class DisplayModeOption {
  final int width;
  final int height;
  final int refreshMHz;

  const DisplayModeOption({
    required this.width,
    required this.height,
    required this.refreshMHz,
  });

  String get resolutionKey => '${width}x$height';
  double get refreshHz => refreshMHz / 1000.0;

  String get formattedRefresh {
    if (refreshMHz <= 0) return 'Auto';
    final hz = refreshHz;
    if ((hz - hz.round()).abs() < 0.05) {
      return '${hz.round()} Hz';
    }
    return '${hz.toStringAsFixed(2)} Hz';
  }

  String get swayModeArg {
    if (refreshMHz <= 0) return resolutionKey;
    return '$resolutionKey@${refreshHz.toStringAsFixed(3)}Hz';
  }
}

List<DisplayModeOption> parseOutputModes(Map<String, dynamic> output) {
  final rawModes = output['modes'];
  if (rawModes is! List) return const [];
  final seen = <String>{};
  final modes = <DisplayModeOption>[];
  for (final m in rawModes) {
    if (m is! Map) continue;
    final w = (m['width'] as num?)?.toInt() ?? 0;
    final h = (m['height'] as num?)?.toInt() ?? 0;
    final r = (m['refresh'] as num?)?.toInt() ?? 0;
    if (w <= 0 || h <= 0) continue;
    final key = '${w}x$h@$r';
    if (seen.add(key)) {
      modes.add(DisplayModeOption(width: w, height: h, refreshMHz: r));
    }
  }
  modes.sort((a, b) {
    final areaCmp = (b.width * b.height).compareTo(a.width * a.height);
    if (areaCmp != 0) return areaCmp;
    return b.refreshMHz.compareTo(a.refreshMHz);
  });
  return modes;
}

DisplayModeOption currentModeForOutput(Map<String, dynamic> output) {
  final cm = output['current_mode'];
  if (cm is Map) {
    final w = (cm['width'] as num?)?.toInt() ?? 0;
    final h = (cm['height'] as num?)?.toInt() ?? 0;
    final r = (cm['refresh'] as num?)?.toInt() ?? 0;
    if (w > 0 && h > 0) {
      return DisplayModeOption(width: w, height: h, refreshMHz: r);
    }
  }
  final rect = output['rect'];
  final w = (rect is Map ? (rect['width'] as num?)?.toInt() : null) ?? 1920;
  final h = (rect is Map ? (rect['height'] as num?)?.toInt() : null) ?? 1080;
  return DisplayModeOption(width: w, height: h, refreshMHz: 0);
}

List<String> uniqueResolutionsForModes(
  List<DisplayModeOption> modes,
  DisplayModeOption current,
) {
  final list = <String>[];
  for (final m in modes) {
    if (!list.contains(m.resolutionKey)) {
      list.add(m.resolutionKey);
    }
  }
  if (!list.contains(current.resolutionKey)) {
    list.insert(0, current.resolutionKey);
  }
  return list;
}

List<DisplayModeOption> refreshModesForResolution(
  List<DisplayModeOption> modes,
  String resolutionKey,
  DisplayModeOption current,
) {
  final matching =
      modes.where((m) => m.resolutionKey == resolutionKey).toList()
        ..sort((a, b) => b.refreshMHz.compareTo(a.refreshMHz));
  if (current.resolutionKey == resolutionKey &&
      !matching.any((m) => m.refreshMHz == current.refreshMHz)) {
    matching.add(current);
    matching.sort((a, b) => b.refreshMHz.compareTo(a.refreshMHz));
  }
  return matching;
}

String buildSwayOutputConfigLine(Map<String, dynamic> out) {
  final name = out['name']?.toString() ?? 'Unknown';
  final rect = (out['rect'] is Map) ? out['rect'] as Map : const {};
  final x = (rect['x'] as num?)?.toInt() ?? 0;
  final y = (rect['y'] as num?)?.toInt() ?? 0;
  final mode = currentModeForOutput(out);
  final scale = (out['scale'] as num?)?.toDouble() ?? 1.0;
  final transform = (out['transform']?.toString() ?? 'normal').trim();
  final vrr = out['adaptive_sync_status']?.toString() == 'enabled';

  final scaleStr = scale == scale.roundToDouble()
      ? scale.toStringAsFixed(0)
      : scale.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  final parts = <String>[
    'output',
    name,
    'mode',
    mode.swayModeArg,
    'position',
    '$x',
    '$y',
    'scale',
    scaleStr,
    'transform',
    transform.isEmpty ? 'normal' : transform,
    'adaptive_sync',
    vrr ? 'on' : 'off',
  ];
  return parts.join(' ');
}

const List<double> kStandardDisplayScales = [1.0, 1.25, 1.5, 1.75, 2.0];

const Map<String, String> kDisplayTransforms = {
  'normal': 'Normal (0°)',
  '90': '90° Clockwise',
  '180': '180° Flipped',
  '270': '270° Counter-Clockwise',
};

class DisplayPane extends StatefulWidget {
  const DisplayPane({super.key});

  @override
  State<DisplayPane> createState() => _DisplayPaneState();
}

class _DisplayPaneState extends State<DisplayPane> {
  List<Map<String, dynamic>> _outputs = [];
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
    if (!mounted) return;
    setState(() {
      _primaryOutput = prefs.getString('primary_output') ?? '';
    });
  }

  Future<void> _setPrimaryOutput(String name) async {
    setState(() => _primaryOutput = name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primary_output', name);

    try {
      final primaryFile = File(
        '${Platform.environment['HOME']}/.config/fyr/primary_display',
      );
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
      await Process.run('swaymsg', [
        '[app_id="fyrtaskbar"]',
        'move',
        'to',
        'output',
        outputName,
      ]);
      await Process.run('swaymsg', [
        '[app_id="fyrtaskbar"]',
        'move',
        'position',
        '0',
        '0',
      ]);
      await Process.run('swaymsg', [
        '[app_id="fyrdock"]',
        'move',
        'to',
        'output',
        outputName,
      ]);

      await Process.run('swaymsg', ['reload']);

      await Process.run('sh', [
        '-c',
        'pkill -x fyrtaskbar 2>/dev/null; pkill -x fyrdock 2>/dev/null; sleep 0.2; '
            '(/opt/fyrtaskbar/fyrtaskbar >/dev/null 2>&1 &); '
            '(/opt/fyrtaskbar/fyrtaskbar --desktop >/dev/null 2>&1 &); '
            '(/opt/fyrdock/fyrdock >/dev/null 2>&1 &); '
            'if pgrep -x fyrdesktop >/dev/null 2>&1; then pkill -x fyrdesktop; (/opt/fyrdesktop/fyrdesktop >/dev/null 2>&1 &); fi',
      ]);
    } catch (e) {
      debugPrint('Error restarting desktop stack: $e');
    }
  }

  Future<void> _updateSwayConfigDisplays() async {
    if (_outputs.isEmpty) return;

    final outputCmds = _outputs.map(buildSwayOutputConfigLine).toList();

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

  Future<void> _loadDisplays({bool writeConfig = false}) async {
    if (_outputs.isEmpty && mounted) setState(() => _loading = true);
    try {
      final result = await Process.run('swaymsg', ['-t', 'get_outputs']);
      if (result.exitCode == 0) {
        final List<dynamic> decoded = jsonDecode(result.stdout);
        final outputs = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        outputs.sort(
          (a, b) => ((a['rect']?['x'] as num?) ?? 0).compareTo(
            (b['rect']?['x'] as num?) ?? 0,
          ),
        );
        if (!mounted) return;
        setState(() {
          _outputs = outputs;
          if (_primaryOutput.isEmpty && outputs.isNotEmpty) {
            _primaryOutput = outputs.first['name']?.toString() ?? '';
          }
        });
        if (writeConfig) {
          await _updateWorkspaceBindings();
          await _updateSwayConfigDisplays();
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyOutputCommand(
    String outputName,
    List<String> swayArgs, {
    bool restartStack = false,
  }) async {
    try {
      await Process.run('swaymsg', ['output', outputName, ...swayArgs]);
      await _loadDisplays(writeConfig: true);
      if (restartStack &&
          (_primaryOutput == outputName || _primaryOutput.isEmpty)) {
        await _restartDesktopStack(
          _primaryOutput.isNotEmpty ? _primaryOutput : outputName,
        );
      }
    } catch (e) {
      debugPrint('Error applying output command: $e');
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
      final name = out['name']?.toString() ?? 'Unknown';
      final rect = out['rect'] ?? {};
      final width = (rect['width'] as num?)?.toInt() ?? 1920;
      await Process.run('swaymsg', ['output', name, 'pos', '$currentX', '0']);
      currentX += width;
    }
    await _loadDisplays(writeConfig: true);
    if (_primaryOutput.isNotEmpty) {
      await _restartDesktopStack(_primaryOutput);
    }
  }

  Future<void> _changeMode(String outputName, DisplayModeOption mode) async {
    await _applyOutputCommand(
      outputName,
      ['mode', mode.swayModeArg],
      restartStack: true,
    );
  }

  Future<void> _changeResolution(
    String outputName,
    String width,
    String height,
  ) async {
    final w = int.tryParse(width.trim());
    final h = int.tryParse(height.trim());
    if (w == null || h == null || w <= 0 || h <= 0) return;
    await _applyOutputCommand(
      outputName,
      ['resolution', '${w}x$h'],
      restartStack: true,
    );
  }

  Future<void> _changeScale(String outputName, double scale) async {
    final scaleStr = scale == scale.roundToDouble()
        ? scale.toStringAsFixed(0)
        : scale.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    await _applyOutputCommand(
      outputName,
      ['scale', scaleStr],
      restartStack: true,
    );
  }

  Future<void> _changeTransform(String outputName, String transform) async {
    await _applyOutputCommand(
      outputName,
      ['transform', transform],
      restartStack: true,
    );
  }

  Future<void> _toggleAdaptiveSync(String outputName, bool enabled) async {
    await _applyOutputCommand(
      outputName,
      ['adaptive_sync', enabled ? 'on' : 'off'],
    );
  }

  Future<void> _mirrorDisplay(String outputName) async {
    if (_primaryOutput.isEmpty || _primaryOutput == outputName) return;
    try {
      final primary = _outputs.firstWhere(
        (o) => o['name'] == _primaryOutput,
        orElse: () => <String, dynamic>{},
      );
      if (primary.isNotEmpty) {
        final rect = primary['rect'];
        await _applyOutputCommand(outputName, [
          'pos',
          '${rect['x']}',
          '${rect['y']}',
        ]);
      }
    } catch (_) {}
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
            'Custom Resolution for $outputName',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: wController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Width',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                  style: TextStyle(color: FyrTheme.textColor),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('x', style: TextStyle(color: FyrTheme.textColor)),
              ),
              Expanded(
                child: TextField(
                  controller: hController,
                  keyboardType: TextInputType.number,
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

  Widget _buildDropdownContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.panelBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Displays & Appearance',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: FyrTheme.textColor,
                ),
              ),
              IconButton(
                tooltip: 'Refresh Displays',
                onPressed: () => _loadDisplays(),
                icon: Icon(Icons.refresh, color: FyrTheme.textColorMuted),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Monitors (Drag to Arrange)',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          if (_loading && _outputs.isEmpty)
            const Center(child: CircularProgressIndicator())
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
                  final name = out['name']?.toString() ?? 'Unknown';
                  final mode = currentModeForOutput(out);
                  return Container(
                    key: ValueKey(name),
                    margin: const EdgeInsets.only(right: 16),
                    width: 170,
                    decoration: BoxDecoration(
                      color: FyrTheme.accentColor.withOpacity(0.25),
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
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${mode.resolutionKey} • ${mode.formattedRefresh}',
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 11,
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
                final name = out['name']?.toString() ?? 'Unknown';
                final make = out['make']?.toString() ?? 'Unknown';
                final model = out['model']?.toString() ?? 'Unknown';
                final active = out['active'] == true;
                final isPrimary = _primaryOutput == name;

                final modes = parseOutputModes(out);
                final currentMode = currentModeForOutput(out);
                final resolutionOptions = uniqueResolutionsForModes(
                  modes,
                  currentMode,
                );
                final refreshOptions = refreshModesForResolution(
                  modes,
                  currentMode.resolutionKey,
                  currentMode,
                );

                final currentScale =
                    (out['scale'] as num?)?.toDouble() ?? 1.0;
                final scaleOptions = <double>[...kStandardDisplayScales];
                if (!scaleOptions.any((s) => (s - currentScale).abs() < 0.01)) {
                  scaleOptions.add(currentScale);
                  scaleOptions.sort();
                }
                final selectedScale = scaleOptions.firstWhere(
                  (s) => (s - currentScale).abs() < 0.01,
                  orElse: () => 1.0,
                );

                final rawTransform =
                    (out['transform']?.toString() ?? 'normal').trim();
                final transformOptions = Map<String, String>.from(
                  kDisplayTransforms,
                );
                if (!transformOptions.containsKey(rawTransform)) {
                  transformOptions[rawTransform] = rawTransform;
                }

                final vrrEnabled =
                    out['adaptive_sync_status']?.toString() == 'enabled';

                return Card(
                  color: FyrTheme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: FyrTheme.isDark
                        ? BorderSide.none
                        : BorderSide(color: FyrTheme.dividerColor),
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
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
                            const SizedBox(width: 16),
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
                            Text(
                              'Set as Primary (Fyr Stack)',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 15,
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
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Mirror Primary Display',
                                style: TextStyle(
                                  color: FyrTheme.textColorMuted,
                                  fontSize: 15,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _mirrorDisplay(name),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: FyrTheme.panelBgColor,
                                ),
                                child: Text(
                                  'Mirror',
                                  style: TextStyle(color: FyrTheme.textColor),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Resolution',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 15,
                              ),
                            ),
                            Row(
                              children: [
                                _buildDropdownContainer(
                                  child: DropdownButton<String>(
                                    value: currentMode.resolutionKey,
                                    dropdownColor: FyrTheme.cardColor,
                                    style: TextStyle(
                                      color: FyrTheme.textColor,
                                      fontSize: 14,
                                    ),
                                    items: resolutionOptions
                                        .map(
                                          (res) => DropdownMenuItem<String>(
                                            value: res,
                                            child: Text(res),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (selectedRes) {
                                      if (selectedRes == null) return;
                                      final bestForRes =
                                          refreshModesForResolution(
                                            modes,
                                            selectedRes,
                                            currentMode,
                                          );
                                      if (bestForRes.isNotEmpty) {
                                        _changeMode(name, bestForRes.first);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Custom Resolution',
                                  icon: Icon(
                                    Icons.edit,
                                    color: FyrTheme.textColorMuted,
                                    size: 18,
                                  ),
                                  onPressed: () => _showResolutionDialog(
                                    name,
                                    currentMode.width,
                                    currentMode.height,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Refresh Rate',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 15,
                              ),
                            ),
                            _buildDropdownContainer(
                              child: DropdownButton<int>(
                                value: currentMode.refreshMHz,
                                dropdownColor: FyrTheme.cardColor,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 14,
                                ),
                                items: refreshOptions
                                    .map(
                                      (m) => DropdownMenuItem<int>(
                                        value: m.refreshMHz,
                                        child: Text(m.formattedRefresh),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (selectedMHz) {
                                  if (selectedMHz == null) return;
                                  final mode = refreshOptions.firstWhere(
                                    (m) => m.refreshMHz == selectedMHz,
                                    orElse: () => currentMode,
                                  );
                                  _changeMode(name, mode);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Scale',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 15,
                              ),
                            ),
                            _buildDropdownContainer(
                              child: DropdownButton<double>(
                                value: selectedScale,
                                dropdownColor: FyrTheme.cardColor,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 14,
                                ),
                                items: scaleOptions
                                    .map(
                                      (s) => DropdownMenuItem<double>(
                                        value: s,
                                        child: Text(
                                          '${(s * 100).round()}% (${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(2).replaceFirst(RegExp(r"0+$"), "")}x)',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (s) {
                                  if (s != null) _changeScale(name, s);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Orientation',
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 15,
                              ),
                            ),
                            _buildDropdownContainer(
                              child: DropdownButton<String>(
                                value: rawTransform,
                                dropdownColor: FyrTheme.cardColor,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 14,
                                ),
                                items: transformOptions.entries
                                    .map(
                                      (e) => DropdownMenuItem<String>(
                                        value: e.key,
                                        child: Text(e.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (t) {
                                  if (t != null) _changeTransform(name, t);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Adaptive Sync (VRR)',
                                  style: TextStyle(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'FreeSync / G-Sync variable refresh rate',
                                  style: TextStyle(
                                    color: FyrTheme.textColorMuted.withOpacity(
                                      0.7,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: vrrEnabled,
                              activeColor: FyrTheme.accentColor,
                              onChanged: (val) =>
                                  _toggleAdaptiveSync(name, val),
                            ),
                          ],
                        ),
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
}
