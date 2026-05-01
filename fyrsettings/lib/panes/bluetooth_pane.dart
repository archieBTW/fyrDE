import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class BluetoothPane extends StatefulWidget {
  const BluetoothPane({super.key});

  @override
  State<BluetoothPane> createState() => _BluetoothPaneState();
}

class _BluetoothPaneState extends State<BluetoothPane> {
  bool _btEnabled = true;
  List<Map<String, String>> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadDevices();
  }

  Future<void> _checkStatus() async {
    try {
      final result = await Process.run('bluetoothctl', ['show']);
      setState(() {
        _btEnabled = (result.stdout as String).contains('Powered: yes');
      });
    } catch (e) {}
  }

  Future<void> _toggleBluetooth(bool value) async {
    setState(() => _btEnabled = value);
    try {
      await Process.run('bluetoothctl', ['power', value ? 'on' : 'off']);
      if (value) {
        _loadDevices();
      } else {
        setState(() => _devices = []);
      }
    } catch (e) {}
  }

  Future<void> _loadDevices() async {
    if (!_btEnabled) return;
    setState(() => _scanning = true);
    try {
      final result = await Process.run('bluetoothctl', ['devices']);
      final lines = (result.stdout as String).split('\n');
      final List<Map<String, String>> devs = [];
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(' ');
        if (parts.length >= 3 && parts[0] == 'Device') {
          final mac = parts[1];
          final name = parts.sublist(2).join(' ');

          final info = await Process.run('bluetoothctl', ['info', mac]);
          final connected = (info.stdout as String).contains('Connected: yes');

          devs.add({
            'mac': mac,
            'name': name,
            'connected': connected.toString(),
          });
        }
      }
      setState(() {
        _devices = devs;
      });
    } catch (e) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(String mac) async {
    try {
      await Process.run('bluetoothctl', ['connect', mac]);
      _loadDevices();
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
            const Text(
              'Bluetooth',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Switch(
              value: _btEnabled,
              onChanged: _toggleBluetooth,
              activeColor: Colors.purpleAccent,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_scanning && _devices.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (!_btEnabled)
          const Center(
            child: Text(
              'Bluetooth is turned off',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final dev = _devices[index];
                final connected = dev['connected'] == 'true';
                return ListTile(
                  leading: Icon(
                    Icons.bluetooth,
                    color: connected ? Colors.purpleAccent : Colors.white,
                  ),
                  title: Text(
                    dev['name']!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    dev['mac']!,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: connected
                      ? const Text(
                          'Connected',
                          style: TextStyle(color: Colors.purpleAccent),
                        )
                      : null,
                  onTap: () {
                    if (!connected) _connect(dev['mac']!);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
