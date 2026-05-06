import 'package:dbus/dbus.dart';
import 'main.dart';

class NotificationService extends DBusObject {
  static DBusClient? _client;

  NotificationService() : super(DBusObjectPath('/org/freedesktop/Notifications'));

  static Future<void> init() async {
    _client = DBusClient.session();
    _instance = NotificationService();
    await _client!.registerObject(_instance!);
    await _client!.requestName('org.freedesktop.Notifications',
        flags: {DBusRequestNameFlag.doNotQueue});
  }

  static NotificationService? _instance;

  static void sendActionInvoked(int id, String actionKey) {
    _instance?.emitSignal('org.freedesktop.Notifications', 'ActionInvoked', [
      DBusUint32(id),
      DBusString(actionKey),
    ]);
  }

  static void sendNotificationClosed(int id, int reason) {
    _instance?.emitSignal('org.freedesktop.Notifications', 'NotificationClosed', [
      DBusUint32(id),
      DBusUint32(reason),
    ]);
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.freedesktop.Notifications',
        methods: [
          DBusIntrospectMethod(
            'Notify',
            args: [
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'app_name'),
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.in_, name: 'replaces_id'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'app_icon'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'summary'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'body'),
              DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_, name: 'actions'),
              DBusIntrospectArgument(DBusSignature('a{sv}'), DBusArgumentDirection.in_, name: 'hints'),
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'expire_timeout'),
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'id'),
            ],
          ),
          DBusIntrospectMethod(
            'CloseNotification',
            args: [
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.in_, name: 'id'),
            ],
          ),
          DBusIntrospectMethod(
            'GetCapabilities',
            args: [
              DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.out, name: 'capabilities'),
            ],
          ),
          DBusIntrospectMethod(
            'GetServerInformation',
            args: [
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'name'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'vendor'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'version'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'spec_version'),
            ],
          ),
        ],
        signals: [
          DBusIntrospectSignal(
            'NotificationClosed',
            args: [
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'id'),
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'reason'),
            ],
          ),
          DBusIntrospectSignal(
            'ActionInvoked',
            args: [
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'id'),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'action_key'),
            ],
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.freedesktop.Notifications') {
      if (methodCall.name == 'Notify') {
        return _handleNotify(methodCall);
      } else if (methodCall.name == 'CloseNotification') {
        return _handleCloseNotification(methodCall);
      } else if (methodCall.name == 'GetCapabilities') {
        return _handleGetCapabilities(methodCall);
      } else if (methodCall.name == 'GetServerInformation') {
        return _handleGetServerInformation(methodCall);
      }
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  Future<DBusMethodResponse> _handleNotify(DBusMethodCall methodCall) async {
    final appName = (methodCall.values[0] as DBusString).value;
    final appIcon = (methodCall.values[2] as DBusString).value;
    final summary = (methodCall.values[3] as DBusString).value;
    final body = (methodCall.values[4] as DBusString).value;
    final expireTimeout = (methodCall.values[7] as DBusInt32).value;

    SystemState.addNotification(
      appName: appName,
      title: summary,
      body: body,
      icon: appIcon,
      timeout: expireTimeout > 0 ? expireTimeout : 5000,
    );

    return DBusMethodSuccessResponse([DBusUint32(1)]);
  }

  Future<DBusMethodResponse> _handleCloseNotification(DBusMethodCall methodCall) async {
    final id = (methodCall.values[0] as DBusUint32).value;
    SystemState.dismissNotification(id.toInt());
    return DBusMethodSuccessResponse([]);
  }

  Future<DBusMethodResponse> _handleGetCapabilities(DBusMethodCall methodCall) async {
    return DBusMethodSuccessResponse([
      DBusArray.string(['body', 'actions', 'icon-static'])
    ]);
  }

  Future<DBusMethodResponse> _handleGetServerInformation(DBusMethodCall methodCall) async {
    return DBusMethodSuccessResponse([
      DBusString('FyrDE Notification Server'),
      DBusString('archieBTW'),
      DBusString('1.0.0'),
      DBusString('1.2'),
    ]);
  }
}
