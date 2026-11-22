import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

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
  final String objectPath;
  final String id;
  final String title;
  final String tooltip;
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
    required this.objectPath,
    required this.id,
    required this.title,
    required this.tooltip,
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.resolvedIconFile,
    required this.pixmapImage,
    required this.itemIsMenu,
    required this.menuPath,
  });

  String get displayLabel {
    if (tooltip.isNotEmpty) return tooltip;
    if (title.isNotEmpty) return title;
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

  static const _iface = 'org.kde.StatusNotifierWatcher';

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _iface,
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
          args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out)],
        ),
        DBusIntrospectSignal(
          'StatusNotifierItemUnregistered',
          args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out)],
        ),
        DBusIntrospectSignal('StatusNotifierHostRegistered'),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == _iface) {
      if (methodCall.name == 'RegisterStatusNotifierItem') {
        final service = methodCall.values.isNotEmpty &&
                methodCall.values.first is DBusString
            ? (methodCall.values.first as DBusString).value
            : '';
        await onRegisterItem(service, methodCall.sender);
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
    if (interface == _iface) {
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
    if (interface == _iface) {
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
    emitSignal(_iface, 'StatusNotifierItemRegistered', [
      DBusString(serviceKey),
    ]);
  }

  void emitUnregistered(String serviceKey) {
    emitSignal(_iface, 'StatusNotifierItemUnregistered', [
      DBusString(serviceKey),
    ]);
  }

  void emitHostRegistered() {
    emitSignal(_iface, 'StatusNotifierHostRegistered', []);
  }
}

class TrayService {
  static const _watcherBus = 'org.kde.StatusNotifierWatcher';
  static const _itemIface = 'org.kde.StatusNotifierItem';
  static const _menuIface = 'com.canonical.dbusmenu';

  static final ValueNotifier<List<TrayItem>> items = ValueNotifier([]);

  static DBusClient? _client;
  static _StatusNotifierWatcherObject? _watcher;
  static StreamSubscription<DBusSignal>? _nameOwnerSub;
  static final Map<String, TrayItem> _itemMap = {};
  static final Map<String, StreamSubscription<DBusSignal>> _itemSubs = {};
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
      final reply = await _client!.requestName(
        _watcherBus,
        flags: {DBusRequestNameFlag.replaceExisting},
      );

      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _watcher!.emitHostRegistered();
      } else {
        // Another watcher already owns the name — subscribe as a host and pull existing items.
        await _syncFromExternalWatcher();
      }

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
          }
        }
      });
    } catch (_) {}
  }

  static Future<void> _syncFromExternalWatcher() async {
    if (_client == null) return;
    try {
      final remote = DBusRemoteObject(
        _client!,
        name: _watcherBus,
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      await remote
          .callMethod(_watcherBus, 'RegisterStatusNotifierHost', [
            DBusString('org.kde.StatusNotifierHost-${pid}'),
          ])
          .timeout(const Duration(seconds: 1));
      final prop = await remote
          .getProperty(_watcherBus, 'RegisteredStatusNotifierItems')
          .timeout(const Duration(seconds: 1));
      if (prop is DBusArray) {
        for (final v in prop.children.whereType<DBusString>()) {
          await _handleRegisterItem(v.value, null);
        }
      }
      DBusSignalStream(
        _client!,
        sender: _watcherBus,
        path: DBusObjectPath('/StatusNotifierWatcher'),
        interface: _watcherBus,
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

  static (String, String) _parseRegistration(String service, String? sender) {
    final trimmed = service.trim();
    if (trimmed.startsWith('/')) {
      return (sender ?? '', trimmed);
    }
    final slashIdx = trimmed.indexOf('/');
    if (slashIdx > 0) {
      return (trimmed.substring(0, slashIdx), trimmed.substring(slashIdx));
    }
    return (trimmed.isNotEmpty ? trimmed : (sender ?? ''), '/StatusNotifierItem');
  }

  static Future<void> _handleRegisterItem(String service, String? sender) async {
    final (busName, objectPath) = _parseRegistration(service, sender);
    if (busName.isEmpty || !objectPath.startsWith('/')) return;

    final serviceKey = '$busName$objectPath';
    final item = await _fetchItem(serviceKey, busName, objectPath);
    if (item == null) return;

    final isNew = !_itemMap.containsKey(serviceKey);
    _itemMap[serviceKey] = item;
    _publishItems();

    if (isNew) {
      _watcher?.emitRegistered(serviceKey);
      _listenToItem(serviceKey, busName, objectPath);
    }
  }

  static void _listenToItem(
    String serviceKey,
    String busName,
    String objectPath,
  ) {
    if (_client == null) return;
    _itemSubs[serviceKey]?.cancel();
    _itemSubs[serviceKey] = DBusSignalStream(
      _client!,
      sender: busName,
      path: DBusObjectPath(objectPath),
      interface: _itemIface,
    ).listen((_) async {
      final updated = await _fetchItem(serviceKey, busName, objectPath);
      if (updated != null && _itemMap.containsKey(serviceKey)) {
        _itemMap[serviceKey] = updated;
        _publishItems();
      }
    });
  }

  static void _removeByBusName(String busName) {
    final toRemove = _itemMap.values
        .where((i) => i.busName == busName)
        .map((i) => i.serviceKey)
        .toList();
    for (final key in toRemove) {
      _removeByServiceKey(key);
    }
  }

  static void _removeByServiceKey(String serviceKey) {
    if (!_itemMap.containsKey(serviceKey)) return;
    _itemSubs.remove(serviceKey)?.cancel();
    _itemMap.remove(serviceKey);
    _publishItems();
    _watcher?.emitUnregistered(serviceKey);
  }

  static void _publishItems() {
    items.value = _itemMap.values
        .where((i) => i.status != 'Passive')
        .toList();
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
      final props = await obj
          .getAllProperties(_itemIface)
          .timeout(const Duration(seconds: 2));

      String readStr(String key) {
        final v = props[key];
        return v is DBusString ? v.value : '';
      }

      final id = readStr('Id');
      final title = readStr('Title');
      final status = readStr('Status').isNotEmpty ? readStr('Status') : 'Active';
      final iconName = readStr('IconName');
      final iconThemePath = readStr('IconThemePath');
      final itemIsMenu = (props['ItemIsMenu'] as DBusBoolean?)?.value ?? false;

      String? menuPath;
      final menuVal = props['Menu'];
      if (menuVal is DBusObjectPath && menuVal.value.isNotEmpty && menuVal.value != '/') {
        menuPath = menuVal.value;
      }

      String tooltip = '';
      final ttVal = props['ToolTip'];
      if (ttVal is DBusStruct && ttVal.children.length >= 3) {
        final ttTitle = ttVal.children[2] is DBusString
            ? (ttVal.children[2] as DBusString).value
            : '';
        tooltip = ttTitle.trim();
      }

      ui.Image? pixmapImage;
      final resolvedIcon = _resolveIconFile(iconName, iconThemePath);
      if (resolvedIcon == null && props['IconPixmap'] is DBusArray) {
        pixmapImage = await _decodeBestPixmap(props['IconPixmap'] as DBusArray);
      }

      return TrayItem(
        serviceKey: serviceKey,
        busName: busName,
        objectPath: objectPath,
        id: id,
        title: title,
        tooltip: tooltip,
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
    final cacheKey = '$iconThemePath::$iconName';
    if (_iconCache.containsKey(cacheKey)) return _iconCache[cacheKey];

    const exts = ['.svg', '.png', '.xpm'];
    final searchDirs = <String>[
      if (iconThemePath.isNotEmpty) iconThemePath,
      '${Platform.environment['HOME'] ?? ''}/.local/share/icons/hicolor/scalable/apps',
      '${Platform.environment['HOME'] ?? ''}/.local/share/icons/hicolor/48x48/apps',
      '/usr/share/icons/Papirus-Dark/24x24/panel',
      '/usr/share/icons/Papirus-Dark/24x24/apps',
      '/usr/share/icons/Papirus/24x24/panel',
      '/usr/share/icons/Papirus/24x24/apps',
      '/usr/share/icons/hicolor/scalable/apps',
      '/usr/share/icons/hicolor/scalable/status',
      '/usr/share/icons/hicolor/48x48/apps',
      '/usr/share/icons/hicolor/32x32/apps',
      '/usr/share/icons/hicolor/24x24/apps',
      '/usr/share/icons/hicolor/22x22/status',
      '/usr/share/icons/Adwaita/scalable/status',
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
      // Also check direct subdirectories in custom iconThemePath (e.g. hicolor/24x24/apps)
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
          .callMethod(_itemIface, 'Activate', [DBusInt32(x), DBusInt32(y)])
          .timeout(const Duration(seconds: 1));
      return true;
    } catch (_) {
      return false;
    }
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
      final raw = childVariant is DBusVariant ? childVariant.value : childVariant;
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

  static Future<void> dispose() async {
    await _nameOwnerSub?.cancel();
    for (final s in _itemSubs.values) {
      await s.cancel();
    }
    _itemSubs.clear();
    await _client?.close();
    _client = null;
  }
}
