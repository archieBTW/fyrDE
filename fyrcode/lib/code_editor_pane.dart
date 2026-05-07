import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:fyrcode/lsp_client.dart';
import 'dart:io';
import 'dart:async';
import 'package:fyrcode/editor_toolbar.dart';
import 'fyr_theme.dart';

class DragAutoScroller extends StatefulWidget {
  final Widget child;
  final ScrollController controller;

  const DragAutoScroller({super.key, required this.child, required this.controller});

  @override
  State<DragAutoScroller> createState() => _DragAutoScrollerState();
}

class _DragAutoScrollerState extends State<DragAutoScroller> {
  Timer? _timer;

  void _checkScroll(PointerEvent event) {
    if (event.down) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.globalToLocal(event.position);
        _timer?.cancel();
        if (position.dy < 40) {
          _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
            if (widget.controller.hasClients) {
              widget.controller.jumpTo((widget.controller.offset - 15).clamp(0.0, widget.controller.position.maxScrollExtent));
            }
          });
        } else if (position.dy > renderBox.size.height - 40) {
          _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
            if (widget.controller.hasClients) {
              widget.controller.jumpTo((widget.controller.offset + 15).clamp(0.0, widget.controller.position.maxScrollExtent));
            }
          });
        } else {
          _timer?.cancel();
        }
      }
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _checkScroll,
      onPointerUp: (_) => _timer?.cancel(),
      onPointerCancel: (_) => _timer?.cancel(),
      child: widget.child,
    );
  }
}

final Map<String, TextStyle> catppuccinTheme = {
  'root': TextStyle(
    backgroundColor: FyrTheme.bgColor, // Deeper Macchiato base
    color: FyrTheme.textColor, // Text
    height: 1.4,
  ),
  'keyword': TextStyle(
    color: FyrTheme.accentColor, // Mauve
    fontWeight: FontWeight.bold,
  ),
  'object': TextStyle(color: Color(0xFFF9E2AF)), // Yellow (better for objects/classes)
  'built_in': TextStyle(color: Color(0xFF89B4FA)), // Blue
  'type': TextStyle(color: Color(0xFFF9E2AF), fontWeight: FontWeight.w500), // Yellow
  'literal': TextStyle(color: Color(0xFFFAB387)), // Peach
  'number': TextStyle(color: Color(0xFFFAB387)), // Peach
  'string': TextStyle(color: Color(0xFFA6E3A1)), // Green
  'title': TextStyle(color: Color(0xFF89B4FA)), // Blue
  'title.class': TextStyle(color: Color(0xFFF9E2AF), fontWeight: FontWeight.bold),
  'title.function': TextStyle(color: Color(0xFF89B4FA)),
  'class': TextStyle(color: Color(0xFFF9E2AF)),
  'function': TextStyle(color: Color(0xFF89B4FA)),
  'comment': TextStyle(
    color: Color(0xFF6C7086), // Surface 2 (better contrast for comments)
    fontStyle: FontStyle.italic,
  ),
  'meta': TextStyle(color: Color(0xFF94E2D5)), // Teal
  'params': TextStyle(
    color: Color(0xFFF5E0DC), // Rosewater
    fontStyle: FontStyle.italic,
  ),
  'operator': TextStyle(color: Color(0xFF89DCEB)), // Sky
  'property': TextStyle(color: Color(0xFFB4BEFE)), // Lavender
  'variable': TextStyle(color: FyrTheme.textColor),
  'attr': TextStyle(color: Color(0xFFF2CDCD)), // Flamingo
};

class FileStateCache {
  final String content;
  final CodeLineSelection selection;
  final double scrollOffset;
  final int documentVersion;

  FileStateCache({
    required this.content,
    required this.selection,
    required this.scrollOffset,
    required this.documentVersion,
  });
}

class CodeEditorPane extends StatefulWidget {
  final String filePath;
  final String projectRoot;
  final bool autoSave;
  final bool smartTabs;
  final int tabWidth;
  final double fontSize;
  final void Function(String filePath, int line, int col)?
  onNavigateToDefinition;

  const CodeEditorPane({
    super.key,
    required this.filePath,
    required this.projectRoot,
    this.autoSave = false,
    this.smartTabs = true,
    this.tabWidth = 2,
    this.fontSize = 14.0,
    this.onNavigateToDefinition,
  });

  @override
  State<CodeEditorPane> createState() => CodeEditorPaneState();
}

class CodeEditorPaneState extends State<CodeEditorPane> {
  static final Map<String, FileStateCache> openFilesCache = {};
  final Set<String> _lspTrackedFiles = {};

  CodeLineEditingController? _controller;
  late CodeScrollController _scrollController;
  CodeFindController? _findController;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  
  ValueNotifier<CodeAutocompleteEditingValue>? _autocompleteNotifier;
  ValueChanged<CodeAutocompleteResult>? _onAutocompleteSelected;

  String _fileContent = '';
  bool _isLoading = true;
  int _documentVersion = 1;

  LspClient? _lspClient;
  List<dynamic> _diagnostics = [];
  List<CodePrompt> _lspPrompts = [];

  Timer? _lspSyncTimer;
  Timer? _autoSaveTimer;
  Timer? _debounceCompletionTimer;
  final GlobalKey _gutterKey = GlobalKey();

  // Hover feature variables
  Timer? _hoverTimer;
  OverlayEntry? _hoverOverlay;

  bool _showSearch = false;

  int _currentLoadVersion = 0;

  TextStyle get _editorTextStyle => TextStyle(
    fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
    fontSize: widget.fontSize,
    height: 1.4,
  );

  // Bypass TextPainter entirely. Because we forced height: 1.3 above,
  // Flutter's engine guarantees the line will be exactly this many pixels tall.
  // REMOVE THIS:
  // double get _lineHeight => widget.fontSize * 1.3;

  // USE THIS INSTEAD:
  double get _lineHeight {
    final style = _editorTextStyle;
    final textPainter = TextPainter(
      text: TextSpan(text: 'X', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.size.height;
  }

  // double get _lineHeight {
  //   final style = TextStyle(
  //     fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
  //     fontSize: widget.fontSize,
  //   );

  //   final textPainter = TextPainter(
  //     text: TextSpan(text: 'X', style: style),
  //     textDirection: TextDirection.ltr,
  //     // 1. Capture system/OS text scaling!
  //     textScaler: MediaQuery.textScalerOf(context),
  //     // 2. Force the exact strut behavior re_editor uses internally
  //     strutStyle: StrutStyle(
  //       fontFamily: style.fontFamily,
  //       fontSize: style.fontSize,
  //       forceStrutHeight: true,
  //     ),
  //   )..layout();

  //   return textPainter.size.height;
  // }

  double get _charWidth {
    final style = _editorTextStyle;
    final textPainter = TextPainter(
      text: TextSpan(text: 'X' * 100, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.size.width / 100;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = CodeScrollController(
      verticalScroller: ScrollController(),
      horizontalScroller: ScrollController(),
    );
    _focusNode.onKeyEvent = _handleKeyEvent;
    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => _showSearch = false);
          _findController?.close();
          _focusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (HardwareKeyboard.instance.isShiftPressed) {
            _findController?.previousMatch();
          } else {
            _findController?.nextMatch();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _initLsp();
    _loadFile();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isModifierPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl + S (Save & Format)
    if (isModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyS &&
        !isShiftPressed) {
      _saveFile();
      return KeyEventResult.handled;
    }

    // Ctrl + F (Search)
    if (isModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        !isShiftPressed) {
      setState(() => _showSearch = true);
      _findController?.findMode();
      // Ensure the search input gets focus
      Future.delayed(const Duration(milliseconds: 50), () {
        _searchFocusNode.requestFocus();
      });
      return KeyEventResult.handled;
    }

    // Ctrl + / (Toggle Comment)
    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.slash) {
      _toggleComment();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Dismiss autocomplete when moving cursor manually
      if (_lspPrompts.isNotEmpty) {
        setState(() {
          _lspPrompts = [];
        });
      }
      final bool isMacOS = Platform.isMacOS;
      final bool isWordModifierPressed = isMacOS 
          ? HardwareKeyboard.instance.isAltPressed 
          : HardwareKeyboard.instance.isControlPressed;
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

      if (isWordModifierPressed) {
        _handleWordNavigation(
          event.logicalKey == LogicalKeyboardKey.arrowRight,
          isShiftPressed,
        );
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_lspPrompts.isNotEmpty &&
          _autocompleteNotifier != null &&
          _autocompleteNotifier!.value.prompts.isNotEmpty) {
        final value = _autocompleteNotifier!.value;
        _onAutocompleteSelected?.call(value.autocomplete);
        return KeyEventResult.handled;
      }
    }

    if (_lspPrompts.isNotEmpty &&
        _autocompleteNotifier != null &&
        _autocompleteNotifier!.value.prompts.isNotEmpty) {
      final value = _autocompleteNotifier!.value;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final nextIndex = (value.index + 1) % value.prompts.length;
        _autocompleteNotifier!.value = value.copyWith(index: nextIndex);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        final nextIndex =
            (value.index - 1 + value.prompts.length) % value.prompts.length;
        _autocompleteNotifier!.value = value.copyWith(index: nextIndex);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_lspPrompts.isNotEmpty) {
        setState(() => _lspPrompts.clear());
        return KeyEventResult.handled;
      }
      if (_showSearch) {
        setState(() => _showSearch = false);
        _findController?.close();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _handleWordNavigation(bool forward, bool select) {
    if (_controller == null) return;
    final selection = _controller!.selection;
    final text = _controller!.text;
    int offset = _getFlatOffset(selection.extentIndex, selection.extentOffset);

    if (forward) {
      if (offset < text.length) {
        final char = text[offset];
        if (char == '\n' || char == '\r') {
          // Stop at newlines
          if (char == '\r' &&
              offset + 1 < text.length &&
              text[offset + 1] == '\n') {
            offset += 2;
          } else {
            offset++;
          }
        } else if (RegExp(r'[ \t]').hasMatch(char)) {
          // Skip horizontal whitespace
          while (offset < text.length &&
              RegExp(r'[ \t]').hasMatch(text[offset])) {
            offset++;
          }
        } else if (RegExp(r'\w').hasMatch(char)) {
          // Skip word characters
          while (offset < text.length && RegExp(r'\w').hasMatch(text[offset])) {
            offset++;
          }
        } else {
          // Skip symbol characters (non-word, non-space)
          while (offset < text.length &&
              !RegExp(r'\w|\s').hasMatch(text[offset])) {
            offset++;
          }
        }
      }
    } else {
      if (offset > 0) {
        final char = text[offset - 1];
        if (char == '\n' || char == '\r') {
          // Stop at newlines backwards
          if (char == '\n' && offset - 2 >= 0 && text[offset - 2] == '\r') {
            offset -= 2;
          } else {
            offset--;
          }
        } else if (RegExp(r'[ \t]').hasMatch(char)) {
          // Skip horizontal whitespace backwards
          while (offset > 0 && RegExp(r'[ \t]').hasMatch(text[offset - 1])) {
            offset--;
          }
        } else if (RegExp(r'\w').hasMatch(char)) {
          // Skip word characters backwards
          while (offset > 0 && RegExp(r'\w').hasMatch(text[offset - 1])) {
            offset--;
          }
        } else {
          // Skip symbol characters backwards
          while (offset > 0 && !RegExp(r'\w|\s').hasMatch(text[offset - 1])) {
            offset--;
          }
        }
      }
    }

    // Ensure we don't go out of bounds
    offset = offset.clamp(0, text.length);

    int currentPos = 0;
    int targetLine = 0;
    int targetCol = 0;
    for (int i = 0; i < _controller!.codeLines.length; i++) {
      final lineLen = _controller!.codeLines[i].text.length + 1;
      if (currentPos + lineLen > offset) {
        targetLine = i;
        targetCol = offset - currentPos;
        break;
      }
      currentPos += lineLen;
      if (i == _controller!.codeLines.length - 1) {
        targetLine = i;
        targetCol = _controller!.codeLines[i].text.length;
      }
    }

    setState(() {
      if (select) {
        _controller!.selection = selection.copyWith(
          extentIndex: targetLine,
          extentOffset: targetCol,
        );
      } else {
        _controller!.selection = CodeLineSelection.collapsed(
          index: targetLine,
          offset: targetCol,
        );
      }
    });
  }

  void _toggleComment() {
    if (_controller == null) return;
    final selection = _controller!.selection;
    final codeLines = _controller!.codeLines;

    int start = min(selection.baseIndex, selection.extentIndex);
    int end = max(selection.baseIndex, selection.extentIndex);

    bool allCommented = true;
    for (int i = start; i <= end; i++) {
      if (i < codeLines.length && !codeLines[i].text.trim().startsWith('//')) {
        allCommented = false;
        break;
      }
    }

    final newLines = List<CodeLine>.generate(codeLines.length, (i) => codeLines[i]);
    for (int i = start; i <= end; i++) {
      if (i >= codeLines.length) continue;
      final lineText = codeLines[i].text;
      if (allCommented) {
        // Uncomment
        final index = lineText.indexOf('//');
        if (index != -1) {
          final before = lineText.substring(0, index);
          final after = lineText.substring(index + 2);
          String newLine;
          if (after.startsWith(' ')) {
            newLine = before + after.substring(1);
          } else {
            newLine = before + after;
          }
          newLines[i] = codeLines[i].copyWith(text: newLine);
        }
      } else {
        // Comment
        newLines[i] = codeLines[i].copyWith(text: '// $lineText');
      }
    }

    final updatedText = newLines.map((l) => l.text).join('\n');
    
    setState(() {
      _controller!.value = _controller!.value.copyWith(
        codeLines: CodeLines.fromText(updatedText),
        selection: selection.copyWith(
          baseOffset: selection.baseOffset.clamp(0, newLines[selection.baseIndex].text.length),
          extentOffset: selection.extentOffset.clamp(0, newLines[selection.extentIndex].text.length),
        ),
      );
    });

    // Re-focus with a slight delay to ensure the framework has updated the focus tree
    Future.delayed(const Duration(milliseconds: 10), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _initLsp() async {
    if (widget.filePath.endsWith('.dart')) {
      _lspClient = LspClient(
        onDiagnostics: (uri, diagnostics) {
          if (mounted && uri == Uri.file(widget.filePath).toString()) {
            setState(() {
              _diagnostics = diagnostics;
            });
          }
        },
      );
      await _lspClient!.start(widget.projectRoot);
      if (mounted) {
        _lspClient?.notifyFileOpened(widget.filePath, _fileContent);
        _lspTrackedFiles.add(widget.filePath);
      }
    }
  }

  @override
  void didUpdateWidget(covariant CodeEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _saveCache(oldWidget.filePath);
      _loadFile();
    }
  }

  void _saveCache(String path) {
    if (_controller == null) return;
    openFilesCache[path] = FileStateCache(
      content: _controller!.text,
      selection: _controller!.selection,
      scrollOffset: _scrollController.verticalScroller.hasClients
          ? _scrollController.verticalScroller.offset
          : 0.0,
      documentVersion: _documentVersion,
    );
  }

  Future<void> _loadFile() async {
    final loadVersion = ++_currentLoadVersion;
    setState(() => _isLoading = true);

    try {
      final cache = openFilesCache[widget.filePath];
      String content;
      int version;

      if (cache != null) {
        content = cache.content;
        version = cache.documentVersion;
      } else {
        final file = File(widget.filePath);
        if (await file.exists()) {
          content = await file.readAsString();
        } else {
          content = '// File not found';
        }
        content = content
            .replaceAll('\r\n', '\n')
            .replaceAll('\t', ' ' * widget.tabWidth);
        version = 1;
      }

      if (!mounted || loadVersion != _currentLoadVersion) return;

      final oldController = _controller;
      final newController = CodeLineEditingController.fromText(content);
      if (cache != null) newController.selection = cache.selection;

      final oldScrollController = _scrollController;
      _scrollController = CodeScrollController(
        verticalScroller: ScrollController(),
        horizontalScroller: ScrollController(),
      );

      setState(() {
        _fileContent = content;
        _documentVersion = version;
        _controller = newController;
        _findController = CodeFindController(_controller!);
        _isLoading = false;
      });

      // Safely dispose old resources after the new ones are active in the tree
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController?.removeListener(_onTextChanged);
        oldController?.dispose();
        oldScrollController.dispose();
      });

      _controller!.addListener(_onTextChanged);
    } catch (e) {
      if (!mounted || loadVersion != _currentLoadVersion) return;
      _fileContent = '// Error reading file: $e';
      setState(() {
        _controller = CodeLineEditingController.fromText(_fileContent);
        _isLoading = false;
      });
    }

    if (!mounted || loadVersion != _currentLoadVersion) return;

    if (widget.filePath.endsWith('.dart') &&
        !_lspTrackedFiles.contains(widget.filePath)) {
      _lspClient?.notifyFileOpened(widget.filePath, _fileContent);
      _lspTrackedFiles.add(widget.filePath);
    }

    setState(() => _isLoading = false);

    final cache = openFilesCache[widget.filePath];
    if (cache != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.verticalScroller.hasClients) {
          _scrollController.verticalScroller.jumpTo(cache.scrollOffset);
          _focusNode.requestFocus();
        }
      });
    }
  }

  void jumpToLine(int line, int col) {
    if (_controller == null) return;
    if (!mounted) return;
    setState(() {
      _controller!.selection = CodeLineSelection.collapsed(
        index: line,
        offset: col,
      );
      if (_scrollController.verticalScroller.hasClients) {
        _scrollController.verticalScroller.jumpTo(
          (line * _lineHeight).clamp(
            0.0,
            _scrollController.verticalScroller.position.maxScrollExtent,
          ),
        );
      }
    });
    _focusNode.requestFocus();
  }

  void _onTextChanged() {
    if (_controller == null) return;
    final currentText = _controller!.text;
    if (currentText == _fileContent) return;

    _fileContent = currentText;
    _documentVersion++;

    if (widget.filePath.endsWith('.dart')) {
      _lspSyncTimer?.cancel();
      _lspSyncTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted)
          _lspClient?.notifyDidChange(
            widget.filePath,
            _fileContent,
            _documentVersion,
          );
      });
    }

    if (widget.autoSave) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 2), _saveFile);
    }

    final selection = _controller!.selection;
    if (selection.isCollapsed) {
      final line = selection.baseIndex;
      final col = selection.baseOffset;
      final currentLineText = _controller!.codeLines[line].text;

      if (col <= currentLineText.length) {
        final textBefore = currentLineText.substring(0, col);
        final isJustDot = textBefore.endsWith('.');
        final isTypingWord = RegExp(r'[a-zA-Z0-9_]$').hasMatch(textBefore);

        if (isJustDot || isTypingWord) {
          final int flatOffset = _getFlatOffset(line, col);
          _debounceCompletionTimer?.cancel();
          
          final duration = isJustDot ? const Duration(milliseconds: 30) : const Duration(milliseconds: 150);
          
          _debounceCompletionTimer = Timer(duration, () {
            if (mounted) {
              final currentSelection = _controller?.selection;
              if (currentSelection != null &&
                  currentSelection.isCollapsed &&
                  currentSelection.baseIndex == line &&
                  currentSelection.baseOffset == col) {
                _syncLsp();
                _triggerCompletion(flatOffset, triggerCharacter: isJustDot ? '.' : null);
              }
            }
          });
        } else {
          if (mounted) setState(() => _lspPrompts = []);
        }
      }
    } else {
      if (mounted) setState(() => _lspPrompts = []);
    }
  }

  void _syncLsp() {
    if (_controller == null || !widget.filePath.endsWith('.dart')) return;
    _lspSyncTimer?.cancel();
    _lspClient?.notifyDidChange(
      widget.filePath,
      _controller!.text,
      _documentVersion,
    );
  }

  int _getFlatOffset(int line, int col) {
    int offset = 0;
    for (int i = 0; i < line; i++) {
      if (i < _controller!.codeLines.length) {
        offset += _controller!.codeLines[i].text.length + 1;
      }
    }
    return offset + col;
  }

  void _applyLspEdits(dynamic editsOrWorkspaceEdit) {
    if (editsOrWorkspaceEdit == null || _controller == null) return;

    List<dynamic> edits = [];
    if (editsOrWorkspaceEdit is List) {
      edits = editsOrWorkspaceEdit;
    } else if (editsOrWorkspaceEdit is Map) {
      // Handle WorkspaceEdit structure
      if (editsOrWorkspaceEdit.containsKey('changes')) {
        final changes = editsOrWorkspaceEdit['changes'] as Map<String, dynamic>;
        final uri = Uri.file(widget.filePath).toString();
        if (changes.containsKey(uri)) {
          edits = changes[uri] as List<dynamic>;
        }
      } else if (editsOrWorkspaceEdit.containsKey('documentChanges')) {
        final docChanges = editsOrWorkspaceEdit['documentChanges'] as List<dynamic>;
        for (final change in docChanges) {
          if (change is Map && change['textDocument'] != null) {
            final docUri = change['textDocument']['uri'] as String;
            if (docUri == Uri.file(widget.filePath).toString()) {
              edits.addAll(change['edits'] as List<dynamic>);
            }
          }
        }
      }
    }

    if (edits.isEmpty) return;

    String currentText = _controller!.text;
    final List<dynamic> sortedEdits = List.from(edits);

    // Sort edits in reverse order to maintain offset validity
    sortedEdits.sort((a, b) {
      final aStart = a['range']['start'];
      final bStart = b['range']['start'];
      if (aStart['line'] != bStart['line']) {
        return bStart['line'].compareTo(aStart['line']);
      }
      return bStart['character'].compareTo(aStart['character']);
    });

    for (final edit in sortedEdits) {
      final start = edit['range']['start'];
      final end = edit['range']['end'];
      final newText = edit['newText'] as String;

      final startOffset = _getFlatOffset(start['line'], start['character']);
      final endOffset = _getFlatOffset(end['line'], end['character']);

      if (startOffset <= currentText.length && endOffset <= currentText.length) {
        currentText = currentText.replaceRange(startOffset, endOffset, newText);
      }
    }

    final selection = _controller!.selection;
    _controller!.value = _controller!.value.copyWith(
      codeLines: CodeLines.fromText(currentText),
      selection: selection,
    );
    _fileContent = currentText;
  }

  Future<void> _handleCodeAction(dynamic action) async {
    if (action == null) return;

    // Apply immediate edits if present
    if (action['edit'] != null) {
      _applyLspEdits(action['edit']);
    }

    // Execute command if present
    if (action['command'] != null) {
      final cmd = action['command'];
      await _lspClient?.executeCommand(cmd['command'], cmd['arguments'] ?? []);
    }
  }

  Future<void> _saveFile() async {
    if (_controller == null) return;
    try {
      final file = File(widget.filePath);
      await file.writeAsString(_controller!.text);

      if (widget.filePath.endsWith('.dart')) {
        await Process.run('dart', ['format', widget.filePath]);
        final newContent = (await file.readAsString()).replaceAll('\r\n', '\n');

        if (newContent != _controller!.text) {
          final currentSelection = _controller!.selection;
          _controller!.value = _controller!.value.copyWith(
            codeLines: CodeLines.fromText(newContent),
            selection: currentSelection,
          );
        }
        _lspClient?.notifyDidSave(widget.filePath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saved & Formatted"),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  void save() => _saveFile();

  // --- LSP Hover Features ---

  void _onPointerHover(PointerHoverEvent event) {
    _hoverTimer?.cancel();
    _hoverOverlay?.remove();
    _hoverOverlay = null;

    final offset = event.localPosition;

    _hoverTimer = Timer(const Duration(milliseconds: 400), () async {
      double gutterWidth = 56.0;
      if (_gutterKey.currentContext != null) {
        final RenderBox? box =
            _gutterKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          gutterWidth = box.size.width;
        }
      }

      final scrollX = _scrollController.horizontalScroller.hasClients
          ? _scrollController.horizontalScroller.offset
          : 0;
      final scrollY = _scrollController.verticalScroller.hasClients
          ? _scrollController.verticalScroller.offset
          : 0;

      // Mouse localPosition acts relative to the Stack.
      // Subtracting gutterWidth gets us accurate horizontal placement inside the editor window.
      // We also need to account for any top offset if the editor content doesn't start at y=0.
      double topOffset = 0.0;
      if (_gutterKey.currentContext != null) {
        final RenderBox? box =
            _gutterKey.currentContext!.findRenderObject() as RenderBox?;
        final RenderBox? editorBox = context.findRenderObject() as RenderBox?;
        if (box != null &&
            editorBox != null &&
            box.attached &&
            editorBox.attached &&
            box.hasSize &&
            editorBox.hasSize) {
          try {
            // Using a more robust relative offset calculation to avoid "not in same tree" errors
            final globalBox = box.localToGlobal(Offset.zero);
            final globalEditor = editorBox.localToGlobal(Offset.zero);
            topOffset = globalBox.dy - globalEditor.dy;
          } catch (_) {
            topOffset = 0.0;
          }
        }
      }

      final x = offset.dx - gutterWidth + scrollX;
      final y = (offset.dy - topOffset) + scrollY;

      final line = (y / _lineHeight).floor();
      final col = (x / _charWidth).floor();

      if (line < 0 || col < 0) return;

      final hoverInfo = await _lspClient?.hover(widget.filePath, line, col);
      if (!mounted) return;

      if (hoverInfo != null && hoverInfo['contents'] != null) {
        _showHoverOverlay(event.position, hoverInfo['contents']);
      }
    });
  }

  void _showHoverOverlay(Offset globalPosition, dynamic contents) {
    _hoverOverlay?.remove();

    String text = '';
    if (contents is String) {
      text = contents;
    } else if (contents is Map && contents['value'] != null) {
      text = contents['value'] as String;
    } else if (contents is List) {
      text = contents
          .map((e) {
            if (e is String) return e;
            if (e is Map) return e['value'];
            return '';
          })
          .join('\n');
    }

    if (text.isEmpty) return;

    _hoverOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 15,
        top: globalPosition.dy + 15,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              border: Border.all(color: FyrTheme.dividerColor),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Text(
                text.replaceAll('```dart', '').replaceAll('```', '').trim(),
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_hoverOverlay!);
  }

  // --- LSP Autocomplete Trigger ---

  Future<void> _triggerCompletion(
    int offset, {
    String? triggerCharacter,
  }) async {
    if (_lspClient == null ||
        _controller == null ||
        !widget.filePath.endsWith('.dart'))
      return;

    final int startVersion = _documentVersion;
    final textBefore = _controller!.text.substring(0, offset);
    final lines = textBefore.split('\n');
    final line = lines.length - 1;
    final col = lines.last.length;

    try {
      final result = await _lspClient!.getCompletions(
        widget.filePath,
        line,
        col,
        triggerCharacter: triggerCharacter,
      );
      
      // If version changed or unmounted while waiting, discard results
      if (!mounted || _documentVersion != startVersion) return;

      List<dynamic> items = [];
      if (result is List)
        items = result;
      else if (result is Map && result['items'] != null)
        items = result['items'] as List<dynamic>;

      if (items.isNotEmpty) {
        setState(() {
          _lspPrompts = items.map((item) => LspPrompt(item)).toList();
        });

        // Nudge the controller to force the autocomplete overlay to refresh
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _controller == null) return;
          final val = _controller!.value;
          _controller!.value = val.copyWith();
        });
      } else {
        setState(() {
          _lspPrompts = [];
        });
      }
    } catch (e) {
      debugPrint('LSP Completion Error: $e');
    }
  }

  @override
  void dispose() {
    _saveCache(widget.filePath);
    _lspSyncTimer?.cancel();
    _autoSaveTimer?.cancel();
    _debounceCompletionTimer?.cancel();
    _hoverTimer?.cancel();
    _hoverOverlay?.remove();
    _hoverOverlay = null;
    final oldController = _controller;
    _controller = null;
    oldController?.removeListener(_onTextChanged);
    oldController?.dispose();
    _findController?.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Container(
      color: FyrTheme.bgColor,
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              onHover: _onPointerHover,
              onExit: (_) {
                _hoverTimer?.cancel();
                _hoverOverlay?.remove();
                _hoverOverlay = null;
              },
              child: Listener(
                onPointerUp: (event) {
                  if (HardwareKeyboard.instance.isControlPressed ||
                      HardwareKeyboard.instance.isMetaPressed) {
                    Future.delayed(const Duration(milliseconds: 50), () async {
                      if (!mounted || _controller == null) return;
                      final selection = _controller!.selection;
                      if (selection.isCollapsed &&
                          widget.onNavigateToDefinition != null) {
                        final result = await _lspClient?.getDefinition(
                          widget.filePath,
                          selection.baseIndex,
                          selection.baseOffset,
                        );
                        if (!mounted) return;

                        if (result != null &&
                            result is List &&
                            result.isNotEmpty) {
                          final loc = result.first;
                          widget.onNavigateToDefinition!(
                            Uri.parse(loc['uri'] as String).toFilePath(),
                            loc['range']['start']['line'] as int,
                            loc['range']['start']['character'] as int,
                          );
                        }
                      }
                    });
                  }
                },

                // --- Native re_editor Autocomplete ---
                child: CodeAutocomplete(
                  viewBuilder: (context, notifier, onSelected) {
                    _autocompleteNotifier = notifier;
                    _onAutocompleteSelected = (result) async {
                      final index = notifier.value.index;
                      final List<CodePrompt> prompts = notifier.value.prompts;
                      
                      onSelected(result);

                      if (index >= 0 && index < prompts.length) {
                        final prompt = prompts[index] as LspPrompt;
                        final resolvedItem = await _lspClient?.resolveCompletionItem(prompt.item);
                        if (resolvedItem != null && resolvedItem['additionalTextEdits'] != null) {
                          _applyLspEdits(resolvedItem['additionalTextEdits']);
                        }
                      }
                    };
                    return LspAutocompleteListView(
                      notifier: notifier,
                      onSelected: _onAutocompleteSelected!,
                    );
                  },
                  promptsBuilder: LspAutocompletePromptsBuilder(_lspPrompts),
                  child: Column(
                    children: [
                      if (_showSearch) _buildSearchBar(),
                      Expanded(
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          removeBottom: true,
                          child: DragAutoScroller(
                            controller: _scrollController.verticalScroller,
                            child: CodeEditor(
                            padding: EdgeInsets.zero,
                            key: ValueKey(widget.filePath),
                            controller: _controller!,
                            focusNode: _focusNode,
                            scrollController: _scrollController,
                            findController: _findController,
                            toolbarController: LspSelectionToolbarController(
                          getCodeActions:
                              (startLine, startCol, endLine, endCol) async {
                            return await _lspClient?.getCodeActions(
                                  widget.filePath,
                                  startLine,
                                  startCol,
                                  endLine,
                                  endCol,
                                ) ??
                                [];
                          },
                          onCodeActionSelected: _handleCodeAction,
                        ),
                        wordWrap: false,
                        style: CodeEditorStyle(
                          fontSize: widget.fontSize,
                          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                          codeTheme: CodeHighlightTheme(
                            languages: {
                              'dart': CodeHighlightThemeMode(mode: langDart),
                            },
                            theme: catppuccinTheme,
                          ),
                        ),
                        indicatorBuilder:
                            (
                              context,
                              editingController,
                              chunkController,
                              notifier,
                            ) {
                              return Row(
                                key: _gutterKey,
                                children: [
                                  DefaultCodeLineNumber(
                                    controller: editingController,
                                    notifier: notifier,
                                    textStyle: _editorTextStyle.copyWith(
                                      color: FyrTheme.textColorMuted,
                                    ),
                                  ),
                                  DefaultCodeChunkIndicator(
                                    width: 20,
                                    controller: chunkController,
                                    notifier: notifier,
                                  ),
                                ],
                              );
                            },
                        ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _scrollController.verticalScroller,
                  _scrollController.horizontalScroller,
                ]),
                builder: (context, child) {
                  // Calculate topOffset to pass to the painter
                  double topOffset = 0.0;
                  if (_gutterKey.currentContext != null) {
                    final RenderBox? box =
                        _gutterKey.currentContext!.findRenderObject()
                            as RenderBox?;
                    final RenderBox? editorBox =
                        context.findRenderObject() as RenderBox?;
                    if (box != null &&
                        editorBox != null &&
                        box.attached &&
                        editorBox.attached &&
                        box.hasSize &&
                        editorBox.hasSize) {
                      try {
                        final globalBox = box.localToGlobal(Offset.zero);
                        final globalEditor = editorBox.localToGlobal(
                          Offset.zero,
                        );
                        topOffset = globalBox.dy - globalEditor.dy;
                      } catch (_) {
                        topOffset = 0.0;
                      }
                    }
                  }

                  return CustomPaint(
                    painter: DiagnosticPainter(
                      gutterKey: _gutterKey,
                      diagnostics: _diagnostics,
                      lineHeight: _lineHeight,
                      charWidth: _charWidth,
                      topOffset: topOffset,
                      scrollY: _scrollController.verticalScroller.hasClients
                          ? _scrollController.verticalScroller.offset
                          : 0.0,
                      scrollX: _scrollController.horizontalScroller.hasClients
                          ? _scrollController.horizontalScroller.offset
                          : 0.0,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    if (_findController == null) return const SizedBox.shrink();
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(
          bottom: BorderSide(color: FyrTheme.cardColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: FyrTheme.dividerColor),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _findController!.findInputController,
              focusNode: _searchFocusNode, // Use our managed focus node with escape handling
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Find...',
                hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (value) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  _findController?.previousMatch();
                } else {
                  _findController?.nextMatch();
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: () => _findController?.previousMatch(),
            color: FyrTheme.textColor,
            tooltip: 'Previous Match',
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: () => _findController?.nextMatch(),
            color: FyrTheme.textColor,
            tooltip: 'Next Match',
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() => _showSearch = false);
              _findController?.close();
              _focusNode.requestFocus();
            },
            color: FyrTheme.textColor,
            tooltip: 'Close (Esc)',
          ),
        ],
      ),
    );
  }
}

// --- LSP Native Prompts & List Views ---

class LspPrompt extends CodePrompt {
  final Map<String, dynamic> item;
  final String currentInput;

  LspPrompt(this.item, {this.currentInput = ''})
    : super(word: item['label'] ?? '');

  @override
  CodeAutocompleteResult get autocomplete {
    String insertText = item['insertText'] ?? item['label'] ?? '';
    if (item['textEdit'] != null && item['textEdit'] is Map) {
      insertText = item['textEdit']['newText'] ?? insertText;
    }
    
    // Basic snippet cleanup (remove $0, $1, etc.)
    insertText = insertText.replaceAll(RegExp(r'\$\d+'), '');
    insertText = insertText.replaceAll(RegExp(r'\$\{\d+:[^}]*\}'), '');

    int kind = item['kind'] ?? 0;
    int cursorOffset = 0;

    // Smart paren insertion for methods/functions (kind 2: Method, 3: Function, 4: Constructor)
    if ((kind == 2 || kind == 3 || kind == 4) && !insertText.contains('(')) {
      insertText += '()';
      cursorOffset = -1;
    }

    return CodeAutocompleteResult(
      input: currentInput,
      word: insertText,
      selection: TextSelection.collapsed(
        offset: insertText.length + cursorOffset,
      ),
    );
  }

  @override
  bool match(String input) {
    if (input.isEmpty) return true;
    final String label = item['filterText'] ?? item['label'] ?? '';
    final String lowInput = input.toLowerCase();
    final String lowLabel = label.toLowerCase();
    // Use contains for better snippet/fuzzy matching, but prioritize startsWith in sorting
    return lowLabel.contains(lowInput);
  }
}

class LspAutocompletePromptsBuilder implements CodeAutocompletePromptsBuilder {
  final List<CodePrompt> lspPrompts;
  LspAutocompletePromptsBuilder(this.lspPrompts);

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (lspPrompts.isEmpty) return null;

    final text = codeLine.text;
    final col = selection.extentOffset;

    final textBeforeCursor = text.substring(0, col);
    
    // Improved word detection: find the identifier prefix immediately before the cursor
    String input = '';
    int i = textBeforeCursor.length - 1;
    while (i >= 0) {
      final char = textBeforeCursor[i];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(char)) {
        i--;
      } else {
        break;
      }
    }
    input = textBeforeCursor.substring(i + 1);
    
    // If the prefix is preceded by a dot, it's still a member completion, but 'input' is the prefix
    // If we just typed a dot, input will be empty, which is correct.
    
    // Detect the word before the dot to filter it out of suggestions (common server quirk)
    String? wordBeforeDot;
    if (input.isEmpty && textBeforeCursor.endsWith('.')) {
      int j = textBeforeCursor.length - 2;
      while (j >= 0 && RegExp(r'[a-zA-Z0-9_]').hasMatch(textBeforeCursor[j])) {
        j--;
      }
      wordBeforeDot = textBeforeCursor.substring(j + 1, textBeforeCursor.length - 1);
    }

    final filtered = lspPrompts
        .where((p) => p.match(input))
        .where((p) {
          // Filter out the variable name itself if it appears after the dot
          if (wordBeforeDot != null && wordBeforeDot.isNotEmpty && p.word == wordBeforeDot) {
            return false;
          }
          return true;
        })
        .map((p) => LspPrompt((p as LspPrompt).item, currentInput: input))
        .toList();

    // Sort the filtered results
    filtered.sort((a, b) {
      final aItem = a.item;
      final bItem = b.item;
      final aLabel = aItem['label']?.toString().toLowerCase() ?? '';
      final bLabel = bItem['label']?.toString().toLowerCase() ?? '';

      if (input.isNotEmpty) {
        final aStarts = aLabel.startsWith(input.toLowerCase());
        final bStarts = bLabel.startsWith(input.toLowerCase());
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;
      }

      // Priority: favor methods/properties (kind 2, 3) over others if input is empty
      if (input.isEmpty) {
        final aKind = aItem['kind'] as int? ?? 0;
        final bKind = bItem['kind'] as int? ?? 0;
        final aIsMember = aKind == 2 || aKind == 3;
        final bIsMember = bKind == 2 || bKind == 3;
        if (aIsMember && !bIsMember) return -1;
        if (!aIsMember && bIsMember) return 1;
      }

      // Fallback to sortText or label
      final aSort =
          aItem['sortText']?.toString() ?? aItem['label']?.toString() ?? '';
      final bSort =
          bItem['sortText']?.toString() ?? bItem['label']?.toString() ?? '';
      return aSort.compareTo(bSort);
    });

    if (filtered.isEmpty) return null;

    return CodeAutocompleteEditingValue(
      input: input,
      prompts: filtered,
      index: 0,
    );
  }
}

class LspAutocompleteListView extends StatefulWidget
    implements PreferredSizeWidget {
  static const double kItemHeight = 26;
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  const LspAutocompleteListView({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  @override
  Size get preferredSize =>
      Size(350, min(kItemHeight * notifier.value.prompts.length, 250) + 2);

  @override
  State<StatefulWidget> createState() => _LspAutocompleteListViewState();
}

class _LspAutocompleteListViewState extends State<LspAutocompleteListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    widget.notifier.addListener(_onValueChanged);
    super.initState();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onValueChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    setState(() {});

    // Auto-scroll logic mimicking the example
    if (_scrollController.hasClients) {
      final targetOffset =
          widget.notifier.value.index * LspAutocompleteListView.kItemHeight;
      final viewport = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.offset;
      if (targetOffset < currentOffset) {
        _scrollController.jumpTo(targetOffset);
      } else if (targetOffset + LspAutocompleteListView.kItemHeight >
          currentOffset + viewport) {
        _scrollController.jumpTo(
          targetOffset + LspAutocompleteListView.kItemHeight - viewport,
        );
      }
    }
  }

  IconData _getKindIcon(int? kind) {
    switch (kind) {
      case 2:
      case 3:
        return Icons.functions;
      case 4:
        return Icons.construction;
      case 5:
      case 6:
      // return Icons.variable_insert_outlined;
      case 7:
      case 8:
        return Icons.class_outlined;
      case 13:
        return Icons.list;
      case 14:
        return Icons.vpn_key;
      case 15:
        return Icons.snippet_folder;
      default:
        return Icons.code;
    }
  }

  Color _getKindColor(int? kind) {
    switch (kind) {
      case 2:
      case 3:
        return FyrTheme.accentColor;
      case 5:
      case 6:
        return FyrTheme.dividerColor;
      case 7:
      case 8:
        return Color(0xFFEED49F);
      case 14:
        return Color(0xFFED8796);
      case 15:
        return Color(0xFFA6DA95);
      default:
        return FyrTheme.textColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints.loose(widget.preferredSize),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border.all(color: FyrTheme.dividerColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          itemCount: widget.notifier.value.prompts.length,
          itemBuilder: (context, index) {
            final prompt = widget.notifier.value.prompts[index] as LspPrompt;
            final isSelected = index == widget.notifier.value.index;
            final kind = prompt.item['kind'] as int?;

            return InkWell(
              onTap: () => widget.onSelected(
                widget.notifier.value.copyWith(index: index).autocomplete,
              ),
              child: Container(
                height: LspAutocompleteListView.kItemHeight,
                color: isSelected
                    ? FyrTheme.cardColor
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      _getKindIcon(kind),
                      size: 16,
                      color: _getKindColor(
                        kind,
                      ).withOpacity(isSelected ? 1 : 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: prompt.word,
                              style: GoogleFonts.jetBrainsMono(
                                color: isSelected
                                    ? FyrTheme.textColor
                                    : FyrTheme.textColor.withOpacity(0.8),
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (prompt.item['labelDetails'] != null) ...[
                              TextSpan(
                                text: prompt.item['labelDetails']['detail'] ?? '',
                                style: GoogleFonts.jetBrainsMono(
                                  color: FyrTheme.textColorMuted,
                                  fontSize: 12,
                                ),
                              ),
                              TextSpan(
                                text: prompt.item['labelDetails']['description'] ?? '',
                                style: GoogleFonts.jetBrainsMono(
                                  color: Color(0xFFF5BDE6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (prompt.item['detail'] != null && prompt.item['labelDetails'] == null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          prompt.item['detail'],
                          style: GoogleFonts.jetBrainsMono(
                            color: FyrTheme.textColorMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class DiagnosticPainter extends CustomPainter {
  final List<dynamic> diagnostics;
  final double lineHeight;
  final double charWidth;
  final double scrollY;
  final double scrollX;
  final double topOffset;
  final GlobalKey gutterKey;

  DiagnosticPainter({
    required this.diagnostics,
    required this.lineHeight,
    required this.charWidth,
    required this.scrollY,
    required this.scrollX,
    required this.topOffset,
    required this.gutterKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    double gutterWidth = 56.0;
    if (gutterKey.currentContext != null) {
      final RenderBox? box =
          gutterKey.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        gutterWidth = box.size.width;
      }
    }

    // Performance Optimization: Limit diagnostic painting to prevent UI lockup
    // and only paint visible diagnostics.
    final List<dynamic> visibleDiagnostics = diagnostics.length > 500
        ? diagnostics.take(500).toList()
        : diagnostics;

    for (final diag in visibleDiagnostics) {
      final range = diag['range'];
      if (range == null) continue;

      // Map LSP severity to colors
      // 1: Error, 2: Warning, 3: Information, 4: Hint
      final int severity = diag['severity'] ?? 1;
      Color diagColor;
      switch (severity) {
        case 1: // Error
          diagColor = Color(0xFFED8796);
          break;
        case 2: // Warning
          diagColor = Color(0xFFEED49F);
          break;
        case 3: // Information
          diagColor = FyrTheme.dividerColor;
          break;
        case 4: // Hint
          diagColor = Color(0xFF8BD5CA);
          break;
        default:
          diagColor = Color(0xFFED8796);
      }

      paint.color = diagColor;

      final int startLine = range['start']['line'];
      final int startCol = range['start']['character'];
      final int endLine = range['end']['line'];
      final int endCol = range['end']['character'];

      if (startLine == endLine) {
        final y = (startLine * lineHeight) - scrollY + lineHeight + topOffset;
        if (y < 0 || y > size.height) continue;

        final startX = gutterWidth + (startCol * charWidth) - scrollX;
        final endX =
            gutterWidth +
            ((endCol == startCol ? startCol + 3 : endCol) * charWidth) -
            scrollX;
        _drawSquiggly(canvas, paint, startX, y, endX);
      }
    }
  }

  void _drawSquiggly(
    Canvas canvas,
    Paint paint,
    double startX,
    double y,
    double endX,
  ) {
    final path = Path();
    path.moveTo(startX, y);
    bool up = true;
    for (double x = startX; x <= endX; x += 3.0) {
      path.lineTo(x, up ? y - 2.0 : y + 2.0);
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DiagnosticPainter oldDelegate) {
    return oldDelegate.diagnostics != diagnostics ||
        oldDelegate.scrollY != scrollY ||
        oldDelegate.scrollX != scrollX ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.charWidth != charWidth ||
        oldDelegate.topOffset != topOffset;
  }
}
