import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:webview_cef/webview_cef.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'fyr_theme.dart';
import 'adblock_engine.dart';
import 'download_manager.dart';

import 'package:intl/intl.dart';

class BrowserTab {
  late WebViewController controller;
  String title;
  String url;
  bool isLoading = false;
  bool isReady = false;
  bool showPwaInstall = false;
  String? pwaIconUrl;

  BrowserTab({this.title = 'New Tab', this.url = 'https://start.duckduckgo.com'});
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  final bool isAppMode;

  const BrowserScreen({super.key, this.initialUrl, this.isAppMode = false});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final WebviewManager _manager = WebviewManager();
  final List<BrowserTab> _tabs = [];
  int _currentTabIndex = 0;
  
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  
  bool _adBlockEnabled = false;
  List<Map<String, String>> _history = [];
  List<Map<String, String>> _bookmarks = [];
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _initManager().then((_) {
      WebviewManager().onPopupCreated = (controller) {
        if (!mounted) return;
        final newTab = BrowserTab(url: 'about:blank');
        newTab.controller = controller;
        newTab.isReady = true;
        _setupTabListeners(newTab);
        setState(() {
          _tabs.add(newTab);
          _currentTabIndex = _tabs.length - 1;
          _urlController.text = newTab.url;
        });
        _urlFocusNode.requestFocus();
        _urlController.selection = TextSelection(baseOffset: 0, extentOffset: _urlController.text.length);
      };
      _addNewTab(url: widget.initialUrl);
    });
    
    _urlFocusNode.addListener(() {
      if (_urlFocusNode.hasFocus) {
        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _urlController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initManager() async {
    const String userAgent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    await _manager.initialize(userAgent: userAgent);
  }

  Future<void> _loadData() async {
    DownloadManager().init();
    try {
      final dir = await getApplicationSupportDirectory();
      final historyFile = File(p.join(dir.path, 'history.json'));
      if (historyFile.existsSync()) {
        final content = await historyFile.readAsString();
        _history = List<Map<String, String>>.from(json.decode(content).map((i) => Map<String, String>.from(i)));
      }
      final bookmarksFile = File(p.join(dir.path, 'bookmarks.json'));
      if (bookmarksFile.existsSync()) {
        final content = await bookmarksFile.readAsString();
        _bookmarks = List<Map<String, String>>.from(json.decode(content).map((i) => Map<String, String>.from(i)));
      }
    } catch (e) {
      debugPrint('Failed to load data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final historyFile = File(p.join(dir.path, 'history.json'));
      await historyFile.writeAsString(json.encode(_history));
      final bookmarksFile = File(p.join(dir.path, 'bookmarks.json'));
      await bookmarksFile.writeAsString(json.encode(_bookmarks));
    } catch (e) {
      debugPrint('Failed to save data: $e');
    }
  }

  void _addNewTab({String? url}) {
    final newTab = BrowserTab(url: url ?? 'https://start.duckduckgo.com');
    newTab.controller = _manager.createWebView();
    
    setState(() {
      _tabs.add(newTab);
      _currentTabIndex = _tabs.length - 1;
      _urlController.text = newTab.url;
    });
    _urlFocusNode.requestFocus();
    _urlController.selection = TextSelection(baseOffset: 0, extentOffset: _urlController.text.length);

    _setupTabListeners(newTab);
    newTab.controller.initialize(newTab.url).then((_) {
      if (mounted) setState(() => newTab.isReady = true);
    });
  }

  void _setupTabListeners(BrowserTab tab) {
    tab.controller.setWebviewListener(WebviewEventsListener(
      onUrlChanged: (String url) {
        if (!mounted) return;
        setState(() {
          // Strictly ignore about:blank during initialization to preserve the target URL
          if (url != 'about:blank' || tab.isReady) {
            tab.url = url;
          }
          if (_tabs.indexOf(tab) == _currentTabIndex) _urlController.text = tab.url;
          tab.showPwaInstall = false;
          tab.pwaIconUrl = null;
          _startPwaCheck(tab);
          if (_adBlockEnabled) tab.controller.executeJavaScript(AdBlockEngine.injectionScript);
          _addToHistory(tab.title, url);
        });
      },
      onTitleChanged: (String title) {
        if (!mounted) return;
        setState(() {
          tab.title = title;
          if (_tabs.indexOf(tab) == _currentTabIndex && widget.isAppMode) {
            windowManager.setTitle(title);
          }
        });
      },
      onLoadStart: (WebViewController controller, String url) {
        if (!mounted) return;
        setState(() => tab.isLoading = true);
      },
      onLoadEnd: (WebViewController controller, String url) {
        if (!mounted) return;
        setState(() {
          tab.isLoading = false;
          _startPwaCheck(tab);
        });
      },
      onDownloadStart: (String suggestedName, String url) {
        if (!mounted) return;
        DownloadManager().startDownload(suggestedName, url);
        _showDownloadDropdown();
      },
      onDownloadUpdated: (String url, int received, int total, int percent, bool complete) {
        if (!mounted) return;
        DownloadManager().updateDownload(url, received, total, percent, complete);
      },
      onContextMenu: (int x, int y, int typeFlags, String linkUrl, String sourceUrl, String selectionText, bool isEditable) {
        if (!mounted) return;
        _showContextMenu(x, y, typeFlags, linkUrl, sourceUrl, selectionText, isEditable);
      },
      onConsoleMessage: (int level, String message, String source, int line) {
        debugPrint('WebView Console [$level] ($source:$line): $message');
      },
      onFileDialog: (int browserId, int callbackId) async {
        try {
          final result = await Process.run('fyrfiles', ['--picker']);
          if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            final paths = output.split('\n').where((p) => p.isNotEmpty).toList();
            tab.controller.continueFileDialog(callbackId, paths);
          } else {
            tab.controller.continueFileDialog(callbackId, []);
          }
          } else {
            tab.controller.continueFileDialog(callbackId, []);
          }
        } catch (e) {
          debugPrint('Failed to run fyrfiles picker: $e');
          tab.controller.continueFileDialog(callbackId, []);
        }
      },
      onExternalProtocol: (String url) {
        if (!mounted) return;
        _showExternalProtocolPrompt(url);
      },
      onBeforePopup: (String targetUrl) {
        // We now allow CEF to handle the popup natively offscreen.
        // We handle the UI via WebviewManager().onPopupCreated
      },
      onClose: () {
        if (!mounted) return;
        setState(() {
          int index = _tabs.indexOf(tab);
          if (index != -1) {
            _tabs.removeAt(index);
            if (_tabs.isEmpty) {
              _addNewTab();
            } else {
              _currentTabIndex = (_currentTabIndex >= _tabs.length) ? _tabs.length - 1 : _currentTabIndex;
              _urlController.text = _tabs[_currentTabIndex].url;
            }
          }
        });
      },
    ));
    void setupChannels() {
      if (tab.controller.value) {
        tab.controller.setJavaScriptChannels({
          JavascriptChannel(
            name: 'FyrBrowser',
            onMessageReceived: (JavascriptMessage message) {
              if (!mounted) return;
              try {
                final data = json.decode(message.message);
                if (data['type'] == 'pwa_detected') {
                  setState(() {
                    tab.showPwaInstall = true;
                    tab.pwaIconUrl = data['icon'];
                  });
                }
              } catch (_) {}
            },
          ),
        });
        if (_adBlockEnabled) tab.controller.executeJavaScript(AdBlockEngine.injectionScript);


      } else {
        tab.controller.addListener(() {
          if (tab.controller.value) setupChannels();
        });
      }
    }

    setupChannels();
  }

  void _startPwaCheck(BrowserTab tab) {
    if (widget.isAppMode) return;
    // Run once after load to avoid resource exhaustion
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && tab.isReady && !tab.showPwaInstall) {
        _checkPwaStatus(tab);
      }
    });
  }

  void _checkPwaStatus(BrowserTab tab) {
    if (!tab.controller.value) return;
    tab.controller.executeJavaScript('''
      (function() {
        if (window.top !== window.self) return; // Only run in main frame
        
        // Force crossOriginIsolated to true for BandLab audio engine
        try {
          if (!window.crossOriginIsolated) {
            Object.defineProperty(window, 'crossOriginIsolated', {
              value: true,
              configurable: true
            });
          }
        } catch (e) {}

        const check = (fn) => { try { return fn(); } catch(e) { return false; } };
        const features = {
          crossOriginIsolated: window.crossOriginIsolated,
          SharedArrayBuffer: check(() => typeof SharedArrayBuffer !== 'undefined'),
          WebAssembly: check(() => typeof WebAssembly !== 'undefined'),
          AudioContext: check(() => typeof AudioContext !== 'undefined'),
          AudioWorklet: check(() => {
             const ctx = new (window.AudioContext || window.webkitAudioContext)();
             const hasWorklet = !!ctx.audioWorklet;
             ctx.close();
             return hasWorklet;
          }),
          OffscreenCanvas: check(() => typeof OffscreenCanvas !== 'undefined'),
          WebGL: check(() => {
            var canvas = document.createElement('canvas');
            return !!(window.WebGLRenderingContext && (canvas.getContext('webgl') || canvas.getContext('experimental-webgl')));
          }),
        };
        /* 
        console.log('FyrBrowser [Features] Detected: ' + Object.entries(features).filter(([k,v]) => v).map(([k,v]) => k).join(', '));
        console.log('FyrBrowser [Features] Missing: ' + Object.entries(features).filter(([k,v]) => !v).map(([k,v]) => k).join(', '));
        */
        
        // Permission Query Polyfill (Bypass "Blocked" state)
        if (navigator.permissions && navigator.permissions.query) {
          const originalQuery = navigator.permissions.query;
          navigator.permissions.query = function(params) {
            if (params && (params.name === 'midi' || params.name === 'camera' || params.name === 'microphone')) {
              return Promise.resolve({
                state: 'granted',
                onchange: null,
                name: params.name
              });
            }
            return originalQuery.call(navigator.permissions, params);
          };
        }

        const getIcon = () => {
          const appleTouch = document.querySelector('link[rel="apple-touch-icon"]');
          if (appleTouch) return appleTouch.href;
          const manifest = document.querySelector('link[rel="manifest"]');
          const icons = document.querySelectorAll('link[rel="icon"]');
          if (icons.length > 0) return icons[0].href;
          return null;
        };
        const indicators = [
          () => !!document.querySelector('link[rel="manifest"]'),
          () => !!document.querySelector('link[rel="apple-touch-icon"]'),
          () => 'serviceWorker' in navigator
        ];
        if (indicators.some(check => check())) {
          const data = { type: 'pwa_detected', icon: getIcon() };
          if (window.FyrBrowser) window.FyrBrowser.postMessage(JSON.stringify(data));
        }
      })();
    ''');
  }

  void _addToHistory(String title, String url) {
    if (url.startsWith('data:') || url.startsWith('blob:') || widget.isAppMode) return;
    _history.insert(0, {'title': title, 'url': url, 'time': DateTime.now().toIso8601String()});
    if (_history.length > 500) _history.removeLast();
    _saveData();
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      windowManager.close();
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_currentTabIndex >= _tabs.length) _currentTabIndex = _tabs.length - 1;
      _urlController.text = _tabs[_currentTabIndex].url;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isControl = HardwareKeyboard.instance.isControlPressed;
      if (isControl && event.logicalKey == LogicalKeyboardKey.keyT) {
        _addNewTab();
      } else if (isControl && event.logicalKey == LogicalKeyboardKey.keyW) {
        _closeTab(_currentTabIndex);
      } else if (isControl && event.logicalKey == LogicalKeyboardKey.tab) {
        setState(() {
          _currentTabIndex = (_currentTabIndex + 1) % _tabs.length;
          _urlController.text = _tabs[_currentTabIndex].url;
        });
      } else if (isControl && event.logicalKey == LogicalKeyboardKey.keyR) {
        _tabs[_currentTabIndex].controller.reload();
      } else if (event.logicalKey == LogicalKeyboardKey.f5) {
        _tabs[_currentTabIndex].controller.reload();
      } else if (isControl && event.logicalKey == LogicalKeyboardKey.keyL) {
        FocusScope.of(context).requestFocus(_urlFocusNode);
      }
    }
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black26, width: 0.5)),
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    final tab = _tabs[index];
    final bool isSelected = index == _currentTabIndex;
    return GestureDetector(
      onTap: () => setState(() {
        _currentTabIndex = index;
        _urlController.text = tab.url;
      }),
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? FyrTheme.bgColor : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          border: isSelected ? Border(
            left: BorderSide(color: FyrTheme.dividerColor),
            right: BorderSide(color: FyrTheme.dividerColor),
            top: BorderSide(color: FyrTheme.dividerColor),
          ) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(tab.title, style: TextStyle(color: FyrTheme.textColor, fontSize: 12), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => _closeTab(index), child: Icon(Icons.close, size: 14, color: FyrTheme.textColor.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }

  void _showSettingsMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return Center(
          child: Container(
            width: 500, height: 600,
            margin: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: FyrTheme.dividerColor),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
            ),
            child: Material(
              color: Colors.transparent,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.settings, color: FyrTheme.accentColor),
                          const SizedBox(width: 12),
                          Text('Settings & Tools', style: TextStyle(color: FyrTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    TabBar(
                      labelColor: FyrTheme.accentColor,
                      unselectedLabelColor: FyrTheme.textColor.withOpacity(0.5),
                      indicatorColor: FyrTheme.accentColor,
                      tabs: const [Tab(text: 'History'), Tab(text: 'Bookmarks')],
                    ),
                    Expanded(child: TabBarView(children: [_buildHistoryList(), _buildBookmarkList()])),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        return ListTile(
          leading: const Icon(Icons.history, size: 18),
          title: Text(item['title'] ?? 'No Title', style: TextStyle(color: FyrTheme.textColor, fontSize: 14)),
          subtitle: Text(item['url'] ?? '', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () { Navigator.pop(context); _tabs[_currentTabIndex].controller.loadUrl(item['url']!); },
        );
      },
    );
  }

  Widget _buildBookmarkList() {
    return ListView.builder(
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final item = _bookmarks[index];
        return ListTile(
          leading: const Icon(Icons.star, size: 18, color: Colors.orangeAccent),
          title: Text(item['title'] ?? 'No Title', style: TextStyle(color: FyrTheme.textColor, fontSize: 14)),
          subtitle: Text(item['url'] ?? '', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () { Navigator.pop(context); _tabs[_currentTabIndex].controller.loadUrl(item['url']!); },
        );
      },
    );
  }

  final LayerLink _downloadLink = LayerLink();
  OverlayEntry? _downloadOverlay;

  void _showDownloadDropdown() {
    _downloadOverlay?.remove();
    _downloadOverlay = _createDownloadOverlay();
    Overlay.of(context).insert(_downloadOverlay!);
  }

  OverlayEntry _createDownloadOverlay() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () { _downloadOverlay?.remove(); _downloadOverlay = null; },
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            width: 350,
            child: CompositedTransformFollower(
              link: _downloadLink,
              showWhenUnlinked: false,
              offset: const Offset(-310, 45),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: 400,
                  decoration: BoxDecoration(
                    color: FyrTheme.bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FyrTheme.dividerColor),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Text('Downloads', style: TextStyle(color: FyrTheme.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            TextButton(
                              onPressed: () { DownloadManager().clearHistory(); setState(() {}); },
                              child: Text('Clear', style: TextStyle(color: FyrTheme.accentColor, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: FyrTheme.dividerColor),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: DownloadManager(),
                          builder: (context, _) {
                            final tasks = DownloadManager().tasks;
                            if (tasks.isEmpty) {
                              return Center(child: Text('No downloads', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5))));
                            }
                            return ListView.builder(
                              itemCount: tasks.length,
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                return ListenableBuilder(
                                  listenable: task,
                                  builder: (context, _) {
                                    return ListTile(
                                      leading: Icon(
                                        task.isComplete ? Icons.insert_drive_file : Icons.downloading,
                                        color: task.isComplete ? Colors.greenAccent : FyrTheme.accentColor,
                                      ),
                                      title: Text(task.suggestedName, style: TextStyle(color: FyrTheme.textColor, fontSize: 13), overflow: TextOverflow.ellipsis),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (!task.isComplete) ...[
                                            const SizedBox(height: 4),
                                            LinearProgressIndicator(value: task.progress / 100, backgroundColor: Colors.grey.withOpacity(0.2), color: FyrTheme.accentColor, minHeight: 2),
                                            const SizedBox(height: 4),
                                            Text('${task.progress}% - ${task.suggestedName}', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5), fontSize: 10)),
                                          ] else ...[
                                            Text(DateFormat('MMM d, HH:mm').format(task.startTime), style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5), fontSize: 10)),
                                          ]
                                        ],
                                      ),
                                      onTap: () async {
                                        if (task.savePath != null) {
                                          final file = File(task.savePath!);
                                          if (await file.exists()) {
                                            Process.run('fyrfiles', [p.dirname(task.savePath!)]);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found')));
                                          }
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleBookmark() {
    final url = _urlController.text;
    final existing = _bookmarks.indexWhere((b) => b['url'] == url);
    setState(() {
      if (existing != -1) _bookmarks.removeAt(existing);
      else _bookmarks.add({'title': _tabs[_currentTabIndex].title, 'url': url});
    });
    _saveData();
  }

  void _showContextMenu(int x, int y, int typeFlags, String linkUrl, String sourceUrl, String selectionText, bool isEditable) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromLTRB(
      x.toDouble(),
      y.toDouble() + (widget.isAppMode ? 34 : 100), // Adjust for header height
      overlay.size.width - x.toDouble(),
      overlay.size.height - y.toDouble(),
    );

    final tab = _tabs[_currentTabIndex];

    showMenu(
      context: context,
      position: position,
      color: FyrTheme.bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: FyrTheme.dividerColor)),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'back',
          child: _buildMenuItem(Icons.arrow_back, 'Back'),
          enabled: true,
        ),
        PopupMenuItem(
          value: 'forward',
          child: _buildMenuItem(Icons.arrow_forward, 'Forward'),
          enabled: true,
        ),
        PopupMenuItem(
          value: 'reload',
          child: _buildMenuItem(Icons.refresh, 'Reload'),
        ),
        const PopupMenuDivider(),
        if (selectionText.isNotEmpty)
          PopupMenuItem(
            value: 'copy',
            child: _buildMenuItem(Icons.copy, 'Copy'),
          ),
        if (isEditable)
          PopupMenuItem(
            value: 'paste',
            child: _buildMenuItem(Icons.paste, 'Paste'),
          ),
        if (linkUrl.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'open_link',
            child: _buildMenuItem(Icons.open_in_new, 'Open Link in New Tab'),
          ),
          PopupMenuItem(
            value: 'copy_link',
            child: _buildMenuItem(Icons.link, 'Copy Link Address'),
          ),
        ],
        if (sourceUrl.isNotEmpty && (typeFlags & 8 != 0)) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'download_image',
            child: _buildMenuItem(Icons.image_outlined, 'Download Image'),
          ),
          PopupMenuItem(
            value: 'copy_image_url',
            child: _buildMenuItem(Icons.link, 'Copy Image Address'),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'inspect',
          child: _buildMenuItem(Icons.code, 'Inspect Element'),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'back': tab.controller.goBack(); break;
        case 'forward': tab.controller.goForward(); break;
        case 'reload': tab.controller.reload(); break;
        case 'copy': Clipboard.setData(ClipboardData(text: selectionText)); break;
        case 'paste': 
          Clipboard.getData(Clipboard.kTextPlain).then((data) {
            if (data?.text != null) {
              // This is a bit complex in CEF, usually we'd send a paste command
              tab.controller.executeJavaScript("document.execCommand('paste')");
            }
          });
          break;
        case 'open_link': _addNewTab(url: linkUrl); break;
        case 'copy_link': Clipboard.setData(ClipboardData(text: linkUrl)); break;
        case 'download_image':
          tab.controller.executeJavaScript("""
            var link = document.createElement('a');
            link.href = '$sourceUrl';
            link.download = '';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
          """);
          break;
        case 'copy_image_url': Clipboard.setData(ClipboardData(text: sourceUrl)); break;
        case 'inspect': tab.controller.openDevTools(); break;
      }
    });
  }

  void _showExternalProtocolPrompt(String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: FyrTheme.dividerColor)),
        title: Text('Open External Application?', style: TextStyle(color: FyrTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A website wants to open an external application for:', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.7), fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Text(url, style: TextStyle(color: FyrTheme.accentColor, fontSize: 12, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: FyrTheme.textColor.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Process.run('xdg-open', [url]);
            },
            style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: FyrTheme.textColor.withOpacity(0.7)),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: FyrTheme.textColor, fontSize: 13)),
      ],
    );
  }

  Future<void> _installPwa() async {
    final url = _urlController.text;
    final tab = _tabs[_currentTabIndex];
    final title = tab.title;
    final iconUrl = tab.pwaIconUrl;
    
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final configDir = await getApplicationSupportDirectory();
      final iconsDir = Directory(p.join(configDir.path, 'icons'));
      if (!iconsDir.existsSync()) iconsDir.createSync(recursive: true);
      
      final appId = title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      String iconPath = 'internet-web-browser';
      
      if (iconUrl != null) {
        try {
          final response = await http.get(Uri.parse(iconUrl));
          if (response.statusCode == 200) {
            final ext = p.extension(Uri.parse(iconUrl).path).isEmpty ? '.png' : p.extension(Uri.parse(iconUrl).path);
            final iconFile = File(p.join(iconsDir.path, '$appId$ext'));
            await iconFile.writeAsBytes(response.bodyBytes);
            iconPath = iconFile.path;
          }
        } catch (e) {
          debugPrint('Failed to download icon: $e');
        }
      }

      final appsDir = Directory(p.join(home, '.local', 'share', 'applications'));
      if (!appsDir.existsSync()) appsDir.createSync(recursive: true);
      final desktopFile = File(p.join(appsDir.path, 'fyrpwa_$appId.desktop'));
      final content = '''
[Desktop Entry]
Version=1.0
Name=$title
Exec=/usr/local/bin/fyrbrowser --app=$url
Icon=$iconPath
Terminal=false
Type=Application
Categories=Network;WebBrowser;
''';
      await desktopFile.writeAsString(content);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Installed $title as PWA'), backgroundColor: FyrTheme.accentColor));
    } catch (e) {
      debugPrint('Failed to install PWA: $e');
    }
  }

  Widget _buildBrowser() {
    if (_tabs.isEmpty) return Container();
    return IndexedStack(
      index: _currentTabIndex,
      children: _tabs.asMap().entries.map((entry) {
        int idx = entry.key;
        var tab = entry.value;
        return ExcludeFocus(
          excluding: idx != _currentTabIndex,
          child: tab.isReady 
            ? SmoothScrollWrapper(
                controller: tab.controller,
                child: WebView(tab.controller),
              ) 
            : const Center(child: CircularProgressIndicator()),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ClipRRect(
          borderRadius: BorderRadius.circular(widget.isAppMode ? 0 : 12),
          child: Container(
            color: FyrTheme.bgColor,
            child: Column(
              children: [
                if (widget.isAppMode)
                  _buildAppModeHeader()
                else
                  _buildBrowserHeader(),
                Expanded(child: _buildBrowser()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppModeHeader() {
    final currentTab = _tabs.isNotEmpty ? _tabs[_currentTabIndex] : null;
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
            _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
            const SizedBox(width: 8),
            _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
            const SizedBox(width: 8),
            _buildTrafficLight(Colors.greenAccent, () async {
              if (await windowManager.isMaximized()) windowManager.unmaximize();
              else windowManager.maximize();
            }),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                currentTab?.title ?? 'PWA',
                style: TextStyle(color: FyrTheme.textColor, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowserHeader() {
    return Column(
      children: [
        DragToMoveArea(
          child: Container(
            height: 40,
            decoration: BoxDecoration(color: FyrTheme.isDark ? Colors.black.withOpacity(0.5) : Colors.grey.withOpacity(0.2)),
            child: Stack(
              children: [
                Positioned(
                  left: 16, top: 14,
                  child: Row(
                    children: [
                      _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                      const SizedBox(width: 8),
                      _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                      const SizedBox(width: 8),
                      _buildTrafficLight(Colors.greenAccent, () async {
                        if (await windowManager.isMaximized()) windowManager.unmaximize();
                        else windowManager.maximize();
                      }),
                    ],
                  ),
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
                          tooltip: 'New Tab',
                        );
                      }
                      return _buildTab(index);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildUrlBar(),
      ],
    );
  }

  Widget _buildUrlBar() {
    final textColor = FyrTheme.textColor;
    final currentTab = _tabs.isNotEmpty ? _tabs[_currentTabIndex] : null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) => windowManager.startDragging(),
      onTap: () => FocusScope.of(context).requestFocus(_urlFocusNode),
      onDoubleTap: () {
        FocusScope.of(context).requestFocus(_urlFocusNode);
        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: FyrTheme.bgColor, border: Border(bottom: BorderSide(color: FyrTheme.dividerColor))),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              onPressed: currentTab?.isReady == true ? () => currentTab!.controller.goBack() : null,
              color: textColor.withOpacity(0.7),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: currentTab?.isReady == true ? () => currentTab!.controller.goForward() : null,
              color: textColor.withOpacity(0.7),
            ),
            IconButton(
              icon: Icon(currentTab?.isLoading == true ? Icons.close : Icons.refresh, size: 20),
              onPressed: currentTab?.isReady == true ? () => currentTab!.isLoading ? currentTab.controller.loadUrl(currentTab.url) : currentTab.controller.reload() : null,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: FyrTheme.isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search or enter URL',
                      hintStyle: TextStyle(color: textColor.withOpacity(0.4)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      prefixIcon: IconButton(
                        icon: Icon(_bookmarks.any((b) => b['url'] == _urlController.text) ? Icons.star : Icons.star_border, size: 16),
                        color: FyrTheme.accentColor,
                        onPressed: _toggleBookmark,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (currentTab?.showPwaInstall == true)
                            IconButton(icon: Icon(Icons.install_desktop, size: 18, color: FyrTheme.accentColor), onPressed: _installPwa, tooltip: 'Install PWA (Detected)'),
                          IconButton(icon: const Icon(Icons.install_desktop_outlined, size: 18), onPressed: _installPwa, tooltip: 'Force Install as PWA'),
                        ],
                      ),
                    ),
                    onSubmitted: (value) {
                      if (currentTab?.isReady != true) return;
                      String url = value.trim();
                      if (!url.startsWith('http')) {
                        url = (url.contains('.') && !url.contains(' ')) ? 'https://$url' : 'https://start.duckduckgo.com/?q=$url';
                      }
                      currentTab!.controller.loadUrl(url);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: Icon(_adBlockEnabled ? Icons.security : Icons.security_outlined, size: 18),
              onPressed: () {
                setState(() => _adBlockEnabled = !_adBlockEnabled);
                for (var tab in _tabs) if (tab.isReady) tab.controller.reload();
              },
              color: _adBlockEnabled ? FyrTheme.accentColor : textColor.withOpacity(0.5),
            ),
            CompositedTransformTarget(
              link: _downloadLink,
              child: IconButton(
                icon: const Icon(Icons.download_outlined, size: 18),
                onPressed: _showDownloadDropdown,
                color: DownloadManager().tasks.any((t) => !t.isComplete) ? FyrTheme.accentColor : textColor.withOpacity(0.7),
                tooltip: 'Downloads',
              ),
            ),
            IconButton(icon: const Icon(Icons.settings, size: 18), onPressed: _showSettingsMenu, color: textColor.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}

class SmoothScrollWrapper extends StatefulWidget {
  final WebViewController controller;
  final Widget child;

  const SmoothScrollWrapper({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<SmoothScrollWrapper> createState() => _SmoothScrollWrapperState();
}

class _SmoothScrollWrapperState extends State<SmoothScrollWrapper> {
  double _scrollTargetY = 0;
  bool _isScrolling = false;

  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is PointerScrollEvent) {
      // Intercept the scroll signal
      GestureBinding.instance.pointerSignalResolver.register(signal, (resolvedSignal) {
        _handleScroll(signal);
      });
    }
  }

  void _handleScroll(PointerScrollEvent signal) {
    // Increase target
    _scrollTargetY += signal.scrollDelta.dy;
    
    if (!_isScrolling) {
      _isScrolling = true;
      _animateScroll(signal.localPosition);
    }
  }

  void _animateScroll(Offset position) {
    if (!mounted || _scrollTargetY.abs() < 0.5) {
      _isScrolling = false;
      _scrollTargetY = 0;
      return;
    }

    // Determine step (speed and smoothness)
    // Using a slightly more aggressive smoothing factor to reduce event count
    double step = _scrollTargetY * 0.2; 
    if (step.abs() < 1) step = _scrollTargetY > 0 ? 1 : -1;
    if (step.abs() > _scrollTargetY.abs()) step = _scrollTargetY;

    // Send to CEF
    widget.controller.setScrollDelta(position, 0, step.round());
    
    _scrollTargetY -= step;

    // Use 16ms (60Hz) to match standard display cycles and avoid overwhelming Blink
    Future.delayed(const Duration(milliseconds: 16), () {
      _animateScroll(position);
    });
  }


  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
