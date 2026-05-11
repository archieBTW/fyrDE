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

  void _initListeners() {
    final listener = task.createListener();
    listener.on<TaskCompleted>((event) {
      isCompleted = true;
      progress = 1.0;
      notifyListeners();
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (task.state == TaskState.stopped) {
        timer.cancel();
        listener.dispose();
        return;
      }
      
      // Update stats
      downloadSpeed = task.currentDownloadSpeed;
      uploadSpeed = task.uploadSpeed;
      progress = task.progress;

      final peersManager = task.peersManager;
      if (peersManager != null) {
        seeders = peersManager.seederNumber;
        leechers = peersManager.connectedPeersNumber - seeders;
      }
      
      notifyListeners();
    });
  }

  void pause() {
    task.pause();
    isPaused = true;
    notifyListeners();
  }

  void resume() {
    task.resume();
    isPaused = false;
    notifyListeners();
  }

  void stop() {
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
      final infoHash = model.infoHash;
      
      if (_items.any((item) => item.infoHash == infoHash)) {
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
      task.start();
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
      final uri = Uri.parse(magnetUrl);
      final xt = uri.queryParameters['xt'];
      if (xt != null && xt.startsWith('urn:btih:')) {
        return xt.substring('urn:btih:'.length).toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  Future<void> addTorrentFromMagnet(String magnetUrl, {String? savePath}) async {
    try {
      final infoHash = _getInfoHashFromMagnet(magnetUrl);
      if (infoHash == null) throw 'Invalid magnet link: info hash not found';

      if (_items.any((item) => item.infoHash == infoHash) || _pendingMagnets.contains(infoHash)) {
        return; // Already exists or pending
      }

      final uri = Uri.parse(magnetUrl);
      final trackers = uri.queryParametersAll['tr']?.map((tr) => Uri.parse(tr)).toList() ?? [];

      debugPrint('Fetching metadata for magnet: $infoHash with ${trackers.length} trackers');
      _pendingMagnets.add(infoHash);
      notifyListeners();
      
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

      downloaderListener.on<MetaDataDownloadComplete>((event) async {
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

          final fullTorrentBytes = bencoding.encode(fullTorrentMap);
          final model = await Torrent.parseFromBytes(Uint8List.fromList(fullTorrentBytes));
          
          final actualSavePath = savePath ?? _defaultSavePath;
          final savedTorrentPath = p.join(_torrentDir.path, '$infoHash.torrent');
          await model.saveAs(savedTorrentPath);

          await addTorrentFromFile(savedTorrentPath, savePath: actualSavePath);
        } catch (e) {
          debugPrint('Error processing downloaded metadata: $e');
        } finally {
          cleanup();
        }
      });

      downloaderListener.on<MetaDataDownloadFailed>((event) {
        debugPrint('Metadata download failed: ${event.error}');
        cleanup();
      });

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
      final hash = entry['hash'];
      final savePath = entry['savePath'];
      final torrentFile = File(p.join(_torrentDir.path, '$hash.torrent'));
      
      if (torrentFile.existsSync()) {
        try {
          final model = await Torrent.parse(torrentFile.path);
          final task = TorrentTask.newTask(model, savePath);
          final item = TorrentItem(
            infoHash: hash,
            name: model.name ?? 'Unknown',
            savePath: savePath,
            task: task,
            model: model,
          );
          _items.add(item);
          // Don't auto-start unless they were running? 
          // For now, let's auto-start.
          task.start();
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
    
    final torrentFile = File(p.join(_torrentDir.path, '${item.infoHash}.torrent'));
    if (torrentFile.existsSync()) {
      torrentFile.deleteSync();
    }

    if (deleteFiles) {
      // Implement file deletion if needed
    }

    _saveState();
    notifyListeners();
  }
}
