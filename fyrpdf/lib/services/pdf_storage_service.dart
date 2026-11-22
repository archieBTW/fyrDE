import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/pdf_models.dart';

/// Handles JSON persistence for recent PDF files and per-document bookmarks
/// inside `~/.config/fyrpdf/` (or a custom directory for tests).
class PdfStorageService {
  static const int maxRecentFiles = 10;

  final String? configDirOverride;

  PdfStorageService({this.configDirOverride});

  String get configDirPath {
    if (configDirOverride != null) return configDirOverride!;
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.config', 'fyrpdf');
  }

  File get _recentFile => File(p.join(configDirPath, 'recent.json'));
  File get _bookmarksFile => File(p.join(configDirPath, 'bookmarks.json'));

  void _ensureConfigDir() {
    final dir = Directory(configDirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<void> _writeAtomic(File target, String content) async {
    _ensureConfigDir();
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  /// Loads persisted recent PDF files, filtering out files that no longer exist
  /// when [checkExists] is true.
  Future<List<RecentPdfEntry>> loadRecentFiles({bool checkExists = true}) async {
    try {
      if (!_recentFile.existsSync()) return [];
      final raw = await _recentFile.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final entries = <RecentPdfEntry>[];
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final entry = RecentPdfEntry.fromJson(item);
        if (entry.path.isEmpty) continue;
        final normalized = p.normalize(entry.path);
        if (seen.contains(normalized)) continue;
        if (checkExists && !File(normalized).existsSync()) continue;
        seen.add(normalized);
        entries.add(entry.copyWith(path: normalized));
        if (entries.length >= maxRecentFiles) break;
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// Saves the list of recent PDF files (capped at [maxRecentFiles]).
  Future<void> saveRecentFiles(List<RecentPdfEntry> entries) async {
    try {
      final capped = entries.take(maxRecentFiles).map((e) => e.toJson()).toList();
      await _writeAtomic(
        _recentFile,
        const JsonEncoder.withIndent('  ').convert(capped),
      );
    } catch (_) {
      // Ignore storage write errors in restricted environments.
    }
  }

  /// Inserts or moves [filePath] to the top of recent files and persists it.
  Future<List<RecentPdfEntry>> recordRecentFile(
    String filePath, {
    int? pageCount,
    bool checkExists = true,
  }) async {
    final normalized = p.normalize(filePath);
    final existing = await loadRecentFiles(checkExists: checkExists);
    final previous = existing.where((e) => e.path == normalized).firstOrNull;
    final filtered = existing.where((e) => e.path != normalized).toList();

    final entry = RecentPdfEntry(
      path: normalized,
      fileName: p.basename(normalized),
      lastOpened: DateTime.now(),
      pageCount: pageCount ?? previous?.pageCount,
    );

    final updated = [entry, ...filtered].take(maxRecentFiles).toList();
    await saveRecentFiles(updated);
    return updated;
  }

  /// Removes a single path from recent history.
  Future<List<RecentPdfEntry>> removeRecentFile(
    String filePath, {
    bool checkExists = true,
  }) async {
    final normalized = p.normalize(filePath);
    final existing = await loadRecentFiles(checkExists: checkExists);
    final updated = existing.where((e) => e.path != normalized).toList();
    await saveRecentFiles(updated);
    return updated;
  }

  /// Clears all recent file history.
  Future<void> clearRecentFiles() async {
    await saveRecentFiles(const []);
  }

  /// Loads all bookmarks across all PDFs, keyed by normalized file path.
  Future<Map<String, List<PdfBookmarkEntry>>> loadAllBookmarks() async {
    try {
      if (!_bookmarksFile.existsSync()) return {};
      final raw = await _bookmarksFile.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      final result = <String, List<PdfBookmarkEntry>>{};
      for (final entry in decoded.entries) {
        if (entry.value is! List) continue;
        final list = <PdfBookmarkEntry>[];
        for (final item in entry.value as List) {
          if (item is Map<String, dynamic>) {
            list.add(PdfBookmarkEntry.fromJson(item));
          }
        }
        list.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
        if (list.isNotEmpty) {
          result[p.normalize(entry.key)] = list;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Persists the entire bookmark map.
  Future<void> saveAllBookmarks(
    Map<String, List<PdfBookmarkEntry>> bookmarksByFile,
  ) async {
    try {
      final serialized = <String, dynamic>{};
      for (final entry in bookmarksByFile.entries) {
        if (entry.value.isEmpty) continue;
        final sorted = [...entry.value]
          ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
        serialized[p.normalize(entry.key)] =
            sorted.map((b) => b.toJson()).toList();
      }
      await _writeAtomic(
        _bookmarksFile,
        const JsonEncoder.withIndent('  ').convert(serialized),
      );
    } catch (_) {
      // Ignore storage write errors in restricted environments.
    }
  }
}
