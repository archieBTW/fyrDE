import 'dart:async';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'main.dart';

class PhoneInfo {
  final String id;
  final String name;
  final bool isPaired;
  final bool isConnected;
  final int batteryLevel;
  final bool isCharging;

  PhoneInfo({
    required this.id,
    required this.name,
    this.isPaired = false,
    this.isConnected = false,
    this.batteryLevel = 0,
    this.isCharging = false,
  });
}

class PhoneService {
  static DBusClient? _client;
  static Timer? _timer;
  static bool _isUpdating = false;

  static void init() {
    _client = DBusClient.session();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _update());
    
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect', path: DBusObjectPath('/modules/kdeconnect'));
    
    DBusSignalStream(_client!,
            sender: 'org.kde.kdeconnect',
            path: DBusObjectPath('/modules/kdeconnect'),
            interface: 'org.kde.kdeconnect.daemon')
        .listen((signal) {
      if (signal.name == 'deviceListChanged' || 
          signal.name == 'deviceAdded' || 
          signal.name == 'deviceRemoved') {
        _update();
      }
    });
  }

  static Future<void> _update() async {
    if (_client == null || _isUpdating) return;
    _isUpdating = true;
    try {
      final remote = DBusRemoteObject(_client!,
          name: 'org.kde.kdeconnect', path: DBusObjectPath('/modules/kdeconnect'));
      final response = await remote.callMethod(
        'org.kde.kdeconnect.daemon',
        'devices',
        [const DBusBoolean(false), const DBusBoolean(false)],
      ).timeout(const Duration(seconds: 3));

      final deviceIds = (response.values[0] as DBusArray).children.map((v) => (v as DBusString).value).toList();
      
      if (deviceIds.isEmpty) {
        SystemState.primaryPhone.value = null;
        return;
      }

      PhoneInfo? bestCandidate;

      for (var id in deviceIds) {
        final deviceRemote = DBusRemoteObject(_client!,
            name: 'org.kde.kdeconnect',
            path: DBusObjectPath('/modules/kdeconnect/devices/$id'));
        
        final isPaired = (await deviceRemote.getProperty('org.kde.kdeconnect.device', 'isPaired').timeout(const Duration(seconds: 1)) as DBusBoolean).value;
        final isReachable = (await deviceRemote.getProperty('org.kde.kdeconnect.device', 'isReachable').timeout(const Duration(seconds: 1)) as DBusBoolean).value;
        final name = (await deviceRemote.getProperty('org.kde.kdeconnect.device', 'name').timeout(const Duration(seconds: 1)) as DBusString).value;

        if (isPaired && isReachable) {
          int battery = 0;
          bool charging = false;
          try {
            final batteryRemote = DBusRemoteObject(_client!,
                name: 'org.kde.kdeconnect',
                path: DBusObjectPath('/modules/kdeconnect/devices/$id/battery'));
            battery = (await batteryRemote.getProperty('org.kde.kdeconnect.device.battery', 'charge').timeout(const Duration(seconds: 1)) as DBusInt32).value;
            charging = (await batteryRemote.getProperty('org.kde.kdeconnect.device.battery', 'isCharging').timeout(const Duration(seconds: 1)) as DBusBoolean).value;
          } catch (_) {}

          bestCandidate = PhoneInfo(
            id: id,
            name: name,
            isPaired: isPaired,
            isConnected: isReachable,
            batteryLevel: battery,
            isCharging: charging,
          );
          break;
        } else if (isPaired && bestCandidate == null) {
          bestCandidate = PhoneInfo(id: id, name: name, isPaired: true, isConnected: false);
        }
      }
      
      SystemState.primaryPhone.value = bestCandidate;
    } catch (_) {
      SystemState.primaryPhone.value = null;
    } finally {
      _isUpdating = false;
    }
  }
  
  static Future<void> ping(String id) async {
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/ping'));
    await remote.callMethod('org.kde.kdeconnect.device.ping', 'sendPing', []);
  }

  static Future<void> mountSftp(String id) async {
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/sftp'));
    await remote.callMethod('org.kde.kdeconnect.device.sftp', 'mount', []);
    final mpRes = await remote.getProperty('org.kde.kdeconnect.device.sftp', 'mountPoint');
    final mp = (mpRes as DBusString).value;
    if (mp.isNotEmpty) {
      Process.run('fyrfiles', [mp]);
    }
  }

  static Future<void> shareText(String id, String text) async {
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/share'));
    await remote.callMethod('org.kde.kdeconnect.device.share', 'shareText', [DBusString(text)]);
  }
}
