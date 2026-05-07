import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DownloadTask extends ChangeNotifier {
  final String id;
  final String url;
  final String suggestedName;
  String? savePath;
  int receivedBytes = 0;
  int totalBytes = 0;
  int progress = 0;
  bool isComplete = false;
  bool isError = false;
  DateTime startTime;

  DownloadTask({
    required this.id,
    required this.url,
    required this.suggestedName,
    this.savePath,
    required this.startTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'suggestedName': suggestedName,
    'savePath': savePath,
    'startTime': startTime.toIso8601String(),
    'isComplete': isComplete,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'],
      url: json['url'],
      suggestedName: json['suggestedName'],
      savePath: json['savePath'],
      startTime: DateTime.parse(json['startTime']),
    )..isComplete = json['isComplete'] ?? false;
  }

  void updateProgress(int received, int total, int percent, bool complete) {
    receivedBytes = received;
    totalBytes = total;
    progress = percent;
    isComplete = complete;
    notifyListeners();
  }
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => _tasks;

  Future<void> init() async {
    await _loadHistory();
  }

  void startDownload(String suggestedName, String url) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    // In Linux, CEF usually downloads to ~/Downloads by default if we use callback->Continue(suggested_name, true)
    // with "true" for showing the dialog. If we want to automate it, we'd need more complex logic.
    // For now, we assume it's going to Downloads.
    final home = Platform.environment['HOME'] ?? '';
    final downloadPath = p.join(home, 'Downloads', suggestedName);

    final task = DownloadTask(
      id: id,
      url: url,
      suggestedName: suggestedName,
      savePath: downloadPath,
      startTime: DateTime.now(),
    );
    _tasks.insert(0, task);
    notifyListeners();
    _saveHistory();
  }

  void updateDownload(String url, int received, int total, int percent, bool complete) {
    // Match task by URL (this is a bit fragile if multiple downloads have same URL, but CEF doesn't give us a task ID easily here)
    final taskIndex = _tasks.indexWhere((t) => t.url == url && !t.isComplete);
    if (taskIndex != -1) {
      _tasks[taskIndex].updateProgress(received, total, percent, complete);
      if (complete) {
        _saveHistory();
      }
      notifyListeners();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'downloads.json'));
      if (file.existsSync()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        _tasks.clear();
        _tasks.addAll(jsonList.map((e) => DownloadTask.fromJson(e)).toList());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load download history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'downloads.json'));
      // Only save completed tasks or metadata
      final content = json.encode(_tasks.map((e) => e.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save download history: $e');
    }
  }

  void clearHistory() {
    _tasks.clear();
    _saveHistory();
    notifyListeners();
  }
}
