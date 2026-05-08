import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

class SoundPane extends StatefulWidget {
  const SoundPane({super.key});

  @override
  State<SoundPane> createState() => _SoundPaneState();
}

class _SoundPaneState extends State<SoundPane> {
  double _outputVolume = 50;
  bool _outputMuted = false;
  double _inputVolume = 50;
  bool _inputMuted = false;

  @override
  void initState() {
    super.initState();
    _loadSoundSettings();
  }

  Future<void> _loadSoundSettings() async {
    try {
      // Get Output Volume
      final outVol = await Process.run('pamixer', ['--get-volume']);
      if (outVol.exitCode == 0) {
        setState(() => _outputVolume = double.tryParse(outVol.stdout.trim()) ?? 50);
      }

      // Get Output Mute
      final outMute = await Process.run('pamixer', ['--get-mute']);
      if (outMute.exitCode == 0) {
        setState(() => _outputMuted = outMute.stdout.trim() == 'true');
      }

      // Get Input Volume (Default Source)
      final inVol = await Process.run('pamixer', ['--default-source', '--get-volume']);
      if (inVol.exitCode == 0) {
        setState(() => _inputVolume = double.tryParse(inVol.stdout.trim()) ?? 50);
      }

      // Get Input Mute
      final inMute = await Process.run('pamixer', ['--default-source', '--get-mute']);
      if (inMute.exitCode == 0) {
        setState(() => _inputMuted = inMute.stdout.trim() == 'true');
      }
    } catch (e) {
      debugPrint('Error loading sound settings: $e');
    }
  }

  Future<void> _setOutputVolume(double value) async {
    setState(() => _outputVolume = value);
    await Process.run('pamixer', ['--set-volume', value.round().toString()]);
  }

  Future<void> _toggleOutputMute() async {
    if (_outputMuted) {
      await Process.run('pamixer', ['--unmute']);
    } else {
      await Process.run('pamixer', ['--mute']);
    }
    setState(() => _outputMuted = !_outputMuted);
  }

  Future<void> _setInputVolume(double value) async {
    setState(() => _inputVolume = value);
    await Process.run('pamixer', ['--default-source', '--set-volume', value.round().toString()]);
  }

  Future<void> _toggleInputMute() async {
    if (_inputMuted) {
      await Process.run('pamixer', ['--default-source', '--unmute']);
    } else {
      await Process.run('pamixer', ['--default-source', '--mute']);
    }
    setState(() => _inputMuted = !_inputMuted);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sound Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: FyrTheme.textColor,
            ),
          ),
          const SizedBox(height: 32),
          
          _buildSectionCard(
            title: 'Output (Speakers)',
            icon: _outputMuted ? Icons.volume_off : Icons.volume_up,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _outputVolume,
                        min: 0,
                        max: 100,
                        activeColor: FyrTheme.accentColor,
                        onChanged: _setOutputVolume,
                      ),
                    ),
                    Text(
                      '${_outputVolume.round()}%',
                      style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ListTile(
                  title: Text('Mute Output', style: TextStyle(color: FyrTheme.textColor)),
                  trailing: Switch(
                    value: _outputMuted,
                    activeColor: FyrTheme.accentColor,
                    onChanged: (v) => _toggleOutputMute(),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          _buildSectionCard(
            title: 'Input (Microphone)',
            icon: _inputMuted ? Icons.mic_off : Icons.mic,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _inputVolume,
                        min: 0,
                        max: 100,
                        activeColor: FyrTheme.accentColor,
                        onChanged: _setInputVolume,
                      ),
                    ),
                    Text(
                      '${_inputVolume.round()}%',
                      style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ListTile(
                  title: Text('Mute Microphone', style: TextStyle(color: FyrTheme.textColor)),
                  trailing: Switch(
                    value: _inputMuted,
                    activeColor: FyrTheme.accentColor,
                    onChanged: (v) => _toggleInputMute(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadSoundSettings,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Audio Status'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Card(
      color: FyrTheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: FyrTheme.accentColor, size: 28),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
