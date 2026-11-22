import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class MprisPlayer {
  final String busName;
  final String identity;
  final String playbackStatus; // 'Playing', 'Paused', 'Stopped'
  final String title;
  final String artist;
  final String album;
  final String artUrl;
  final bool canGoNext;
  final bool canGoPrevious;
  final bool canPlay;
  final bool canPause;

  const MprisPlayer({
    required this.busName,
    required this.identity,
    required this.playbackStatus,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUrl,
    this.canGoNext = true,
    this.canGoPrevious = true,
    this.canPlay = true,
    this.canPause = true,
  });

  bool get isPlaying => playbackStatus == 'Playing';
  bool get hasTrack => title.isNotEmpty || artist.isNotEmpty;

  String get displayTitle =>
      title.isNotEmpty ? title : (identity.isNotEmpty ? identity : 'Media');

  String get shortBusLabel {
    const prefix = 'org.mpris.MediaPlayer2.';
    var raw = busName.startsWith(prefix) ? busName.substring(prefix.length) : busName;
    final dotIdx = raw.indexOf('.');
    if (dotIdx > 0) raw = raw.substring(0, dotIdx);
    if (raw.isEmpty) return 'Media';
    return raw[0].toUpperCase() + raw.substring(1);
  }
}

class MprisService {
  static const _mprisPrefix = 'org.mpris.MediaPlayer2.';
  static const _mprisPath = '/org/mpris/MediaPlayer2';
  static const _mprisInterface = 'org.mpris.MediaPlayer2';
  static const _playerInterface = 'org.mpris.MediaPlayer2.Player';

  static final ValueNotifier<List<MprisPlayer>> players = ValueNotifier([]);
  static final ValueNotifier<MprisPlayer?> activePlayer = ValueNotifier(null);

  static DBusClient? _client;
  static StreamSubscription<DBusSignal>? _nameOwnerSub;
  static StreamSubscription<DBusSignal>? _propsSub;
  static Timer? _pollTimer;
  static String? _preferredBusName;
  static bool _refreshing = false;

  static Future<void> init() async {
    if (_client != null) return;
    try {
      _client = DBusClient.session();

      _nameOwnerSub = DBusSignalStream(
        _client!,
        sender: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
      ).listen((signal) {
        if (signal.values.isNotEmpty) {
          final name = (signal.values.first as DBusString).value;
          if (name.startsWith(_mprisPrefix)) {
            refresh();
          }
        }
      });

      _propsSub = DBusSignalStream(
        _client!,
        path: DBusObjectPath(_mprisPath),
        interface: 'org.freedesktop.DBus.Properties',
        name: 'PropertiesChanged',
      ).listen((_) {
        refresh();
      });

      await refresh();
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (players.value.isNotEmpty) {
          refresh();
        }
      });
    } catch (_) {}
  }

  static Future<void> refresh() async {
    if (_client == null || _refreshing) return;
    _refreshing = true;
    try {
      final dbusObj = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      );
      final res = await dbusObj
          .callMethod('org.freedesktop.DBus', 'ListNames', [])
          .timeout(const Duration(seconds: 2));
      final names = (res.values.first as DBusArray).children
          .map((e) => (e as DBusString).value)
          .where((n) => n.startsWith(_mprisPrefix))
          .toList();

      final loaded = <MprisPlayer>[];
      for (final busName in names) {
        final p = await _readPlayer(busName);
        if (p != null) loaded.add(p);
      }

      // Prefer playing players first, then paused, then stopped.
      loaded.sort((a, b) {
        int rank(MprisPlayer p) {
          if (p.isPlaying) return 0;
          if (p.playbackStatus == 'Paused') return 1;
          return 2;
        }
        final cmp = rank(a).compareTo(rank(b));
        if (cmp != 0) return cmp;
        return a.identity.compareTo(b.identity);
      });

      players.value = loaded;
      _updateActivePlayer(loaded);
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  static void _updateActivePlayer(List<MprisPlayer> loaded) {
    if (loaded.isEmpty) {
      activePlayer.value = null;
      return;
    }
    if (_preferredBusName != null) {
      final pref = loaded.where((p) => p.busName == _preferredBusName).toList();
      if (pref.isNotEmpty) {
        activePlayer.value = pref.first;
        return;
      }
      _preferredBusName = null;
    }
    final playing = loaded.where((p) => p.isPlaying).toList();
    if (playing.isNotEmpty) {
      activePlayer.value = playing.first;
      return;
    }
    final withTrack = loaded.where((p) => p.hasTrack).toList();
    activePlayer.value = withTrack.isNotEmpty ? withTrack.first : loaded.first;
  }

  static void selectPlayer(String busName) {
    _preferredBusName = busName;
    _updateActivePlayer(players.value);
  }

  static Future<MprisPlayer?> _readPlayer(String busName) async {
    if (_client == null) return null;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: busName,
        path: DBusObjectPath(_mprisPath),
      );

      String identity = '';
      try {
        final idVal = await obj
            .getProperty(_mprisInterface, 'Identity')
            .timeout(const Duration(milliseconds: 500));
        if (idVal is DBusString) identity = idVal.value;
      } catch (_) {}

      final allProps = await obj
          .getAllProperties(_playerInterface)
          .timeout(const Duration(milliseconds: 800));

      final statusVal = allProps['PlaybackStatus'];
      final playbackStatus =
          statusVal is DBusString ? statusVal.value : 'Stopped';

      final canGoNext = (allProps['CanGoNext'] as DBusBoolean?)?.value ?? true;
      final canGoPrevious =
          (allProps['CanGoPrevious'] as DBusBoolean?)?.value ?? true;
      final canPlay = (allProps['CanPlay'] as DBusBoolean?)?.value ?? true;
      final canPause = (allProps['CanPause'] as DBusBoolean?)?.value ?? true;

      String title = '';
      String artist = '';
      String album = '';
      String artUrl = '';

      final metaVal = allProps['Metadata'];
      if (metaVal is DBusDict) {
        for (final entry in metaVal.children.entries) {
          final key = (entry.key as DBusString).value;
          final raw = entry.value is DBusVariant
              ? (entry.value as DBusVariant).value
              : entry.value;
          if (key == 'xesam:title' && raw is DBusString) {
            title = raw.value.trim();
          } else if (key == 'xesam:album' && raw is DBusString) {
            album = raw.value.trim();
          } else if (key == 'mpris:artUrl' && raw is DBusString) {
            artUrl = raw.value.trim();
          } else if (key == 'xesam:artist') {
            if (raw is DBusArray) {
              artist = raw.children
                  .whereType<DBusString>()
                  .map((s) => s.value.trim())
                  .where((s) => s.isNotEmpty)
                  .join(', ');
            } else if (raw is DBusString) {
              artist = raw.value.trim();
            }
          }
        }
      }

      if (playbackStatus == 'Stopped' && title.isEmpty && artist.isEmpty) {
        return null;
      }

      return MprisPlayer(
        busName: busName,
        identity: identity,
        playbackStatus: playbackStatus,
        title: title,
        artist: artist,
        album: album,
        artUrl: artUrl,
        canGoNext: canGoNext,
        canGoPrevious: canGoPrevious,
        canPlay: canPlay,
        canPause: canPause,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _callPlayerMethod(String busName, String method) async {
    if (_client == null) return;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: busName,
        path: DBusObjectPath(_mprisPath),
      );
      await obj
          .callMethod(_playerInterface, method, [])
          .timeout(const Duration(seconds: 1));
      Future.delayed(const Duration(milliseconds: 120), refresh);
    } catch (_) {}
  }

  static Future<void> playPause([String? busName]) async {
    final target = busName ?? activePlayer.value?.busName;
    if (target != null) await _callPlayerMethod(target, 'PlayPause');
  }

  static Future<void> next([String? busName]) async {
    final target = busName ?? activePlayer.value?.busName;
    if (target != null) await _callPlayerMethod(target, 'Next');
  }

  static Future<void> previous([String? busName]) async {
    final target = busName ?? activePlayer.value?.busName;
    if (target != null) await _callPlayerMethod(target, 'Previous');
  }

  static Future<void> dispose() async {
    _pollTimer?.cancel();
    await _nameOwnerSub?.cancel();
    await _propsSub?.cancel();
    await _client?.close();
    _client = null;
  }
}
