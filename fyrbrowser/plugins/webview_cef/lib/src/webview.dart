import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_cef/src/webview_inject_user_script.dart';

import 'webview_manager.dart';
import 'webview_events_listener.dart';
import 'webview_javascript.dart';
import 'webview_textinput.dart';
import 'webview_tooltip.dart';

class WebViewController extends ValueNotifier<bool> {
  WebViewController(this._pluginChannel, this._index, {Widget? loading})
      : super(false) {
    _loadingWidget = loading;
  }
  final MethodChannel _pluginChannel;
  Widget? _loadingWidget;

  late WebView _webviewWidget;
  Widget get webviewWidget => _webviewWidget;
  Widget get loadingWidget => _loadingWidget ?? const Text("loading...");

  late Completer<void> _creatingCompleter;
  Future<void> get ready => _creatingCompleter.future;
  bool _isDisposed = false;
  bool _focusEditable = false;

  final int _index;
  late int _browserId;
  late int _textureId;
  final Map<String, JavascriptChannel> _javascriptChannels =
      <String, JavascriptChannel>{};
  Map<String, JavascriptChannel> get javascriptChannels => _javascriptChannels;
  WebviewEventsListener? _listener;
  WebviewEventsListener? get listener => _listener;

  get onJavascriptChannelMessage => (final String channelName,
          final String message, final String callbackId, final String frameId) {
        if (_javascriptChannels.containsKey(channelName)) {
          _javascriptChannels[channelName]!.onMessageReceived(
              JavascriptMessage(message, callbackId, frameId));
        } else {
          print('Channel "$channelName" is not exstis');
        }
      };

  get onToolTip => _onToolTip;
  get onCursorChanged => _onCursorChanged;
  get onFocusedNodeChangeMessage => _onFocusedNodeChangeMessage;
  get onImeCompositionRangeChangedMessage =>
      _onImeCompositionRangeChangedMessage;

  /// Initializes the underlying platform view.
  Future<void> initialize(String url) async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    _creatingCompleter = Completer<void>();
    try {
      await WebviewManager().ready;
      List args = await _pluginChannel.invokeMethod('create', url);
      _browserId = args[0] as int;
      _textureId = args[1] as int;
      WebviewManager().onBrowserCreated(_index, _browserId);
      await Future.delayed(const Duration(milliseconds: 50));
      _webviewWidget = WebView(this);
      value = true;
      _creatingCompleter.complete();
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  setWebviewListener(WebviewEventsListener listener) {
    _listener = listener;
  }

  void setPopupInfo(int browserId, int textureId) {
    _browserId = browserId;
    _textureId = textureId;
    _creatingCompleter = Completer<void>();
    _webviewWidget = WebView(this);
    value = true;
    _creatingCompleter.complete();
  }

  @override
  Future<void> dispose() async {
    await _creatingCompleter.future;
    if (!_isDisposed) {
      _isDisposed = true;
      WebviewManager().removeWebView(_browserId);
      await _pluginChannel.invokeMethod('close', _browserId);
    }
    super.dispose();
  }

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('loadUrl', [_browserId, url]);
  }

  /// Reloads the current document.
  Future<void> reload() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('reload', _browserId);
  }

  Future<void> goForward() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('goForward', _browserId);
  }

  Future<void> goBack() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('goBack', _browserId);
  }

  /// Stops loading the current document.
  Future<void> stopLoad() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('stopLoad', _browserId);
  }

  /// Searches for [searchText] in the active page.
  Future<void> findInPage(
    String searchText, {
    bool forward = true,
    bool matchCase = false,
    bool findNext = false,
  }) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod(
        'findInPage', [_browserId, searchText, forward, matchCase, findNext]);
  }

  /// Stops an active find-in-page session.
  Future<void> stopFinding({bool clearSelection = true}) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod(
        'stopFinding', [_browserId, clearSelection]);
  }

  /// Sets CEF browser zoom level (`0.0` is 100%).
  Future<void> setZoomLevel(double zoomLevel) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('setZoomLevel', [_browserId, zoomLevel]);
  }

  Future<void> openDevTools() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('openDevTools', _browserId);
  }

  Future<void> imeSetComposition(String composingText) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('imeSetComposition', [_browserId, composingText]);
  }

  Future<void> imeCommitText(String composingText) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('imeCommitText', [_browserId, composingText]);
  }

  Future<void> setClientFocus(bool focus) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('setClientFocus', [_browserId, focus]);
  }

  Future<void> setJavaScriptChannels(Set<JavascriptChannel> channels) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    _assertJavascriptChannelNamesAreUnique(channels);

    for (var channel in channels) {
      _javascriptChannels[channel.name] = channel;
    }

    return _pluginChannel.invokeMethod('setJavaScriptChannels',
        [_browserId, _extractJavascriptChannelNames(channels).toList()]);
  }

  Future<void> sendJavaScriptChannelCallBack(
      bool error, String result, String callbackId, String frameId) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('sendJavaScriptChannelCallBack',
        [error, result, callbackId, _browserId, frameId]);
  }

  Future<void> executeJavaScript(String code) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('executeJavaScript', [_browserId, code]);
  }

  Future<void> continueFileDialog(int callbackId, List<String> filePaths) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('continueFileDialog', [callbackId, filePaths]);
  }

  Future<dynamic> evaluateJavascript(String code) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('evaluateJavascript', [_browserId, code]);
  }

  /// Moves the virtual cursor to [position].
  Future<void> _cursorMove(Offset position) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod(
        'cursorMove', [_browserId, position.dx.round(), position.dy.round()]);
  }

  Future<void> _cursorDragging(Offset position) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorDragging',
        [_browserId, position.dx.round(), position.dy.round()]);
  }

  Future<void> _cursorClickDown(Offset position, [int button = 0]) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorClickDown',
        [_browserId, position.dx.round(), position.dy.round(), button]);
  }

  Future<void> _cursorClickUp(Offset position, [int button = 0]) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorClickUp',
        [_browserId, position.dx.round(), position.dy.round(), button]);
  }

  /// Sets the horizontal and vertical scroll delta.
  Future<void> setScrollDelta(Offset position, int dx, int dy) async {

    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('setScrollDelta',
        [_browserId, position.dx.round(), position.dy.round(), dx, dy]);
  }

  /// Sets the surface size to the provided [size].
  Future<void> _setSize(double dpi, Size size) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('setSize', [_browserId, dpi, size.width, size.height]);
  }

  Set<String> _extractJavascriptChannelNames(Set<JavascriptChannel> channels) {
    final Set<String> channelNames =
        channels.map((JavascriptChannel channel) => channel.name).toSet();
    return channelNames;
  }

  void _assertJavascriptChannelNamesAreUnique(
      final Set<JavascriptChannel>? channels) {
    if (channels == null || channels.isEmpty) {
      return;
    }
    assert(_extractJavascriptChannelNames(channels).length == channels.length);
  }

  Function(String)? _onToolTip;
  Function(int)? _onCursorChanged;
  Function(bool editable)? _onFocusedNodeChangeMessage;
  Function(int, int)? _onImeCompositionRangeChangedMessage;
}

class WebView extends StatefulWidget {
  final WebViewController controller;

  const WebView(this.controller, {Key? key}) : super(key: key);

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends State<WebView> with WebeViewTextInput {
  final GlobalKey _key = GlobalKey();
  String _composingText = '';
  late final _focusNode = FocusNode();
  bool isPrimaryFocus = false;
  bool _lastClientFocus = false;
  WebviewTooltip? _tooltip;
  MouseCursor _mouseType = SystemMouseCursors.basic;
  int _lastButton = 0;

  Timer? _scrollTimer;
  double _pendingScrollDx = 0;
  double _pendingScrollDy = 0;
  Offset _lastScrollPos = Offset.zero;

  WebViewController get _controller => widget.controller;

  @override
  updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    /// Handles IME composition only
    for (var d in textEditingDeltas) {
      if (d is TextEditingDeltaInsertion) {
        // composing text
        if (d.composing.isValid) {
          _composingText += d.textInserted;
          _controller.imeSetComposition(_composingText);
        } else if (!Platform.isWindows) {
          _controller.imeCommitText(d.textInserted);
        }
      } else if (d is TextEditingDeltaDeletion) {
        if (d.composing.isValid) {
          if (_composingText == d.textDeleted) {
            _composingText = "";
          }
          _controller.imeSetComposition(_composingText);
        }
      } else if (d is TextEditingDeltaReplacement) {
        if (d.composing.isValid) {
          _composingText = d.replacementText;
          _controller.imeSetComposition(_composingText);
        }
      } else if (d is TextEditingDeltaNonTextUpdate) {
        if (_composingText.isNotEmpty) {
          _controller.imeCommitText(_composingText);
          _composingText = '';
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller._onFocusedNodeChangeMessage = (editable) {
      _composingText = '';
      editable ? attachTextInputClient() : detachTextInputClient();
      _controller._focusEditable = editable;
    };

    _controller._onImeCompositionRangeChangedMessage = (x, y) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      updateIMEComposionPosition(
          x.toDouble(), y.toDouble(), box.localToGlobal(Offset.zero));
    };

    _controller._onToolTip = (final String text) {
      if (!mounted) return;
      final ctx = _key.currentContext;
      if (ctx == null) return;
      _tooltip ??= WebviewTooltip(ctx);
      _tooltip?.showToolTip(text);
    };

    _controller._onCursorChanged = (int type) {
      if (!mounted) return;
      final MouseCursor nextCursor;
      switch (type) {
        case 0:
          nextCursor = SystemMouseCursors.basic;
          break;
        case 1:
          nextCursor = SystemMouseCursors.precise;
          break;
        case 2:
          nextCursor = SystemMouseCursors.click;
          break;
        case 3:
          nextCursor = SystemMouseCursors.text;
          break;
        case 4:
          nextCursor = SystemMouseCursors.wait;
          break;
        default:
          nextCursor = SystemMouseCursors.basic;
          break;
      }
      if (nextCursor != _mouseType) {
        setState(() {
          _mouseType = nextCursor;
        });
      }
    };

    // Report initial surface size
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportSurfaceSize(context));
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _focusNode.dispose();
    _controller._onFocusedNodeChangeMessage = null;
    _controller._onImeCompositionRangeChangedMessage = null;
    _controller._onToolTip = null;
    _controller._onCursorChanged = null;
    super.dispose();
  }

  void _startSmoothScrollLoop() {
    if (_scrollTimer != null) return;
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted ||
          (_pendingScrollDx.abs() < 0.5 && _pendingScrollDy.abs() < 0.5)) {
        _pendingScrollDx = 0;
        _pendingScrollDy = 0;
        timer.cancel();
        _scrollTimer = null;
        return;
      }
      int stepX = 0;
      if (_pendingScrollDx.abs() >= 0.5) {
        double rawX = _pendingScrollDx * 0.35;
        if (rawX.abs() < 1) rawX = _pendingScrollDx > 0 ? 1 : -1;
        if (rawX.abs() > _pendingScrollDx.abs()) rawX = _pendingScrollDx;
        stepX = rawX.round();
        _pendingScrollDx -= stepX;
      } else {
        _pendingScrollDx = 0;
      }
      int stepY = 0;
      if (_pendingScrollDy.abs() >= 0.5) {
        double rawY = _pendingScrollDy * 0.35;
        if (rawY.abs() < 1) rawY = _pendingScrollDy > 0 ? 1 : -1;
        if (rawY.abs() > _pendingScrollDy.abs()) rawY = _pendingScrollDy;
        stepY = rawY.round();
        _pendingScrollDy -= stepY;
      } else {
        _pendingScrollDy = 0;
      }
      if (stepX != 0 || stepY != 0) {
        _controller.setScrollDelta(_lastScrollPos, stepX, stepY);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      focusNode: _focusNode,
      canRequestFocus: true,
      debugLabel: "webview_cef",
      onFocusChange: (focused) {
        _composingText = '';
        if (_lastClientFocus != focused) {
          _lastClientFocus = focused;
          _controller.setClientFocus(focused);
        }
        if (focused) {
          if (_controller._focusEditable) {
            attachTextInputClient();
          }
        } else {
          if (_controller._focusEditable) {
            detachTextInputClient();
          }
        }
      },
      child: SizedBox.expand(key: _key, child: _buildInner()),
    );
  }

  Widget _buildInner() {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _reportSurfaceSize(context);
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: Listener(
          onPointerHover: (ev) {
            _controller._cursorMove(ev.localPosition);
            _tooltip?.cursorOffset = ev.position;
          },
          onPointerDown: (ev) {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
            if (!_lastClientFocus) {
              _lastClientFocus = true;
              _controller.setClientFocus(true);
            }
            int button = 0;
            if (ev.buttons & 2 != 0) button = 2; // Right
            else if (ev.buttons & 4 != 0) button = 1; // Middle
            _lastButton = button;
            _controller._cursorClickDown(ev.localPosition, button);
          },
          onPointerUp: (ev) {
            _controller._cursorClickUp(ev.localPosition, _lastButton);
          },
          onPointerCancel: (ev) {
            _controller._cursorClickUp(ev.localPosition, _lastButton);
          },
          onPointerMove: (ev) {
            _controller._cursorDragging(ev.localPosition);
          },
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver
                  .register(signal, (event) {
                final scroll = event as PointerScrollEvent;
                _pendingScrollDx += scroll.scrollDelta.dx * 0.65;
                _pendingScrollDy += scroll.scrollDelta.dy * 0.65;
                _lastScrollPos = scroll.localPosition;
                _startSmoothScrollLoop();
              });
            }
          },
          onPointerPanZoomUpdate: (event) {
            _controller.setScrollDelta(event.localPosition,
                event.panDelta.dx.round(), event.panDelta.dy.round());

          },
          child: MouseRegion(
            cursor: _mouseType,
            child: Texture(textureId: _controller._textureId),
          ),
        ),
      ),
    );
  }

  void _reportSurfaceSize(BuildContext context) async {
    double dpi = MediaQuery.of(context).devicePixelRatio;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      await _controller.ready;
      unawaited(
          _controller._setSize(dpi, Size(box.size.width, box.size.height)));
    }
  }
}
