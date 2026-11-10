import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

class AudioDevice {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDefault;
  final String? cardName;
  final String? profileName;
  final bool isCardProfile;

  AudioDevice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isDefault = false,
    this.cardName,
    this.profileName,
    this.isCardProfile = false,
  });
}

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

  List<AudioDevice> _outputDevices = [];
  List<AudioDevice> _inputDevices = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadSoundSettings();
    // Auto-detect plugged-in devices (e.g. HDMI, USB, Bluetooth) dynamically
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _loadSoundSettings(isBackground: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSoundSettings({bool isBackground = false}) async {
    if (!isBackground && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      // 1. Get Volumes & Mutes
      final outVol = await Process.run('pamixer', ['--get-volume']);
      if (outVol.exitCode == 0) {
        final val = double.tryParse(outVol.stdout.trim());
        if (val != null) _outputVolume = val;
      }

      final outMute = await Process.run('pamixer', ['--get-mute']);
      if (outMute.exitCode == 0) {
        _outputMuted = outMute.stdout.trim() == 'true';
      }

      final inVol = await Process.run('pamixer', ['--default-source', '--get-volume']);
      if (inVol.exitCode == 0) {
        final val = double.tryParse(inVol.stdout.trim());
        if (val != null) _inputVolume = val;
      }

      final inMute = await Process.run('pamixer', ['--default-source', '--get-mute']);
      if (inMute.exitCode == 0) {
        _inputMuted = inMute.stdout.trim() == 'true';
      }

      // 2. Query default sink and source
      final defaultSinkRes = await Process.run('pactl', ['get-default-sink']);
      final defaultSourceRes = await Process.run('pactl', ['get-default-source']);
      final currentDefaultSink = defaultSinkRes.stdout.toString().trim();
      final currentDefaultSource = defaultSourceRes.stdout.toString().trim();

      // 3. Query pactl sinks, sources, cards
      final sinksRes = await Process.run('pactl', ['-f', 'json', 'list', 'sinks']);
      final sourcesRes = await Process.run('pactl', ['-f', 'json', 'list', 'sources']);
      final cardsRes = await Process.run('pactl', ['-f', 'json', 'list', 'cards']);

      List<dynamic> sinks = [];
      List<dynamic> sources = [];
      List<dynamic> cards = [];

      if (sinksRes.exitCode == 0 && sinksRes.stdout.toString().trim().isNotEmpty) {
        try {
          sinks = jsonDecode(sinksRes.stdout.toString());
        } catch (_) {}
      }
      if (sourcesRes.exitCode == 0 && sourcesRes.stdout.toString().trim().isNotEmpty) {
        try {
          sources = jsonDecode(sourcesRes.stdout.toString());
        } catch (_) {}
      }
      if (cardsRes.exitCode == 0 && cardsRes.stdout.toString().trim().isNotEmpty) {
        try {
          cards = jsonDecode(cardsRes.stdout.toString());
        } catch (_) {}
      }

      // Build Output Devices List
      List<AudioDevice> outputDevices = [];
      Set<String> seenDeviceNames = {};

      for (final sink in sinks) {
        final name = sink['name']?.toString() ?? '';
        final desc = sink['description']?.toString() ?? name;
        final activePort = sink['active_port']?.toString() ?? '';
        final isDefault = (name == currentDefaultSink);

        IconData icon = Icons.speaker;
        String displayTitle = desc;

        if (name.toLowerCase().contains('hdmi') || desc.toLowerCase().contains('hdmi')) {
          icon = Icons.tv;
          displayTitle = 'HDMI / DisplayPort Audio';
        } else if (activePort.contains('headphone') || desc.toLowerCase().contains('headphone')) {
          icon = Icons.headphones;
          displayTitle = 'Headphones';
        } else if (name.toLowerCase().contains('bluez') || desc.toLowerCase().contains('bluetooth')) {
          icon = Icons.bluetooth_audio;
          displayTitle = 'Bluetooth ($desc)';
        } else if (name.toLowerCase().contains('usb') || desc.toLowerCase().contains('usb')) {
          icon = Icons.usb;
          displayTitle = 'USB Audio ($desc)';
        } else if (activePort.contains('speaker')) {
          icon = Icons.speaker;
          displayTitle = 'Speakers';
        }

        outputDevices.add(AudioDevice(
          id: name,
          title: displayTitle,
          subtitle: desc,
          icon: icon,
          isDefault: isDefault,
        ));
        seenDeviceNames.add(name);
      }

      // Inspect cards for HDMI ports/profiles and analog fallback
      for (final card in cards) {
        final cardName = card['name']?.toString() ?? '';
        final activeProfile = card['active_profile']?.toString() ?? '';
        final cardDesc = card['properties']?['device.description']?.toString() ?? 'Built-in Audio';
        final Map<String, dynamic> ports = card['ports'] is Map ? Map<String, dynamic>.from(card['ports']) : {};
        final Map<String, dynamic> profiles = card['profiles'] is Map ? Map<String, dynamic>.from(card['profiles']) : {};

        // 1. Detect connected HDMI ports (auto-detected when HDMI is plugged in)
        for (final entry in ports.entries) {
          final portName = entry.key;
          final portData = entry.value is Map ? Map<String, dynamic>.from(entry.value) : <String, dynamic>{};
          final portType = portData['type']?.toString() ?? '';
          final portAvail = portData['availability']?.toString() ?? '';
          final portDesc = portData['description']?.toString() ?? 'HDMI / DisplayPort';

          final isHdmi = portType == 'HDMI' || portName.contains('hdmi') || portDesc.toLowerCase().contains('hdmi');
          final isConnected = (portAvail != 'not available');

          if (isHdmi && isConnected) {
            // Check if there is already an active sink for this HDMI port/card
            final cleanCardId = cardName.replaceAll('alsa_card.', '');
            bool alreadyInSinks = outputDevices.any((d) => d.id.contains('hdmi') && d.id.contains(cleanCardId));
            if (!alreadyInSinks) {
              final portProfiles = (portData['profiles'] as List?)?.cast<String>() ?? [];
              String targetProfile = portProfiles.firstWhere(
                (p) => p.contains('stereo') && p.contains('input:'),
                orElse: () => portProfiles.firstWhere(
                  (p) => p.contains('stereo'),
                  orElse: () => portProfiles.isNotEmpty ? portProfiles.first : 'output:hdmi-stereo',
                ),
              );

              final isCardActiveOnThis = (activeProfile == targetProfile);
              outputDevices.add(AudioDevice(
                id: '$cardName:$targetProfile',
                title: '$portDesc ($cardDesc)',
                subtitle: 'Digital Audio via HDMI/DisplayPort (Connected)',
                icon: Icons.tv,
                isDefault: isCardActiveOnThis,
                cardName: cardName,
                profileName: targetProfile,
                isCardProfile: true,
              ));
            }
          }
        }

        // 2. If card is currently switched to HDMI, ensure Analog Speakers is available to switch back
        if (activeProfile.contains('hdmi')) {
          final analogProfile = profiles.keys.firstWhere(
            (p) => p.startsWith('output:analog-stereo'),
            orElse: () => 'output:analog-stereo+input:analog-stereo',
          );
          bool hasAnalogSink = outputDevices.any((d) => d.id.contains('analog-stereo'));
          if (!hasAnalogSink) {
            outputDevices.add(AudioDevice(
              id: '$cardName:$analogProfile',
              title: 'Speakers ($cardDesc)',
              subtitle: 'Built-in Analog Audio',
              icon: Icons.speaker,
              isDefault: false,
              cardName: cardName,
              profileName: analogProfile,
              isCardProfile: true,
            ));
          }
        }
      }

      // Build Input Sources List
      List<AudioDevice> inputDevices = [];
      for (final src in sources) {
        final name = src['name']?.toString() ?? '';
        if (name.contains('.monitor')) continue;

        final desc = src['description']?.toString() ?? name;
        final activePort = src['active_port']?.toString() ?? '';
        final isDefault = (name == currentDefaultSource);

        IconData icon = Icons.mic;
        String displayTitle = desc;

        if (activePort.contains('headphone') || activePort.contains('headset') || desc.toLowerCase().contains('headset')) {
          icon = Icons.headset_mic;
          displayTitle = 'Headset Microphone';
        } else if (activePort.contains('internal') || desc.toLowerCase().contains('internal')) {
          icon = Icons.mic;
          displayTitle = 'Internal Microphone';
        } else if (name.toLowerCase().contains('usb') || desc.toLowerCase().contains('usb')) {
          icon = Icons.mic;
          displayTitle = 'USB Microphone';
        }

        inputDevices.add(AudioDevice(
          id: name,
          title: displayTitle,
          subtitle: desc,
          icon: icon,
          isDefault: isDefault,
        ));
      }

      if (mounted) {
        setState(() {
          _outputDevices = outputDevices;
          _inputDevices = inputDevices;
        });
      }
    } catch (e) {
      debugPrint('Error loading sound settings: $e');
    } finally {
      if (!isBackground && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectOutputDevice(AudioDevice device) async {
    try {
      if (device.isCardProfile && device.cardName != null && device.profileName != null) {
        // 1. Switch ALSA card profile to HDMI or Analog
        await Process.run('pactl', ['set-card-profile', device.cardName!, device.profileName!]);
        await Future.delayed(const Duration(milliseconds: 150));

        // 2. Discover newly activated sink
        final sinksRes = await Process.run('pactl', ['-f', 'json', 'list', 'sinks']);
        if (sinksRes.exitCode == 0 && sinksRes.stdout.toString().trim().isNotEmpty) {
          final sinks = jsonDecode(sinksRes.stdout.toString()) as List;
          String? targetSinkName;
          if (device.profileName!.contains('hdmi')) {
            final match = sinks.firstWhere(
              (s) => s['name'].toString().contains('hdmi'),
              orElse: () => null,
            );
            if (match != null) targetSinkName = match['name']?.toString();
          } else {
            final match = sinks.firstWhere(
              (s) => s['name'].toString().contains('analog'),
              orElse: () => null,
            );
            if (match != null) targetSinkName = match['name']?.toString();
          }
          if (targetSinkName != null) {
            await Process.run('pactl', ['set-default-sink', targetSinkName]);
            await _moveSinkInputs(targetSinkName);
          }
        }
      } else {
        await Process.run('pactl', ['set-default-sink', device.id]);
        await _moveSinkInputs(device.id);
      }
      await _loadSoundSettings();
    } catch (e) {
      debugPrint('Error selecting output device: $e');
    }
  }

  Future<void> _moveSinkInputs(String sinkName) async {
    try {
      final res = await Process.run('pactl', ['list', 'short', 'sink-inputs']);
      if (res.exitCode == 0) {
        for (final line in LineSplitter.split(res.stdout.toString())) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            await Process.run('pactl', ['move-sink-input', parts[0], sinkName]);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _selectInputDevice(AudioDevice device) async {
    try {
      await Process.run('pactl', ['set-default-source', device.id]);
      final res = await Process.run('pactl', ['list', 'short', 'source-outputs']);
      if (res.exitCode == 0) {
        for (final line in LineSplitter.split(res.stdout.toString())) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            await Process.run('pactl', ['move-source-output', parts[0], device.id]);
          }
        }
      }
      await _loadSoundSettings();
    } catch (e) {
      debugPrint('Error selecting input device: $e');
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
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sound Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: FyrTheme.textColor,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 32),

          // Output Device & Volume Card
          _buildSectionCard(
            title: 'Output Device',
            icon: _outputMuted ? Icons.volume_off : Icons.volume_up,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_outputDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No output devices found',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    ),
                  )
                else
                  ..._outputDevices.map((device) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      decoration: BoxDecoration(
                        color: device.isDefault
                            ? FyrTheme.accentColor.withOpacity(0.12)
                            : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: device.isDefault
                              ? FyrTheme.accentColor
                              : Colors.white.withOpacity(0.06),
                          width: device.isDefault ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          device.icon,
                          color: device.isDefault
                              ? FyrTheme.accentColor
                              : FyrTheme.textColorMuted,
                          size: 24,
                        ),
                        title: Text(
                          device.title,
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontWeight: device.isDefault ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          device.subtitle,
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: device.isDefault
                            ? Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: FyrTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              )
                            : null,
                        onTap: () => _selectOutputDevice(device),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  'Output Volume',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _outputMuted ? Icons.volume_off : Icons.volume_up,
                      color: FyrTheme.textColorMuted,
                      size: 20,
                    ),
                    Expanded(
                      child: Slider(
                        value: _outputVolume.clamp(0.0, 100.0),
                        min: 0,
                        max: 100,
                        activeColor: FyrTheme.accentColor,
                        onChanged: _setOutputVolume,
                      ),
                    ),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${_outputVolume.round()}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Mute Output',
                    style: TextStyle(color: FyrTheme.textColor),
                  ),
                  trailing: Switch(
                    value: _outputMuted,
                    activeColor: FyrTheme.accentColor,
                    onChanged: (_) => _toggleOutputMute(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Input Device & Volume Card
          _buildSectionCard(
            title: 'Input Device (Microphone)',
            icon: _inputMuted ? Icons.mic_off : Icons.mic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_inputDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No microphone devices found',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    ),
                  )
                else
                  ..._inputDevices.map((device) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      decoration: BoxDecoration(
                        color: device.isDefault
                            ? FyrTheme.accentColor.withOpacity(0.12)
                            : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: device.isDefault
                              ? FyrTheme.accentColor
                              : Colors.white.withOpacity(0.06),
                          width: device.isDefault ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          device.icon,
                          color: device.isDefault
                              ? FyrTheme.accentColor
                              : FyrTheme.textColorMuted,
                          size: 24,
                        ),
                        title: Text(
                          device.title,
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontWeight: device.isDefault ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          device.subtitle,
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: device.isDefault
                            ? Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: FyrTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              )
                            : null,
                        onTap: () => _selectInputDevice(device),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  'Input Volume',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _inputMuted ? Icons.mic_off : Icons.mic,
                      color: FyrTheme.textColorMuted,
                      size: 20,
                    ),
                    Expanded(
                      child: Slider(
                        value: _inputVolume.clamp(0.0, 100.0),
                        min: 0,
                        max: 100,
                        activeColor: FyrTheme.accentColor,
                        onChanged: _setInputVolume,
                      ),
                    ),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${_inputVolume.round()}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Mute Microphone',
                    style: TextStyle(color: FyrTheme.textColor),
                  ),
                  trailing: Switch(
                    value: _inputMuted,
                    activeColor: FyrTheme.accentColor,
                    onChanged: (_) => _toggleInputMute(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _loadSoundSettings(isBackground: false),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Audio Devices'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
