import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_cef/src/webview_inject_user_script.dart';

import 'webview.dart';

class WebviewManager extends ValueNotifier<bool> {
  static final WebviewManager _instance = WebviewManager._internal();

  factory WebviewManager() => _instance;

  late Completer<void> _creatingCompleter;

  final MethodChannel pluginChannel = const MethodChannel("webview_cef");

  final Map<int, WebViewController> _webViews = <int, WebViewController>{};

  final Map<int, WebViewController> _tempWebViews = <int, WebViewController>{};
  InjectUserScripts? _injectUserScripts = InjectUserScripts();

  void Function(WebViewController)? onPopupCreated;

  int nextIndex = 1;

  get ready => _creatingCompleter.future;

  WebViewController createWebView({
    Widget? loading,
    InjectUserScripts? injectUserScripts,
  }) {
    int browserIndex = nextIndex++;
    final controller =
        WebViewController(pluginChannel, browserIndex, loading: loading);
    _tempWebViews[browserIndex] = controller;
    _injectUserScripts = injectUserScripts;

    return controller;
  }

  void removeWebView(int browserId) {
    if (browserId > 0) {
      _webViews.remove(browserId);
    }
  }

  WebviewManager._internal() : super(false);

  Future<void> initialize({String? userAgent}) async {
    _creatingCompleter = Completer<void>();
    try {
      if (userAgent != null && userAgent.isNotEmpty) {
        await pluginChannel.invokeMethod('init', userAgent);
      } else {
        await pluginChannel.invokeMethod('init');
      }
      pluginChannel.setMethodCallHandler(methodCallhandler);
      // Wait for the platform to complete initialization.
      await Future.delayed(const Duration(milliseconds: 300));
      _creatingCompleter.complete();
      value = true;
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    pluginChannel.setMethodCallHandler(null);
    _webViews.clear();
  }

  void onBrowserCreated(int browserIndex, int browserId) {
    _webViews[browserId] = _tempWebViews[browserIndex]!;
    _tempWebViews.remove(browserIndex);
  }

  Future<void> methodCallhandler(MethodCall call) async {
    switch (call.method) {
      case "urlChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onUrlChanged
            ?.call(call.arguments["url"] as String);
        return;
      case "titleChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onTitleChanged
            ?.call(call.arguments["title"] as String);
        return;
      case "onConsoleMessage":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]?.listener?.onConsoleMessage?.call(
            call.arguments["level"] as int,
            call.arguments["message"] as String,
            call.arguments["source"] as String,
            call.arguments["line"] as int);
        return;
      case 'javascriptChannelMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onJavascriptChannelMessage?.call(
            call.arguments['channel'] as String,
            call.arguments['message'] as String,
            call.arguments['callbackId'] as String,
            call.arguments['frameId'] as String);
        return;
      case 'onTooltip':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onToolTip?.call(call.arguments['text'] as String);
        return;
      case 'onCursorChanged':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]
            ?.onCursorChanged
            ?.call(call.arguments['type'] as int);
        return;
      case 'onFocusedNodeChangeMessage':
        int browserId = call.arguments['browserId'] as int;
        bool editable = call.arguments['editable'] as bool;
        _webViews[browserId]?.onFocusedNodeChangeMessage(editable);
        return;
      case 'onImeCompositionRangeChangedMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]
            ?.onImeCompositionRangeChangedMessage
            ?.call(call.arguments['x'] as int, call.arguments['y'] as int);
        return;
      case 'onLoadStart':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(browserId, _injectUserScripts?.retrieveLoadStartInjectScripts() ?? []);

        WebViewController controller =
        _webViews[browserId] as WebViewController;
        _webViews[browserId]?.listener?.onLoadStart?.call(controller, urlId);
        return;
      case 'onLoadEnd':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(browserId, _injectUserScripts?.retrieveLoadEndInjectScripts() ?? []);

        WebViewController controller =
        _webViews[browserId] as WebViewController;
        _webViews[browserId]?.listener?.onLoadEnd?.call(controller, urlId);
        return;
      case 'onDownloadStart':
        int browserId = call.arguments["browserId"] as int;
        String suggestedName = call.arguments["suggestedName"] as String;
        String url = call.arguments["url"] as String;
        _webViews[browserId]?.listener?.onDownloadStart?.call(suggestedName, url);
        return;
      case 'onDownloadUpdated':
        int browserId = call.arguments["browserId"] as int;
        String url = call.arguments["url"] as String;
        int receivedBytes = call.arguments["receivedBytes"] as int;
        int totalBytes = call.arguments["totalBytes"] as int;
        int percent = call.arguments["percent"] as int;
        bool isComplete = call.arguments["isComplete"] as bool;
        _webViews[browserId]?.listener?.onDownloadUpdated?.call(url, receivedBytes, totalBytes, percent, isComplete);
        return;
      case 'onContextMenu':
        int browserId = call.arguments["browserId"] as int;
        int x = call.arguments["x"] as int;
        int y = call.arguments["y"] as int;
        int typeFlags = call.arguments["typeFlags"] as int;
        String linkUrl = call.arguments["linkUrl"] as String;
        String sourceUrl = call.arguments["sourceUrl"] as String;
        String selectionText = call.arguments["selectionText"] as String;
        bool isEditable = call.arguments["isEditable"] as bool;
        _webViews[browserId]?.listener?.onContextMenu?.call(x, y, typeFlags, linkUrl, sourceUrl, selectionText, isEditable);
        return;
      case 'onFileDialog':
        int browserId = call.arguments["browserId"] as int;
        int callbackId = call.arguments["callbackId"] as int;
        _webViews[browserId]?.listener?.onFileDialog?.call(browserId, callbackId);
        return;
      case 'onExternalProtocol':
        int browserId = call.arguments["browserId"] as int;
        String url = call.arguments["url"] as String;
        _webViews[browserId]?.listener?.onExternalProtocol?.call(url);
        return;
      case 'onBeforePopup':
        int browserId = call.arguments["browserId"] as int;
        String targetUrl = call.arguments["targetUrl"] as String;
        _webViews[browserId]?.listener?.onBeforePopup?.call(targetUrl);
        return;
      case 'onPopupCreated':
        int browserId = call.arguments["browserId"] as int;
        int textureId = call.arguments["textureId"] as int;
        _onPopupCreated(browserId, textureId);
        return;
      case 'onBrowserClose':
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]?.listener?.onClose?.call();
        return;
      default:
    }
  }

  Future<void> _injectUserScriptIfNeeds(int browserId, List<UserScript> scripts) async {
    if (scripts.isEmpty) return;

    await _webViews[browserId]?.ready;

    scripts.forEach((script) async {
      await _webViews[browserId]?.executeJavaScript(script.script);
    },);
  }

  void _onPopupCreated(int browserId, int textureId) {
    int browserIndex = nextIndex++;
    final controller = WebViewController(pluginChannel, browserIndex);
    controller.setPopupInfo(browserId, textureId);
    _webViews[browserId] = controller;
    onPopupCreated?.call(controller);
  }

  Future<void> setCookie(String domain, String key, String val) async {
    assert(value);
    return pluginChannel.invokeMethod('setCookie', [domain, key, val]);
  }

  Future<void> deleteCookie(String domain, String key) async {
    assert(value);
    return pluginChannel.invokeMethod('deleteCookie', [domain, key]);
  }

  Future<dynamic> visitAllCookies() async {
    assert(value);
    return pluginChannel.invokeMethod('visitAllCookies');
  }

  Future<dynamic> visitUrlCookies(String domain, bool isHttpOnly) async {
    assert(value);
    return pluginChannel.invokeMethod('visitUrlCookies', [domain, isHttpOnly]);
  }

  Future<void> quit() async {
    //only call this method when you want to quit the app
    assert(value);
    return pluginChannel.invokeMethod('quit');
  }
}
