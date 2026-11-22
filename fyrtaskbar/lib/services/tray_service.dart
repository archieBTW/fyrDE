import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:fyrtaskbar/fyr_theme.dart';

class TrayMenuEntry {
  final int id;
  final String label;
  final bool enabled;
  final bool isSeparator;
  final bool? checked;
  final List<TrayMenuEntry> children;

  const TrayMenuEntry({
    required this.id,
    required this.label,
    this.enabled = true,
    this.isSeparator = false,
    this.checked,
    this.children = const [],
  });
}

class TrayItem {
  final String serviceKey; // "$busName$objectPath"
  final String busName;
  final String uniqueOwner;
  final String objectPath;
  final String interfaceName;
  final String id;
  final String title;
  final String tooltip;
  final String iconAccessibleDesc;
  final String status; // 'Passive', 'Active', 'NeedsAttention'
  final String iconName;
  final String iconThemePath;
  final String? resolvedIconFile;
  final ui.Image? pixmapImage;
  final bool itemIsMenu;
  final String? menuPath;

  const TrayItem({
    required this.serviceKey,
    required this.busName,
    this.uniqueOwner = '',
    required this.objectPath,
    this.interfaceName = 'org.kde.StatusNotifierItem',
    required this.id,
    required this.title,
    required this.tooltip,
    this.iconAccessibleDesc = '',
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.resolvedIconFile,
    required this.pixmapImage,
    required this.itemIsMenu,
    required this.menuPath,
  });

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (tooltip.isNotEmpty) return tooltip;
    if (id.isNotEmpty) return id;
    return busName;
  }

  String get displayLabel {
    if (title.isNotEmpty &&
        iconAccessibleDesc.isNotEmpty &&
        iconAccessibleDesc.toLowerCase() != title.toLowerCase()) {
      return '$title — $iconAccessibleDesc';
    }
    if (tooltip.isNotEmpty) return tooltip;
    if (title.isNotEmpty) return title;
    if (iconAccessibleDesc.isNotEmpty) return iconAccessibleDesc;
    if (id.isNotEmpty) return id;
    return busName;
  }
}

class _StatusNotifierWatcherObject extends DBusObject {
  final Future<void> Function(String service, String? sender) onRegisterItem;
  final List<String> Function() getRegisteredItems;
  final void Function(String host) onRegisterHost;

  _StatusNotifierWatcherObject({
    required this.onRegisterItem,
    required this.getRegisteredItems,
    required this.onRegisterHost,
  }) : super(DBusObjectPath('/StatusNotifierWatcher'));

  static const _kdeIface = 'org.kde.StatusNotifierWatcher';
  static const _fdoIface = 'org.freedesktop.StatusNotifierWatcher';
  static const _ifaces = [_kdeIface, _fdoIface];

  static DBusIntrospectInterface _buildIntrospect(String iface) =>
      DBusIntrospectInterface(
        iface,
        methods: [
          DBusIntrospectMethod(
            'RegisterStatusNotifierItem',
            args: [
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.in_,
                name: 'service',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'RegisterStatusNotifierHost',
            args: [
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.in_,
                name: 'service',
              ),
            ],
          ),
        ],
        properties: [
          DBusIntrospectProperty(
            'RegisteredStatusNotifierItems',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'IsStatusNotifierHostRegistered',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'ProtocolVersion',
            DBusSignature('i'),
            access: DBusPropertyAccess.read,
          ),
        ],
        signals: [
          DBusIntrospectSignal(
            'StatusNotifierItemRegistered',
            args: [
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.out,
              ),
            ],
          ),
          DBusIntrospectSignal(
            'StatusNotifierItemUnregistered',
            args: [
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.out,
              ),
            ],
          ),
          DBusIntrospectSignal('StatusNotifierHostRegistered'),
        ],
      );

  @override
  List<DBusIntrospectInterface> introspect() =>
      _ifaces.map(_buildIntrospect).toList();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (_ifaces.contains(methodCall.interface)) {
      if (methodCall.name == 'RegisterStatusNotifierItem') {
        final service = methodCall.values.isNotEmpty &&
                methodCall.values.first is DBusString
            ? (methodCall.values.first as DBusString).value
            : '';
        final sender = methodCall.sender;
        // Reply immediately before querying the item's D-Bus properties.
        // Single-threaded clients (e.g. ProtonVPN/GTK/libappindicator) call
        // RegisterStatusNotifierItem synchronously and deadlock on GetAll if
        // we wait here before sending the reply.
        Future.delayed(Duration.zero, () {
          onRegisterItem(service, sender);
        });
        return DBusMethodSuccessResponse();
      }
      if (methodCall.name == 'RegisterStatusNotifierHost') {
        final host = methodCall.values.isNotEmpty &&
                methodCall.values.first is DBusString
            ? (methodCall.values.first as DBusString).value
            : '';
        onRegisterHost(host);
        return DBusMethodSuccessResponse();
      }
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (_ifaces.contains(interface)) {
      if (name == 'RegisteredStatusNotifierItems') {
        return DBusGetPropertyResponse(
          DBusArray.string(getRegisteredItems()),
        );
      }
      if (name == 'IsStatusNotifierHostRegistered') {
        return DBusGetPropertyResponse(const DBusBoolean(true));
      }
      if (name == 'ProtocolVersion') {
        return DBusGetPropertyResponse(const DBusInt32(0));
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (_ifaces.contains(interface)) {
      return DBusGetAllPropertiesResponse({
        'RegisteredStatusNotifierItems':
            DBusArray.string(getRegisteredItems()),
        'IsStatusNotifierHostRegistered': const DBusBoolean(true),
        'ProtocolVersion': const DBusInt32(0),
      });
    }
    return DBusGetAllPropertiesResponse({});
  }

  void emitRegistered(String serviceKey) {
    for (final iface in _ifaces) {
      emitSignal(iface, 'StatusNotifierItemRegistered', [
        DBusString(serviceKey),
      ]);
    }
  }

  void emitUnregistered(String serviceKey) {
    for (final iface in _ifaces) {
      emitSignal(iface, 'StatusNotifierItemUnregistered', [
        DBusString(serviceKey),
      ]);
    }
  }

  void emitHostRegistered() {
    for (final iface in _ifaces) {
      emitSignal(iface, 'StatusNotifierHostRegistered', []);
    }
  }
}

class TrayService {
  static const _kdeWatcherBus = 'org.kde.StatusNotifierWatcher';
  static const _fdoWatcherBus = 'org.freedesktop.StatusNotifierWatcher';
  static const _watcherBuses = [_kdeWatcherBus, _fdoWatcherBus];

  static const _kdeItemIface = 'org.kde.StatusNotifierItem';
  static const _fdoItemIface = 'org.freedesktop.StatusNotifierItem';
  static const _menuIface = 'com.canonical.dbusmenu';

  static final ValueNotifier<List<TrayItem>> items = ValueNotifier([]);

  static DBusClient? _client;
  static _StatusNotifierWatcherObject? _watcher;
  static StreamSubscription<DBusSignal>? _nameOwnerSub;
  static final Set<String> _ownedWatchers = {};
  static final Map<String, StreamSubscription<DBusSignal>> _externalWatcherSubs =
      {};
  static final Map<String, TrayItem> _itemMap = {};
  static final Map<String, List<StreamSubscription<DBusSignal>>> _itemSubs = {};
  static final Map<String, Timer> _refreshTimers = {};
  static final Map<String, String?> _iconCache = {};

  static Future<void> init() async {
    if (_client != null) return;
    try {
      _client = DBusClient.session();

      _watcher = _StatusNotifierWatcherObject(
        onRegisterItem: _handleRegisterItem,
        getRegisteredItems: () => _itemMap.keys.toList(),
        onRegisterHost: (_) => _watcher?.emitHostRegistered(),
      );

      await _client!.registerObject(_watcher!);

      for (final busName in _watcherBuses) {
        await _claimOrSyncWatcher(busName);
      }

      // Pick up any already-running StatusNotifierItem apps (e.g. after a
      // taskbar restart while ProtonVPN or other tray apps are open).
      await _discoverExistingItems();

      _nameOwnerSub = DBusSignalStream(
        _client!,
        sender: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
      ).listen((signal) {
        if (signal.values.length >= 3) {
          final name = (signal.values[0] as DBusString).value;
          final newOwner = (signal.values[2] as DBusString).value;
          if (newOwner.isEmpty) {
            _removeByBusName(name);
            if (_watcherBuses.contains(name) && !_ownedWatchers.contains(name)) {
              _claimOrSyncWatcher(name);
            }
          }
        }
      });
    } catch (_) {}
  }

  static Future<void> _claimOrSyncWatcher(String watcherBus) async {
    if (_client == null) return;
    try {
      final reply = await _client!.requestName(
        watcherBus,
        flags: {
          DBusRequestNameFlag.replaceExisting,
          DBusRequestNameFlag.doNotQueue,
        },
      );

      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _ownedWatchers.add(watcherBus);
        await _externalWatcherSubs.remove(watcherBus)?.cancel();
        _watcher?.emitHostRegistered();
      } else {
        await _syncFromExternalWatcher(watcherBus);
      }
    } catch (_) {}
  }

  static Future<void> _syncFromExternalWatcher(String watcherBus) async {
    if (_client == null) return;
    try {
      final hostPrefix = watcherBus.startsWith('org.freedesktop.')
          ? 'org.freedesktop.StatusNotifierHost'
          : 'org.kde.StatusNotifierHost';
      final hostName = '$hostPrefix-$pid';
      try {
        await _client!.requestName(hostName);
      } catch (_) {}

      final remote = DBusRemoteObject(
        _client!,
        name: watcherBus,
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      try {
        await remote
            .callMethod(watcherBus, 'RegisterStatusNotifierHost', [
              DBusString(hostName),
            ])
            .timeout(const Duration(seconds: 1));
      } catch (_) {}

      final prop = await remote
          .getProperty(watcherBus, 'RegisteredStatusNotifierItems')
          .timeout(const Duration(seconds: 1));
      if (prop is DBusArray) {
        for (final v in prop.children.whereType<DBusString>()) {
          await _handleRegisterItem(v.value, null);
        }
      }

      await _externalWatcherSubs[watcherBus]?.cancel();
      _externalWatcherSubs[watcherBus] = DBusSignalStream(
        _client!,
        sender: watcherBus,
        path: DBusObjectPath('/StatusNotifierWatcher'),
        interface: watcherBus,
      ).listen((sig) {
        if (sig.values.isEmpty || sig.values.first is! DBusString) return;
        final key = (sig.values.first as DBusString).value;
        if (sig.name == 'StatusNotifierItemRegistered') {
          _handleRegisterItem(key, null);
        } else if (sig.name == 'StatusNotifierItemUnregistered') {
          _removeByServiceKey(key);
        }
      });
    } catch (_) {}
  }

  @visibleForTesting
  static (String, String) parseRegistration(String service, String? sender) {
    final trimmed = service.trim();
    if (trimmed.startsWith('/')) {
      return (sender ?? '', trimmed);
    }
    final slashIdx = trimmed.indexOf('/');
    if (slashIdx > 0) {
      return (trimmed.substring(0, slashIdx), trimmed.substring(slashIdx));
    }
    return (
      trimmed.isNotEmpty ? trimmed : (sender ?? ''),
      '/StatusNotifierItem',
    );
  }

  static Future<void> _discoverExistingItems() async {
    if (_client == null) return;
    try {
      final dbus = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      );
      final res = await dbus
          .callMethod('org.freedesktop.DBus', 'ListNames', [])
          .timeout(const Duration(seconds: 1));
      if (res.values.isEmpty || res.values.first is! DBusArray) return;
      for (final nameVal in (res.values.first as DBusArray).children) {
        if (nameVal is! DBusString) continue;
        final name = nameVal.value;
        if (name.startsWith('org.kde.StatusNotifierItem-') ||
            name.startsWith('org.freedesktop.StatusNotifierItem-')) {
          await _handleRegisterItem(name, null);
        }
      }
    } catch (_) {}
  }

  static Future<void> _handleRegisterItem(String service, String? sender) async {
    final (busName, objectPath) = parseRegistration(service, sender);
    if (busName.isEmpty || !objectPath.startsWith('/')) return;

    final serviceKey = '$busName$objectPath';
    var item = await _fetchItem(serviceKey, busName, objectPath);
    if (item == null) {
      // Retry once in case the client registered before finishing object export.
      await Future.delayed(const Duration(milliseconds: 300));
      item = await _fetchItem(serviceKey, busName, objectPath);
    }
    if (item == null) return;

    final isNew = !_itemMap.containsKey(serviceKey);
    _itemMap[serviceKey] = item;
    _publishItems();

    if (isNew) {
      _watcher?.emitRegistered(serviceKey);
      _listenToItem(serviceKey, item);
    }
  }

  static void _scheduleRefresh(TrayItem item) {
    final key = item.serviceKey;
    _refreshTimers[key]?.cancel();
    _refreshTimers[key] = Timer(const Duration(milliseconds: 60), () async {
      _refreshTimers.remove(key);
      if (!_itemMap.containsKey(key)) return;
      final updated = await _fetchItem(key, item.busName, item.objectPath);
      if (updated != null && _itemMap.containsKey(key)) {
        _itemMap[key] = updated;
        _publishItems();
      }
    });
  }

  static void _listenToItem(String serviceKey, TrayItem item) {
    if (_client == null) return;
    final oldSubs = _itemSubs.remove(serviceKey);
    if (oldSubs != null) {
      for (final s in oldSubs) {
        s.cancel();
      }
    }

    final targetSender =
        item.uniqueOwner.isNotEmpty ? item.uniqueOwner : item.busName;

    final sniSub = DBusSignalStream(
      _client!,
      sender: targetSender,
      path: DBusObjectPath(item.objectPath),
      interface: item.interfaceName,
    ).listen((_) => _scheduleRefresh(item));

    final propsSub = DBusSignalStream(
      _client!,
      sender: targetSender,
      path: DBusObjectPath(item.objectPath),
      interface: 'org.freedesktop.DBus.Properties',
      name: 'PropertiesChanged',
    ).listen((_) => _scheduleRefresh(item));

    _itemSubs[serviceKey] = [sniSub, propsSub];
  }

  static void _removeByBusName(String busName) {
    final toRemove = _itemMap.values
        .where((i) => i.busName == busName || i.uniqueOwner == busName)
        .map((i) => i.serviceKey)
        .toList();
    for (final key in toRemove) {
      _removeByServiceKey(key);
    }
  }

  static void _removeByServiceKey(String serviceKey) {
    if (!_itemMap.containsKey(serviceKey)) return;
    _refreshTimers.remove(serviceKey)?.cancel();
    final subs = _itemSubs.remove(serviceKey);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _itemMap.remove(serviceKey);
    _publishItems();
    _watcher?.emitUnregistered(serviceKey);
  }

  static void _publishItems() {
    items.value = _itemMap.values
        .where((i) => i.status != 'Passive')
        .toList();
  }

  static Future<String> _resolveUniqueOwner(String busName) async {
    if (_client == null || busName.startsWith(':')) return busName;
    try {
      final dbus = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      );
      final res = await dbus
          .callMethod('org.freedesktop.DBus', 'GetNameOwner', [
            DBusString(busName),
          ])
          .timeout(const Duration(milliseconds: 500));
      if (res.values.isNotEmpty && res.values.first is DBusString) {
        return (res.values.first as DBusString).value;
      }
    } catch (_) {}
    return '';
  }

  static Future<TrayItem?> _fetchItem(
    String serviceKey,
    String busName,
    String objectPath,
  ) async {
    if (_client == null) return null;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: busName,
        path: DBusObjectPath(objectPath),
      );

      String activeIface = _kdeItemIface;
      Map<String, DBusValue> props = {};
      for (final iface in [_kdeItemIface, _fdoItemIface]) {
        try {
          final fetched = await obj
              .getAllProperties(iface)
              .timeout(const Duration(seconds: 2));
          if (fetched.isNotEmpty) {
            props = fetched;
            activeIface = iface;
            break;
          }
        } catch (_) {}
      }
      if (props.isEmpty) return null;

      String readStr(String key) {
        final v = props[key];
        return v is DBusString ? v.value : '';
      }

      final id = readStr('Id');
      final title = readStr('Title');
      final statusRaw = readStr('Status');
      final status = statusRaw.isNotEmpty ? statusRaw : 'Active';
      final iconThemePath = readStr('IconThemePath');
      final iconAccessibleDesc = readStr('IconAccessibleDesc').trim();
      final itemIsMenu = (props['ItemIsMenu'] as DBusBoolean?)?.value ?? false;

      String iconName = readStr('IconName');
      DBusValue? pixmapVal = props['IconPixmap'];
      if (status == 'NeedsAttention') {
        final attnName = readStr('AttentionIconName');
        if (attnName.isNotEmpty) {
          iconName = attnName;
        }
        if (props['AttentionIconPixmap'] is DBusArray &&
            (props['AttentionIconPixmap'] as DBusArray).children.isNotEmpty) {
          pixmapVal = props['AttentionIconPixmap'];
        }
      }

      String? menuPath;
      final menuVal = props['Menu'];
      if (menuVal is DBusObjectPath &&
          menuVal.value.isNotEmpty &&
          menuVal.value != '/') {
        menuPath = menuVal.value;
      }

      String tooltip = '';
      final ttVal = props['ToolTip'];
      if (ttVal is DBusStruct && ttVal.children.length >= 3) {
        final ttTitle = ttVal.children[2] is DBusString
            ? (ttVal.children[2] as DBusString).value.trim()
            : '';
        final ttDesc = ttVal.children.length >= 4 && ttVal.children[3] is DBusString
            ? (ttVal.children[3] as DBusString).value.trim()
            : '';
        if (ttTitle.isNotEmpty && ttDesc.isNotEmpty && ttDesc != ttTitle) {
          tooltip = '$ttTitle — $ttDesc';
        } else {
          tooltip = ttTitle.isNotEmpty ? ttTitle : ttDesc;
        }
      }

      ui.Image? pixmapImage;
      final resolvedIcon = _resolveIconFile(iconName, iconThemePath);
      if (resolvedIcon == null && pixmapVal is DBusArray) {
        pixmapImage = await _decodeBestPixmap(pixmapVal);
      }

      final uniqueOwner = await _resolveUniqueOwner(busName);

      return TrayItem(
        serviceKey: serviceKey,
        busName: busName,
        uniqueOwner: uniqueOwner,
        objectPath: objectPath,
        interfaceName: activeIface,
        id: id,
        title: title,
        tooltip: tooltip,
        iconAccessibleDesc: iconAccessibleDesc,
        status: status,
        iconName: iconName,
        iconThemePath: iconThemePath,
        resolvedIconFile: resolvedIcon,
        pixmapImage: pixmapImage,
        itemIsMenu: itemIsMenu,
        menuPath: menuPath,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _decodeBestPixmap(DBusArray pixmaps) async {
    int bestW = 0;
    int bestH = 0;
    List<int>? bestBytes;
    int bestScore = 1 << 30;

    for (final entry in pixmaps.children) {
      if (entry is! DBusStruct || entry.children.length < 3) continue;
      final w = (entry.children[0] as DBusInt32?)?.value ?? 0;
      final h = (entry.children[1] as DBusInt32?)?.value ?? 0;
      final raw = entry.children[2];
      if (w <= 0 || h <= 0 || raw is! DBusArray) continue;
      final bytes = raw.children.whereType<DBusByte>().map((b) => b.value).toList();
      if (bytes.length != w * h * 4) continue;
      final score = (w - 24).abs();
      if (score < bestScore) {
        bestScore = score;
        bestW = w;
        bestH = h;
        bestBytes = bytes;
      }
    }

    if (bestBytes == null || bestW <= 0 || bestH <= 0) return null;

    // StatusNotifierItem IconPixmap is ARGB32 in network byte order (A, R, G, B).
    // Flutter decodeImageFromPixels expects RGBA8888 (R, G, B, A).
    final rgba = Uint8List(bestBytes.length);
    for (int i = 0; i < bestBytes.length; i += 4) {
      rgba[i] = bestBytes[i + 1];
      rgba[i + 1] = bestBytes[i + 2];
      rgba[i + 2] = bestBytes[i + 3];
      rgba[i + 3] = bestBytes[i];
    }

    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      rgba,
      bestW,
      bestH,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => null,
    );
  }

  static String? _resolveIconFile(String iconName, String iconThemePath) {
    if (iconName.isEmpty) return null;
    if (iconName.startsWith('/')) {
      return File(iconName).existsSync() ? iconName : null;
    }

    final activeTheme = FyrTheme.iconThemeName;
    final cacheKey = '$activeTheme::$iconThemePath::$iconName';
    if (_iconCache.containsKey(cacheKey)) return _iconCache[cacheKey];

    const exts = ['.svg', '.png', '.xpm'];
    final home = Platform.environment['HOME'] ?? '';

    List<String> themeDirs(String theme) {
      if (theme.isEmpty) return const [];
      const subpaths = [
        '24x24/panel',
        '22x22/panel',
        '24x24/status',
        '22x22/status',
        'scalable/status',
        'symbolic/status',
        '24x24/apps',
        '32x32/apps',
        '48x48/apps',
        'scalable/apps',
        'symbolic/apps',
        '16x16/panel',
        '16x16/status',
        '16x16/apps',
      ];
      return [
        for (final sub in subpaths) ...[
          if (home.isNotEmpty) '$home/.local/share/icons/$theme/$sub',
          '/usr/share/icons/$theme/$sub',
        ],
      ];
    }

    final searchDirs = <String>[
      if (iconThemePath.isNotEmpty) iconThemePath,
      ...themeDirs(activeTheme),
      if (home.isNotEmpty) ...[
        '$home/.local/share/icons/hicolor/scalable/status',
        '$home/.local/share/icons/hicolor/scalable/apps',
        '$home/.local/share/icons/hicolor/48x48/apps',
        '$home/.local/share/icons/hicolor/32x32/apps',
        '$home/.local/share/icons/hicolor/24x24/apps',
        '$home/.local/share/icons/hicolor/22x22/status',
      ],
      '/usr/share/icons/Papirus-Dark/24x24/panel',
      '/usr/share/icons/Papirus-Dark/24x24/apps',
      '/usr/share/icons/Papirus/24x24/panel',
      '/usr/share/icons/Papirus/24x24/apps',
      '/usr/share/icons/hicolor/scalable/status',
      '/usr/share/icons/hicolor/scalable/apps',
      '/usr/share/icons/hicolor/48x48/apps',
      '/usr/share/icons/hicolor/32x32/apps',
      '/usr/share/icons/hicolor/24x24/status',
      '/usr/share/icons/hicolor/24x24/apps',
      '/usr/share/icons/hicolor/22x22/status',
      '/usr/share/icons/hicolor/22x22/apps',
      '/usr/share/icons/hicolor/16x16/status',
      '/usr/share/icons/hicolor/16x16/apps',
      '/usr/share/icons/Adwaita/scalable/status',
      '/usr/share/icons/Adwaita/symbolic/status',
      '/usr/share/pixmaps',
    ];

    for (final dir in searchDirs) {
      for (final ext in exts) {
        final path = '$dir/$iconName$ext';
        if (File(path).existsSync()) {
          _iconCache[cacheKey] = path;
          return path;
        }
      }
      // Also check subdirectories in custom iconThemePath (e.g. hicolor/24x24/apps)
      if (dir == iconThemePath && Directory(dir).existsSync()) {
        try {
          for (final entity in Directory(dir).listSync(recursive: true)) {
            if (entity is File) {
              final base = entity.uri.pathSegments.last;
              for (final ext in exts) {
                if (base == '$iconName$ext') {
                  _iconCache[cacheKey] = entity.path;
                  return entity.path;
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    _iconCache[cacheKey] = null;
    return null;
  }

  static Future<bool> activate(TrayItem item, int x, int y) async {
    if (_client == null) return false;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: item.busName,
        path: DBusObjectPath(item.objectPath),
      );
      await obj
          .callMethod(item.interfaceName, 'Activate', [
            DBusInt32(x),
            DBusInt32(y),
          ])
          .timeout(const Duration(seconds: 1));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> secondaryActivate(TrayItem item, int x, int y) async {
    if (_client == null) return false;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: item.busName,
        path: DBusObjectPath(item.objectPath),
      );
      await obj
          .callMethod(item.interfaceName, 'SecondaryActivate', [
            DBusInt32(x),
            DBusInt32(y),
          ])
          .timeout(const Duration(seconds: 1));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> scroll(
    TrayItem item,
    int delta, {
    String orientation = 'vertical',
  }) async {
    if (_client == null) return;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: item.busName,
        path: DBusObjectPath(item.objectPath),
      );
      await obj
          .callMethod(item.interfaceName, 'Scroll', [
            DBusInt32(delta),
            DBusString(orientation),
          ])
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {}
  }

  static Future<List<TrayMenuEntry>> fetchMenu(TrayItem item) async {
    if (_client == null || item.menuPath == null) return [];
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: item.busName,
        path: DBusObjectPath(item.menuPath!),
      );
      // Let app refresh dynamic menus first if supported
      try {
        await obj
            .callMethod(_menuIface, 'AboutToShow', [const DBusInt32(0)])
            .timeout(const Duration(milliseconds: 400));
      } catch (_) {}

      final res = await obj
          .callMethod(_menuIface, 'GetLayout', [
            const DBusInt32(0),
            const DBusInt32(2),
            DBusArray.string(const [
              'label',
              'enabled',
              'visible',
              'type',
              'toggle-state',
              'toggle-type',
            ]),
          ])
          .timeout(const Duration(seconds: 2));

      if (res.values.length < 2 || res.values[1] is! DBusStruct) return [];
      final root = res.values[1] as DBusStruct;
      return _parseMenuChildren(root);
    } catch (_) {
      return [];
    }
  }

  static List<TrayMenuEntry> _parseMenuChildren(DBusStruct node) {
    if (node.children.length < 3 || node.children[2] is! DBusArray) {
      return [];
    }
    final result = <TrayMenuEntry>[];
    for (final childVariant in (node.children[2] as DBusArray).children) {
      final raw =
          childVariant is DBusVariant ? childVariant.value : childVariant;
      if (raw is! DBusStruct || raw.children.length < 3) continue;

      final id = (raw.children[0] as DBusInt32?)?.value ?? 0;
      final props = raw.children[1] is DBusDict
          ? (raw.children[1] as DBusDict).children
          : <DBusValue, DBusValue>{};

      DBusValue? prop(String name) {
        for (final e in props.entries) {
          if (e.key is DBusString && (e.key as DBusString).value == name) {
            return e.value is DBusVariant
                ? (e.value as DBusVariant).value
                : e.value;
          }
        }
        return null;
      }

      final visible = (prop('visible') as DBusBoolean?)?.value ?? true;
      if (!visible) continue;

      final type = (prop('type') as DBusString?)?.value ?? 'standard';
      final isSeparator = type == 'separator';
      final enabled = (prop('enabled') as DBusBoolean?)?.value ?? true;
      final rawLabel = (prop('label') as DBusString?)?.value ?? '';
      // Strip GTK mnemonic underscores (keeping doubled __ as literal _)
      final label = rawLabel
          .replaceAll('__', '\x00')
          .replaceAll('_', '')
          .replaceAll('\x00', '_')
          .trim();

      final toggleType = (prop('toggle-type') as DBusString?)?.value ?? '';
      final toggleState = (prop('toggle-state') as DBusInt32?)?.value;
      bool? checked;
      if (toggleType == 'checkmark' || toggleType == 'radio') {
        checked = toggleState == 1;
      }

      final children = _parseMenuChildren(raw);
      if (!isSeparator && label.isEmpty && children.isEmpty) continue;

      result.add(
        TrayMenuEntry(
          id: id,
          label: label,
          enabled: enabled,
          isSeparator: isSeparator,
          checked: checked,
          children: children,
        ),
      );
    }
    return result;
  }

  static Future<void> triggerMenuItem(TrayItem item, int menuId) async {
    if (_client == null || item.menuPath == null) return;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: item.busName,
        path: DBusObjectPath(item.menuPath!),
      );
      await obj
          .callMethod(_menuIface, 'Event', [
            DBusInt32(menuId),
            const DBusString('clicked'),
            const DBusVariant(DBusString('')),
            DBusUint32(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ])
          .timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    for (final t in _refreshTimers.values) {
      t.cancel();
    }
    _refreshTimers.clear();
    _itemMap.clear();
    _iconCache.clear();
    items.value = [];
  }

  static Future<void> dispose() async {
    await _nameOwnerSub?.cancel();
    _nameOwnerSub = null;
    for (final s in _externalWatcherSubs.values) {
      await s.cancel();
    }
    _externalWatcherSubs.clear();
    _ownedWatchers.clear();
    for (final t in _refreshTimers.values) {
      t.cancel();
    }
    _refreshTimers.clear();
    for (final subs in _itemSubs.values) {
      for (final s in subs) {
        await s.cancel();
      }
    }
    _itemSubs.clear();
    await _client?.close();
    _client = null;
  }
}
