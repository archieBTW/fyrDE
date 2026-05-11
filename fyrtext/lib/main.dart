import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:simple_spell_checker/simple_spell_checker.dart';
import 'package:simple_spell_checker_en_lan/simple_spell_checker_en_lan.dart';
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
        _ResizeHandle(edge: ResizeZoneEdge.left, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.right, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.top, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottom, size: _resizeThickness),
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
      case ResizeZoneEdge.left: return ResizeEdge.left;
      case ResizeZoneEdge.right: return ResizeEdge.right;
      case ResizeZoneEdge.top: return ResizeEdge.top;
      case ResizeZoneEdge.bottom: return ResizeEdge.bottom;
      case ResizeZoneEdge.topLeft: return ResizeEdge.topLeft;
      case ResizeZoneEdge.topRight: return ResizeEdge.topRight;
      case ResizeZoneEdge.bottomLeft: return ResizeEdge.bottomLeft;
      case ResizeZoneEdge.bottomRight: return ResizeEdge.bottomRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    Alignment alignment;
    double? width;
    double? height;

    switch (edge) {
      case ResizeZoneEdge.left: alignment = Alignment.centerLeft; width = size; height = double.infinity; break;
      case ResizeZoneEdge.right: alignment = Alignment.centerRight; width = size; height = double.infinity; break;
      case ResizeZoneEdge.top: alignment = Alignment.topCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.bottom: alignment = Alignment.bottomCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.topLeft: alignment = Alignment.topLeft; width = size; height = size; break;
      case ResizeZoneEdge.topRight: alignment = Alignment.topRight; width = size; height = size; break;
      case ResizeZoneEdge.bottomLeft: alignment = Alignment.bottomLeft; width = size; height = size; break;
      case ResizeZoneEdge.bottomRight: alignment = Alignment.bottomRight; width = size; height = size; break;
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

class FyrChecker extends SimpleSpellChecker {
  FyrChecker({required super.language});
  bool isValid(String word) => isWordValid(word);
}

class FyrSpellCheckService extends SpellCheckService {
  final FyrChecker _checker = FyrChecker(language: 'en');

  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(
      Locale locale, String text) async {
    final List<SuggestionSpan> suggestionSpans = [];
    final RegExp wordRegExp = RegExp(r"\b\w+\b");
    final Iterable<RegExpMatch> matches = wordRegExp.allMatches(text);

    final dictionary = _checker.getDictionary();

    for (final match in matches) {
      final String word = text.substring(match.start, match.end);
      if (!_checker.isValid(word)) {
        List<String> suggestions = [];
        if (dictionary != null) {
          // Basic suggestion generation (limit to first 3 matches for performance)
          for (final key in dictionary.keys) {
            if (_isNear(word, key)) {
              suggestions.add(key);
              if (suggestions.length >= 3) break;
            }
          }
        }
        
        suggestionSpans.add(
          SuggestionSpan(
            TextRange(start: match.start, end: match.end),
            suggestions,
          ),
        );
      }
    }

    return suggestionSpans;
  }

  bool _isNear(String s1, String s2) {
    if ((s1.length - s2.length).abs() > 1) return false;
    int dist = 0;
    int i = 0, j = 0;
    while (i < s1.length && j < s2.length) {
      if (s1[i] != s2[j]) {
        dist++;
        if (dist > 1) return false;
        if (s1.length > s2.length) i++;
        else if (s2.length > s1.length) j++;
        else { i++; j++; }
      } else {
        i++; j++;
      }
    }
    return dist + (s1.length - i) + (s2.length - j) <= 1;
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  SimpleSpellCheckerEnRegister.registerLan();
  
  String? initialFile;
  if (args.isNotEmpty) {
    initialFile = args[0];
  }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(FyrTextApp(initialFile: initialFile));
}

class FyrTextApp extends StatelessWidget {
  final String? initialFile;
  const FyrTextApp({super.key, this.initialFile});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: FyrTheme.themeMode,
          theme: ThemeData.light().copyWith(
            useMaterial3: true,
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF000000),
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor),
          ),
          home: FyrTextHome(initialFile: initialFile),
        );
      },
    );
  }
}

class FyrTextHome extends StatefulWidget {
  final String? initialFile;
  const FyrTextHome({super.key, this.initialFile});

  @override
  State<FyrTextHome> createState() => _FyrTextHomeState();
}

class _FyrTextHomeState extends State<FyrTextHome> {
  final TextEditingController _controller = TextEditingController();
  String? _currentFilePath;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _spellCheckEnabled = true;
  final FyrSpellCheckService _spellCheckService = FyrSpellCheckService();

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _openFile(widget.initialFile!);
    }
    _controller.addListener(() {
      if (!_isDirty) {
        setState(() => _isDirty = true);
      }
    });
  }

  Future<void> _openFile([String? path]) async {
    String? targetPath = path;
    if (targetPath == null) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        targetPath = result.files.single.path;
      }
    }

    if (targetPath != null) {
      try {
        final file = File(targetPath);
        final content = await file.readAsString();
        setState(() {
          _controller.text = content;
          _currentFilePath = targetPath;
          _isDirty = false;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening file: $e')),
          );
        }
      }
    }
  }

  Future<void> _saveFile() async {
    if (_currentFilePath == null) {
      return _saveFileAs();
    }

    setState(() => _isSaving = true);
    try {
      final file = File(_currentFilePath!);
      await file.writeAsString(_controller.text);
      setState(() {
        _isDirty = false;
        _isSaving = false;
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }
    }
  }

  Future<void> _saveFileAs() async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save As',
      fileName: _currentFilePath != null ? p.basename(_currentFilePath!) : 'untitled.txt',
    );

    if (outputFile != null) {
      setState(() {
        _currentFilePath = outputFile;
        _isSaving = true;
      });
      try {
        final file = File(outputFile);
        await file.writeAsString(_controller.text);
        setState(() {
          _isDirty = false;
          _isSaving = false;
        });
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving file: $e')),
          );
        }
      }
    }
  }

  void _newFile() {
    if (_isDirty) {
      // Show confirmation dialog (omitted for brevity but recommended)
    }
    setState(() {
      _controller.clear();
      _currentFilePath = null;
      _isDirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _currentFilePath != null ? p.basename(_currentFilePath!) : 'Untitled';

    return Scaffold(
      backgroundColor: FyrTheme.isDark ? const Color(0xFF000000) : FyrTheme.bgColor,
      body: ResizableWindow(
        child: Column(
          children: [
            // Title Bar
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () => windowManager.maximize(),
              child: Container(
                height: 55,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: FyrTheme.isDark ? const Color(0xFF000000) : Colors.transparent,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => windowManager.close(),
                      child: Icon(Icons.circle, color: Colors.red.shade300, size: 16),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Process.run('swaymsg', ['[pid="$pid"] move scratchpad']),
                      child: Icon(Icons.circle, color: Colors.amber.shade300, size: 16),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']),
                      child: Icon(Icons.circle, color: Colors.green.shade300, size: 16),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      'FyrText',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '— $fileName${_isDirty ? '*' : ''}',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (_isSaving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
            // Toolbar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                border: Border(
                  bottom: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  _ToolbarButton(
                    icon: Icons.note_add_outlined,
                    label: 'New',
                    onPressed: _newFile,
                  ),
                  _ToolbarButton(
                    icon: Icons.file_open_outlined,
                    label: 'Open',
                    onPressed: () => _openFile(),
                  ),
                  _ToolbarButton(
                    icon: Icons.save_outlined,
                    label: 'Save',
                    onPressed: _saveFile,
                  ),
                  _ToolbarButton(
                    icon: Icons.save_as_outlined,
                    label: 'Save As',
                    onPressed: _saveFileAs,
                  ),
                  const VerticalDivider(width: 24, indent: 12, endIndent: 12),
                  _ToolbarButton(
                    icon: Icons.copy,
                    label: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _controller.text));
                    },
                  ),
                  _ToolbarButton(
                    icon: Icons.content_paste,
                    label: 'Paste',
                    onPressed: () async {
                      ClipboardData? data = await Clipboard.getData('text/plain');
                      if (data != null && data.text != null) {
                        _controller.text += data.text!;
                      }
                    },
                  ),
                  const VerticalDivider(width: 24, indent: 12, endIndent: 12),
                  _ToolbarButton(
                    icon: _spellCheckEnabled ? Icons.spellcheck : Icons.spellcheck_outlined,
                    label: 'Toggle Spell Check',
                    color: _spellCheckEnabled ? FyrTheme.accentColor : null,
                    onPressed: () {
                      setState(() {
                        _spellCheckEnabled = !_spellCheckEnabled;
                      });
                    },
                  ),
                ],
              ),
            ),
            // Editor
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                  spellCheckConfiguration: _spellCheckEnabled
                      ? SpellCheckConfiguration(
                          spellCheckService: _spellCheckService,
                          misspelledTextStyle: const TextStyle(
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.redAccent,
                            decorationStyle: TextDecorationStyle.wavy,
                            decorationThickness: 2.0,
                          ),
                        )
                      : const SpellCheckConfiguration.disabled(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Start typing...',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
            // Status Bar
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                border: Border(
                  top: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Lines: ${_controller.text.split('\n').length}',
                    style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Chars: ${_controller.text.length}',
                    style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    _currentFilePath ?? 'Local',
                    style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, color: color ?? FyrTheme.textColor, size: 20),
        onPressed: onPressed,
        splashRadius: 20,
      ),
    );
  }
}
