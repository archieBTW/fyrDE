import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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

class _BrowserScreenState extends State<BrowserScreen> {
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

  BrowserTab? get _activeTab =>
      (_tabs.isNotEmpty && _activeTabIndex >= 0 && _activeTabIndex < _tabs.length)
          ? _tabs[_activeTabIndex]
          : null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _urlController.addListener(_onUrlTextChanged);
    _initBrowser();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _writeDataToDisk();
    _removeAutocompleteOverlay();
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

  Future<void> _initBrowser() async {
    DownloadManager().init();
    await _loadData();

    try {
      await WebviewManager().initialize(userAgent: _kUserAgent);
      await _syncAdBlockConfig();

      WebviewManager().onPopupCreated = (controller) {
        if (!mounted) return;
        final popupTab = BrowserTab(
          id: 'tab_${_nextTabId++}',
          controller: controller,
          url: 'about:blank',
          isReady: true,
        );
        _bindTabListeners(popupTab);
        setState(() {
          _tabs.add(popupTab);
          _activeTabIndex = _tabs.length - 1;
          _urlController.text = popupTab.url;
        });
      };

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
    if (widget.isAppMode ||
        url.isEmpty ||
        isInternalUrl(url) ||
        url.startsWith('data:') ||
        url.startsWith('blob:')) {
      return;
    }
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
    if (url.isEmpty || isInternalUrl(url)) return false;
    return _bookmarks.any((b) => b['url'] == url);
  }

  void _toggleBookmark(BrowserTab tab) {
    if (tab.url.isEmpty || isInternalUrl(tab.url)) return;
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
    final raw = (initialUrl ?? _settings.homePage).trim();
    final target = raw.isNotEmpty ? raw : kDefaultHomePage;
    final controller = WebviewManager().createWebView();
    final tab = BrowserTab(
      id: 'tab_${_nextTabId++}',
      controller: controller,
      title: 'New Tab',
      url: target,
      isReady: false,
      isLoading: true,
    );

    _bindTabListeners(tab);

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    _syncUrlBarWithActiveTab();

    await controller.initialize(target);
    if (!mounted) return;
    setState(() {
      tab.isReady = true;
    });
  }

  void _bindTabListeners(BrowserTab tab) {
    tab.controller.setWebviewListener(
      WebviewEventsListener(
        onTitleChanged: (title) {
          if (!mounted || title.isEmpty || title == 'about:blank') return;
          setState(() => tab.title = title);
          if (_activeTab?.id == tab.id && widget.isAppMode) {
            windowManager.setTitle(title);
          }
        },
        onUrlChanged: (url) {
          if (!mounted) return;
          if (url == 'about:blank' && !tab.isReady) return;
          setState(() => tab.url = url);
          if (_activeTab?.id == tab.id && !_urlFocusNode.hasFocus) {
            _urlController.text = url;
          }
        },
        onLoadStart: (controller, url) {
          if (!mounted) return;
          if (url == 'about:blank' && !tab.isReady) return;
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
          if (!mounted || url == 'about:blank') return;
          setState(() => tab.isLoading = false);
          if (tab.isReady && tab.controller.value) {
            _applyCosmeticAdBlock(tab, url);
            _checkPwaStatus(tab);
          }
          _addToHistory(tab.title, url);
        },
        onLoadError: (controller, errorCode, errorText, failedUrl) {
          // Ignore ERR_ABORTED (-3) from user Stop or fast redirects.
          if (!mounted || errorCode == -3 || failedUrl == 'about:blank') return;
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
          if (!mounted) return;
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
        onExternalProtocol: (url) => _showExternalProtocolPrompt(url),
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
    for (final picker in [
      ['fyrfiles', '--picker'],
      ['zenity', '--file-selection'],
    ]) {
      try {
        final result = await Process.run(picker.first, picker.sublist(1));
        if (result.exitCode == 0) {
          final lines = result.stdout
              .toString()
              .trim()
              .split('\n')
              .where((s) => s.isNotEmpty)
              .toList();
          if (lines.isNotEmpty) {
            files = lines;
            break;
          }
        }
      } catch (_) {}
    }
    await WebviewManager()
        .pluginChannel
        .invokeMethod('continueFileDialog', [callbackId, files]);
  }

  Future<void> _applyCosmeticAdBlock(BrowserTab tab, String url) async {
    if (!tab.isReady || !tab.controller.value) return;
    final script = _shouldBlockOnUrl(url)
        ? AdBlockEngine.cosmeticCssScript
        : AdBlockEngine.removeCosmeticCssScript;
    await tab.controller.executeJavaScript(script);
  }

  Future<void> _checkPwaStatus(BrowserTab tab) async {
    if (widget.isAppMode || !tab.isReady || !tab.controller.value) return;
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

  Future<void> _installPwa(BrowserTab tab) async {
    if (tab.url.isEmpty || isInternalUrl(tab.url)) return;
    try {
      final uri = Uri.parse(tab.url);
      final appId = uri.host.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final title = tab.title.replaceAll(RegExp(r'["\$`]'), '').trim();
      final home = Platform.environment['HOME'] ?? '/tmp';
      String iconPath = '';

      if (tab.faviconUrl != null) {
        try {
          final response = await http.get(Uri.parse(tab.faviconUrl!));
          if (response.statusCode == 200) {
            final iconsDir =
                Directory(p.join(home, '.local', 'share', 'icons', 'fyrpwa'));
            if (!iconsDir.existsSync()) iconsDir.createSync(recursive: true);
            final iconFile = File(p.join(iconsDir.path, '$appId.png'));
            await iconFile.writeAsBytes(response.bodyBytes);
            iconPath = iconFile.path;
          }
        } catch (_) {}
      }

      final appsDir = Directory(p.join(home, '.local', 'share', 'applications'));
      if (!appsDir.existsSync()) appsDir.createSync(recursive: true);
      final desktopFile = File(p.join(appsDir.path, 'fyrpwa_$appId.desktop'));
      await desktopFile.writeAsString('''
[Desktop Entry]
Version=1.0
Name=${title.isNotEmpty ? title : uri.host}
Exec=/usr/local/bin/fyrbrowser --app=${tab.url}
Icon=$iconPath
Terminal=false
Type=Application
Categories=Network;WebBrowser;
''');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Installed ${title.isNotEmpty ? title : uri.host} as PWA',
            ),
            backgroundColor: FyrTheme.accentColor,
          ),
        );
      }
    } catch (e) {
      logger.w('Failed to install PWA: $e');
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length <= 1) {
      windowManager.close();
      return;
    }

    final closing = _tabs[index];
    if (closing.url.isNotEmpty && !isInternalUrl(closing.url)) {
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
    final prev = _activeTab;
    if (prev != null && prev.isReady && prev.controller.value) {
      prev.controller.setClientFocus(false);
    }
    setState(() => _activeTabIndex = index);
    _syncUrlBarWithActiveTab();
  }

  void _syncUrlBarWithActiveTab() {
    final tab = _activeTab;
    if (tab == null) return;
    _urlController.text = tab.url;
  }

  Future<void> _navigateActiveTabTo(String rawInput) async {
    final tab = _activeTab;
    if (tab == null || !tab.isReady || !tab.controller.value) return;

    final resolved = resolveNavigationInput(rawInput, _settings.searchEngine);
    _urlFocusNode.unfocus();
    _removeAutocompleteOverlay();

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
    if (tab == null || !tab.isReady || !tab.controller.value) return;

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
    if (tab == null || !tab.isReady || !tab.controller.value) return;
    final next = (tab.zoomLevel + delta).clamp(-3.0, 5.0);
    setState(() => tab.zoomLevel = next);
    await tab.controller.setZoomLevel(next);
  }

  Future<void> _resetZoom() async {
    final tab = _activeTab;
    if (tab == null || !tab.isReady || !tab.controller.value) return;
    setState(() => tab.zoomLevel = 0.0);
    await tab.controller.setZoomLevel(0.0);
  }

  String _zoomLabel(double zoomLevel) {
    final pct = (100 + zoomLevel * 20).round();
    return '$pct%';
  }

  void _openFindBar() {
    final tab = _activeTab;
    if (tab == null || !tab.isReady) return;
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
    final tab = _activeTab;
    if (tab != null && tab.isReady && tab.controller.value) {
      tab.controller.stopFinding();
    }
  }

  void _runFind({bool forward = true, bool findNext = false}) {
    final tab = _activeTab;
    if (tab == null || !tab.isReady || !tab.controller.value) return;
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
        _urlController.text = tab.url;
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
          offset: const Offset(0, 40),
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

  void _showExternalProtocolPrompt(String url) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: FyrTheme.dividerColor),
        ),
        title: Text(
          'Open External Application?',
          style: TextStyle(color: FyrTheme.textColor),
        ),
        content: Text(
          'Open "$url" in its default handler?',
          style: TextStyle(color: FyrTheme.textColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWebContextMenu({
    required BrowserTab tab,
    required double x,
    required double y,
    required String linkUrl,
    required String selectionText,
  }) async {
    if (!mounted) return;
    final headerOffset = widget.isAppMode ? 34.0 : 100.0;
    final action = await showMenu<String>(
      context: context,
      color: FyrTheme.bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      position:
          RelativeRect.fromLTRB(x, y + headerOffset, x + 1, y + headerOffset + 1),
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

    if (!mounted || action == null || !tab.isReady) return;
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
          if (tab != null && tab.isReady) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: FyrTheme.dividerColor),
        ),
        title: Row(
          children: [
            Text('Downloads', style: TextStyle(color: FyrTheme.textColor)),
            const Spacer(),
            TextButton(
              onPressed: () {
                DownloadManager().clearHistory();
                Navigator.of(context).pop();
                setState(() {});
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 300,
          child: ListenableBuilder(
            listenable: DownloadManager(),
            builder: (context, _) {
              final tasks = DownloadManager().tasks;
              if (tasks.isEmpty) {
                return Center(
                  child: Text(
                    'No downloads',
                    style: TextStyle(
                      color: FyrTheme.textColor.withValues(alpha: 0.5),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return ListenableBuilder(
                    listenable: task,
                    builder: (context, _) => ListTile(
                      dense: true,
                      leading: Icon(
                        task.isComplete
                            ? Icons.insert_drive_file
                            : Icons.downloading,
                        color: task.isComplete
                            ? Colors.greenAccent
                            : FyrTheme.accentColor,
                      ),
                      title: Text(
                        task.suggestedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: FyrTheme.textColor, fontSize: 13),
                      ),
                      subtitle: Text(
                        task.isComplete
                            ? DateFormat('MMM d, HH:mm').format(task.startTime)
                            : '${task.progress}%',
                        style: TextStyle(
                          color: FyrTheme.textColor.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        if (task.savePath != null) {
                          Process.run('fyrfiles', [p.dirname(task.savePath!)]);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
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
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(widget.isAppMode ? 0 : 12),
        child: Container(
          color: FyrTheme.bgColor,
          child: Column(
            children: [
              if (widget.isAppMode)
                _buildAppModeHeader()
              else ...[
                _buildTabStrip(),
                _buildToolbar(),
              ],
              if (_showFindBar) _buildFindBar(),
              Expanded(child: _buildViewport()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTrafficLightsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
        const SizedBox(width: 8),
        _buildTrafficLight(
            Colors.orangeAccent, () => windowManager.minimize()),
        const SizedBox(width: 8),
        _buildTrafficLight(Colors.greenAccent, () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }),
      ],
    );
  }

  Widget _buildAppModeHeader() {
    return DragToMoveArea(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: FyrTheme.isDark ? Colors.black : Colors.white,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            _buildTrafficLightsRow(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _activeTab?.title ?? 'PWA',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabStrip() {
    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: FyrTheme.isDark
              ? Colors.black.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 16,
              top: 14,
              child: _buildTrafficLightsRow(),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 80, top: 6, right: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length + 1,
                itemBuilder: (context, index) {
                  if (index == _tabs.length) {
                    return IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () => _addNewTab(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34),
                      tooltip: 'New Tab (Ctrl+T)',
                    );
                  }
                  return _buildTabChip(index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(int index) {
    final tab = _tabs[index];
    final selected = index == _activeTabIndex;
    return GestureDetector(
      key: ValueKey(tab.id),
      onTap: () => _selectTab(index),
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? FyrTheme.bgColor : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          border: selected
              ? Border(
                  left: BorderSide(color: FyrTheme.dividerColor),
                  right: BorderSide(color: FyrTheme.dividerColor),
                  top: BorderSide(color: FyrTheme.dividerColor),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                tab.title.isNotEmpty ? tab.title : tab.url,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _closeTab(index),
              child: Icon(
                Icons.close,
                size: 14,
                color: FyrTheme.textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final tab = _activeTab;
    final ready = tab?.isReady == true;
    final canBack = ready && (tab?.canGoBack ?? false);
    final canForward = ready && (tab?.canGoForward ?? false);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          _navButton(
            icon: Icons.arrow_back_ios_new,
            size: 16,
            tooltip: 'Back',
            enabled: canBack,
            onPressed: () => tab?.controller.goBack(),
          ),
          _navButton(
            icon: Icons.arrow_forward_ios,
            size: 16,
            tooltip: 'Forward',
            enabled: canForward,
            onPressed: () => tab?.controller.goForward(),
          ),
          _navButton(
            icon: (tab?.isLoading ?? false) ? Icons.close : Icons.refresh,
            size: 19,
            tooltip: (tab?.isLoading ?? false) ? 'Stop' : 'Reload (Ctrl+R)',
            enabled: ready,
            onPressed: _reloadOrStop,
          ),
          _navButton(
            icon: Icons.home_outlined,
            size: 19,
            tooltip: 'Home',
            enabled: ready,
            onPressed: () => _navigateActiveTabTo(_settings.homePage),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildUrlBar(tab)),
          const SizedBox(width: 8),
          if (tab != null && tab.zoomLevel != 0.0)
            TextButton(
              onPressed: _resetZoom,
              child: Text(
                _zoomLabel(tab.zoomLevel),
                style: TextStyle(color: FyrTheme.accentColor, fontSize: 12),
              ),
            ),
          if (tab != null) _buildShieldMenu(tab),
          _navButton(
            icon: DownloadManager().tasks.any((t) => !t.isComplete)
                ? Icons.downloading
                : Icons.download_outlined,
            size: 18,
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
    required double size,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      iconSize: size,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        icon,
        color: enabled
            ? FyrTheme.textColor.withValues(alpha: 0.78)
            : FyrTheme.textColor.withValues(alpha: 0.25),
      ),
    );
  }

  Widget _buildUrlBar(BrowserTab? tab) {
    final url = tab?.url ?? kDefaultHomePage;
    final isSecure = url.startsWith('https://');
    final isError = tab?.loadError != null;
    final bookmarked = tab != null && _isBookmarked(url);

    return CompositedTransformTarget(
      link: _urlBarLink,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: FyrTheme.isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: _urlFocusNode.hasFocus
              ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.6))
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              isError
                  ? Icons.warning_amber_rounded
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
            if (tab != null) ...[
              if (tab.isPwa)
                IconButton(
                  icon: Icon(
                    Icons.install_desktop,
                    size: 17,
                    color: FyrTheme.accentColor,
                  ),
                  tooltip: 'Install PWA',
                  onPressed: () => _installPwa(tab),
                ),
              IconButton(
                onPressed: () => _toggleBookmark(tab),
                tooltip: bookmarked ? 'Remove Bookmark' : 'Bookmark Page',
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  bookmarked ? Icons.star : Icons.star_border,
                  color: bookmarked ? FyrTheme.accentColor : FyrTheme.textColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShieldMenu(BrowserTab tab) {
    final host = AdBlockEngine.extractHost(tab.url);
    final whitelisted = host.isNotEmpty && _settings.isHostWhitelisted(host);
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
                  ? FyrTheme.accentColor
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
        Icons.settings,
        size: 18,
        color: FyrTheme.textColor.withValues(alpha: 0.75),
      ),
      onSelected: (action) {
        final tab = _activeTab;
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
          case 'install_pwa':
            if (tab != null) _installPwa(tab);
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
            if (tab != null && tab.isReady) tab.controller.openDevTools();
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
        PopupMenuItem(value: 'install_pwa', child: Text('Install as PWA')),
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
          bottom: BorderSide(color: FyrTheme.dividerColor),
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
      children: _tabs.asMap().entries.map((entry) {
        final idx = entry.key;
        final tab = entry.value;
        return ExcludeFocus(
          key: ValueKey('exclude_${tab.id}'),
          excluding: idx != _activeTabIndex,
          child: Stack(
            children: [
              if (tab.isReady)
                WebView(
                  tab.controller,
                  key: ValueKey('webview_${tab.id}'),
                )
              else
                Center(
                  child: CircularProgressIndicator(color: FyrTheme.accentColor),
                ),
              if (tab.loadError != null)
                Positioned.fill(
                  child: FyrErrorPage(
                    error: tab.loadError!,
                    onRetry: _reloadOrStop,
                    onGoHome: () => _navigateActiveTabTo(_settings.homePage),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
