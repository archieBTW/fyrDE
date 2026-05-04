import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fyr_theme.dart';

enum ResizeZoneEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class ResizableWindow extends StatelessWidget {
  final Widget child;
  const ResizableWindow({super.key, required this.child});

  static const _resizeThickness = 6.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Edges
        _ResizeHandle(edge: ResizeZoneEdge.left, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.right, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.top, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottom, size: _resizeThickness),
        // Corners
        _ResizeHandle(edge: ResizeZoneEdge.topLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.topRight, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomRight, size: _resizeThickness),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ResizeZoneEdge edge;
  final double size;

  const _ResizeHandle({required this.edge, required this.size});

  SystemMouseCursor get cursor {
    switch (edge) {
      case ResizeZoneEdge.left:
      case ResizeZoneEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case ResizeZoneEdge.top:
      case ResizeZoneEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeZoneEdge.topLeft:
      case ResizeZoneEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeZoneEdge.topRight:
      case ResizeZoneEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  ResizeEdge get resizeEdge {
    switch (edge) {
      case ResizeZoneEdge.left:
        return ResizeEdge.left;
      case ResizeZoneEdge.right:
        return ResizeEdge.right;
      case ResizeZoneEdge.top:
        return ResizeEdge.top;
      case ResizeZoneEdge.bottom:
        return ResizeEdge.bottom;
      case ResizeZoneEdge.topLeft:
        return ResizeEdge.topLeft;
      case ResizeZoneEdge.topRight:
        return ResizeEdge.topRight;
      case ResizeZoneEdge.bottomLeft:
        return ResizeEdge.bottomLeft;
      case ResizeZoneEdge.bottomRight:
        return ResizeEdge.bottomRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    Alignment alignment;
    double? width;
    double? height;

    switch (edge) {
      case ResizeZoneEdge.left:
        alignment = Alignment.centerLeft;
        width = size;
        height = double.infinity;
        break;
      case ResizeZoneEdge.right:
        alignment = Alignment.centerRight;
        width = size;
        height = double.infinity;
        break;
      case ResizeZoneEdge.top:
        alignment = Alignment.topCenter;
        width = double.infinity;
        height = size;
        break;
      case ResizeZoneEdge.bottom:
        alignment = Alignment.bottomCenter;
        width = double.infinity;
        height = size;
        break;
      case ResizeZoneEdge.topLeft:
        alignment = Alignment.topLeft;
        width = size;
        height = size;
        break;
      case ResizeZoneEdge.topRight:
        alignment = Alignment.topRight;
        width = size;
        height = size;
        break;
      case ResizeZoneEdge.bottomLeft:
        alignment = Alignment.bottomLeft;
        width = size;
        height = size;
        break;
      case ResizeZoneEdge.bottomRight:
        alignment = Alignment.bottomRight;
        width = size;
        height = size;
        break;
    }

    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(resizeEdge),
          child: SizedBox(width: width, height: height),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  await SettingsManager().init();

  final initialSize = SettingsManager().getSavedWindowSize();
  WindowOptions windowOptions = WindowOptions(
    size: initialSize,
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  if (Platform.isLinux) {
    await windowManager.show();
    await windowManager.focus();
  } else {
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(Flutterm());
}

bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

class Flutterm extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SettingsManager(), FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) {
        return MaterialApp(
          title: 'fyrTerm',
          debugShowCheckedModeBanner: false,
          themeMode: FyrTheme.themeMode,
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: FyrTheme.accentColor, secondary: FyrTheme.accentColor),
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF2A282C),
            colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor, secondary: FyrTheme.accentColor),
          ),
          home: Home(),
        );
      },
    );
  }
}

class Home extends StatefulWidget {
  Home({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with WindowListener {
  final List<TerminalTab> _tabs = [];
  int _activeTabIndex = 0;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    SettingsManager().addListener(_onSettingsChanged);

    _addTab();

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _addTab() {
    final terminal = Terminal(maxLines: 10000);
    final controller = TerminalController();
    final focusNode = FocusNode();

    final tab = TerminalTab(
      terminal: terminal,
      controller: controller,
      focusNode: focusNode,
    );

    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      if (mounted) _startPty(tab);
    });

    if (mounted) setState(() {});
  }

  void _closeTab(int index, {bool force = false}) async {
    if (_tabs.length == 1) {
      if (force) {
        windowManager.destroy();
      }
      return;
    }

    final tab = _tabs[index];

    if (!force) {
      bool shouldClose =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Close Tab?'),
                content: const Text(
                  'Are you sure you want to close this tab? Any running process will be terminated.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!shouldClose) return;
    }

    tab.pty.kill();
    tab.focusNode.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabs.isNotEmpty) {
        _tabs[_activeTabIndex].focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    SettingsManager().removeListener(_onSettingsChanged);
    for (var tab in _tabs) {
      tab.pty.kill();
      tab.focusNode.dispose();
    }
    super.dispose();
  }

  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    SettingsManager().saveWindowSize(size.width, size.height);
  }

  @override
  void onWindowClose() async {
    bool shouldClose =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Close Terminal?'),
              content: Text(
                _tabs.length > 1
                    ? 'You have multiple tabs open. Are you sure you want to close the terminal? All running processes will be terminated.'
                    : 'Are you sure you want to close the terminal? Any running process will be terminated.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (shouldClose) {
      await windowManager.destroy();
    }
  }

  void _startPty(TerminalTab tab) {
    tab.pty = Pty.start(
      shell,
      columns: tab.terminal.viewWidth,
      rows: tab.terminal.viewHeight,
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    tab.pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .transform(DcsFilter())
        .listen(tab.terminal.write);

    tab.pty.exitCode.then((code) {
      if (mounted) {
        final index = _tabs.indexOf(tab);
        if (index != -1) {
          _closeTab(index, force: true);
        }
      }
    });

    tab.terminal.onOutput = (data) {
      tab.pty.write(const Utf8Encoder().convert(data));
    };

    tab.terminal.onResize = (w, h, pw, ph) {
      tab.pty.resize(h, w);
    };
  }

  final terminalShortcuts = <ShortcutActivator, Intent>{
    LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyC,
    ): const CopyIntent(),
    LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyV,
    ): const PasteIntent(),
    LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyT,
    ): const NewTabIntent(),
    LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyW,
    ): const CloseTabIntent(),
    LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.tab,
    ): const CycleTabIntent(),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
        const TerminalShortcutIntent('\x01'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyE):
        const TerminalShortcutIntent('\x05'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
        const TerminalShortcutIntent('\x0b'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyU):
        const TerminalShortcutIntent('\x15'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW):
        const TerminalShortcutIntent('\x17'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyL):
        const TerminalShortcutIntent('\x0c'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
        const TerminalShortcutIntent('\x03'),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyD):
        const TerminalShortcutIntent('\x04'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResizableWindow(
          child: Column(
            children: [
              CustomTitleBar(onAddTab: _addTab),
              if (_tabs.length > 1)
                Container(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _tabs.length,
                          itemBuilder: (context, index) {
                            final isActive = index == _activeTabIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _activeTabIndex = index;
                                });
                                _tabs[index].focusNode.requestFocus();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? (FyrTheme.isDark
                                            ? const Color.fromARGB(255, 0, 0, 0)
                                            : const Color(0xFFeff1f5))
                                      : Colors.transparent,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isActive
                                          ? FyrTheme.accentColor
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Terminal ${index + 1}',
                                      style: TextStyle(
                                        color: isActive
                                            ? (FyrTheme.isDark
                                                  ? const Color(0xFFcdd6f4)
                                                  : const Color(0xFF4c4f69))
                                            : (FyrTheme.isDark
                                                  ? const Color(0xFFa6adc8)
                                                  : const Color(0xFF9ca0b0)),
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    if (_tabs.length > 1) ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _closeTab(index),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: isActive
                                              ? (FyrTheme.isDark
                                                    ? const Color(0xFFcdd6f4)
                                                    : const Color(0xFF4c4f69))
                                              : (FyrTheme.isDark
                                                    ? const Color(0xFFa6adc8)
                                                    : const Color(0xFF9ca0b0)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _activeTabIndex,
                  children: _tabs.map((tab) {
                    return Actions(
                      actions: {
                        TerminalShortcutIntent: SendTerminalSequenceAction((
                          sequence,
                        ) {
                          tab.pty.write(const Utf8Encoder().convert(sequence));
                        }),
                        CopyIntent: CallbackAction<CopyIntent>(
                          onInvoke: (intent) async {
                            final selection = tab.controller.selection;
                            final selectedText = selection != null
                                ? tab.terminal.buffer.getText(selection)
                                : null;
                            if (selectedText != null) {
                              await Clipboard.setData(
                                ClipboardData(text: selectedText),
                              );
                              tab.controller.clearSelection();
                            }
                            return null;
                          },
                        ),
                        PasteIntent: CallbackAction<PasteIntent>(
                          onInvoke: (intent) async {
                            final data = await Clipboard.getData('text/plain');
                            final text = data?.text;
                            if (text != null) {
                              tab.terminal.paste(text);
                            }
                            return null;
                          },
                        ),
                        NewTabIntent: CallbackAction<NewTabIntent>(
                          onInvoke: (intent) {
                            _addTab();
                            return null;
                          },
                        ),
                        CloseTabIntent: CallbackAction<CloseTabIntent>(
                          onInvoke: (intent) {
                            _closeTab(_tabs.indexOf(tab));
                            return null;
                          },
                        ),
                        CycleTabIntent: CallbackAction<CycleTabIntent>(
                          onInvoke: (intent) {
                            if (_tabs.length > 1) {
                              setState(() {
                                _activeTabIndex = (_activeTabIndex + 1) % _tabs.length;
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _tabs[_activeTabIndex].focusNode.requestFocus();
                              });
                            }
                            return null;
                          },
                        ),
                      },
                      child: TerminalView(
                        tab.terminal,
                        controller: tab.controller,
                        focusNode: tab.focusNode,
                        autofocus: true,
                        shortcuts: terminalShortcuts,
                        onSecondaryTapDown: (details, offset) async {
                          final RenderBox overlay =
                              Overlay.of(context).context.findRenderObject()
                                  as RenderBox;

                          final selection = tab.controller.selection;
                          final selectedText = selection != null
                              ? tab.terminal.buffer.getText(selection)
                              : null;

                          final choice = await showMenu<String>(
                            context: context,
                            position: RelativeRect.fromRect(
                              details.globalPosition & const Size(40, 40),
                              Offset.zero & overlay.size,
                            ),
                            items: [
                              if (selectedText != null)
                                const PopupMenuItem<String>(
                                  value: 'cut',
                                  child: Text('Cut'),
                                ),
                              if (selectedText != null)
                                const PopupMenuItem<String>(
                                  value: 'copy',
                                  child: Text('Copy'),
                                ),
                              const PopupMenuItem<String>(
                                value: 'paste',
                                child: Text('Paste'),
                              ),
                            ],
                          );

                          switch (choice) {
                            case 'cut':
                              if (selectedText != null) {
                                await Clipboard.setData(
                                  ClipboardData(text: selectedText),
                                );
                                tab.terminal.paste('');
                                tab.controller.clearSelection();
                              }
                              break;
                            case 'copy':
                              if (selectedText != null) {
                                await Clipboard.setData(
                                  ClipboardData(text: selectedText),
                                );
                                tab.controller.clearSelection();
                              }
                              break;
                            case 'paste':
                              final data = await Clipboard.getData(
                                'text/plain',
                              );
                              final text = data?.text;
                              if (text != null) {
                                tab.terminal.paste(text);
                              }
                              break;
                          }
                        },
                        textStyle: TerminalStyle(
                          fontSize: SettingsManager().fontSize,
                          fontFamily: SettingsManager().fontFamily,
                        ),
                        theme: FyrTheme.isDark
                            ? darkTerminalTheme
                            : lightTerminalTheme,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get shell {
  if (Platform.isMacOS || Platform.isLinux) {
    return Platform.environment['SHELL'] ?? 'bash';
  }

  if (Platform.isWindows) {
    return 'cmd.exe';
  }

  return 'sh';
}

class CustomTitleBar extends StatelessWidget {
  final VoidCallback onAddTab;

  const CustomTitleBar({super.key, required this.onAddTab});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () {
        Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']);
      },
      child: Container(
        height: 45,
        color: FyrTheme.isDark
            ? const Color.fromARGB(255, 0, 0, 0)
            : const Color(0xFFeff1f5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Traffic Light Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _WindowButton(
                  color: Colors.red.shade300,
                  onPressed: () => windowManager.close(),
                ),
                const SizedBox(width: 8),
                _WindowButton(
                  color: Colors.amber.shade300,
                  onPressed: () {
                    Process.run('swaymsg', ['[pid="$pid"] move scratchpad']);
                  },
                ),
                const SizedBox(width: 8),
                _WindowButton(
                  color: Colors.green.shade300,
                  onPressed: () {
                    Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']);
                  },
                ),
              ],
            ),
            const Spacer(),
            Text(
              '',
              style: TextStyle(
                color: FyrTheme.isDark
                    ? const Color(0xFFcdd6f4)
                    : const Color(0xFF4c4f69),
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(flex: 2),
            IconButton(
              icon: Icon(
                Icons.add,
                color: FyrTheme.isDark
                    ? Colors.grey
                    : Colors.black54,
                size: 16,
              ),
              onPressed: onAddTab,
            ),
            IconButton(
              icon: Icon(
                Icons.settings,
                color: FyrTheme.isDark
                    ? Colors.grey
                    : Colors.black54,
                size: 16,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const SettingsDialog(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final Color color;
  final VoidCallback onPressed;

  const _WindowButton({required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class TerminalShortcutIntent extends Intent {
  final String sequence;
  const TerminalShortcutIntent(this.sequence);
}

class SendTerminalSequenceAction extends Action<TerminalShortcutIntent> {
  final void Function(String sequence) send;

  SendTerminalSequenceAction(this.send);

  @override
  Object? invoke(covariant TerminalShortcutIntent intent) {
    send(intent.sequence);
    return null;
  }
}

class TerminalTab {
  final Terminal terminal;
  final TerminalController controller;
  late final Pty pty;
  final FocusNode focusNode;

  TerminalTab({
    required this.terminal,
    required this.controller,
    required this.focusNode,
  });
}

class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class CycleTabIntent extends Intent {
  const CycleTabIntent();
}

class DcsFilter extends StreamTransformerBase<String, String> {
  @override
  Stream<String> bind(Stream<String> stream) async* {
    String buffer = '';

    await for (final chunk in stream) {
      buffer += chunk;

      while (buffer.isNotEmpty) {
        int dcsStart = buffer.indexOf('\x1bP');
        if (dcsStart == -1) {
          if (buffer.endsWith('\x1b')) {
            int keepLen = buffer.lastIndexOf('\x1b');
            if (keepLen > 0) {
              yield buffer.substring(0, keepLen);
              buffer = buffer.substring(keepLen);
            }
          } else {
            yield buffer;
            buffer = '';
          }
          break;
        } else {
          int dcsEnd = buffer.indexOf('\x1b\\', dcsStart);
          if (dcsEnd == -1) {
            if (dcsStart > 0) {
              yield buffer.substring(0, dcsStart);
              buffer = buffer.substring(dcsStart);
            }
            break;
          } else {
            if (dcsStart > 0) {
              yield buffer.substring(0, dcsStart);
            }
            buffer = buffer.substring(dcsEnd + 2);
          }
        }
      }
    }
  }
}

class SettingsManager extends ChangeNotifier {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  late SharedPreferences _prefs;

  bool _isDarkMode = true;
  String _fontFamily = 'JetBrains Mono';
  double _fontSize = 16.0;
  double _defaultWidth = 700.0;
  double _defaultHeight = 500.0;

  bool get isDarkMode => _isDarkMode;
  String get fontFamily => _fontFamily;
  double get fontSize => _fontSize;
  double get defaultWidth => _defaultWidth;
  double get defaultHeight => _defaultHeight;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs.getBool('isDarkMode') ?? true;
    _fontFamily = _prefs.getString('fontFamily') ?? 'JetBrains Mono';
    _fontSize = _prefs.getDouble('fontSize') ?? 16.0;
    _defaultWidth = _prefs.getDouble('defaultWidth') ?? 700.0;
    _defaultHeight = _prefs.getDouble('defaultHeight') ?? 500.0;

    await _loadSystemFont(_fontFamily);
  }

  Future<void> _loadSystemFont(String family) async {
    if (family == 'Fira Code' || family == 'JetBrains Mono') return;
    if (Platform.isLinux) {
      try {
        final check = await Process.run('fc-list', [family]);
        if ((check.stdout as String).trim().isEmpty) {
          return;
        }

        final result = await Process.run('fc-match', [family, '-f', '%{file}']);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim();
          if (path.isNotEmpty && File(path).existsSync()) {
            final bytes = await File(path).readAsBytes();
            await ui.loadFontFromList(bytes, fontFamily: family);
          }
        }
      } catch (e) {
        // Fallback or ignore
      }
    }
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    await _prefs.setBool('isDarkMode', value);
    notifyListeners();
  }

  Future<void> setFontSize(double value) async {
    _fontSize = value;
    await _prefs.setDouble('fontSize', value);
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    _fontFamily = value;
    await _prefs.setString('fontFamily', value);
    await _loadSystemFont(value);
    notifyListeners();
  }

  Future<void> setDefaultSize(double width, double height) async {
    _defaultWidth = width;
    _defaultHeight = height;
    await _prefs.setDouble('defaultWidth', width);
    await _prefs.setDouble('defaultHeight', height);
    notifyListeners();
  }

  Future<void> saveWindowSize(double width, double height) async {
    await _prefs.setDouble('windowWidth', width);
    await _prefs.setDouble('windowHeight', height);
  }

  Size getSavedWindowSize() {
    final w = _prefs.getDouble('windowWidth');
    final h = _prefs.getDouble('windowHeight');
    if (w != null && h != null) return Size(w, h);
    return Size(_defaultWidth, _defaultHeight);
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  // ignore: library_private_types_in_public_api
  _SettingsDialogState createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _fontController;
  late TextEditingController _fontFamilyController;
  bool _isDark = true;
  List<String> _systemFonts = [
    'Fira Code',
    'JetBrains Mono',
    'monospace',
    'sans-serif',
    'serif',
  ];
  bool _fontsLoaded = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsManager();
    _widthController = TextEditingController(text: s.defaultWidth.toString());
    _heightController = TextEditingController(text: s.defaultHeight.toString());
    _fontController = TextEditingController(text: s.fontSize.toString());
    _fontFamilyController = TextEditingController(text: s.fontFamily);
    _isDark = s.isDarkMode;
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    if (Platform.isLinux) {
      try {
        final result = await Process.run('fc-list', [':', 'family']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          final fonts = <String>{};
          for (var line in lines) {
            if (line.trim().isNotEmpty) {
              final families = line.split(',');
              for (var family in families) {
                if (family.trim().isNotEmpty) fonts.add(family.trim());
              }
            }
          }
          if (mounted) {
            setState(() {
              if (!fonts.contains('Fira Code')) fonts.add('Fira Code');
              if (!fonts.contains('JetBrains Mono'))
                fonts.add('JetBrains Mono');
              if (_fontFamilyController.text.isNotEmpty &&
                  !fonts.contains(_fontFamilyController.text)) {
                fonts.add(_fontFamilyController.text);
              }
              _systemFonts = fonts.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              _fontsLoaded = true;
            });
          }
          return;
        }
      } catch (e) {
        // Fallback
      }
    }
    if (mounted) setState(() => _fontsLoaded = true);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _fontController.dispose();
    _fontFamilyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            _fontsLoaded
                ? DropdownMenu<String>(
                    controller: _fontFamilyController,
                    initialSelection: _fontFamilyController.text,
                    label: const Text('Font Family'),
                    enableFilter: true,
                    enableSearch: true,
                    width: 250,
                    dropdownMenuEntries: _systemFonts.map((String font) {
                      return DropdownMenuEntry<String>(
                        value: font,
                        label: font,
                      );
                    }).toList(),
                    onSelected: (String? value) {
                      if (value != null) {
                        _fontFamilyController.text = value;
                      }
                    },
                  )
                : const SizedBox(
                    height: 56,
                    child: Center(child: CircularProgressIndicator()),
                  ),
            const SizedBox(height: 12),
            TextField(
              controller: _fontController,
              decoration: const InputDecoration(labelText: 'Font Size'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _widthController,
              decoration: const InputDecoration(labelText: 'Default Width'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Default Height'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final s = SettingsManager();
            s.setFontSize(double.tryParse(_fontController.text) ?? 18.0);
            s.setFontFamily(_fontFamilyController.text.trim());
            s.setDefaultSize(
              double.tryParse(_widthController.text) ?? 700.0,
              double.tryParse(_heightController.text) ?? 500.0,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

final darkTerminalTheme = TerminalTheme(
  background: const Color.fromARGB(255, 0, 0, 0),
  foreground: const Color(0xFFcdd6f4),
  cursor: const Color(0xFFf5e0dc),
  selection: const Color(0x80313244),
  black: const Color(0xFF45475a),
  red: const Color(0xFFf38ba8),
  green: const Color(0xFFa6e3a1),
  yellow: const Color(0xFFf9e2af),
  blue: const Color(0xFF89b4fa),
  magenta: const Color(0xFFf5c2e7),
  cyan: const Color(0xFF94e2d5),
  white: const Color(0xFFbac2de),
  brightBlack: const Color(0xFF585b70),
  brightRed: const Color(0xFFf38ba8),
  brightGreen: const Color(0xFFa6e3a1),
  brightYellow: const Color(0xFFf9e2af),
  brightBlue: const Color(0xFF89b4fa),
  brightMagenta: const Color(0xFFf5c2e7),
  brightCyan: const Color(0xFF94e2d5),
  brightWhite: const Color(0xFFa6adc8),
  searchHitBackground: const Color(0xFF45475a),
  searchHitBackgroundCurrent: const Color(0xFF89b4fa),
  searchHitForeground: const Color(0xFFcdd6f4),
);

final lightTerminalTheme = TerminalTheme(
  background: const Color(0xFFeff1f5), // catppuccin latte base
  foreground: const Color(0xFF4c4f69), // text
  cursor: const Color(0xFFdc8a78), // rosewater
  selection: const Color(0x40bcc0cc), // surface2
  black: const Color(0xFF5c5f77),
  red: const Color(0xFFd20f39),
  green: const Color(0xFF40a02b),
  yellow: const Color(0xFFdf8e1d),
  blue: const Color(0xFF1e66f5),
  magenta: const Color(0xFFea76cb),
  cyan: const Color(0xFF179299),
  white: const Color(0xFFacb0be),
  brightBlack: const Color(0xFF6c6f85),
  brightRed: const Color(0xFFd20f39),
  brightGreen: const Color(0xFF40a02b),
  brightYellow: const Color(0xFFdf8e1d),
  brightBlue: const Color(0xFF1e66f5),
  brightMagenta: const Color(0xFFea76cb),
  brightCyan: const Color(0xFF179299),
  brightWhite: const Color(0xFFbcc0cc),
  searchHitBackground: const Color(0xFFccd0da),
  searchHitBackgroundCurrent: const Color(0xFF1e66f5),
  searchHitForeground: const Color(0xFFeff1f5),
);
