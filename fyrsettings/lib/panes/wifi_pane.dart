import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

class WiFiPane extends StatefulWidget {
  const WiFiPane({super.key});

  @override
  State<WiFiPane> createState() => _WiFiPaneState();
}

class _WiFiPaneState extends State<WiFiPane> {
  bool _wifiEnabled = true;
  List<Map<String, String>> _networks = [];
  bool _scanning = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _scanNetworks();
    _scanTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _scanNetworks(),
    );
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final result = await Process.run('nmcli', ['radio', 'wifi']);
      setState(() {
        _wifiEnabled = (result.stdout as String).trim() == 'enabled';
      });
    } catch (e) {}
  }

  Future<void> _toggleWiFi(bool value) async {
    setState(() => _wifiEnabled = value);
    try {
      await Process.run('nmcli', ['radio', 'wifi', value ? 'on' : 'off']);
      if (value) {
        _scanNetworks();
      } else {
        setState(() => _networks = []);
      }
    } catch (e) {}
  }

  Future<void> _scanNetworks() async {
    if (!_wifiEnabled || _scanning) return;
    setState(() => _scanning = true);
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'IN-USE,SSID,SECURITY,BARS',
        'dev',
        'wifi',
        'list',
      ]);
      final lines = (result.stdout as String).split('\n');
      final Set<String> seen = {};
      final List<Map<String, String>> nets = [];
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(':');
        if (parts.length >= 4) {
          final inUse = parts[0] == '*';
          var ssid = parts[1];
          // Sometimes colon in SSID is escaped
          if (parts.length > 4) {
            ssid = parts.sublist(1, parts.length - 2).join(':');
          }
          final security = parts[parts.length - 2];
          final bars = parts[parts.length - 1];
          if (ssid.isNotEmpty && !seen.contains(ssid)) {
            seen.add(ssid);
            nets.add({
              'ssid': ssid,
              'security': security,
              'bars': bars,
              'inUse': inUse.toString(),
            });
          }
        }
      }
      setState(() {
        _networks = nets;
      });
    } catch (e) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(String ssid) async {
    try {
      await Process.run('nmcli', ['dev', 'wifi', 'connect', ssid]);
      _scanNetworks();
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Wi-Fi',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: FyrTheme.textColor,
              ),
            ),
            Switch(
              value: _wifiEnabled,
              onChanged: _toggleWiFi,
              activeColor: FyrTheme.accentColor,
            ),
          ],
        ),
        SizedBox(height: 24),
        if (_scanning && _networks.isEmpty)
          Center(child: CircularProgressIndicator())
        else if (!_wifiEnabled)
          Center(
            child: Text(
              'Wi-Fi is turned off',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _networks.length,
              itemBuilder: (context, index) {
                final net = _networks[index];
                final inUse = net['inUse'] == 'true';
                return ListTile(
                  leading: Icon(
                    inUse ? Icons.wifi : Icons.wifi_outlined,
                    color: inUse ? FyrTheme.accentColor : FyrTheme.textColor,
                  ),
                  title: Text(
                    net['ssid']!,
                    style: TextStyle(color: FyrTheme.textColor),
                  ),
                  subtitle: Text(
                    net['security']!,
                    style: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                  trailing: inUse
                      ? Icon(Icons.check, color: FyrTheme.accentColor)
                      : null,
                  onTap: () {
                    if (!inUse) _connect(net['ssid']!);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
