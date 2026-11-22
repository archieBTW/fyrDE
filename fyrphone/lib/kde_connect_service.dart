import 'dart:async';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class KdeConnectDevice {
  final String id;
  final String name;
  final String type;
  final bool isPaired;
  final bool isReachable;
  final int batteryLevel;
  final bool isCharging;
  final bool isPairRequested;
  final bool isPairRequestedByPeer;

  const KdeConnectDevice({
    required this.id,
    required this.name,
    this.type = 'phone',
    this.isPaired = false,
    this.isReachable = false,
    this.batteryLevel = -1,
    this.isCharging = false,
    this.isPairRequested = false,
    this.isPairRequestedByPeer = false,
  });

  KdeConnectDevice copyWith({
    String? name,
    String? type,
    bool? isPaired,
    bool? isReachable,
    int? batteryLevel,
    bool? isCharging,
    bool? isPairRequested,
    bool? isPairRequestedByPeer,
  }) {
    return KdeConnectDevice(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      isPaired: isPaired ?? this.isPaired,
      isReachable: isReachable ?? this.isReachable,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      isPairRequested: isPairRequested ?? this.isPairRequested,
      isPairRequestedByPeer:
          isPairRequestedByPeer ?? this.isPairRequestedByPeer,
    );
  }
}

class KdePairingState {
  final bool isPaired;
  final bool isPairRequested;
  final bool isPairRequestedByPeer;

  const KdePairingState({
    required this.isPaired,
    required this.isPairRequested,
    required this.isPairRequestedByPeer,
  });
}

class KdeConnectService {
  static final KdeConnectService _instance = KdeConnectService._internal();
  factory KdeConnectService() => _instance;
  KdeConnectService._internal();

  DBusClient? _client;
  bool _initialized = false;
  bool _daemonSignalsAttached = false;
  Timer? _periodicTimer;
  final Set<String> _listenedDeviceIds = <String>{};
  final List<StreamSubscription<DBusSignal>> _subscriptions = [];

  final ValueNotifier<List<KdeConnectDevice>> devices = ValueNotifier([]);
  final ValueNotifier<bool> isAvailable = ValueNotifier(false);
  final ValueNotifier<bool> isScanning = ValueNotifier(false);
  final ValueNotifier<String> announcedName = ValueNotifier('');
  final ValueNotifier<List<String>> customDevices = ValueNotifier([]);
  final ValueNotifier<List<String>> localLanIps = ValueNotifier([]);
  final ValueNotifier<bool> ufwActive = ValueNotifier(false);
  final ValueNotifier<bool> kdeConnectFirewallAllowed = ValueNotifier(false);
  final ValueNotifier<List<String>> activeVpnInterfaces = ValueNotifier([]);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  static const String _daemonBusName = 'org.kde.kdeconnect';
  static const String _daemonInterface = 'org.kde.kdeconnect.daemon';
  static const String _deviceInterface = 'org.kde.kdeconnect.device';
  static final DBusObjectPath _daemonPath = DBusObjectPath('/modules/kdeconnect');

  static const List<String> _ignoredLanPrefixes = [
    'lo',
    'docker',
    'br-',
    'veth',
    'virbr',
    'podman',
    'cni',
    'flannel',
    'proton',
    'wg',
    'tun',
    'tap',
    'tailscale',
    'zt',
    'nordlynx',
    'mullvad',
  ];

  static const List<String> _vpnPrefixes = [
    'proton',
    'wg',
    'tun',
    'tailscale',
    'nordlynx',
    'mullvad',
  ];

  /// Resolves device pairing flags from modern `pairState` (0..3) and/or legacy
  /// boolean properties (`isPaired`, `isPairRequested`, `isPairRequestedByPeer`).
  static KdePairingState resolvePairingState({
    int? pairState,
    bool? isPaired,
    bool? isPairRequested,
    bool? isPairRequestedByPeer,
  }) {
    if (pairState != null) {
      switch (pairState) {
        case 1:
          return const KdePairingState(
            isPaired: false,
            isPairRequested: true,
            isPairRequestedByPeer: false,
          );
        case 2:
          return const KdePairingState(
            isPaired: false,
            isPairRequested: false,
            isPairRequestedByPeer: true,
          );
        case 3:
          return const KdePairingState(
            isPaired: true,
            isPairRequested: false,
            isPairRequestedByPeer: false,
          );
        case 0:
        default:
          return KdePairingState(
            isPaired: isPaired ?? false,
            isPairRequested: isPairRequested ?? false,
            isPairRequestedByPeer: isPairRequestedByPeer ?? false,
          );
      }
    }
    return KdePairingState(
      isPaired: isPaired ?? false,
      isPairRequested: isPairRequested ?? false,
      isPairRequestedByPeer: isPairRequestedByPeer ?? false,
    );
  }

  /// Returns true if an interface name should be considered a LAN interface.
  static bool isLanInterfaceName(String name) {
    final lower = name.toLowerCase();
    for (final prefix in _ignoredLanPrefixes) {
      if (lower == prefix || lower.startsWith(prefix)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if an interface name matches a common VPN tunnel interface.
  static bool isVpnInterfaceName(String name) {
    final lower = name.toLowerCase();
    for (final prefix in _vpnPrefixes) {
      if (lower == prefix || lower.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  /// Parses `/etc/ufw/ufw.conf` content for `ENABLED=yes`.
  static bool parseUfwConfEnabled(String content) {
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('=');
      if (parts.length == 2 && parts[0].trim().toUpperCase() == 'ENABLED') {
        return parts[1].trim().toLowerCase() == 'yes';
      }
    }
    return false;
  }

  /// Checks whether `/etc/ufw/user.rules` already allows KDE Connect ports 1714:1764.
  static bool hasKdeConnectUfwRule(String userRulesContent) {
    bool hasTcp = false;
    bool hasUdp = false;
    for (final rawLine in userRulesContent.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('### tuple ###')) continue;
      final tokens = line.substring('### tuple ###'.length).trim().split(RegExp(r'\s+'));
      if (tokens.length < 3) continue;
      final action = tokens[0].toLowerCase();
      final proto = tokens[1].toLowerCase();
      final dport = tokens[2];
      if (!action.startsWith('allow')) continue;
      if (dport == '1714:1764') {
        if (proto == 'tcp') hasTcp = true;
        if (proto == 'udp') hasUdp = true;
        if (proto == 'any') {
          hasTcp = true;
          hasUdp = true;
        }
      }
    }
    return hasTcp && hasUdp;
  }

  Future<void> init() async {
    if (_initialized) {
      await refresh();
      return;
    }
    _initialized = true;
    _client ??= DBusClient.session();

    await refreshDiagnostics();
    await _connectToDaemon(launchIfNeeded: true);

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshDevices(),
    );
  }

  Future<bool> _connectToDaemon({bool launchIfNeeded = true}) async {
    if (await _probeDaemon()) {
      await _onDaemonConnected();
      return true;
    }

    if (launchIfNeeded) {
      await _tryStartKdeConnectDaemon();
      for (int attempt = 0; attempt < 6; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await _probeDaemon()) {
          await _onDaemonConnected();
          return true;
        }
      }
    }

    isAvailable.value = false;
    lastError.value = 'KDE Connect daemon is not running on the session bus.';
    return false;
  }

  Future<bool> _probeDaemon() async {
    final client = _client;
    if (client == null) return false;
    try {
      final remote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: _daemonPath,
      );
      await remote.callMethod(_daemonInterface, 'announcedName', []);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _tryStartKdeConnectDaemon() async {
    const candidates = [
      'kdeconnectd',
      '/usr/bin/kdeconnectd',
      '/usr/lib/kdeconnectd',
      '/usr/libexec/kdeconnectd',
    ];
    for (final executable in candidates) {
      try {
        await Process.start(
          executable,
          [],
          mode: ProcessStartMode.detached,
        );
        return;
      } catch (_) {
        // Try next candidate path.
      }
    }
  }

  Future<void> _onDaemonConnected() async {
    isAvailable.value = true;
    lastError.value = null;
    await _ensureLanLinkProviderEnabled();
    await _readDaemonMetadata();
    await _triggerNetworkRefresh();
    await _refreshDevices();
    _listenToDaemonSignals();
  }

  Future<void> _ensureLanLinkProviderEnabled() async {
    final client = _client;
    if (client == null) return;
    try {
      final remote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: _daemonPath,
      );
      final resp = await remote.callMethod(_daemonInterface, 'linkProviders', []);
      if (resp.values.isNotEmpty && resp.values[0] is DBusArray) {
        final providers = (resp.values[0] as DBusArray)
            .children
            .whereType<DBusString>()
            .map((v) => v.value)
            .toList();
        for (final p in providers) {
          if (p.toLowerCase().contains('lan')) {
            try {
              await remote.callMethod(
                _daemonInterface,
                'setLinkProviderState',
                [DBusString(p), const DBusBoolean(true)],
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Optional on older daemons.
    }
  }

  Future<void> _readDaemonMetadata() async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: _daemonPath,
    );

    try {
      final resp = await remote.callMethod(_daemonInterface, 'announcedName', []);
      if (resp.values.isNotEmpty && resp.values[0] is DBusString) {
        announcedName.value = (resp.values[0] as DBusString).value;
      }
    } catch (_) {
      if (announcedName.value.isEmpty) {
        announcedName.value = Platform.localHostname;
      }
    }

    try {
      final customProp = await remote.getProperty(_daemonInterface, 'customDevices');
      if (customProp is DBusArray) {
        customDevices.value = customProp.children
            .whereType<DBusString>()
            .map((v) => v.value)
            .where((v) => v.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Older daemon without customDevices property.
    }
  }

  Future<void> _triggerNetworkRefresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final remote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: _daemonPath,
      );
      await remote.callMethod(_daemonInterface, 'forceOnNetworkChange', []);
    } catch (_) {}
  }

  /// Refreshes network diagnostics, reconnects if needed, triggers daemon
  /// network rediscovery, and reloads the device list.
  Future<void> refresh() async {
    isScanning.value = true;
    try {
      await refreshDiagnostics();
      if (!isAvailable.value) {
        final connected = await _connectToDaemon(launchIfNeeded: true);
        if (!connected) return;
      } else {
        await _readDaemonMetadata();
        await _triggerNetworkRefresh();
        await _refreshDevices();
      }
    } finally {
      isScanning.value = false;
    }
  }

  /// Unprivileged network, VPN, and UFW diagnostics (never prompts for password).
  Future<void> refreshDiagnostics() async {
    // 1. Local LAN IPv4 addresses & active VPN interfaces
    final lanIps = <String>[];
    final vpnIfaces = <String>{};
    try {
      final ipv4Ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ipv4Ifaces) {
        if (isLanInterfaceName(iface.name)) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && !addr.isLinkLocal) {
              lanIps.add(addr.address);
            }
          }
        }
      }

      final allIfaces = await NetworkInterface.list(
        type: InternetAddressType.any,
        includeLoopback: false,
      );
      for (final iface in allIfaces) {
        if (isVpnInterfaceName(iface.name)) {
          final hasRoutableAddress = iface.addresses.any(
            (addr) => !addr.isLoopback && !addr.isLinkLocal,
          );
          if (hasRoutableAddress) {
            vpnIfaces.add(iface.name);
          }
        }
      }
    } catch (_) {}

    localLanIps.value = lanIps;
    activeVpnInterfaces.value = vpnIfaces.toList()..sort();

    // 2. UFW status (unprivileged: /etc/ufw/ufw.conf + systemctl is-active ufw)
    bool confEnabled = false;
    try {
      final confFile = File('/etc/ufw/ufw.conf');
      if (confFile.existsSync()) {
        confEnabled = parseUfwConfEnabled(await confFile.readAsString());
      }
    } catch (_) {}

    bool serviceActive = confEnabled;
    try {
      final result = await Process.run('systemctl', ['is-active', 'ufw']);
      serviceActive = result.stdout.toString().trim() == 'active';
    } catch (_) {
      // If systemctl is unavailable, trust ufw.conf.
    }

    final isUfwEnabled = confEnabled && serviceActive;
    ufwActive.value = isUfwEnabled;

    // 3. Check if KDE Connect ports are already allowed (unprivileged read if permitted)
    bool allowed = false;
    if (isUfwEnabled) {
      try {
        final rulesFile = File('/etc/ufw/user.rules');
        if (rulesFile.existsSync()) {
          allowed = hasKdeConnectUfwRule(await rulesFile.readAsString());
        }
      } catch (_) {
        allowed = false;
      }
    }
    kdeConnectFirewallAllowed.value = allowed;
  }

  /// Opens KDE Connect ports (1714:1764 TCP & UDP) in UFW via pkexec.
  /// Must ONLY be invoked in response to an explicit user button click.
  Future<bool> openFirewallPorts() async {
    try {
      final result = await Process.run('pkexec', [
        'sh',
        '-c',
        'ufw allow 1714:1764/tcp && ufw allow 1714:1764/udp',
      ]);
      if (result.exitCode == 0) {
        await refresh();
        return true;
      }
      lastError.value = result.stderr.toString().trim().isNotEmpty
          ? result.stderr.toString().trim()
          : 'Failed to update firewall rules.';
      return false;
    } catch (e) {
      lastError.value = 'Could not update firewall: $e';
      return false;
    }
  }

  Future<void> _refreshDevices() async {
    final client = _client;
    if (client == null || !isAvailable.value) return;

    try {
      final remote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: _daemonPath,
      );

      final response = await remote.callMethod(
        _daemonInterface,
        'devices',
        [const DBusBoolean(false), const DBusBoolean(false)],
      );

      final deviceIds = response.values.isNotEmpty && response.values[0] is DBusArray
          ? (response.values[0] as DBusArray)
              .children
              .whereType<DBusString>()
              .map((v) => v.value)
              .toList()
          : <String>[];

      final newDevices = <KdeConnectDevice>[];
      for (final id in deviceIds) {
        try {
          final device = await _getDeviceInfo(id);
          newDevices.add(device);
          _listenToDeviceSignals(id);
        } catch (e) {
          debugPrint('Skipping device $id due to error: $e');
        }
      }

      // Sort reachable devices first, then paired, then alphabetical.
      newDevices.sort((a, b) {
        if (a.isReachable != b.isReachable) return a.isReachable ? -1 : 1;
        if (a.isPaired != b.isPaired) return a.isPaired ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      devices.value = newDevices;
    } catch (e) {
      debugPrint('Error refreshing KDE Connect devices: $e');
    }
  }

  Future<DBusValue?> _safeGetProperty(
    DBusRemoteObject remote,
    String interface,
    String name,
  ) async {
    try {
      return await remote.getProperty(interface, name);
    } catch (_) {
      return null;
    }
  }

  Future<KdeConnectDevice> _getDeviceInfo(String id) async {
    final client = _client!;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id'),
    );

    final nameVal = await _safeGetProperty(remote, _deviceInterface, 'name');
    final typeVal = await _safeGetProperty(remote, _deviceInterface, 'type');
    final reachableVal = await _safeGetProperty(remote, _deviceInterface, 'isReachable');
    final pairStateVal = await _safeGetProperty(remote, _deviceInterface, 'pairState');
    final pairedVal = await _safeGetProperty(remote, _deviceInterface, 'isPaired');
    final pairReqVal = await _safeGetProperty(remote, _deviceInterface, 'isPairRequested');
    final pairReqPeerVal = await _safeGetProperty(
      remote,
      _deviceInterface,
      'isPairRequestedByPeer',
    );

    int? pairStateInt;
    if (pairStateVal is DBusInt32) {
      pairStateInt = pairStateVal.value;
    } else if (pairStateVal is DBusUint32) {
      pairStateInt = pairStateVal.value;
    }

    final pairing = resolvePairingState(
      pairState: pairStateInt,
      isPaired: pairedVal is DBusBoolean ? pairedVal.value : null,
      isPairRequested: pairReqVal is DBusBoolean ? pairReqVal.value : null,
      isPairRequestedByPeer:
          pairReqPeerVal is DBusBoolean ? pairReqPeerVal.value : null,
    );

    int battery = -1;
    bool charging = false;
    try {
      final batteryRemote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/battery'),
      );
      final bRes = await _safeGetProperty(
        batteryRemote,
        'org.kde.kdeconnect.device.battery',
        'charge',
      );
      final cRes = await _safeGetProperty(
        batteryRemote,
        'org.kde.kdeconnect.device.battery',
        'isCharging',
      );
      if (bRes is DBusInt32) battery = bRes.value;
      if (cRes is DBusBoolean) charging = cRes.value;
    } catch (_) {}

    return KdeConnectDevice(
      id: id,
      name: nameVal is DBusString && nameVal.value.isNotEmpty ? nameVal.value : id,
      type: typeVal is DBusString && typeVal.value.isNotEmpty ? typeVal.value : 'phone',
      isPaired: pairing.isPaired,
      isReachable: reachableVal is DBusBoolean ? reachableVal.value : false,
      isPairRequested: pairing.isPairRequested,
      isPairRequestedByPeer: pairing.isPairRequestedByPeer,
      batteryLevel: battery,
      isCharging: charging,
    );
  }

  void _listenToDaemonSignals() {
    final client = _client;
    if (client == null || _daemonSignalsAttached) return;
    _daemonSignalsAttached = true;

    final stream = DBusSignalStream(
      client,
      sender: _daemonBusName,
      interface: _daemonInterface,
    );

    _subscriptions.add(
      stream.listen((signal) {
        switch (signal.name) {
          case 'deviceListChanged':
          case 'deviceAdded':
          case 'deviceRemoved':
          case 'deviceVisibilityChanged':
          case 'pairingRequestsChanged':
            _refreshDevices();
            break;
          case 'customDevicesChanged':
            if (signal.values.isNotEmpty && signal.values[0] is DBusArray) {
              customDevices.value = (signal.values[0] as DBusArray)
                  .children
                  .whereType<DBusString>()
                  .map((v) => v.value)
                  .where((v) => v.trim().isNotEmpty)
                  .toList();
            } else {
              _readDaemonMetadata();
            }
            _refreshDevices();
            break;
          case 'announcedNameChanged':
            if (signal.values.isNotEmpty && signal.values[0] is DBusString) {
              announcedName.value = (signal.values[0] as DBusString).value;
            }
            break;
        }
      }),
    );
  }

  void _listenToDeviceSignals(String id) {
    final client = _client;
    if (client == null || _listenedDeviceIds.contains(id)) return;
    _listenedDeviceIds.add(id);

    _subscriptions.add(
      DBusSignalStream(
        client,
        sender: _daemonBusName,
        path: DBusObjectPath('/modules/kdeconnect/devices/$id'),
      ).listen((_) {
        _updateDeviceState(id);
      }),
    );

    _subscriptions.add(
      DBusSignalStream(
        client,
        sender: _daemonBusName,
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/notifications'),
        interface: 'org.kde.kdeconnect.device.notifications',
      ).listen((signal) {
        if (signal.name == 'notificationPosted' && signal.values.isNotEmpty) {
          _handleNotification(id, signal.values);
        }
      }),
    );
  }

  Future<void> _updateDeviceState(String id) async {
    if (_client == null) return;
    try {
      final updated = await _getDeviceInfo(id);
      final list = List<KdeConnectDevice>.from(devices.value);
      final index = list.indexWhere((d) => d.id == id);
      if (index != -1) {
        list[index] = updated;
        devices.value = list;
      }
    } catch (_) {}
  }

  Future<void> _handleNotification(String deviceId, List<DBusValue> values) async {
    final client = _client;
    if (client == null || values.isEmpty || values[0] is! DBusString) return;
    final notificationId = (values[0] as DBusString).value;

    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath(
        '/modules/kdeconnect/devices/$deviceId/notifications/$notificationId',
      ),
    );

    try {
      final title = (await remote.getProperty(
            'org.kde.kdeconnect.device.notifications.notification',
            'title',
          ) as DBusString)
          .value;
      final text = (await remote.getProperty(
            'org.kde.kdeconnect.device.notifications.notification',
            'text',
          ) as DBusString)
          .value;
      final appName = (await remote.getProperty(
            'org.kde.kdeconnect.device.notifications.notification',
            'appName',
          ) as DBusString)
          .value;

      List<String> actions = [];
      try {
        final actionsRes = await remote.getProperty(
          'org.kde.kdeconnect.device.notifications.notification',
          'actions',
        );
        if (actionsRes is DBusArray) {
          actions = actionsRes.children
              .whereType<DBusString>()
              .map((v) => v.value)
              .toList();
        }
      } catch (_) {}

      final desktopNotify = DBusRemoteObject(
        client,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );

      await desktopNotify.callMethod('org.freedesktop.Notifications', 'Notify', [
        DBusString(appName),
        const DBusUint32(0),
        const DBusString('phone'),
        DBusString('$title (from phone)'),
        DBusString(text),
        DBusArray.string(actions),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        const DBusInt32(5000),
      ]);
    } catch (e) {
      debugPrint('Error fetching notification details: $e');
    }
  }

  Future<void> _callDeviceMethodWithFallback(
    String id,
    List<String> methodNames,
  ) async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id'),
    );
    Object? lastErr;
    for (final method in methodNames) {
      try {
        await remote.callMethod(_deviceInterface, method, []);
        await _updateDeviceState(id);
        return;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) {
      debugPrint('KDE Connect method $methodNames failed for $id: $lastErr');
    }
  }

  Future<void> pair(String id) async {
    await _callDeviceMethodWithFallback(id, ['requestPairing', 'requestPair']);
  }

  Future<void> acceptPairing(String id) async {
    await _callDeviceMethodWithFallback(id, ['acceptPairing', 'acceptPair']);
  }

  Future<void> cancelPairing(String id) async {
    await _callDeviceMethodWithFallback(id, ['cancelPairing', 'rejectPair']);
  }

  Future<void> unpair(String id) async {
    await _callDeviceMethodWithFallback(id, ['unpair']);
  }

  /// Adds a custom device IP/hostname via the modern `customDevices` D-Bus
  /// property on `org.kde.kdeconnect.daemon` and triggers `forceOnNetworkChange()`.
  Future<bool> addDeviceByIp(String rawIp) async {
    final ip = rawIp.trim();
    if (ip.isEmpty) return false;

    if (!isAvailable.value) {
      final connected = await _connectToDaemon(launchIfNeeded: true);
      if (!connected) return false;
    }

    final client = _client;
    if (client == null) return false;

    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: _daemonPath,
    );

    try {
      final current = <String>[];
      try {
        final prop = await remote.getProperty(_daemonInterface, 'customDevices');
        if (prop is DBusArray) {
          current.addAll(
            prop.children
                .whereType<DBusString>()
                .map((v) => v.value.trim())
                .where((v) => v.isNotEmpty),
          );
        }
      } catch (_) {
        current.addAll(customDevices.value);
      }

      if (!current.contains(ip)) {
        current.add(ip);
      }

      await remote.setProperty(
        _daemonInterface,
        'customDevices',
        DBusArray.string(current),
      );
      customDevices.value = List<String>.from(current);
      await _triggerNetworkRefresh();
      await _refreshDevices();
      return true;
    } catch (e) {
      lastError.value = 'Could not add custom device IP: $e';
      debugPrint('Error setting customDevices: $e');
      return false;
    }
  }

  /// Removes a saved custom device IP/hostname from `customDevices`.
  Future<bool> removeCustomDevice(String rawIp) async {
    final ip = rawIp.trim();
    final client = _client;
    if (client == null || ip.isEmpty) return false;

    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: _daemonPath,
    );

    try {
      final current = List<String>.from(customDevices.value);
      try {
        final prop = await remote.getProperty(_daemonInterface, 'customDevices');
        if (prop is DBusArray) {
          current
            ..clear()
            ..addAll(
              prop.children
                  .whereType<DBusString>()
                  .map((v) => v.value.trim())
                  .where((v) => v.isNotEmpty),
            );
        }
      } catch (_) {}

      current.remove(ip);
      await remote.setProperty(
        _daemonInterface,
        'customDevices',
        DBusArray.string(current),
      );
      customDevices.value = List<String>.from(current);
      await _triggerNetworkRefresh();
      await _refreshDevices();
      return true;
    } catch (e) {
      debugPrint('Error removing custom device $ip: $e');
      return false;
    }
  }

  Future<void> ping(String id) async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id/ping'),
    );
    await remote.callMethod('org.kde.kdeconnect.device.ping', 'sendPing', []);
  }

  Future<void> ring(String id) async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id/findmyphone'),
    );
    await remote.callMethod('org.kde.kdeconnect.device.findmyphone', 'ring', []);
  }

  Future<void> mountSftp(String id) async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id/sftp'),
    );
    await remote.callMethod('org.kde.kdeconnect.device.sftp', 'mount', []);
  }

  Future<String?> getSftpMountPoint(String id) async {
    final client = _client;
    if (client == null) return null;
    try {
      final remote = DBusRemoteObject(
        client,
        name: _daemonBusName,
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/sftp'),
      );
      final res = await remote.getProperty(
        'org.kde.kdeconnect.device.sftp',
        'mountPoint',
      );
      return res is DBusString ? res.value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> shareText(String id, String text) async {
    final client = _client;
    if (client == null) return;
    final remote = DBusRemoteObject(
      client,
      name: _daemonBusName,
      path: DBusObjectPath('/modules/kdeconnect/devices/$id/share'),
    );
    await remote.callMethod(
      'org.kde.kdeconnect.device.share',
      'shareText',
      [DBusString(text)],
    );
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _listenedDeviceIds.clear();
    _daemonSignalsAttached = false;
    _initialized = false;
    _client?.close();
    _client = null;
  }
}
