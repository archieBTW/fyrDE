import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Active section inside the collapsible left sidebar.
enum SidebarTab { thumbnails, outline, bookmarks }

/// A persisted entry in the recent PDF files list.
class RecentPdfEntry {
  final String path;
  final String fileName;
  final DateTime lastOpened;
  final int? pageCount;

  const RecentPdfEntry({
    required this.path,
    required this.fileName,
    required this.lastOpened,
    this.pageCount,
  });

  String get directoryPath => p.dirname(path);

  RecentPdfEntry copyWith({
    String? path,
    String? fileName,
    DateTime? lastOpened,
    int? pageCount,
  }) {
    return RecentPdfEntry(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      lastOpened: lastOpened ?? this.lastOpened,
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileName': fileName,
        'lastOpened': lastOpened.toIso8601String(),
        'pageCount': pageCount,
      };

  factory RecentPdfEntry.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    return RecentPdfEntry(
      path: path,
      fileName: json['fileName'] as String? ?? p.basename(path),
      lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? '') ??
          DateTime.now(),
      pageCount: json['pageCount'] as int?,
    );
  }
}

/// A user-created page bookmark persisted per PDF document.
class PdfBookmarkEntry {
  final int pageNumber;
  final String label;
  final DateTime createdAt;

  const PdfBookmarkEntry({
    required this.pageNumber,
    required this.label,
    required this.createdAt,
  });

  PdfBookmarkEntry copyWith({
    int? pageNumber,
    String? label,
    DateTime? createdAt,
  }) {
    return PdfBookmarkEntry(
      pageNumber: pageNumber ?? this.pageNumber,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PdfBookmarkEntry.fromJson(Map<String, dynamic> json) {
    final page = json['pageNumber'] as int? ?? 1;
    return PdfBookmarkEntry(
      pageNumber: page,
      label: json['label'] as String? ?? 'Page $page',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Runtime state for a single open PDF tab.
class PdfTabState {
  final String id;
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final PdfViewerController viewerController;
  PdfTextSearcher? textSearcher;

  PdfDocument? document;
  List<PdfOutlineNode> outline = const [];
  bool outlineLoaded = false;

  int currentPage = 1;
  int pageCount = 0;
  double currentZoom = 1.0;
  int rotationQuarterTurns = 0;

  bool showSearchBar = false;
  String searchQuery = '';
  bool searchCaseSensitive = false;

  bool isReady = false;
  String? errorMessage;

  PdfTabState({
    required this.id,
    required this.filePath,
    String? fileName,
    int? fileSizeBytes,
    PdfViewerController? viewerController,
  })  : fileName = fileName ?? p.basename(filePath),
        fileSizeBytes = fileSizeBytes ?? _safeFileSize(filePath),
        viewerController = viewerController ?? PdfViewerController();

  /// Lazily attaches [PdfTextSearcher] once [viewerController] is ready.
  /// In pdfrx 2.x, `PdfTextSearcher` immediately accesses `controller!.document`
  /// on construction, so it must only be created after `onViewerReady`.
  PdfTextSearcher? ensureTextSearcher(VoidCallback onChanged) {
    if (textSearcher != null) return textSearcher;
    if (!viewerController.isReady) return null;
    textSearcher = PdfTextSearcher(viewerController)..addListener(onChanged);
    return textSearcher;
  }

  static int _safeFileSize(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  PdfPageRotation get pdfPageRotation =>
      PdfPageRotation.values[rotationQuarterTurns % 4];

  int get rotationDegrees => (rotationQuarterTurns % 4) * 90;

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void dispose() {
    textSearcher?.dispose();
    textSearcher = null;
  }
}
