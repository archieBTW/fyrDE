import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class KdeConnectDevice {
  final String id;
  final String name;
  final bool isPaired;
  final bool isReachable;
  final int batteryLevel;
  final bool isCharging;

  KdeConnectDevice({
    required this.id,
    required this.name,
    this.isPaired = false,
    this.isReachable = false,
    this.batteryLevel = -1,
    this.isCharging = false,
  });

  KdeConnectDevice copyWith({
    bool? isPaired,
    bool? isReachable,
    int? batteryLevel,
    bool? isCharging,
    String? name,
  }) {
    return KdeConnectDevice(
      id: id,
      name: name ?? this.name,
      isPaired: isPaired ?? this.isPaired,
      isReachable: isReachable ?? this.isReachable,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
    );
  }
}

class KdeConnectService {
  static final KdeConnectService _instance = KdeConnectService._internal();
  factory KdeConnectService() => _instance;
  KdeConnectService._internal();

  late DBusClient _client;
  final ValueNotifier<List<KdeConnectDevice>> devices = ValueNotifier([]);
  final ValueNotifier<bool> isAvailable = ValueNotifier(false);

  Future<void> init() async {
    _client = DBusClient.session();

    try {
      final remote = DBusRemoteObject(_client,
          name: 'org.kde.kdeconnect', path: DBusObjectPath('/modules/kdeconnect'));
      await remote.callMethod('org.kde.kdeconnect.daemon', 'forceOnNetworkChange', []);

      await _refreshDevices();
      _listenToDaemonSignals();
      isAvailable.value = true;
      
      // Periodic refresh every 30 seconds
      Timer.periodic(const Duration(seconds: 30), (_) => _refreshDevices());
    } catch (e) {
      print('KDE Connect daemon not found or error: $e');
      isAvailable.value = false;
    }
  }

  Future<void> _refreshDevices() async {
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect', path: DBusObjectPath('/modules/kdeconnect'));

    final response = await remote.callMethod(
      'org.kde.kdeconnect.daemon',
      'devices',
      [const DBusBoolean(false), const DBusBoolean(false)], // showPaired, showUnpaired
    );

    final List<String> deviceIds = (response.values[0] as DBusArray)
        .children
        .map((v) => (v as DBusString).value)
        .toList();

    List<KdeConnectDevice> newDevices = [];
    for (var id in deviceIds) {
      final device = await _getDeviceInfo(id);
      newDevices.add(device);
      _listenToDeviceSignals(id);
    }
    devices.value = newDevices;
  }

  Future<KdeConnectDevice> _getDeviceInfo(String id) async {
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id'));

    final nameRes = await remote.getProperty('org.kde.kdeconnect.device', 'name');
    final pairedRes = await remote.getProperty('org.kde.kdeconnect.device', 'isPaired');
    final reachableRes = await remote.getProperty('org.kde.kdeconnect.device', 'isReachable');

    int battery = -1;
    bool charging = false;
    try {
      final batteryRemote = DBusRemoteObject(_client,
          name: 'org.kde.kdeconnect',
          path: DBusObjectPath('/modules/kdeconnect/devices/$id/battery'));
      final bRes = await batteryRemote.getProperty('org.kde.kdeconnect.device.battery', 'charge');
      final cRes = await batteryRemote.getProperty('org.kde.kdeconnect.device.battery', 'isCharging');
      battery = (bRes as DBusInt32).value;
      charging = (cRes as DBusBoolean).value;
    } catch (_) {}

    return KdeConnectDevice(
      id: id,
      name: (nameRes as DBusString).value,
      isPaired: (pairedRes as DBusBoolean).value,
      isReachable: (reachableRes as DBusBoolean).value,
      batteryLevel: battery,
      isCharging: charging,
    );
  }

  void _listenToDaemonSignals() {
    final stream = DBusSignalStream(_client,
            sender: 'org.kde.kdeconnect',
            interface: 'org.kde.kdeconnect.daemon');
            
    stream.listen((signal) {
      if (signal.name == 'deviceListChanged' || 
          signal.name == 'deviceAdded' || 
          signal.name == 'deviceRemoved') {
        _refreshDevices();
      }
    });
  }

  void _listenToDeviceSignals(String id) {
    DBusSignalStream(_client,
            sender: 'org.kde.kdeconnect',
            path: DBusObjectPath('/modules/kdeconnect/devices/$id'))
        .listen((signal) {
      _updateDeviceState(id);
    });

    DBusSignalStream(_client,
            sender: 'org.kde.kdeconnect',
            path: DBusObjectPath('/modules/kdeconnect/devices/$id/notifications'),
            interface: 'org.kde.kdeconnect.device.notifications')
        .listen((signal) {
      if (signal.name == 'notificationPosted') {
        _handleNotification(id, signal.values);
      }
    });
  }

  Future<void> _updateDeviceState(String id) async {
    final updated = await _getDeviceInfo(id);
    final list = List<KdeConnectDevice>.from(devices.value);
    final index = list.indexWhere((d) => d.id == id);
    if (index != -1) {
      list[index] = updated;
      devices.value = list;
    }
  }

  void _handleNotification(String deviceId, List<DBusValue> values) async {
    final notificationId = (values[0] as DBusString).value;
    
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$deviceId/notifications/$notificationId'));
        
    try {
      final title = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'title') as DBusString).value;
      final text = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'text') as DBusString).value;
      final appName = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'appName') as DBusString).value;
      
      // Forward to desktop notifications
      final desktopNotify = DBusRemoteObject(_client,
          name: 'org.freedesktop.Notifications',
          path: DBusObjectPath('/org/freedesktop/Notifications'));
          
      await desktopNotify.callMethod('org.freedesktop.Notifications', 'Notify', [
        DBusString(appName),
        const DBusUint32(0),
        const DBusString('phone'),
        DBusString('$title (from phone)'),
        DBusString(text),
        DBusArray(DBusSignature('s'), []),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {}),
        const DBusInt32(5000),
      ]);
    } catch (e) {
      print('Error fetching notification details: $e');
    }
  }

  Future<void> pair(String id) async {
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id'));
    await remote.callMethod('org.kde.kdeconnect.device', 'pair', []);
  }

  Future<void> unpair(String id) async {
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id'));
    await remote.callMethod('org.kde.kdeconnect.device', 'unpair', []);
  }

  Future<void> addDeviceByIp(String ip) async {
    final remote = DBusRemoteObject(_client,
        name: 'org.kde.kdeconnect', path: DBusObjectPath('/modules/kdeconnect'));
    await remote.callMethod('org.kde.kdeconnect.daemon', 'addDeviceByIp', [DBusString(ip)]);
  }

  void dispose() {
    _client.close();
  }
}
