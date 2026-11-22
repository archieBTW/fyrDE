import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum ClipboardEntryType { text, image }

class ClipboardEntry {
  final String id;
  final ClipboardEntryType type;
  final String text;
  final String? imagePath;
  final int byteSize;
  final DateTime timestamp;
  final bool pinned;

  const ClipboardEntry({
    required this.id,
    required this.type,
    this.text = '',
    this.imagePath,
    this.byteSize = 0,
    required this.timestamp,
    this.pinned = false,
  });

  ClipboardEntry copyWith({
    DateTime? timestamp,
    bool? pinned,
  }) {
    return ClipboardEntry(
      id: id,
      type: type,
      text: text,
      imagePath: imagePath,
      byteSize: byteSize,
      timestamp: timestamp ?? this.timestamp,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'imagePath': imagePath,
    'byteSize': byteSize,
    'timestamp': timestamp.toIso8601String(),
    'pinned': pinned,
  };

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString() ?? 'text';
    return ClipboardEntry(
      id: json['id']?.toString() ?? '',
      type: typeStr == 'image'
          ? ClipboardEntryType.image
          : ClipboardEntryType.text,
      text: json['text']?.toString() ?? '',
      imagePath: json['imagePath']?.toString(),
      byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      pinned: json['pinned'] == true,
    );
  }
}

class ClipboardStore {
  static const int maxUnpinnedItems = 60;
  static const int maxTextBytes = 256 * 1024;
  static const int maxImageBytes = 15 * 1024 * 1024;

  final String dataDir;
  final ValueNotifier<List<ClipboardEntry>> entries = ValueNotifier([]);

  Process? _watchProcess;
  Timer? _debounceTimer;
  Timer? _restartTimer;
  bool _disposed = false;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _capturing = false;

  ClipboardStore({String? dataDir})
      : dataDir = dataDir ??
            '${Platform.environment['HOME'] ?? ''}/.local/share/fyrclipboard';

  String get _historyFilePath => '$dataDir/history.json';
  String get _imagesDirPath => '$dataDir/images';

  static String computeHash(List<int> bytes) {
    // 64-bit FNV-1a hash (split into two 32-bit halves for JS/VM safety)
    int h1 = 0x811c9dc5;
    int h2 = 0x01000193;
    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xffffffff;
      h2 ^= (b + i) & 0xff;
      h2 = (h2 * 0x85ebca6b) & 0xffffffff;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}'
        '_${bytes.length}';
  }

  Future<void> init({bool startWatcher = true}) async {
    await Directory(dataDir).create(recursive: true);
    await Directory(_imagesDirPath).create(recursive: true);
    await load();
    if (startWatcher) {
      _startWatcher();
    }
  }

  Future<void> load() async {
    final file = File(_historyFilePath);
    if (!await file.exists()) {
      entries.value = [];
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final loaded = decoded
            .whereType<Map>()
            .map((e) => ClipboardEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) {
              if (e.id.isEmpty) return false;
              if (e.type == ClipboardEntryType.image) {
                return e.imagePath != null && File(e.imagePath!).existsSync();
              }
              return e.text.trim().isNotEmpty;
            })
            .toList();
        entries.value = _sortEntries(loaded);
      }
    } catch (_) {
      entries.value = [];
    }
  }

  Future<void> _save() async {
    try {
      final file = File(_historyFilePath);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(entries.value.map((e) => e.toJson()).toList()),
      );
      await tmp.rename(file.path);
    } catch (_) {}
  }

  List<ClipboardEntry> _sortEntries(List<ClipboardEntry> list) {
    final sorted = List<ClipboardEntry>.from(list);
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return sorted;
  }

  Future<void> addText(String text, {DateTime? now}) async {
    if (text.trim().isEmpty) return;
    final bytes = utf8.encode(text);
    if (bytes.length > maxTextBytes) return;

    final id = 'txt_${computeHash(bytes)}';
    final ts = now ?? DateTime.now();
    final list = List<ClipboardEntry>.from(entries.value);
    final idx = list.indexWhere((e) => e.id == id);

    if (idx >= 0) {
      final existing = list.removeAt(idx);
      list.insert(0, existing.copyWith(timestamp: ts));
    } else {
      list.insert(
        0,
        ClipboardEntry(
          id: id,
          type: ClipboardEntryType.text,
          text: text,
          byteSize: bytes.length,
          timestamp: ts,
        ),
      );
    }

    await _trimAndCommit(list);
  }

  Future<void> addImageBytes(Uint8List pngBytes, {DateTime? now}) async {
    if (pngBytes.isEmpty || pngBytes.length > maxImageBytes) return;

    final id = 'img_${computeHash(pngBytes)}';
    final imgPath = '$_imagesDirPath/$id.png';
    final ts = now ?? DateTime.now();

    final file = File(imgPath);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes, flush: true);
    }

    final list = List<ClipboardEntry>.from(entries.value);
    final idx = list.indexWhere((e) => e.id == id);

    if (idx >= 0) {
      final existing = list.removeAt(idx);
      list.insert(0, existing.copyWith(timestamp: ts));
    } else {
      list.insert(
        0,
        ClipboardEntry(
          id: id,
          type: ClipboardEntryType.image,
          imagePath: imgPath,
          byteSize: pngBytes.length,
          timestamp: ts,
        ),
      );
    }

    await _trimAndCommit(list);
  }

  Future<void> _trimAndCommit(List<ClipboardEntry> list) async {
    final pinned = list.where((e) => e.pinned).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final unpinned = list.where((e) => !e.pinned).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (unpinned.length > maxUnpinnedItems) {
      final dropped = unpinned.sublist(maxUnpinnedItems);
      unpinned.removeRange(maxUnpinnedItems, unpinned.length);
      for (final item in dropped) {
        _deleteImageIfUnreferenced(item, [...pinned, ...unpinned]);
      }
    }

    entries.value = [...pinned, ...unpinned];
    await _save();
  }

  void _deleteImageIfUnreferenced(
    ClipboardEntry removed,
    List<ClipboardEntry> remaining,
  ) {
    if (removed.type != ClipboardEntryType.image || removed.imagePath == null) {
      return;
    }
    final stillUsed = remaining.any((e) => e.imagePath == removed.imagePath);
    if (!stillUsed) {
      try {
        final f = File(removed.imagePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> togglePin(String id) async {
    final list = entries.value.map((e) {
      if (e.id == id) return e.copyWith(pinned: !e.pinned);
      return e;
    }).toList();
    entries.value = _sortEntries(list);
    await _save();
  }

  Future<void> deleteEntry(String id) async {
    final list = List<ClipboardEntry>.from(entries.value);
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final removed = list.removeAt(idx);
    _deleteImageIfUnreferenced(removed, list);
    entries.value = list;
    await _save();
  }

  Future<void> clearUnpinned() async {
    final pinned = entries.value.where((e) => e.pinned).toList();
    final removed = entries.value.where((e) => !e.pinned).toList();
    for (final item in removed) {
      _deleteImageIfUnreferenced(item, pinned);
    }
    entries.value = pinned;
    await _save();
  }

  Future<void> copyEntryToClipboard(ClipboardEntry entry) async {
    _suppressUntil = DateTime.now().add(const Duration(milliseconds: 900));
    try {
      if (entry.type == ClipboardEntryType.image && entry.imagePath != null) {
        final path = entry.imagePath!;
        if (File(path).existsSync()) {
          await Process.start(
            'sh',
            ['-c', 'wl-copy -t image/png < "\$1"', '--', path],
            mode: ProcessStartMode.detached,
          );
        }
      } else {
        final proc = await Process.start('wl-copy', []);
        proc.stdin.write(entry.text);
        await proc.stdin.close();
      }
      // Bump timestamp so the copied item floats to the top
      final list = entries.value.map((e) {
        if (e.id == entry.id) return e.copyWith(timestamp: DateTime.now());
        return e;
      }).toList();
      entries.value = _sortEntries(list);
      await _save();
    } catch (_) {}
  }

  void _startWatcher() async {
    if (_disposed) return;
    try {
      _watchProcess?.kill();
      _watchProcess = await Process.start('wl-paste', [
        '--watch',
        'sh',
        '-c',
        'cat >/dev/null; echo changed',
      ]);

      _watchProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (_) => _scheduleCapture(),
            onError: (_) {},
          );
      _watchProcess!.stderr.drain<void>().catchError((_) {});

      _watchProcess!.exitCode.then((_) {
        if (!_disposed) {
          _restartTimer?.cancel();
          _restartTimer = Timer(const Duration(seconds: 2), _startWatcher);
        }
      });
    } catch (_) {
      if (!_disposed) {
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(seconds: 5), _startWatcher);
      }
    }
  }

  void _scheduleCapture() {
    if (DateTime.now().isBefore(_suppressUntil)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 120),
      _captureCurrentClipboard,
    );
  }

  Future<void> _captureCurrentClipboard() async {
    if (_disposed || _capturing) return;
    if (DateTime.now().isBefore(_suppressUntil)) return;
    _capturing = true;
    try {
      final typesRes = await Process.run('wl-paste', ['--list-types']);
      if (typesRes.exitCode != 0) return;
      final types = typesRes.stdout
          .toString()
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet();

      if (types.contains('image/png')) {
        final imgRes = await Process.run(
          'wl-paste',
          ['--type', 'image/png'],
          stdoutEncoding: null,
        );
        if (imgRes.exitCode == 0 && imgRes.stdout is List<int>) {
          final bytes = Uint8List.fromList(imgRes.stdout as List<int>);
          if (bytes.isNotEmpty) {
            await addImageBytes(bytes);
            return;
          }
        }
      }

      String? textType;
      if (types.contains('text/plain;charset=utf-8')) {
        textType = 'text/plain;charset=utf-8';
      } else if (types.contains('text/plain')) {
        textType = 'text/plain';
      } else if (types.contains('UTF8_STRING')) {
        textType = 'UTF8_STRING';
      }

      if (textType != null) {
        final txtRes = await Process.run(
          'wl-paste',
          ['--no-newline', '--type', textType],
        );
        if (txtRes.exitCode == 0) {
          final text = txtRes.stdout.toString();
          if (text.trim().isNotEmpty) {
            await addText(text);
          }
        }
      }
    } catch (_) {
    } finally {
      _capturing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _restartTimer?.cancel();
    _watchProcess?.kill();
    _watchProcess = null;
    entries.dispose();
  }
}
