import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'kde_connect_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  FyrTheme.initialize();
  final kdeService = KdeConnectService();
  await kdeService.init();

  runApp(const FyrPhoneApp());
}

class FyrPhoneApp extends StatelessWidget {
  const FyrPhoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FyrPhone',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Inter',
      ),
      home: const PhoneHomePage(),
    );
  }
}

class PhoneHomePage extends StatefulWidget {
  const PhoneHomePage({super.key});

  @override
  State<PhoneHomePage> createState() => _PhoneHomePageState();
}

class _PhoneHomePageState extends State<PhoneHomePage> {
  final KdeConnectService _kdeService = KdeConnectService();
  KdeConnectDevice? _selectedDevice;
  final TextEditingController _ipController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FyrTheme.cardColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(),
                  VerticalDivider(width: 1, color: FyrTheme.cardColor),
                  Expanded(
                    child: _selectedDevice == null
                        ? _buildEmptyState()
                        : _buildDeviceDetails(_selectedDevice!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return DragToMoveArea(
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: FyrTheme.cardColor)),
        ),
        child: Row(
          children: [
            // Traffic Light Buttons
            _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
            const SizedBox(width: 8),
            _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
            const SizedBox(width: 8),
            _buildTrafficLight(Colors.greenAccent, () => windowManager.maximize()),
            const SizedBox(width: 20),
            Icon(Icons.phone_android, color: FyrTheme.accentColor, size: 20),
            const SizedBox(width: 12),
            Text(
              'FyrPhone',
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_link, size: 20),
              color: FyrTheme.textColorMuted,
              onPressed: _showAddIpDialog,
              tooltip: 'Connect by IP',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: Colors.black12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'DEVICES',
              style: TextStyle(
                color: FyrTheme.textColorMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<KdeConnectDevice>>(
              valueListenable: _kdeService.devices,
              builder: (context, devices, _) {
                if (devices.isEmpty) {
                  return Center(
                    child: Text(
                      'No devices found',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = _selectedDevice?.id == device.id;
                    return _buildDeviceTile(device, isSelected);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(KdeConnectDevice device, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedDevice = device),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? FyrTheme.accentColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                device.isReachable ? Icons.smartphone : Icons.phonelink_erase,
                color: device.isReachable ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        color: isSelected ? FyrTheme.textColor : FyrTheme.textColor.withOpacity(0.8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      device.isPaired ? 'Paired' : 'Not paired',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (device.batteryLevel >= 0)
                Icon(
                  _getBatteryIcon(device.batteryLevel),
                  size: 14,
                  color: FyrTheme.textColorMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phonelink_ring, size: 64, color: FyrTheme.cardColor),
          const SizedBox(height: 16),
          Text(
            'Select a device to manage',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceDetails(KdeConnectDevice device) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.smartphone, size: 48, color: FyrTheme.accentColor),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Device ID: ${device.id}',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (device.isPairRequestedByPeer)
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _kdeService.acceptPairing(device.id),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept Pair'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _kdeService.cancelPairing(device.id),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ],
                )
              else if (device.isPairRequested)
                OutlinedButton.icon(
                  onPressed: () => _kdeService.cancelPairing(device.id),
                  icon: const Icon(Icons.hourglass_empty),
                  label: const Text('Cancel Request'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FyrTheme.textColorMuted,
                    side: BorderSide(color: FyrTheme.cardColor),
                  ),
                )
              else if (!device.isPaired)
                ElevatedButton.icon(
                  onPressed: () => _kdeService.pair(device.id),
                  icon: const Icon(Icons.link),
                  label: const Text('Pair Device'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FyrTheme.accentColor,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _kdeService.unpair(device.id),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Unpair'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            'STATUS',
            style: TextStyle(
              color: FyrTheme.textColorMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusGrid(device),
          const SizedBox(height: 40),
          Text(
            'ACTIONS',
            style: TextStyle(
              color: FyrTheme.textColorMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionCard(Icons.notifications, 'Ping', 'Ring your device', () {
                _kdeService.ping(device.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pinging ${device.name}...')),
                );
              }),
              _buildActionCard(Icons.file_present, 'Files', 'Browse device files', () async {
                await _kdeService.mountSftp(device.id);
                final mountPoint = await _kdeService.getSftpMountPoint(device.id);
                if (mountPoint != null && mountPoint.isNotEmpty) {
                  Process.run('fyrfiles', [mountPoint]);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not mount device storage.')),
                  );
                }
              }),
              _buildActionCard(Icons.mouse, 'Remote Input', 'Use phone as touchpad', () {}),
              _buildActionCard(Icons.content_paste, 'Clipboard', 'Sync clipboard', () async {
                final result = await Process.run('xclip', ['-o', '-selection', 'clipboard']);
                if (result.exitCode == 0) {
                  final text = result.stdout.toString();
                  await _kdeService.shareText(device.id, text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clipboard synced to phone.')),
                  );
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusGrid(KdeConnectDevice device) {
    return Row(
      children: [
        _buildStatusItem(
          Icons.wifi,
          device.isReachable ? 'Reachable' : 'Offline',
          device.isReachable ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 32),
        _buildStatusItem(
          device.isCharging ? Icons.battery_charging_full : _getBatteryIcon(device.batteryLevel),
          device.batteryLevel >= 0 ? '${device.batteryLevel}%' : 'Unknown',
          FyrTheme.textColor,
        ),
      ],
    );
  }

  Widget _buildStatusItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color.withOpacity(0.8)),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildActionCard(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FyrTheme.cardColor.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: FyrTheme.accentColor),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBatteryIcon(int level) {
    if (level >= 90) return Icons.battery_full;
    if (level >= 70) return Icons.battery_6_bar;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 30) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  void _showAddIpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: const Text('Connect by IP'),
        content: TextField(
          controller: _ipController,
          decoration: const InputDecoration(
            hintText: 'Enter IP address (e.g. 192.168.1.5)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _kdeService.addDeviceByIp(_ipController.text);
              Navigator.pop(context);
              _ipController.clear();
            },
            style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
