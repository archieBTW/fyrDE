import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import '../models/pdf_models.dart';
import '../services/pdf_storage_service.dart';

/// Application-wide state controller for fyrPDF.
class PdfAppController extends ChangeNotifier {
  final PdfStorageService storage;
  final bool checkRecentFilesExist;

  final List<PdfTabState> _tabs = [];
  int _activeTabIndex = -1;
  int _nextTabId = 1;

  List<RecentPdfEntry> _recentFiles = [];
  Map<String, List<PdfBookmarkEntry>> _bookmarksByFile = {};

  bool _sidebarVisible = true;
  SidebarTab _sidebarTab = SidebarTab.thumbnails;
  bool _darkReadingMode = false;

  String? _statusMessage;
  Timer? _statusTimer;

  PdfAppController({
    PdfStorageService? storage,
    this.checkRecentFilesExist = true,
  }) : storage = storage ?? PdfStorageService();

  List<PdfTabState> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  PdfTabState? get activeTab =>
      (_activeTabIndex >= 0 && _activeTabIndex < _tabs.length)
          ? _tabs[_activeTabIndex]
          : null;
  bool get hasOpenDocument => activeTab != null;

  List<RecentPdfEntry> get recentFiles => List.unmodifiable(_recentFiles);

  bool get sidebarVisible => _sidebarVisible;
  SidebarTab get sidebarTab => _sidebarTab;
  bool get darkReadingMode => _darkReadingMode;
  String? get statusMessage => _statusMessage;

  List<PdfBookmarkEntry> bookmarksForFile(String filePath) {
    final key = p.normalize(filePath);
    return List.unmodifiable(_bookmarksByFile[key] ?? const []);
  }

  List<PdfBookmarkEntry> get activeBookmarks {
    final tab = activeTab;
    if (tab == null) return const [];
    return bookmarksForFile(tab.filePath);
  }

  bool get isCurrentPageBookmarked {
    final tab = activeTab;
    if (tab == null) return false;
    return activeBookmarks.any((b) => b.pageNumber == tab.currentPage);
  }

  /// Loads persisted recent files and bookmarks from disk.
  Future<void> initialize() async {
    _recentFiles =
        await storage.loadRecentFiles(checkExists: checkRecentFilesExist);
    _bookmarksByFile = await storage.loadAllBookmarks();
    notifyListeners();
  }

  void setStatus(String message, {Duration duration = const Duration(seconds: 3)}) {
    _statusTimer?.cancel();
    _statusMessage = message;
    notifyListeners();
    _statusTimer = Timer(duration, () {
      _statusMessage = null;
      notifyListeners();
    });
  }

  /// Opens a PDF file in a tab (or focuses the existing tab if already open).
  Future<bool> openFile(String filePath, {bool verifyExists = true}) async {
    final normalized = p.normalize(filePath);
    if (verifyExists && !File(normalized).existsSync()) {
      setStatus('File not found: ${p.basename(normalized)}');
      return false;
    }

    final existingIdx = _tabs.indexWhere((t) => t.filePath == normalized);
    if (existingIdx != -1) {
      _activeTabIndex = existingIdx;
      _recentFiles = await storage.recordRecentFile(
        normalized,
        pageCount: _tabs[existingIdx].pageCount > 0
            ? _tabs[existingIdx].pageCount
            : null,
        checkExists: checkRecentFilesExist,
      );
      notifyListeners();
      return true;
    }

    final tab = PdfTabState(
      id: 'tab_${_nextTabId++}',
      filePath: normalized,
    );

    tab.viewerController.addListener(() => _onViewerMatrixChanged(tab));

    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    notifyListeners();

    _recentFiles = await storage.recordRecentFile(
      normalized,
      checkExists: checkRecentFilesExist,
    );
    notifyListeners();
    return true;
  }

  void _onViewerMatrixChanged(PdfTabState tab) {
    if (!tab.viewerController.isReady) return;
    final zoom = tab.viewerController.currentZoom;
    if ((zoom - tab.currentZoom).abs() > 0.005) {
      tab.currentZoom = zoom;
      notifyListeners();
    }
  }

  /// Called by [PdfViewerParams.onViewerReady] once PDFium finishes loading.
  Future<void> onViewerReady(
    PdfTabState tab,
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    if (!_tabs.contains(tab)) return;
    tab.document = document;
    tab.pageCount = document.pages.length;
    tab.currentPage = controller.pageNumber ?? 1;
    tab.currentZoom = controller.isReady ? controller.currentZoom : 1.0;
    tab.isReady = true;
    tab.errorMessage = null;
    tab.ensureTextSearcher(notifyListeners);
    notifyListeners();

    // Update page count in recent files metadata
    _recentFiles = await storage.recordRecentFile(
      tab.filePath,
      pageCount: tab.pageCount,
      checkExists: checkRecentFilesExist,
    );

    // Load document outline (table of contents)
    try {
      final outline = await document.loadOutline();
      if (_tabs.contains(tab)) {
        tab.outline = outline;
        tab.outlineLoaded = true;
        notifyListeners();
      }
    } catch (_) {
      if (_tabs.contains(tab)) {
        tab.outline = const [];
        tab.outlineLoaded = true;
        notifyListeners();
      }
    }
  }

  /// Called by [PdfViewerParams.onPageChanged] when the active page changes.
  void onPageChanged(PdfTabState tab, int? pageNumber) {
    if (!_tabs.contains(tab) || pageNumber == null) return;
    if (tab.currentPage != pageNumber) {
      tab.currentPage = pageNumber;
      notifyListeners();
    }
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeTabIndex = index;
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final removed = _tabs.removeAt(index);
    removed.dispose();

    if (_tabs.isEmpty) {
      _activeTabIndex = -1;
    } else if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (index < _activeTabIndex) {
      _activeTabIndex--;
    }
    notifyListeners();
  }

  void closeActiveTab() {
    if (_activeTabIndex >= 0) {
      closeTab(_activeTabIndex);
    }
  }

  Future<void> removeRecentFile(String filePath) async {
    _recentFiles = await storage.removeRecentFile(
      filePath,
      checkExists: checkRecentFilesExist,
    );
    notifyListeners();
  }

  Future<void> clearRecentFiles() async {
    _recentFiles = [];
    notifyListeners();
    setStatus('Recent file history cleared');
    await storage.clearRecentFiles();
  }

  // --- Sidebar & Reading Mode ---

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    notifyListeners();
  }

  void setSidebarTab(SidebarTab tab) {
    _sidebarTab = tab;
    if (!_sidebarVisible) {
      _sidebarVisible = true;
    }
    notifyListeners();
  }

  void toggleDarkReadingMode() {
    _darkReadingMode = !_darkReadingMode;
    setStatus(_darkReadingMode
        ? 'Dark Reading Mode enabled'
        : 'Dark Reading Mode disabled');
  }

  // --- Navigation ---

  Future<void> goToPage(int pageNumber) async {
    final tab = activeTab;
    if (tab == null) return;
    final maxPage = tab.pageCount > 0 ? tab.pageCount : 1;
    final clamped = pageNumber.clamp(1, maxPage);
    tab.currentPage = clamped;
    notifyListeners();
    if (tab.viewerController.isReady) {
      await tab.viewerController.goToPage(pageNumber: clamped);
    }
  }

  Future<void> nextPage() async {
    final tab = activeTab;
    if (tab == null) return;
    await goToPage(tab.currentPage + 1);
  }

  Future<void> previousPage() async {
    final tab = activeTab;
    if (tab == null) return;
    await goToPage(tab.currentPage - 1);
  }

  Future<void> firstPage() async => goToPage(1);

  Future<void> lastPage() async {
    final tab = activeTab;
    if (tab == null || tab.pageCount <= 0) return;
    await goToPage(tab.pageCount);
  }

  Future<void> goToDest(PdfDest? dest) async {
    final tab = activeTab;
    if (tab == null || dest == null) return;
    if (tab.viewerController.isReady) {
      await tab.viewerController.goToDest(dest);
    }
  }

  // --- Zoom Controls ---

  Future<void> zoomIn() async {
    final tab = activeTab;
    if (tab == null || !tab.viewerController.isReady) return;
    await tab.viewerController.zoomUp();
    tab.currentZoom = tab.viewerController.currentZoom;
    notifyListeners();
  }

  Future<void> zoomOut() async {
    final tab = activeTab;
    if (tab == null || !tab.viewerController.isReady) return;
    await tab.viewerController.zoomDown();
    tab.currentZoom = tab.viewerController.currentZoom;
    notifyListeners();
  }

  Future<void> resetZoom() async {
    final tab = activeTab;
    if (tab == null || !tab.viewerController.isReady) return;
    await tab.viewerController.setZoom(tab.viewerController.centerPosition, 1.0);
    tab.currentZoom = tab.viewerController.currentZoom;
    notifyListeners();
  }

  Future<void> fitWidth() async {
    final tab = activeTab;
    if (tab == null || !tab.viewerController.isReady) return;
    final page = tab.currentPage.clamp(1, tab.pageCount > 0 ? tab.pageCount : 1);
    final matrix = tab.viewerController.calcMatrixFitWidthForPage(pageNumber: page);
    if (matrix != null) {
      await tab.viewerController.goTo(matrix);
      tab.currentZoom = tab.viewerController.currentZoom;
      notifyListeners();
    }
  }

  Future<void> fitPage() async {
    final tab = activeTab;
    if (tab == null || !tab.viewerController.isReady) return;
    final page = tab.currentPage.clamp(1, tab.pageCount > 0 ? tab.pageCount : 1);
    final matrix = tab.viewerController.calcMatrixForFit(pageNumber: page);
    if (matrix != null) {
      await tab.viewerController.goTo(matrix);
      tab.currentZoom = tab.viewerController.currentZoom;
      notifyListeners();
    }
  }

  // --- Rotation ---

  void rotateClockwise() {
    final tab = activeTab;
    if (tab == null) return;
    tab.rotationQuarterTurns = (tab.rotationQuarterTurns + 1) % 4;
    notifyListeners();
  }

  void rotateCounterClockwise() {
    final tab = activeTab;
    if (tab == null) return;
    tab.rotationQuarterTurns = (tab.rotationQuarterTurns + 3) % 4;
    notifyListeners();
  }

  void resetRotation() {
    final tab = activeTab;
    if (tab == null) return;
    tab.rotationQuarterTurns = 0;
    notifyListeners();
  }

  // --- Search ---

  void openSearchBar() {
    final tab = activeTab;
    if (tab == null) return;
    tab.showSearchBar = true;
    notifyListeners();
  }

  void closeSearchBar() {
    final tab = activeTab;
    if (tab == null) return;
    tab.showSearchBar = false;
    tab.searchQuery = '';
    tab.textSearcher?.resetTextSearch();
    notifyListeners();
  }

  void toggleSearchBar() {
    final tab = activeTab;
    if (tab == null) return;
    if (tab.showSearchBar) {
      closeSearchBar();
    } else {
      openSearchBar();
    }
  }

  void updateSearchQuery(String query) {
    final tab = activeTab;
    if (tab == null) return;
    tab.searchQuery = query;
    final searcher = tab.ensureTextSearcher(notifyListeners);
    if (query.trim().isEmpty) {
      searcher?.resetTextSearch();
    } else {
      searcher?.startTextSearch(
        query,
        caseInsensitive: !tab.searchCaseSensitive,
        goToFirstMatch: true,
      );
    }
    notifyListeners();
  }

  void toggleSearchCaseSensitive() {
    final tab = activeTab;
    if (tab == null) return;
    tab.searchCaseSensitive = !tab.searchCaseSensitive;
    final searcher = tab.ensureTextSearcher(notifyListeners);
    if (tab.searchQuery.trim().isNotEmpty) {
      searcher?.startTextSearch(
        tab.searchQuery,
        caseInsensitive: !tab.searchCaseSensitive,
        goToFirstMatch: true,
      );
    }
    notifyListeners();
  }

  Future<void> nextSearchMatch() async {
    final tab = activeTab;
    final searcher = tab?.textSearcher;
    if (searcher == null || !searcher.hasMatches) return;
    await searcher.goToNextMatch();
    notifyListeners();
  }

  Future<void> prevSearchMatch() async {
    final tab = activeTab;
    final searcher = tab?.textSearcher;
    if (searcher == null || !searcher.hasMatches) return;
    await searcher.goToPrevMatch();
    notifyListeners();
  }

  // --- Bookmarks ---

  Future<void> toggleBookmarkForCurrentPage({String? label}) async {
    final tab = activeTab;
    if (tab == null) return;
    final key = p.normalize(tab.filePath);
    final list = [...(_bookmarksByFile[key] ?? const <PdfBookmarkEntry>[])];
    final existingIdx = list.indexWhere((b) => b.pageNumber == tab.currentPage);
    if (existingIdx != -1) {
      list.removeAt(existingIdx);
      _bookmarksByFile[key] = list;
      await storage.saveAllBookmarks(_bookmarksByFile);
      setStatus('Removed bookmark on Page ${tab.currentPage}');
    } else {
      list.add(
        PdfBookmarkEntry(
          pageNumber: tab.currentPage,
          label: (label != null && label.trim().isNotEmpty)
              ? label.trim()
              : 'Page ${tab.currentPage}',
          createdAt: DateTime.now(),
        ),
      );
      list.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      _bookmarksByFile[key] = list;
      await storage.saveAllBookmarks(_bookmarksByFile);
      setStatus('Bookmarked Page ${tab.currentPage}');
    }
    notifyListeners();
  }

  Future<void> addBookmark(String filePath, int pageNumber, {String? label}) async {
    final key = p.normalize(filePath);
    final list = [...(_bookmarksByFile[key] ?? const <PdfBookmarkEntry>[])];
    list.removeWhere((b) => b.pageNumber == pageNumber);
    list.add(
      PdfBookmarkEntry(
        pageNumber: pageNumber,
        label: (label != null && label.trim().isNotEmpty)
            ? label.trim()
            : 'Page $pageNumber',
        createdAt: DateTime.now(),
      ),
    );
    list.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    _bookmarksByFile[key] = list;
    await storage.saveAllBookmarks(_bookmarksByFile);
    notifyListeners();
  }

  Future<void> removeBookmark(String filePath, int pageNumber) async {
    final key = p.normalize(filePath);
    final list = [...(_bookmarksByFile[key] ?? const <PdfBookmarkEntry>[])];
    list.removeWhere((b) => b.pageNumber == pageNumber);
    if (list.isEmpty) {
      _bookmarksByFile.remove(key);
    } else {
      _bookmarksByFile[key] = list;
    }
    await storage.saveAllBookmarks(_bookmarksByFile);
    notifyListeners();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
