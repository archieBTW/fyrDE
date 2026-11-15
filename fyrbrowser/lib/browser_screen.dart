import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_cef/webview_cef.dart';
import 'package:window_manager/window_manager.dart';

import 'adblock_engine.dart';
import 'browser_models.dart';
import 'download_manager.dart';
import 'fyr_theme.dart';
import 'home_page.dart';
import 'logger_service.dart';
import 'settings_dialog.dart';

const String _kUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  final bool isAppMode;

  const BrowserScreen({
    super.key,
    this.initialUrl,
    this.isAppMode = false,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with WindowListener {
  final List<BrowserTab> _tabs = [];
  int _activeTabIndex = 0;
  int _nextTabId = 1;
  final List<String> _closedTabUrls = [];

  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final LayerLink _urlBarLink = LayerLink();
  OverlayEntry? _autocompleteOverlay;

  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  bool _showFindBar = false;
  int _findMatchCount = 0;
  int _findActiveOrdinal = 0;

  BrowserSettings _settings = BrowserSettings();
  List<Map<String, String>> _history = [];
  List<Map<String, String>> _bookmarks = [];
  Timer? _saveDebounce;

  bool _isEngineReady = false;
  bool _isMaximized = false;

  BrowserTab? get _activeTab =>
      (_tabs.isNotEmpty && _activeTabIndex >= 0 && _activeTabIndex < _tabs.length)
          ? _tabs[_activeTabIndex]
          : null;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _urlController.addListener(_onUrlTextChanged);
    _initBrowser();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _removeAutocompleteOverlay();
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _urlController.removeListener(_onUrlTextChanged);
    _urlFocusNode.dispose();
    _urlController.dispose();
    _findFocusNode.dispose();
    _findController.dispose();
    for (final tab in _tabs) {
      tab.controller.dispose();
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _initBrowser() async {
    await _loadData();
    try {
      _isMaximized = await windowManager.isMaximized();
    } catch (_) {}

    try {
      await WebviewManager().initialize(userAgent: _kUserAgent);
      await _syncAdBlockConfig();
      if (!mounted) return;
      setState(() => _isEngineReady = true);

      final startUrl = widget.initialUrl ?? _settings.homePage;
      await _addNewTab(initialUrl: startUrl);
    } catch (e, stack) {
      logger.e('Failed to initialize CEF WebviewManager', e, stack);
    }
  }

  Future<Directory> _dataDir() => getApplicationSupportDirectory();

  Future<void> _loadData() async {
    try {
      final dir = await _dataDir();
      final historyFile = File(p.join(dir.path, 'history.json'));
      if (await historyFile.exists()) {
        final decoded = jsonDecode(await historyFile.readAsString());
        if (decoded is List) {
          _history = decoded
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
              .toList();
        }
      }

      final bookmarksFile = File(p.join(dir.path, 'bookmarks.json'));
      if (await bookmarksFile.exists()) {
        final decoded = jsonDecode(await bookmarksFile.readAsString());
        if (decoded is List) {
          _bookmarks = decoded
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
              .toList();
        }
      }

      final settingsFile = File(p.join(dir.path, 'settings.json'));
      if (await settingsFile.exists()) {
        final decoded = jsonDecode(await settingsFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          _settings = BrowserSettings.fromJson(decoded);
        }
      }
    } catch (e) {
      logger.w('Failed loading persisted browser data: $e');
    }
  }

  void _scheduleSaveData() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _writeDataToDisk();
    });
  }

  Future<void> _writeDataToDisk() async {
    try {
      final dir = await _dataDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await Future.wait([
        File(p.join(dir.path, 'history.json'))
            .writeAsString(jsonEncode(_history)),
        File(p.join(dir.path, 'bookmarks.json'))
            .writeAsString(jsonEncode(_bookmarks)),
        File(p.join(dir.path, 'settings.json'))
            .writeAsString(jsonEncode(_settings.toJson())),
      ]);
    } catch (e) {
      logger.w('Failed writing browser data: $e');
    }
  }

  Future<void> _syncAdBlockConfig() async {
    if (!WebviewManager().value) return;
    await WebviewManager().setAdBlockConfig(
      enabled: _settings.adBlockEnabled,
      blockedDomains: AdBlockEngine.blockedDomains,
      whitelistHosts: _settings.adBlockWhitelist,
    );
  }

  bool _shouldBlockOnUrl(String url) {
    if (!_settings.adBlockEnabled || isInternalUrl(url)) return false;
    final host = AdBlockEngine.extractHost(url);
    return host.isNotEmpty && !_settings.isHostWhitelisted(host);
  }

  void _addToHistory(String title, String url) {
    if (url.isEmpty || isInternalUrl(url) || url.startsWith('about:')) return;
    if (_history.isNotEmpty && _history.first['url'] == url) {
      if (title.isNotEmpty && _history.first['title'] != title) {
        _history.first['title'] = title;
        _scheduleSaveData();
      }
      return;
    }
    _history.insert(0, {
      'title': title.isNotEmpty ? title : url,
      'url': url,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_history.length > 500) {
      _history.removeRange(500, _history.length);
    }
    _scheduleSaveData();
  }

  bool _isBookmarked(String url) {
    if (isInternalUrl(url)) return false;
    return _bookmarks.any((b) => b['url'] == url);
  }

  void _toggleBookmark(BrowserTab tab) {
    if (tab.isHomePage || tab.url.isEmpty) return;
    setState(() {
      final idx = _bookmarks.indexWhere((b) => b['url'] == tab.url);
      if (idx >= 0) {
        _bookmarks.removeAt(idx);
      } else {
        _bookmarks.insert(0, {
          'title': tab.title.isNotEmpty ? tab.title : tab.url,
          'url': tab.url,
        });
      }
    });
    _scheduleSaveData();
  }

  Future<void> _addNewTab({String? initialUrl}) async {
    final target = (initialUrl ?? kFyrHomeUrl).trim();
    final isHome = target == kFyrHomeUrl;
    final controller = WebviewManager().createWebView();
    final tab = BrowserTab(
      id: 'tab_${_nextTabId++}',
      controller: controller,
      title: isHome ? 'New Tab' : target,
      url: isHome ? kFyrHomeUrl : target,
      isLoading: !isHome,
    );

    _bindTabListeners(tab);

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    _syncUrlBarWithActiveTab();

    await controller.initialize(isHome ? 'about:blank' : target);
  }

  void _bindTabListeners(BrowserTab tab) {
    tab.controller.setWebviewListener(
      WebviewEventsListener(
        onTitleChanged: (title) {
          if (!mounted || tab.isHomePage) return;
          if (title.isEmpty || title == 'about:blank') return;
          setState(() => tab.title = title);
        },
        onUrlChanged: (url) {
          if (!mounted) return;
          if (tab.isHomePage && url == 'about:blank') return;
          setState(() => tab.url = url);
          if (_activeTab?.id == tab.id && !_urlFocusNode.hasFocus) {
            _urlController.text = tab.isHomePage ? '' : url;
          }
        },
        onLoadStart: (controller, url) {
          if (!mounted) return;
          if (tab.isHomePage && url == 'about:blank') return;
          setState(() {
            tab.isLoading = true;
            tab.loadError = null;
            tab.url = url;
          });
          if (_activeTab?.id == tab.id && !_urlFocusNode.hasFocus) {
            _urlController.text = url;
          }
        },
        onLoadEnd: (controller, url) {
          if (!mounted) return;
          if (tab.isHomePage || url == 'about:blank') return;
          setState(() => tab.isLoading = false);
          _applyCosmeticAdBlock(tab, url);
          _checkPwaStatus(tab);
          _addToHistory(tab.title, url);
        },
        onLoadError: (controller, errorCode, errorText, failedUrl) {
          // Ignore ERR_ABORTED (-3) from user Stop or fast redirects.
          if (!mounted || errorCode == -3) return;
          if (tab.isHomePage || failedUrl == 'about:blank') return;
          setState(() {
            tab.isLoading = false;
            tab.loadError = LoadErrorInfo(
              errorCode: errorCode,
              errorText: errorText,
              failedUrl: failedUrl,
            );
          });
        },
        onLoadingStateChanged: (isLoading, canGoBack, canGoForward) {
          if (!mounted || tab.isHomePage) return;
          setState(() {
            tab.isLoading = isLoading;
            tab.canGoBack = canGoBack;
            tab.canGoForward = canGoForward;
          });
        },
        onFindResult: (count, activeMatchOrdinal, finalUpdate) {
          if (!mounted || _activeTab?.id != tab.id) return;
          setState(() {
            _findMatchCount = count;
            _findActiveOrdinal = activeMatchOrdinal;
          });
        },
        onAdBlocked: (totalCount) {
          if (!mounted) return;
          setState(() => tab.blockedCount = totalCount);
        },
        onBeforePopup: (targetUrl) {
          if (!mounted || targetUrl.isEmpty) return;
          _addNewTab(initialUrl: targetUrl);
        },
        onExternalProtocol: (url) async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        onDownloadStart: (suggestedName, url) {
          if (!mounted) return;
          DownloadManager().startDownload(suggestedName, url);
          setState(() {});
        },
        onDownloadUpdated:
            (url, receivedBytes, totalBytes, percent, isComplete) {
          if (!mounted) return;
          DownloadManager().updateDownload(
            url,
            receivedBytes,
            totalBytes,
            percent,
            isComplete,
          );
          setState(() {});
        },
        onContextMenu:
            (x, y, typeFlags, linkUrl, sourceUrl, selectionText, isEditable) {
          _showWebContextMenu(
            tab: tab,
            x: x.toDouble(),
            y: y.toDouble(),
            linkUrl: linkUrl,
            selectionText: selectionText,
          );
        },
        onFileDialog: (browserId, callbackId) async {
          await _handleFileDialog(callbackId);
        },
        onClose: () {
          if (!mounted) return;
          final idx = _tabs.indexOf(tab);
          if (idx >= 0) _closeTab(idx);
        },
      ),
    );
  }

  Future<void> _handleFileDialog(int callbackId) async {
    List<String> files = [];
    try {
      final result = await Process.run('zenity', ['--file-selection']);
      if (result.exitCode == 0) {
        final chosen = result.stdout.toString().trim();
        if (chosen.isNotEmpty) files = [chosen];
      }
    } catch (_) {}
    await WebviewManager()
        .pluginChannel
        .invokeMethod('continueFileDialog', [callbackId, files]);
  }

  Future<void> _applyCosmeticAdBlock(BrowserTab tab, String url) async {
    final script = _shouldBlockOnUrl(url)
        ? AdBlockEngine.cosmeticCssScript
        : AdBlockEngine.removeCosmeticCssScript;
    await tab.controller.executeJavaScript(script);
  }

  Future<void> _checkPwaStatus(BrowserTab tab) async {
    try {
      final raw = await tab.controller.evaluateJavascript('''
        (function() {
          var m = document.querySelector('link[rel="manifest"]');
          var appleIcon = document.querySelector('link[rel="apple-touch-icon"]');
          var icon = document.querySelector('link[rel*="icon"]');
          return JSON.stringify({
            hasManifest: !!m,
            icon: (appleIcon && appleIcon.href) || (icon && icon.href) || null
          });
        })();
      ''');
      if (!mounted || raw is! String || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is Map) {
        setState(() {
          tab.isPwa = data['hasManifest'] == true;
          final icon = data['icon'];
          if (icon is String && icon.isNotEmpty) {
            tab.faviconUrl = icon;
          }
        });
      }
    } catch (_) {}
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length == 1) {
      _navigateActiveTabTo(kFyrHomeUrl);
      return;
    }

    final closing = _tabs[index];
    if (!closing.isHomePage && closing.url.isNotEmpty) {
      _closedTabUrls.add(closing.url);
      if (_closedTabUrls.length > 20) _closedTabUrls.removeAt(0);
    }

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (_activeTabIndex > index) {
        _activeTabIndex--;
      }
    });
    closing.controller.dispose();
    _syncUrlBarWithActiveTab();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() => _activeTabIndex = index);
    _syncUrlBarWithActiveTab();
  }

  void _syncUrlBarWithActiveTab() {
    final tab = _activeTab;
    if (tab == null) return;
    _urlController.text = tab.isHomePage ? '' : tab.url;
  }

  Future<void> _navigateActiveTabTo(String rawInput) async {
    final tab = _activeTab;
    if (tab == null) return;

    final resolved = resolveNavigationInput(rawInput, _settings.searchEngine);
    _urlFocusNode.unfocus();
    _removeAutocompleteOverlay();

    if (resolved == kFyrHomeUrl) {
      await tab.controller.stopLoad();
      await tab.controller.loadUrl('about:blank');
      setState(() {
        tab.url = kFyrHomeUrl;
        tab.title = 'New Tab';
        tab.isLoading = false;
        tab.loadError = null;
        tab.isPwa = false;
        tab.blockedCount = 0;
      });
      _urlController.text = '';
      return;
    }

    setState(() {
      tab.url = resolved;
      tab.loadError = null;
      tab.isLoading = true;
    });
    _urlController.text = resolved;
    await tab.controller.loadUrl(resolved);
  }

  Future<void> _reloadOrStop() async {
    final tab = _activeTab;
    if (tab == null) return;
    if (tab.isHomePage) return;

    if (tab.isLoading) {
      await tab.controller.stopLoad();
      setState(() => tab.isLoading = false);
      return;
    }

    if (tab.loadError != null) {
      final retryUrl = tab.loadError!.failedUrl;
      setState(() {
        tab.loadError = null;
        tab.isLoading = true;
      });
      await tab.controller.loadUrl(retryUrl);
      return;
    }

    await tab.controller.reload();
  }

  Future<void> _adjustZoom(double delta) async {
    final tab = _activeTab;
    if (tab == null || tab.isHomePage) return;
    final next = (tab.zoomLevel + delta).clamp(-3.0, 5.0);
    setState(() => tab.zoomLevel = next);
    await tab.controller.setZoomLevel(next);
  }

  Future<void> _resetZoom() async {
    final tab = _activeTab;
    if (tab == null || tab.isHomePage) return;
    setState(() => tab.zoomLevel = 0.0);
    await tab.controller.setZoomLevel(0.0);
  }

  String _zoomLabel(double zoomLevel) {
    final pct = (100 + zoomLevel * 20).round();
    return '$pct%';
  }

  void _openFindBar() {
    if (_activeTab?.isHomePage ?? true) return;
    setState(() => _showFindBar = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _findFocusNode.requestFocus();
      _findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findController.text.length,
      );
    });
  }

  void _closeFindBar() {
    setState(() {
      _showFindBar = false;
      _findMatchCount = 0;
      _findActiveOrdinal = 0;
    });
    _activeTab?.controller.stopFinding();
  }

  void _runFind({bool forward = true, bool findNext = false}) {
    final tab = _activeTab;
    if (tab == null || tab.isHomePage) return;
    final query = _findController.text;
    if (query.isEmpty) {
      tab.controller.stopFinding();
      setState(() {
        _findMatchCount = 0;
        _findActiveOrdinal = 0;
      });
      return;
    }
    tab.controller.findInPage(query, forward: forward, findNext: findNext);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.f5) {
      _reloadOrStop();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _showFindBar) {
      _closeFindBar();
      return true;
    }
    if (!ctrl) return false;

    if (key == LogicalKeyboardKey.keyR) {
      if (_activeTab?.isLoading == false) _reloadOrStop();
      return true;
    }
    if (key == LogicalKeyboardKey.keyT) {
      if (shift && _closedTabUrls.isNotEmpty) {
        _addNewTab(initialUrl: _closedTabUrls.removeLast());
      } else {
        _addNewTab();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyW) {
      _closeTab(_activeTabIndex);
      return true;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _urlFocusNode.requestFocus();
      _urlController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _urlController.text.length,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _openFindBar();
      return true;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _adjustZoom(0.5);
      return true;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _adjustZoom(-0.5);
      return true;
    }
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _resetZoom();
      return true;
    }
    if (key == LogicalKeyboardKey.tab && _tabs.length > 1) {
      final delta = shift ? -1 : 1;
      _selectTab((_activeTabIndex + delta + _tabs.length) % _tabs.length);
      return true;
    }
    return false;
  }

  void _onUrlFocusChanged() {
    if (_urlFocusNode.hasFocus) {
      _urlController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _urlController.text.length,
      );
      _updateAutocompleteOverlay();
    } else {
      _removeAutocompleteOverlay();
      final tab = _activeTab;
      if (tab != null) {
        _urlController.text = tab.isHomePage ? '' : tab.url;
      }
    }
  }

  void _onUrlTextChanged() {
    if (_urlFocusNode.hasFocus) {
      _updateAutocompleteOverlay();
    }
  }

  List<Map<String, String>> _buildSuggestions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final results = <Map<String, String>>[];
    for (final list in [_bookmarks, _history]) {
      for (final item in list) {
        final url = item['url'] ?? '';
        final title = item['title'] ?? '';
        if (url.isEmpty || isInternalUrl(url) || seen.contains(url)) continue;
        if (url.toLowerCase().contains(q) ||
            title.toLowerCase().contains(q)) {
          seen.add(url);
          results.add({'title': title, 'url': url});
          if (results.length >= 6) return results;
        }
      }
    }
    return results;
  }

  void _updateAutocompleteOverlay() {
    _removeAutocompleteOverlay();
    if (!_urlFocusNode.hasFocus) return;
    final suggestions = _buildSuggestions(_urlController.text);
    if (suggestions.isEmpty) return;

    final overlay = Overlay.of(context);
    _autocompleteOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 520,
        child: CompositedTransformFollower(
          link: _urlBarLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 38),
          child: Material(
            elevation: 8,
            color: FyrTheme.bgColor,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: FyrTheme.dividerColor.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: suggestions.map((s) {
                  final url = s['url'] ?? '';
                  final title = (s['title'] ?? '').trim();
                  return InkWell(
                    onTap: () => _navigateActiveTabTo(url),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.public,
                            size: 14,
                            color: FyrTheme.textColor.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title.isNotEmpty ? title : url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: FyrTheme.textColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: FyrTheme.accentColor,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_autocompleteOverlay!);
  }

  void _removeAutocompleteOverlay() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
  }

  Future<void> _showWebContextMenu({
    required BrowserTab tab,
    required double x,
    required double y,
    required String linkUrl,
    required String selectionText,
  }) async {
    if (!mounted) return;
    final action = await showMenu<String>(
      context: context,
      color: FyrTheme.bgColor,
      position: RelativeRect.fromLTRB(x, y + 84, x + 1, y + 85),
      items: [
        PopupMenuItem(
          enabled: tab.canGoBack,
          value: 'back',
          child: const Text('Back'),
        ),
        PopupMenuItem(
          enabled: tab.canGoForward,
          value: 'forward',
          child: const Text('Forward'),
        ),
        const PopupMenuItem(value: 'reload', child: Text('Reload')),
        if (linkUrl.isNotEmpty) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'open_link_tab',
            child: Text('Open Link in New Tab'),
          ),
          const PopupMenuItem(
            value: 'copy_link',
            child: Text('Copy Link Address'),
          ),
        ],
        if (selectionText.isNotEmpty)
          const PopupMenuItem(value: 'copy_text', child: Text('Copy')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'devtools', child: Text('Inspect Element')),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'back':
        tab.controller.goBack();
        break;
      case 'forward':
        tab.controller.goForward();
        break;
      case 'reload':
        tab.controller.reload();
        break;
      case 'open_link_tab':
        _addNewTab(initialUrl: linkUrl);
        break;
      case 'copy_link':
        Clipboard.setData(ClipboardData(text: linkUrl));
        break;
      case 'copy_text':
        Clipboard.setData(ClipboardData(text: selectionText));
        break;
      case 'devtools':
        tab.controller.openDevTools();
        break;
    }
  }

  void _openSettingsModal({int initialTab = 0}) {
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        settings: _settings,
        history: _history,
        bookmarks: _bookmarks,
        initialTab: initialTab,
        onSettingsChanged: (updated) {
          setState(() => _settings = updated);
          _syncAdBlockConfig();
          _scheduleSaveData();
          final tab = _activeTab;
          if (tab != null && !tab.isHomePage) {
            _applyCosmeticAdBlock(tab, tab.url);
          }
        },
        onNavigate: (url) => _navigateActiveTabTo(url),
        onRemoveBookmark: (url) {
          setState(() => _bookmarks.removeWhere((b) => b['url'] == url));
          _scheduleSaveData();
        },
        onClearHistory: () {
          setState(() => _history.clear());
          _scheduleSaveData();
        },
      ),
    );
  }

  void _showDownloadsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        title: Text('Downloads', style: TextStyle(color: FyrTheme.textColor)),
        content: SizedBox(
          width: 420,
          height: 280,
          child: DownloadManager().tasks.isEmpty
              ? Center(
                  child: Text(
                    'No downloads yet.',
                    style: TextStyle(
                      color: FyrTheme.textColor.withValues(alpha: 0.55),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: DownloadManager().tasks.length,
                  itemBuilder: (context, index) {
                    final task = DownloadManager().tasks[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        task.suggestedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                      ),
                      subtitle: Text(
                        task.isComplete
                            ? 'Completed (~/Downloads)'
                            : '${task.progress}%',
                        style: TextStyle(
                          color: FyrTheme.textColor.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              DownloadManager().clearHistory();
              Navigator.of(context).pop();
              setState(() {});
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FyrTheme.bgColor,
      body: Column(
        children: [
          if (!widget.isAppMode) ...[
            _buildTabStrip(),
            _buildToolbar(),
          ],
          if (_showFindBar) _buildFindBar(),
          Expanded(child: _buildViewport()),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    return Container(
      height: 38,
      color: FyrTheme.bgColor,
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) => _buildTabChip(index),
                  ),
                ),
                IconButton(
                  onPressed: () => _addNewTab(),
                  tooltip: 'New Tab (Ctrl+T)',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(
                    Icons.add,
                    color: FyrTheme.textColor.withValues(alpha: 0.75),
                  ),
                ),
                const Expanded(
                  child: DragToMoveArea(child: SizedBox.expand()),
                ),
              ],
            ),
          ),
          _buildWindowControls(),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index) {
    final tab = _tabs[index];
    final active = index == _activeTabIndex;
    return GestureDetector(
      key: ValueKey(tab.id),
      onTap: () => _selectTab(index),
      child: Container(
        constraints: const BoxConstraints(minWidth: 110, maxWidth: 200),
        margin: const EdgeInsets.only(top: 5, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.textColor.withValues(alpha: 0.1)
              : FyrTheme.textColor.withValues(alpha: 0.03),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          border: active
              ? Border(
                  top: BorderSide(color: FyrTheme.accentColor, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            if (tab.isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: FyrTheme.accentColor,
                ),
              )
            else
              Icon(
                tab.isHomePage ? Icons.home_outlined : Icons.public,
                size: 13,
                color: FyrTheme.textColor.withValues(alpha: 0.65),
              ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                tab.title.isNotEmpty ? tab.title : tab.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? FyrTheme.textColor
                      : FyrTheme.textColor.withValues(alpha: 0.68),
                  fontSize: 12,
                ),
              ),
            ),
            InkWell(
              onTap: () => _closeTab(index),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: FyrTheme.textColor.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => windowManager.minimize(),
          iconSize: 15,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.remove, color: FyrTheme.textColor.withValues(alpha: 0.75)),
        ),
        IconButton(
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          iconSize: 14,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            _isMaximized ? Icons.filter_none : Icons.crop_square,
            color: FyrTheme.textColor.withValues(alpha: 0.75),
          ),
        ),
        IconButton(
          onPressed: () => windowManager.close(),
          iconSize: 15,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.close, color: FyrTheme.textColor.withValues(alpha: 0.75)),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final tab = _activeTab;
    final canBack = tab?.canGoBack ?? false;
    final canForward = tab?.canGoForward ?? false;
    final isHome = tab?.isHomePage ?? true;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(
          bottom: BorderSide(
            color: FyrTheme.dividerColor.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          _navButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            enabled: canBack,
            onPressed: () => tab?.controller.goBack(),
          ),
          _navButton(
            icon: Icons.arrow_forward,
            tooltip: 'Forward',
            enabled: canForward,
            onPressed: () => tab?.controller.goForward(),
          ),
          _navButton(
            icon: (tab?.isLoading ?? false) ? Icons.close : Icons.refresh,
            tooltip: (tab?.isLoading ?? false) ? 'Stop' : 'Reload (Ctrl+R)',
            enabled: tab != null && !isHome,
            onPressed: _reloadOrStop,
          ),
          _navButton(
            icon: Icons.home_outlined,
            tooltip: 'Home',
            enabled: tab != null,
            onPressed: () => _navigateActiveTabTo(_settings.homePage),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildUrlBar(tab)),
          const SizedBox(width: 6),
          if (tab != null && tab.zoomLevel != 0.0)
            TextButton(
              onPressed: _resetZoom,
              child: Text(
                _zoomLabel(tab.zoomLevel),
                style: TextStyle(color: FyrTheme.accentColor, fontSize: 12),
              ),
            ),
          if (tab != null && !isHome) _buildShieldMenu(tab),
          _navButton(
            icon: DownloadManager().tasks.any((t) => !t.isComplete)
                ? Icons.downloading
                : Icons.download_outlined,
            tooltip: 'Downloads',
            enabled: true,
            onPressed: _showDownloadsDialog,
          ),
          _buildOverflowMenu(),
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      iconSize: 18,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        icon,
        color: enabled
            ? FyrTheme.textColor.withValues(alpha: 0.85)
            : FyrTheme.textColor.withValues(alpha: 0.25),
      ),
    );
  }

  Widget _buildUrlBar(BrowserTab? tab) {
    final url = tab?.url ?? kFyrHomeUrl;
    final isSecure = url.startsWith('https://');
    final isError = tab?.loadError != null;
    final bookmarked = tab != null && _isBookmarked(url);

    return CompositedTransformTarget(
      link: _urlBarLink,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: FyrTheme.textColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _urlFocusNode.hasFocus
                ? FyrTheme.accentColor.withValues(alpha: 0.7)
                : FyrTheme.dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              isError
                  ? Icons.warning_amber_rounded
                  : isInternalUrl(url)
                      ? Icons.search
                      : isSecure
                          ? Icons.lock_outline
                          : Icons.lock_open,
              size: 14,
              color: isError
                  ? Colors.orangeAccent
                  : isSecure
                      ? Colors.greenAccent
                      : FyrTheme.textColor.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _urlController,
                focusNode: _urlFocusNode,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText:
                      'Search with ${_settings.searchEngine.label} or enter URL',
                  hintStyle: TextStyle(
                    color: FyrTheme.textColor.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _navigateActiveTabTo,
              ),
            ),
            if (tab != null && !tab.isHomePage)
              IconButton(
                onPressed: () => _toggleBookmark(tab),
                tooltip: bookmarked ? 'Remove Bookmark' : 'Bookmark Page',
                iconSize: 16,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  bookmarked ? Icons.star : Icons.star_border,
                  color: bookmarked
                      ? Colors.amber
                      : FyrTheme.textColor.withValues(alpha: 0.55),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildShieldMenu(BrowserTab tab) {
    final host = AdBlockEngine.extractHost(tab.url);
    final whitelisted =
        host.isNotEmpty && _settings.isHostWhitelisted(host);
    final active = _settings.adBlockEnabled && !whitelisted;

    return PopupMenuButton<String>(
      tooltip: active
          ? 'AdBlock Active (${tab.blockedCount} blocked)'
          : 'AdBlock Paused',
      color: FyrTheme.bgColor,
      onSelected: (value) async {
        if (value == 'toggle_site' && host.isNotEmpty) {
          setState(() => _settings.toggleWhitelistHost(host));
          await _syncAdBlockConfig();
          _scheduleSaveData();
          await _applyCosmeticAdBlock(tab, tab.url);
        } else if (value == 'toggle_global') {
          setState(() => _settings.adBlockEnabled = !_settings.adBlockEnabled);
          await _syncAdBlockConfig();
          _scheduleSaveData();
          await _applyCosmeticAdBlock(tab, tab.url);
        } else if (value == 'settings') {
          _openSettingsModal(initialTab: 0);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            active
                ? 'Shield Active • ${tab.blockedCount} blocked'
                : 'Shield Paused',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        if (host.isNotEmpty)
          PopupMenuItem(
            value: 'toggle_site',
            child: Text(
              whitelisted ? 'Enable on $host' : 'Pause on $host',
            ),
          ),
        PopupMenuItem(
          value: 'toggle_global',
          child: Text(
            _settings.adBlockEnabled
                ? 'Disable AdBlock Globally'
                : 'Enable AdBlock Globally',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: Text('AdBlock Settings...'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.shield : Icons.shield_outlined,
              size: 18,
              color: active
                  ? Colors.greenAccent
                  : FyrTheme.textColor.withValues(alpha: 0.45),
            ),
            if (active && tab.blockedCount > 0) ...[
              const SizedBox(width: 3),
              Text(
                '${tab.blockedCount}',
                style: TextStyle(
                  color: FyrTheme.textColor.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      color: FyrTheme.bgColor,
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: FyrTheme.textColor.withValues(alpha: 0.8),
      ),
      onSelected: (action) {
        switch (action) {
          case 'find':
            _openFindBar();
            break;
          case 'zoom_in':
            _adjustZoom(0.5);
            break;
          case 'zoom_out':
            _adjustZoom(-0.5);
            break;
          case 'zoom_reset':
            _resetZoom();
            break;
          case 'history':
            _openSettingsModal(initialTab: 1);
            break;
          case 'bookmarks':
            _openSettingsModal(initialTab: 2);
            break;
          case 'settings':
            _openSettingsModal(initialTab: 0);
            break;
          case 'devtools':
            _activeTab?.controller.openDevTools();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'find', child: Text('Find in Page (Ctrl+F)')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'zoom_in', child: Text('Zoom In (Ctrl++)')),
        PopupMenuItem(value: 'zoom_out', child: Text('Zoom Out (Ctrl+-)')),
        PopupMenuItem(value: 'zoom_reset', child: Text('Reset Zoom (Ctrl+0)')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'history', child: Text('History')),
        PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
        PopupMenuItem(value: 'settings', child: Text('Settings')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'devtools', child: Text('Developer Tools')),
      ],
    );
  }

  Widget _buildFindBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(
          bottom: BorderSide(
            color: FyrTheme.dividerColor.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _findController,
              focusNode: _findFocusNode,
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Find in page...',
                hintStyle: TextStyle(
                  color: FyrTheme.textColor.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: (_) => _runFind(forward: true, findNext: false),
              onSubmitted: (_) => _runFind(forward: true, findNext: true),
            ),
          ),
          Text(
            _findController.text.isEmpty
                ? ''
                : '$_findActiveOrdinal/$_findMatchCount',
            style: TextStyle(
              color: FyrTheme.textColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          IconButton(
            onPressed: () => _runFind(forward: false, findNext: true),
            iconSize: 16,
            icon: Icon(Icons.keyboard_arrow_up, color: FyrTheme.textColor),
          ),
          IconButton(
            onPressed: () => _runFind(forward: true, findNext: true),
            iconSize: 16,
            icon: Icon(Icons.keyboard_arrow_down, color: FyrTheme.textColor),
          ),
          IconButton(
            onPressed: _closeFindBar,
            iconSize: 16,
            icon: Icon(Icons.close, color: FyrTheme.textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    if (!_isEngineReady || _tabs.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: FyrTheme.accentColor),
      );
    }

    return IndexedStack(
      index: _activeTabIndex,
      children: _tabs.map((tab) {
        final hideWebView = tab.isHomePage || tab.loadError != null;
        return Stack(
          key: ValueKey('stack_${tab.id}'),
          children: [
            IgnorePointer(
              ignoring: hideWebView,
              child: WebView(
                tab.controller,
                key: ValueKey('webview_${tab.id}'),
              ),
            ),
            if (tab.isHomePage)
              Positioned.fill(
                child: FyrHomePage(
                  searchEngine: _settings.searchEngine,
                  adBlockEnabled: _settings.adBlockEnabled,
                  bookmarks: _bookmarks,
                  history: _history,
                  onNavigate: _navigateActiveTabTo,
                  onOpenSettings: () => _openSettingsModal(initialTab: 0),
                ),
              )
            else if (tab.loadError != null)
              Positioned.fill(
                child: FyrErrorPage(
                  error: tab.loadError!,
                  onRetry: _reloadOrStop,
                  onGoHome: () => _navigateActiveTabTo(kFyrHomeUrl),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}
