import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;
import 'package:dart_ipify/dart_ipify.dart';

const List<String> _kDefaultTrackerUrls = [
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.demonii.com:1337/announce',
  'udp://open.stealth.si:80/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://tracker.torrent.eu.org:451/announce',
  'udp://tracker.moeking.me:6969/announce',
  'udp://explodie.org:6969/announce',
  'udp://tracker1.bt.moack.co.kr:80/announce',
  'udp://tracker.openbittorrent.com:6969/announce',
  'udp://opentracker.io:6969/announce',
  'udp://tracker.tiny-vps.com:6969/announce',
  'udp://tracker.dler.org:6969/announce',
  'udp://retracker.lanta.me:2710/announce',
  'udp://open.free-tracker.ga:6969/announce',
  'http://tracker.opentrackr.org:1337/announce',
  'http://tracker.openbittorrent.com:80/announce',
  'http://open.acgnxtracker.com:80/announce',
];

List<int>? _hexString2Buffer(String hexStr) {
  if (hexStr.isEmpty || hexStr.length.remainder(2) != 0) return null;
  var size = hexStr.length ~/ 2;
  var re = <int>[];
  for (var i = 0; i < size; i++) {
    var s = hexStr.substring(i * 2, i * 2 + 2);
    var byte = int.parse(s, radix: 16);
    re.add(byte);
  }
  return re;
}

String? _base32ToHex(String base32) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final cleaned = base32.trim().toUpperCase().replaceAll('=', '');
  if (cleaned.length != 32) return null;
  int buffer = 0;
  int bitsLeft = 0;
  final bytes = <int>[];
  for (int i = 0; i < cleaned.length; i++) {
    final val = alphabet.indexOf(cleaned[i]);
    if (val < 0) return null;
    buffer = (buffer << 5) | val;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bitsLeft -= 8;
      bytes.add((buffer >> bitsLeft) & 0xFF);
    }
  }
  if (bytes.length != 20) return null;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class TorrentItem extends ChangeNotifier {
  final String infoHash;
  final String name;
  final String savePath;
  final TorrentTask task;
  final Torrent model;
  
  double progress = 0.0;
  double downloadSpeed = 0.0;
  double uploadSpeed = 0.0;
  int seeders = 0;
  int leechers = 0;
  bool isCompleted = false;
  bool isPaused = false;

  TorrentItem({
    required this.infoHash,
    required this.name,
    required this.savePath,
    required this.task,
    required this.model,
  }) {
    _initListeners();
  }

  Timer? _pollTimer;
  dynamic _taskListener;

  void _initListeners() {
    final listener = task.createListener();
    _taskListener = listener;
    listener.on<TaskCompleted>((event) {
      isCompleted = true;
      progress = 1.0;
      downloadSpeed = 0.0;
      notifyListeners();
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (task.state == TaskState.stopped) {
        timer.cancel();
        listener.dispose();
        return;
      }
      
      // SpeedCalculator in dtorrent_task returns KB/s; convert to B/s for UI
      if (isPaused) {
        downloadSpeed = 0.0;
        uploadSpeed = 0.0;
      } else {
        downloadSpeed = task.currentDownloadSpeed * 1024.0;
        uploadSpeed = task.uploadSpeed * 1024.0;
      }
      progress = task.progress;
      if (progress >= 1.0) {
        isCompleted = true;
      }

      final peersManager = task.peersManager;
      if (peersManager != null) {
        seeders = peersManager.seederNumber;
        final totalConnected = peersManager.connectedPeersNumber;
        leechers = totalConnected >= seeders ? (totalConnected - seeders) : 0;
      }
      
      notifyListeners();
    });
  }

  void pause() {
    task.pause();
    isPaused = true;
    downloadSpeed = 0.0;
    uploadSpeed = 0.0;
    notifyListeners();
  }

  void resume() {
    task.resume();
    isPaused = false;
    notifyListeners();
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _taskListener?.dispose();
    _taskListener = null;
    task.stop();
    notifyListeners();
  }
}

class TorrentService extends ChangeNotifier {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  final List<TorrentItem> _items = [];
  List<TorrentItem> get items => _items;

  final List<String> _pendingMagnets = [];
  List<String> get pendingMagnets => _pendingMagnets;

  late Directory _appDir;
  late Directory _torrentDir;
  String _defaultSavePath = '';
  String? publicIp;

  List<Uri> _buildTrackerList([List<Uri>? existing]) {
    final seen = <String>{};
    final result = <Uri>[];
    if (existing != null) {
      for (final u in existing) {
        if (seen.add(u.toString())) {
          result.add(u);
        }
      }
    }
    for (final raw in _kDefaultTrackerUrls) {
      if (seen.add(raw)) {
        try {
          result.add(Uri.parse(raw));
        } catch (_) {}
      }
    }
    return result;
  }

  void _boostTaskDiscovery(TorrentTask task, Torrent model) {
    final infoHashBuf = Uint8List.fromList(model.infoHashBuffer);
    for (final tr in _buildTrackerList(model.announces.toList())) {
      try {
        task.startAnnounceUrl(tr, infoHashBuf);
      } catch (_) {}
    }
    if (model.nodes.isNotEmpty) {
      for (final node in model.nodes) {
        try {
          task.addDHTNode(node);
        } catch (_) {}
      }
    }
    task.requestPeersFromDHT();
  }

  Future<void> init() async {
    _appDir = await getApplicationSupportDirectory();
    _torrentDir = Directory(p.join(_appDir.path, 'torrents'));
    if (!_torrentDir.existsSync()) {
      _torrentDir.createSync(recursive: true);
    }

    try {
      publicIp = await Ipify.ipv4();
    } catch (_) {}

    final downloadsDir = await getDownloadsDirectory();
    _defaultSavePath = downloadsDir?.path ?? p.join(Platform.environment['HOME'] ?? '', 'Downloads');
    
    // Ensure downloads dir exists
    final dir = Directory(_defaultSavePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await _loadPersistedTorrents();
  }

  Future<void> addTorrentFromFile(String filePath, {String? savePath}) async {
    try {
      final model = await Torrent.parse(filePath);
      final infoHash = model.infoHash.toLowerCase();
      
      if (_items.any((item) => item.infoHash.toLowerCase() == infoHash)) {
        return; // Already exists
      }

      final actualSavePath = savePath ?? _defaultSavePath;
      final task = TorrentTask.newTask(model, actualSavePath);
      
      final item = TorrentItem(
        infoHash: infoHash,
        name: model.name,
        savePath: actualSavePath,
        task: task,
        model: model,
      );

      _items.add(item);
      await task.start();
      _boostTaskDiscovery(task, model);
      notifyListeners();
      
      // Persist
      final savedTorrentPath = p.join(_torrentDir.path, '$infoHash.torrent');
      if (filePath != savedTorrentPath) {
        await File(filePath).copy(savedTorrentPath);
      }
      await _saveState();
    } catch (e) {
      debugPrint('Error adding torrent: $e');
      rethrow;
    }
  }

  String? _getInfoHashFromMagnet(String magnetUrl) {
    try {
      final match = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(magnetUrl);
      String? rawHash = match?.group(1);
      if (rawHash == null) {
        final uri = Uri.parse(magnetUrl);
        final xt = uri.queryParameters['xt'];
        if (xt != null && xt.toLowerCase().startsWith('urn:btih:')) {
          rawHash = xt.substring('urn:btih:'.length);
        }
      }
      if (rawHash == null) return null;
      if (rawHash.length == 40) {
        return rawHash.toLowerCase();
      } else if (rawHash.length == 32) {
        return _base32ToHex(rawHash);
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _tryFetchTorrentFromCaches(String infoHash, List<Uri> trackers) async {
    final upper = infoHash.toUpperCase();
    final urls = [
      'https://itorrents.org/torrent/$upper.torrent',
      'https://btcache.me/torrent/$upper',
    ];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final url in urls) {
        try {
          final req = await client.getUrl(Uri.parse(url));
          req.headers.set(HttpHeaders.userAgentHeader, 'Transmission/4.0.5');
          final resp = await req.close().timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(resp);
            if (bytes.length > 64 && bytes[0] == 0x64) { // starts with 'd' (bencoded dict)
              final parsed = await Torrent.parseFromBytes(bytes);
              if (parsed.infoHash.toLowerCase() == infoHash.toLowerCase()) {
                final decoded = bencoding.decode(bytes);
                if (decoded is Map) {
                  decoded['announce-list'] = trackers.map((tr) => [tr.toString()]).toList();
                  if (trackers.isNotEmpty) {
                    decoded['announce'] = trackers.first.toString();
                  }
                  return Uint8List.fromList(bencoding.encode(decoded));
                }
                return bytes;
              }
            }
          }
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<void> addTorrentFromMagnet(String magnetUrl, {String? savePath}) async {
    try {
      final infoHash = _getInfoHashFromMagnet(magnetUrl);
      if (infoHash == null) throw 'Invalid magnet link: info hash not found';

      if (_items.any((item) => item.infoHash.toLowerCase() == infoHash) ||
          _pendingMagnets.contains(infoHash)) {
        return; // Already exists or pending
      }

      final uri = Uri.parse(magnetUrl);
      final magnetTrackers = <Uri>[];
      for (final tr in uri.queryParametersAll['tr'] ?? const <String>[]) {
        try {
          magnetTrackers.add(Uri.parse(tr));
        } catch (_) {}
      }
      final trackers = _buildTrackerList(magnetTrackers);

      debugPrint('Fetching metadata for magnet: $infoHash with ${trackers.length} trackers');
      _pendingMagnets.add(infoHash);
      notifyListeners();

      bool resolved = false;
      
      // Start metadata downloader
      final downloader = MetadataDownloader(infoHash);
      final downloaderListener = downloader.createListener();

      // Start trackers to find peers for metadata
      final announceTracker = TorrentAnnounceTracker(downloader);
      final trackerListener = announceTracker.createListener();
      
      final infoHashBuffer = Uint8List.fromList(_hexString2Buffer(infoHash)!);

      trackerListener.on<AnnouncePeerEventEvent>((event) {
        if (event.event != null) {
          for (var peer in event.event!.peers) {
            downloader.addNewPeerAddress(peer, PeerSource.tracker);
          }
        }
      });

      void cleanup() {
        _pendingMagnets.remove(infoHash);
        notifyListeners();
        downloaderListener.dispose();
        trackerListener.dispose();
        announceTracker.dispose();
        downloader.stop();
      }

      Future<void> completeWithTorrentBytes(Uint8List fullTorrentBytes) async {
        if (resolved) return;
        resolved = true;
        try {
          final model = await Torrent.parseFromBytes(fullTorrentBytes);
          final actualSavePath = savePath ?? _defaultSavePath;
          final savedTorrentPath = p.join(_torrentDir.path, '$infoHash.torrent');
          await model.saveAs(savedTorrentPath);
          await addTorrentFromFile(savedTorrentPath, savePath: actualSavePath);
        } catch (e) {
          debugPrint('Error processing downloaded metadata: $e');
        } finally {
          cleanup();
        }
      }

      downloaderListener.on<MetaDataDownloadComplete>((event) async {
        if (resolved) return;
        try {
          final infoBuffer = event.data;
          final infoMap = bencoding.decode(Uint8List.fromList(infoBuffer));
          
          final fullTorrentMap = {
            'info': infoMap,
            'announce-list': trackers.map((tr) => [tr.toString()]).toList(),
          };
          
          if (trackers.isNotEmpty) {
            fullTorrentMap['announce'] = trackers[0].toString();
          }

          final fullTorrentBytes = Uint8List.fromList(bencoding.encode(fullTorrentMap));
          await completeWithTorrentBytes(fullTorrentBytes);
        } catch (e) {
          debugPrint('Error processing downloaded metadata: $e');
          cleanup();
        }
      });

      downloaderListener.on<MetaDataDownloadFailed>((event) {
        debugPrint('Metadata download failed: ${event.error}');
        if (!resolved) {
          cleanup();
        }
      });

      // Race HTTP torrent caches in parallel with DHT/tracker ut_metadata exchange
      unawaited(_tryFetchTorrentFromCaches(infoHash, trackers).then((cachedBytes) async {
        if (cachedBytes != null && !resolved) {
          debugPrint('Resolved magnet metadata via torrent cache for $infoHash');
          await completeWithTorrentBytes(cachedBytes);
        }
      }));

      await downloader.startDownload();
      announceTracker.runTrackers(trackers, infoHashBuffer);
    } catch (e) {
      debugPrint('Error adding magnet: $e');
      _pendingMagnets.remove(_getInfoHashFromMagnet(magnetUrl) ?? '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadPersistedTorrents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('torrents_state');
    if (jsonStr == null) return;

    final List<dynamic> list = json.decode(jsonStr);
    for (var entry in list) {
      final hash = (entry['hash'] as String).toLowerCase();
      final savePath = entry['savePath'];
      final torrentFile = File(p.join(_torrentDir.path, '$hash.torrent'));
      
      if (torrentFile.existsSync()) {
        try {
          final model = await Torrent.parse(torrentFile.path);
          final task = TorrentTask.newTask(model, savePath);
          final item = TorrentItem(
            infoHash: hash,
            name: model.name,
            savePath: savePath,
            task: task,
            model: model,
          );
          _items.add(item);
          await task.start();
          _boostTaskDiscovery(task, model);
        } catch (e) {
          debugPrint('Failed to reload torrent $hash: $e');
        }
      }
    }
    notifyListeners();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final state = _items.map((item) => {
      'hash': item.infoHash,
      'savePath': item.savePath,
    }).toList();
    await prefs.setString('torrents_state', json.encode(state));
  }

  void removeTorrent(TorrentItem item, {bool deleteFiles = false}) {
    item.stop();
    _items.remove(item);
    
    for (final candidate in {item.infoHash, item.infoHash.toLowerCase()}) {
      final torrentFile = File(p.join(_torrentDir.path, '$candidate.torrent'));
      if (torrentFile.existsSync()) {
        torrentFile.deleteSync();
      }
    }

    if (deleteFiles) {
      // Implement file deletion if needed
    }

    _saveState();
    notifyListeners();
  }
}
