import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'kde_connect_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
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

  runApp(const FyrConnectApp());
}

class FyrConnectApp extends StatelessWidget {
  const FyrConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'fyrConnect',
        themeMode: FyrTheme.themeMode,
        theme: ThemeData.light().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Inter'),
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: FyrTheme.surfaceColor,
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: FyrTheme.surfaceColor,
          ),
        ),
        home: const ConnectHomePage(),
      ),
    );
  }
}

class ConnectHomePage extends StatefulWidget {
  const ConnectHomePage({super.key});

  @override
  State<ConnectHomePage> createState() => _ConnectHomePageState();
}

class _ConnectHomePageState extends State<ConnectHomePage> {
  final KdeConnectService _kdeService = KdeConnectService();
  String? _selectedDeviceId;
  final TextEditingController _ipController = TextEditingController();
  bool _openingFirewall = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  KdeConnectDevice? _findSelectedDevice(List<KdeConnectDevice> devices) {
    if (_selectedDeviceId == null) return null;
    for (final d in devices) {
      if (d.id == _selectedDeviceId) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FyrTheme.dividerColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: ValueListenableBuilder<List<KdeConnectDevice>>(
                valueListenable: _kdeService.devices,
                builder: (context, devices, _) {
                  final selectedDevice = _findSelectedDevice(devices);
                  return Row(
                    children: [
                      _buildSidebar(devices, selectedDevice),
                      VerticalDivider(width: 1, color: FyrTheme.dividerColor),
                      Expanded(
                        child: selectedDevice == null
                            ? _buildEmptyState(devices.isEmpty)
                            : _buildDeviceDetails(selectedDevice),
                      ),
                    ],
                  );
                },
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
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
            const SizedBox(width: 8),
            _buildTrafficLight(
              Colors.orangeAccent,
              () => windowManager.minimize(),
            ),
            const SizedBox(width: 8),
            _buildTrafficLight(Colors.greenAccent, () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }),
            const SizedBox(width: 20),
            Icon(Icons.devices, color: FyrTheme.accentColor, size: 20),
            const SizedBox(width: 12),
            Text(
              'fyrConnect',
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: _kdeService.isScanning,
              builder: (context, scanning, _) {
                if (scanning) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                  );
                }
                return IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: FyrTheme.textColorMuted,
                  onPressed: () => _kdeService.refresh(),
                  tooltip: 'Scan / Refresh devices',
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_link, size: 20),
              color: FyrTheme.textColorMuted,
              onPressed: _showAddIpDialog,
              tooltip: 'Add Phone by IP',
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

  Widget _buildSidebar(
    List<KdeConnectDevice> devices,
    KdeConnectDevice? selectedDevice,
  ) {
    return Container(
      width: 280,
      color: FyrTheme.sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
            child: Row(
              children: [
                Text(
                  'DEVICES',
                  style: TextStyle(
                    color: FyrTheme.textColorMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _kdeService.isAvailable,
                  builder: (context, available, _) => Tooltip(
                    message: available
                        ? 'KDE Connect daemon active'
                        : 'KDE Connect daemon offline',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: available ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.phonelink_off,
                            size: 32,
                            color: FyrTheme.textColorMuted.withOpacity(0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No devices found',
                            style: TextStyle(color: FyrTheme.textColorMuted),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => _kdeService.refresh(),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Scan Now'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isSelected = selectedDevice?.id == device.id;
                      return _buildDeviceTile(device, isSelected);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(KdeConnectDevice device, bool isSelected) {
    final contrastColor = FyrTheme.getContrastingColor(FyrTheme.accentColor);
    String subtitle;
    if (device.isPairRequestedByPeer) {
      subtitle = 'Pair request received';
    } else if (device.isPairRequested) {
      subtitle = 'Pairing requested...';
    } else if (device.isPaired) {
      subtitle = device.isReachable ? 'Paired • Connected' : 'Paired • Offline';
    } else {
      subtitle = device.isReachable ? 'Not paired • Available' : 'Not paired';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedDeviceId = device.id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? FyrTheme.accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                device.isReachable ? Icons.smartphone : Icons.phonelink_erase,
                color: isSelected
                    ? contrastColor
                    : (device.isReachable
                        ? FyrTheme.accentColor
                        : FyrTheme.textColorMuted),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? contrastColor : FyrTheme.textColor,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? contrastColor.withOpacity(0.8)
                            : FyrTheme.textColorMuted,
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
                  color: isSelected ? contrastColor : FyrTheme.textColorMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool noDevicesFound) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _kdeService.isAvailable,
        _kdeService.isScanning,
        _kdeService.announcedName,
        _kdeService.localLanIps,
        _kdeService.customDevices,
        _kdeService.ufwActive,
        _kdeService.kdeConnectFirewallAllowed,
        _kdeService.activeVpnInterfaces,
      ]),
      builder: (context, _) {
        final hostName = _kdeService.announcedName.value.isNotEmpty
            ? _kdeService.announcedName.value
            : Platform.localHostname;
        final lanIps = _kdeService.localLanIps.value;
        final customIps = _kdeService.customDevices.value;
        final showFirewallBanner = _kdeService.ufwActive.value &&
            !_kdeService.kdeConnectFirewallAllowed.value;
        final vpnIfaces = _kdeService.activeVpnInterfaces.value;
        final scanning = _kdeService.isScanning.value;
        final accentContrast = FyrTheme.getContrastingColor(FyrTheme.accentColor);

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: FyrTheme.accentColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.phonelink_ring,
                        size: 44,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    noDevicesFound
                        ? 'No devices found yet'
                        : 'Select a device to manage',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Open KDE Connect on your phone on the same Wi-Fi network, or pair directly by IP.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: scanning ? null : () => _kdeService.refresh(),
                        icon: scanning
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: accentContrast,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(scanning ? 'Scanning...' : 'Scan for Devices'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FyrTheme.accentColor,
                          foregroundColor: accentContrast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddIpDialog,
                        icon: const Icon(Icons.add_link, size: 18),
                        label: const Text('Add Phone by IP'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FyrTheme.textColor,
                          side: BorderSide(color: FyrTheme.dividerColor),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (showFirewallBanner) ...[
                    _buildFirewallBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (vpnIfaces.isNotEmpty) ...[
                    _buildVpnBanner(vpnIfaces),
                    const SizedBox(height: 16),
                  ],
                  _buildConnectionHelperCard(hostName, lanIps, customIps),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFirewallBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'UFW Firewall is Active',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'UFW blocks KDE Connect discovery and pairing unless ports 1714–1764 (TCP & UDP) are allowed.',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openingFirewall
                ? null
                : () async {
                    setState(() => _openingFirewall = true);
                    final ok = await _kdeService.openFirewallPorts();
                    if (!mounted) return;
                    setState(() => _openingFirewall = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Allowed KDE Connect ports 1714–1764 in UFW. Rescanning...'
                              : (_kdeService.lastError.value ??
                                  'Firewall update cancelled or failed.'),
                        ),
                      ),
                    );
                  },
            icon: _openingFirewall
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.lock_open, size: 16),
            label: Text(
              _openingFirewall
                  ? 'Updating Firewall...'
                  : 'Allow KDE Connect in Firewall (Ports 1714–1764)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVpnBanner(List<String> vpnIfaces) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FyrTheme.accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FyrTheme.accentColor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vpn_lock, color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VPN Active (${vpnIfaces.join(', ')})',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'VPN tunnels can block LAN UDP discovery broadcasts. Enable local network access in your VPN client or add your phone directly by IP.',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionHelperCard(
    String hostName,
    List<String> lanIps,
    List<String> customIps,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: FyrTheme.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'CONNECTION HELPER',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'This PC:',
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hostName,
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (lanIps.isEmpty)
            Text(
              'No local LAN IPv4 address detected.',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add this PC in your phone\'s KDE Connect app (Add devices by IP):',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: lanIps.map((ip) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: FyrTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ip,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: FyrTheme.textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: ip));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied $ip to clipboard')),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy,
                                size: 15,
                                color: FyrTheme.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          if (customIps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: FyrTheme.dividerColor, height: 1),
            const SizedBox(height: 12),
            Text(
              'Saved Phone IPs',
              style: TextStyle(
                color: FyrTheme.textColorMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: customIps.map((ip) {
                return Chip(
                  backgroundColor: FyrTheme.surfaceColor,
                  side: BorderSide(color: FyrTheme.dividerColor),
                  label: Text(
                    ip,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  deleteIcon: Icon(
                    Icons.close,
                    size: 14,
                    color: FyrTheme.textColorMuted,
                  ),
                  onDeleted: () => _kdeService.removeCustomDevice(ip),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceDetails(KdeConnectDevice device) {
    final accentContrast = FyrTheme.getContrastingColor(FyrTheme.accentColor);
    return SingleChildScrollView(
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
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Device ID: ${device.id}',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 12,
                      ),
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
                    side: BorderSide(color: FyrTheme.dividerColor),
                  ),
                )
              else if (!device.isPaired)
                ElevatedButton.icon(
                  onPressed: () => _kdeService.pair(device.id),
                  icon: const Icon(Icons.link),
                  label: const Text('Pair Device'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FyrTheme.accentColor,
                    foregroundColor: accentContrast,
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
              _buildActionCard(
                Icons.notifications_active,
                'Ring',
                'Find your device',
                () {
                  _kdeService.ring(device.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ringing ${device.name}...')),
                  );
                },
              ),
              _buildActionCard(
                Icons.file_present,
                'Files',
                'Browse device files',
                () async {
                  await _kdeService.mountSftp(device.id);
                  final mountPoint = await _kdeService.getSftpMountPoint(device.id);
                  if (!mounted) return;
                  if (mountPoint != null && mountPoint.isNotEmpty) {
                    Process.run('fyrfiles', [mountPoint]);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not mount device storage.'),
                      ),
                    );
                  }
                },
              ),
              _buildActionCard(
                Icons.wifi_tethering,
                'Ping',
                'Send a test ping',
                () async {
                  await _kdeService.ping(device.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pinged ${device.name}')),
                  );
                },
              ),
              _buildActionCard(
                Icons.content_paste,
                'Clipboard',
                'Send clipboard to phone',
                () async {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = clip?.text;
                  if (text != null && text.isNotEmpty) {
                    await _kdeService.shareText(device.id, text);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Clipboard synced to phone.'),
                      ),
                    );
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Clipboard is empty.')),
                    );
                  }
                },
              ),
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
          device.isCharging
              ? Icons.battery_charging_full
              : _getBatteryIcon(device.batteryLevel),
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

  Widget _buildActionCard(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FyrTheme.dividerColor.withOpacity(0.5)),
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
    final accentContrast = FyrTheme.getContrastingColor(FyrTheme.accentColor);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('Add Phone by IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your phone\'s local IP address or hostname. fyrConnect will add it to KDE Connect custom devices and rescan.',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. 192.168.1.42',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitAddIp(dialogContext),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _submitAddIp(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor: accentContrast,
            ),
            child: const Text('Add & Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAddIp(BuildContext dialogContext) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    Navigator.pop(dialogContext);
    _ipController.clear();
    final ok = await _kdeService.addDeviceByIp(ip);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Added $ip to fyrConnect. Scanning for device...'
              : (_kdeService.lastError.value ?? 'Could not add $ip.'),
        ),
      ),
    );
  }
}
