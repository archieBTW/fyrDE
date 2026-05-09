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
  static final Set<String> _listenedDevices = {};

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
          
          if (isReachable) {
            _setupNotificationListener(id);
          }
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
  
  static Future<void> ring(String id) async {
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/findmyphone'));
    await remote.callMethod('org.kde.kdeconnect.device.findmyphone', 'ring', []);
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
  }

  static Future<void> shareText(String id, String text) async {
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath('/modules/kdeconnect/devices/$id/share'));
    await remote.callMethod('org.kde.kdeconnect.device.share', 'shareText', [DBusString(text)]);
  }

  static void _setupNotificationListener(String id) {
    if (_listenedDevices.contains(id)) return;
    _listenedDevices.add(id);

    DBusSignalStream(_client!,
            sender: 'org.kde.kdeconnect',
            path: DBusObjectPath('/modules/kdeconnect/devices/$id/notifications'),
            interface: 'org.kde.kdeconnect.device.notifications')
        .listen((signal) {
      if (signal.name == 'notificationPosted') {
        _handlePhoneNotification(id, signal.values);
      }
    });
  }

  static void _handlePhoneNotification(String deviceId, List<DBusValue> values) async {
    final rawNotificationId = (values[0] as DBusString).value;
    // KDE Connect sanitizes IDs for object paths by replacing non-alphanumeric with _
    final notificationId = rawNotificationId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    
    final path = '/modules/kdeconnect/devices/$deviceId/notifications/$notificationId';
    final remote = DBusRemoteObject(_client!,
        name: 'org.kde.kdeconnect',
        path: DBusObjectPath(path));
        
    try {
      final title = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'title') as DBusString).value;
      final text = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'text') as DBusString).value;
      final appName = (await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'appName') as DBusString).value;
      
      List<String> actions = [];
      try {
        final actionsRes = await remote.getProperty('org.kde.kdeconnect.device.notifications.notification', 'actions');
        actions = (actionsRes as DBusArray).children.map((v) => (v as DBusString).value).toList();
      } catch (_) {}

      SystemState.addNotification(
        appName: appName,
        title: '$title (from phone)',
        body: text,
        icon: 'phone',
        actions: actions,
      );
    } catch (e) {
      print('Error fetching phone notification details: $e');
    }
  }
}
