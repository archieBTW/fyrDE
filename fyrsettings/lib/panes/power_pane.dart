import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fyr_theme.dart';

class PowerPane extends StatefulWidget {
  const PowerPane({super.key});

  @override
  State<PowerPane> createState() => _PowerPaneState();
}

class _PowerPaneState extends State<PowerPane> {
  Map<String, String> _powerInfo = {};
  bool _loading = true;

  int _dimMinutes = 0;
  int _offMinutes = 0;
  int _sleepMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadPower();
    _loadSettings();
  }

  Future<void> _loadPower() async {
    setState(() => _loading = true);
    try {
      final enumResult = await Process.run('upower', ['-e']);
      final paths = (enumResult.stdout as String)
          .split('\n')
          .where((l) => l.contains('BAT') || l.contains('DisplayDevice'));

      if (paths.isNotEmpty) {
        final infoResult = await Process.run('upower', ['-i', paths.first]);
        final lines = (infoResult.stdout as String).split('\n');

        final info = <String, String>{};
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            if (key.isNotEmpty && value.isNotEmpty) {
              info[key] = value;
            }
          }
        }
        setState(() {
          _powerInfo = info;
        });
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dimMinutes = prefs.getInt('power_dim_min') ?? 0;
      _offMinutes = prefs.getInt('power_off_min') ?? 0;
      _sleepMinutes = prefs.getInt('power_sleep_min') ?? 0;
    });
  }

  Future<void> _updateSettings({int? dim, int? off, int? sleep}) async {
    setState(() {
      if (dim != null) _dimMinutes = dim;
      if (off != null) _offMinutes = off;
      if (sleep != null) _sleepMinutes = sleep;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('power_dim_min', _dimMinutes);
    await prefs.setInt('power_off_min', _offMinutes);
    await prefs.setInt('power_sleep_min', _sleepMinutes);

    _applySwayIdle();
  }

  Future<void> _applySwayIdle() async {
    await Process.run('killall', ['swayidle']);

    List<String> args = ['-w'];
    if (_dimMinutes > 0) {
      args.addAll([
        'timeout',
        '${_dimMinutes * 60}',
        'brightnessctl -s set 10%',
        'resume',
        'brightnessctl -r',
      ]);
    }
    if (_offMinutes > 0) {
      args.addAll([
        'timeout',
        '${_offMinutes * 60}',
        'swaymsg "output * dpms off"',
        'resume',
        'swaymsg "output * dpms on"',
      ]);
    }
    if (_sleepMinutes > 0) {
      args.addAll(['timeout', '${_sleepMinutes * 60}', 'systemctl suspend']);
    }

    if (args.length > 1) {
      Process.start('swayidle', args);
    }
    final configFile = File(
      '${Platform.environment['HOME']}/.config/sway/config',
    );
    if (await configFile.exists()) {
      var lines = await configFile.readAsLines();
      bool inBlock = false;
      var newLines = <String>[];
      for (var line in lines) {
        if (line == '# POWER SETTINGS') {
          inBlock = true;
          continue;
        }
        if (line == '# END POWER SETTINGS') {
          inBlock = false;
          continue;
        }
        if (!inBlock) {
          newLines.add(line);
        }
      }

      if (args.length > 1) {
        newLines.add('# POWER SETTINGS');
        final cmdStr =
            'exec swayidle ' +
            args.map((a) => a.contains(' ') ? "'\$a'" : a).join(' ');
        newLines.add(cmdStr);
        newLines.add('# END POWER SETTINGS');
      }

      await configFile.writeAsString('${newLines.join('\n')}\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _powerInfo['percentage'] ?? 'Unknown';
    final state = _powerInfo['state'] ?? 'Unknown';
    final timeToEmpty = _powerInfo['time to empty'];
    final timeToFull = _powerInfo['time to full'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Power Management',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: FyrTheme.textColor,
          ),
        ),
        SizedBox(height: 24),

        // Auto-Sleep & Display Settings
        Text(
          'Auto-Sleep & Display',
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        Card(
          color: FyrTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildDropdown(
                  'Dim display after',
                  _dimMinutes,
                  [0, 1, 2, 5, 10, 15, 30],
                  (val) => _updateSettings(dim: val),
                ),
                SizedBox(height: 16),
                _buildDropdown(
                  'Turn off display after',
                  _offMinutes,
                  [0, 2, 5, 10, 15, 30, 60],
                  (val) => _updateSettings(off: val),
                ),
                SizedBox(height: 16),
                _buildDropdown(
                  'Put system to sleep after',
                  _sleepMinutes,
                  [0, 5, 10, 15, 30, 60, 120],
                  (val) => _updateSettings(sleep: val),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 24),
        Text(
          'Battery Status',
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        if (_loading)
          Center(child: CircularProgressIndicator())
        else if (_powerInfo.isEmpty)
          Center(
            child: Text(
              'No battery information found',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          )
        else
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
                    children: [
                      Icon(
                        state.toLowerCase().contains('charging')
                            ? Icons.battery_charging_full
                            : Icons.battery_full,
                        color: FyrTheme.accentColor,
                        size: 40,
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            percentage,
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            state,
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                  if (timeToEmpty != null)
                    _buildProp('Time to empty', timeToEmpty),
                  if (timeToEmpty != null) SizedBox(height: 12),
                  if (timeToFull != null)
                    _buildProp('Time to full', timeToFull),
                  if (timeToFull != null) SizedBox(height: 12),
                  _buildProp('Vendor', _powerInfo['vendor'] ?? 'Unknown'),
                  SizedBox(height: 12),
                  _buildProp('Model', _powerInfo['model'] ?? 'Unknown'),
                  SizedBox(height: 12),
                  _buildProp('Capacity', _powerInfo['capacity'] ?? 'Unknown'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    int currentValue,
    List<int> options,
    ValueChanged<int?> onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
        ),
        DropdownButton<int>(
          value: currentValue,
          dropdownColor: FyrTheme.cardColor,
          style: TextStyle(color: FyrTheme.textColor, fontSize: 16),
          underline: Container(),
          icon: Icon(Icons.arrow_drop_down, color: FyrTheme.accentColor),
          items: options.map((int value) {
            return DropdownMenuItem<int>(
              value: value,
              child: Text(value == 0 ? 'Never' : '$value minutes'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
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
