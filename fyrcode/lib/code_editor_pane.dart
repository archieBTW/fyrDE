import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:fyrcode/lsp_client.dart';
import 'dart:io';
import 'dart:async';
import 'package:fyrcode/editor_toolbar.dart';
import 'package:fyrcode/ai/agent_controller.dart';
import 'package:fyrcode/ai/ai_settings_dialog.dart';
import 'package:fyrcode/ai/inline_completion_service.dart';
import 'package:fyrcode/ai/inline_edit_overlay.dart';
import 'package:fyrcode/bottom_panel.dart';
import 'package:fyrcode/language_support.dart';
import 'package:fyrcode/quick_open_dialog.dart';
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
  final void Function(String filePath, int errorCount)? onDiagnosticsChanged;
  final void Function(String filePath, List<dynamic> diagnostics)?
  onDiagnosticsDetailChanged;
  final AgentController? agentController;
  final void Function(String selectedText, int startLine, int endLine)?
  onAskAiAboutSelection;
  final void Function(String filePath, bool isDirty)? onDirtyChanged;
  final void Function(List<ReferenceLocation> refs, String symbolName)?
  onShowReferences;

  const CodeEditorPane({
    super.key,
    required this.filePath,
    required this.projectRoot,
    this.autoSave = false,
    this.smartTabs = true,
    this.tabWidth = 2,
    this.fontSize = 14.0,
    this.onNavigateToDefinition,
    this.onDiagnosticsChanged,
    this.onDiagnosticsDetailChanged,
    this.agentController,
    this.onAskAiAboutSelection,
    this.onDirtyChanged,
    this.onShowReferences,
  });

  @override
  State<CodeEditorPane> createState() => CodeEditorPaneState();
}

class CodeEditorPaneState extends State<CodeEditorPane> {
  static final Map<String, FileStateCache> openFilesCache = {};
  static final Map<String, String> savedContentCache = {};
  final Set<String> _lspTrackedFiles = {};

  late LanguageSpec _langSpec;
  String _savedContent = '';
  bool _isDirty = false;
  StreamSubscription? _lspDiagnosticsSub;

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
  Timer? _fileWatchTimer;
  final GlobalKey _gutterKey = GlobalKey();

  DateTime? _lastDiskModified;
  String _lastDiskContent = '';

  // Hover feature variables
  Timer? _hoverTimer;
  OverlayEntry? _hoverOverlay;

  // Signature help & inline AI ghost text
  String? _signatureText;
  String? _ghostText;
  int _ghostLine = 0;
  int _ghostCol = 0;
  Timer? _ghostTimer;
  InlineCompletionService? _inlineCompletionService;

  bool _showSearch = false;
  bool _showInlineEdit = false;
  int _inlineEditStartLine = 0;
  int _inlineEditEndLine = 0;
  String _inlineEditTargetText = '';

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
    _langSpec = LanguageRegistry.detect(widget.filePath);
    if (widget.agentController != null) {
      _inlineCompletionService = InlineCompletionService(
        llmClient: widget.agentController!.llmClient,
      );
    }
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

    _lspDiagnosticsSub = LspSessionManager.instance.diagnosticsStream.listen((
      event,
    ) {
      if (!mounted || event.filePath != widget.filePath) return;
      final diagnostics = event.diagnostics;
      final errorCount = diagnostics
          .where((d) => (d['severity'] ?? 1) == 1)
          .length;
      setState(() {
        _diagnostics = diagnostics;
      });
      widget.onDiagnosticsChanged?.call(widget.filePath, errorCount);
      widget.onDiagnosticsDetailChanged?.call(widget.filePath, diagnostics);
    });

    _initLsp();
    _loadFile();
    _startFileWatcher();
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

    // Ctrl + K (Inline AI Edit)
    if (isModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyK &&
        !isShiftPressed &&
        widget.agentController != null) {
      openInlineEdit();
      return KeyEventResult.handled;
    }

    // Ctrl + / (Toggle Comment)
    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.slash) {
      _toggleComment();
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+E (Next Error)
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyE) {
      _goToNextError();
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+O (Go to Symbol in File)
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyO) {
      openDocumentSymbols();
      return KeyEventResult.handled;
    }

    // F2 (LSP Rename Symbol)
    if (!isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.f2) {
      renameSymbolAtCursor();
      return KeyEventResult.handled;
    }

    // Shift+F12 (LSP Find References)
    if (!isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.f12) {
      findReferencesAtCursor();
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
      if (_ghostText != null && _ghostText!.isNotEmpty) {
        _acceptGhostText();
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
      if (_ghostText != null || _signatureText != null) {
        _inlineCompletionService?.cancel();
        setState(() {
          _ghostText = null;
          _signatureText = null;
        });
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
    final prefix = _langSpec.lineCommentPrefix;

    int start = min(selection.baseIndex, selection.extentIndex);
    int end = max(selection.baseIndex, selection.extentIndex);

    bool allCommented = true;
    for (int i = start; i <= end; i++) {
      if (i < codeLines.length &&
          !codeLines[i].text.trim().startsWith(prefix)) {
        allCommented = false;
        break;
      }
    }

    final newLines = List<CodeLine>.generate(
      codeLines.length,
      (i) => codeLines[i],
    );
    for (int i = start; i <= end; i++) {
      if (i >= codeLines.length) continue;
      final lineText = codeLines[i].text;
      if (allCommented) {
        // Uncomment
        final index = lineText.indexOf(prefix);
        if (index != -1) {
          final before = lineText.substring(0, index);
          final after = lineText.substring(index + prefix.length);
          final newLine = after.startsWith(' ')
              ? before + after.substring(1)
              : before + after;
          newLines[i] = codeLines[i].copyWith(text: newLine);
        }
      } else {
        // Comment
        newLines[i] = codeLines[i].copyWith(text: '$prefix $lineText');
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

  void _goToNextError() {
    if (_controller == null || _diagnostics.isEmpty) return;

    final selection = _controller!.selection;
    final currentLine = selection.baseIndex;
    final currentCol = selection.baseOffset;

    final errors = _diagnostics
        .where((d) => d['range'] != null && (d['severity'] ?? 1) == 1)
        .toList()
      ..sort((a, b) {
        final aLine = a['range']['start']['line'] as int;
        final bLine = b['range']['start']['line'] as int;
        if (aLine != bLine) return aLine.compareTo(bLine);
        return (a['range']['start']['character'] as int)
            .compareTo(b['range']['start']['character'] as int);
      });

    if (errors.isEmpty) return;

    // Find next error after cursor (same line + after column, or later line)
    dynamic nextError;
    for (final err in errors) {
      final startLine = err['range']['start']['line'] as int;
      final startCol = err['range']['start']['character'] as int;
      if (startLine > currentLine ||
          (startLine == currentLine && startCol > currentCol)) {
        nextError = err;
        break;
      }
    }

    // Wrap to first error
    nextError ??= errors.first;

    final line = nextError['range']['start']['line'] as int;
    final col = nextError['range']['start']['character'] as int;
    jumpToLine(line, col);
  }

  Future<void> _initLsp() async {
    _langSpec = LanguageRegistry.detect(widget.filePath);
    if (!_langSpec.hasLsp) {
      _lspClient = null;
      return;
    }

    final client = await LspSessionManager.instance.getOrStartClient(
      projectRoot: widget.projectRoot,
      language: _langSpec,
    );
    if (!mounted) return;
    _lspClient = client;

    if (client != null && !client.isDisposed) {
      if (!_lspTrackedFiles.contains(widget.filePath)) {
        client.notifyFileOpened(
          widget.filePath,
          _fileContent,
          languageId: _langSpec.id,
        );
        _lspTrackedFiles.add(widget.filePath);
      }
      final existing = LspSessionManager.instance.diagnosticsForFile(
        widget.filePath,
      );
      if (existing.isNotEmpty) {
        setState(() => _diagnostics = existing);
      }
    }
  }

  void _startFileWatcher() {
    _fileWatchTimer?.cancel();
    _fileWatchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkFileChanged();
    });
  }

  Future<void> _checkFileChanged() async {
    if (!mounted || _controller == null) return;
    final file = File(widget.filePath);
    if (!await file.exists()) return;

    final stat = await file.stat();
    final diskModified = stat.modified;
    if (_lastDiskModified != null && diskModified == _lastDiskModified) return;
    _lastDiskModified = diskModified;

    final diskContent = await file.readAsString();
    if (diskContent == _lastDiskContent) return;

    final editorContent = _controller!.text;
    if (editorContent == _lastDiskContent) {
      // User hasn't modified the file — auto-reload from disk
      _lastDiskContent = diskContent;
      _reloadFromDisk(diskContent);
    } else {
      // User has local changes — silently track that disk changed,
      // but preserve the user's edits.
      _lastDiskContent = diskContent;
    }
  }

  void _reloadFromDisk(String content) {
    if (_controller == null || !mounted) return;
    final selection = _controller!.selection;
    _controller!.removeListener(_onTextChanged);
    _controller!.value = _controller!.value.copyWith(
      codeLines: CodeLines.fromText(content),
      selection: selection,
    );
    _fileContent = content;
    _controller!.addListener(_onTextChanged);
  }

  /// Immediately reloads the active file from disk (e.g. after an AI edit or checkpoint revert).
  Future<void> reloadFromDiskNow() async {
    if (!mounted || _controller == null) return;
    final file = File(widget.filePath);
    if (!await file.exists()) return;
    final stat = await file.stat();
    final diskContent = await file.readAsString();
    _lastDiskModified = stat.modified;
    _lastDiskContent = diskContent;
    _reloadFromDisk(diskContent);
  }

  /// Returns the currently selected text and 0-based line range, if any.
  ({String? selectedText, int startLine, int endLine}) getCurrentSelectionInfo() {
    if (_controller == null) {
      return (selectedText: null, startLine: 0, endLine: 0);
    }
    final sel = _controller!.selection;
    final startLine = sel.startIndex.clamp(0, _controller!.codeLines.length - 1);
    final endLine = sel.endIndex.clamp(0, _controller!.codeLines.length - 1);
    if (sel.isCollapsed) {
      return (selectedText: null, startLine: startLine, endLine: endLine);
    }
    final selected = _controller!.selectedText;
    return (selectedText: selected, startLine: startLine, endLine: endLine);
  }

  /// Inserts [code] at the current cursor / selection in the editor.
  void insertTextAtCursor(String code) {
    if (_controller == null) return;
    _controller!.replaceSelection(code);
    _focusNode.requestFocus();
  }

  /// Opens the Cursor-style Ctrl+K inline edit overlay for the selection or current line.
  void openInlineEdit() {
    if (_controller == null || widget.agentController == null) return;
    final sel = _controller!.selection;
    final totalLines = _controller!.codeLines.length;
    if (totalLines == 0) return;

    final startLine = (sel.startIndex < sel.endIndex ? sel.startIndex : sel.endIndex)
        .clamp(0, totalLines - 1);
    final endLine = (sel.startIndex > sel.endIndex ? sel.startIndex : sel.endIndex)
        .clamp(0, totalLines - 1);

    final targetLines = <String>[];
    for (var i = startLine; i <= endLine; i++) {
      targetLines.add(_controller!.codeLines[i].text);
    }

    setState(() {
      _inlineEditStartLine = startLine;
      _inlineEditEndLine = endLine;
      _inlineEditTargetText = targetLines.join('\n');
      _showInlineEdit = true;
    });
  }

  void _applyInlineEditReplacement(String replacementText) {
    if (_controller == null) return;
    final lines = _controller!.codeLines.toList();
    final start = _inlineEditStartLine.clamp(0, lines.length - 1);
    final end = _inlineEditEndLine.clamp(start, lines.length - 1);

    final newLines = <String>[
      for (var i = 0; i < start; i++) lines[i].text,
      ...replacementText.split('\n'),
      for (var i = end + 1; i < lines.length; i++) lines[i].text,
    ];

    _controller!.value = _controller!.value.copyWith(
      codeLines: CodeLines.fromText(newLines.join('\n')),
      selection: CodeLineSelection.collapsed(index: start, offset: 0),
    );
    setState(() => _showInlineEdit = false);
    _focusNode.requestFocus();
  }

  /// Opens the Go-to-Symbol dialog (`Ctrl+Shift+O`) backed by LSP documentSymbols.
  Future<void> openDocumentSymbols() async {
    if (_lspClient == null || _lspClient!.isDisposed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Document symbols require an active ${_langSpec.displayName} LSP server.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final raw = await _lspClient!.getDocumentSymbols(widget.filePath);
    if (!mounted) return;
    final entries = DocumentSymbolEntry.flatten(raw ?? const []);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No symbols found in this file.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await DocumentSymbolsDialog.show(
      context,
      symbols: entries,
      onSymbolSelected: jumpToLine,
    );
  }

  /// Renames the symbol under the cursor (`F2`) across workspace files via LSP.
  Future<void> renameSymbolAtCursor() async {
    if (_controller == null || _lspClient == null || _lspClient!.isDisposed) {
      return;
    }
    final sel = _controller!.selection;
    final line = sel.baseIndex;
    final col = sel.baseOffset;
    final lineText = line < _controller!.codeLines.length
        ? _controller!.codeLines[line].text
        : '';
    final currentWord = _extractWordAt(lineText, col);
    final nameCtrl = TextEditingController(text: currentWord);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(
          'Rename Symbol',
          style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(
            color: FyrTheme.textColor,
            fontSize: 13,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: InputDecoration(
            hintText: 'New identifier name',
            hintStyle: TextStyle(color: FyrTheme.textColorMuted),
            filled: true,
            fillColor: FyrTheme.bgColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor: FyrTheme.getContrastingColor(
                FyrTheme.accentColor,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (newName == null || newName.isEmpty || newName == currentWord) return;
    _syncLsp();
    final edit = await _lspClient!.renameSymbol(
      widget.filePath,
      line,
      col,
      newName,
    );
    if (edit != null) {
      await _applyWorkspaceEditAcrossFiles(edit);
    }
  }

  /// Finds all references (`Shift+F12`) via LSP and emits them to the BottomPanel.
  Future<void> findReferencesAtCursor() async {
    if (_controller == null || _lspClient == null || _lspClient!.isDisposed) {
      return;
    }
    _syncLsp();
    final sel = _controller!.selection;
    final line = sel.baseIndex;
    final col = sel.baseOffset;
    final lineText = line < _controller!.codeLines.length
        ? _controller!.codeLines[line].text
        : '';
    final symbolName = _extractWordAt(lineText, col);
    final raw = await _lspClient!.findReferences(widget.filePath, line, col);
    if (!mounted) return;

    final refs = <ReferenceLocation>[];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final uriStr =
            (item['uri'] ?? item['targetUri'])?.toString() ?? '';
        final range = item['range'] ?? item['targetSelectionRange'];
        if (uriStr.isEmpty || range is! Map) continue;
        final start = range['start'];
        if (start is! Map) continue;
        final refLine = (start['line'] as num?)?.toInt() ?? 0;
        final refCol = (start['character'] as num?)?.toInt() ?? 0;
        final refPath = uriStr.startsWith('file://')
            ? Uri.parse(uriStr).toFilePath()
            : uriStr;
        var preview = '';
        try {
          final lines = await File(refPath).readAsLines();
          if (refLine >= 0 && refLine < lines.length) {
            preview = lines[refLine].trim();
          }
        } catch (_) {}
        refs.add(
          ReferenceLocation(
            filePath: refPath,
            line: refLine,
            col: refCol,
            preview: preview,
          ),
        );
      }
    }
    widget.onShowReferences?.call(
      refs,
      symbolName.isEmpty ? 'symbol' : symbolName,
    );
  }

  Future<void> _applyWorkspaceEditAcrossFiles(
    Map<dynamic, dynamic> workspaceEdit,
  ) async {
    final activeUri = Uri.file(widget.filePath).toString();
    final perUriEdits = <String, List<dynamic>>{};
    final changes = workspaceEdit['changes'];
    if (changes is Map) {
      changes.forEach((uri, edits) {
        if (edits is List) {
          perUriEdits[uri.toString()] = edits;
        }
      });
    }
    final docChanges = workspaceEdit['documentChanges'];
    if (docChanges is List) {
      for (final change in docChanges.whereType<Map>()) {
        final doc = change['textDocument'];
        final edits = change['edits'];
        if (doc is Map && doc['uri'] != null && edits is List) {
          perUriEdits
              .putIfAbsent(doc['uri'].toString(), () => [])
              .addAll(edits);
        }
      }
    }

    for (final entry in perUriEdits.entries) {
      if (entry.key == activeUri) {
        _applyLspEdits({'changes': {activeUri: entry.value}});
        _markDirtyIfNeeded();
      } else if (entry.key.startsWith('file://')) {
        try {
          final targetPath = Uri.parse(entry.key).toFilePath();
          final file = File(targetPath);
          if (!await file.exists()) continue;
          var text = (await file.readAsString()).replaceAll('\r\n', '\n');
          final lines = text.split('\n');
          final lineStarts = <int>[];
          var acc = 0;
          for (final l in lines) {
            lineStarts.add(acc);
            acc += l.length + 1;
          }
          int offsetFor(int l, int c) {
            if (l < 0) return 0;
            if (l >= lineStarts.length) return text.length;
            return (lineStarts[l] + c).clamp(0, text.length);
          }

          final sorted = List<dynamic>.from(entry.value)
            ..sort((a, b) {
              final as = a['range']['start'];
              final bs = b['range']['start'];
              final lineCmp = (bs['line'] as int).compareTo(as['line'] as int);
              if (lineCmp != 0) return lineCmp;
              return (bs['character'] as int).compareTo(as['character'] as int);
            });
          for (final ed in sorted) {
            final start = ed['range']['start'];
            final end = ed['range']['end'];
            final sOff = offsetFor(start['line'] as int, start['character'] as int);
            final eOff = offsetFor(end['line'] as int, end['character'] as int);
            text = text.replaceRange(sOff, eOff, ed['newText'].toString());
          }
          await file.writeAsString(text);
          openFilesCache.remove(targetPath);
        } catch (e) {
          debugPrint('WorkspaceEdit write error for ${entry.key}: $e');
        }
      }
    }
  }

  static String _extractWordAt(String lineText, int col) {
    if (lineText.isEmpty) return '';
    final idx = col.clamp(0, lineText.length);
    var start = idx;
    var end = idx;
    final wordRe = RegExp(r'[a-zA-Z0-9_]');
    while (start > 0 && wordRe.hasMatch(lineText[start - 1])) {
      start--;
    }
    while (end < lineText.length && wordRe.hasMatch(lineText[end])) {
      end++;
    }
    return lineText.substring(start, end);
  }

  Future<void> _triggerSignatureHelp(int line, int col) async {
    if (_lspClient == null || _lspClient!.isDisposed) return;
    final res = await _lspClient!.getSignatureHelp(widget.filePath, line, col);
    if (!mounted || res == null) return;
    final sigs = res['signatures'];
    if (sigs is! List || sigs.isEmpty) {
      if (_signatureText != null) setState(() => _signatureText = null);
      return;
    }
    final activeIdx = ((res['activeSignature'] as num?)?.toInt() ?? 0).clamp(
      0,
      sigs.length - 1,
    );
    final label = (sigs[activeIdx] as Map?)?['label']?.toString();
    if (mounted) {
      setState(() => _signatureText = label);
    }
  }

  void _scheduleGhostCompletion(int line, int col) {
    final service = _inlineCompletionService;
    final ctrl = widget.agentController;
    if (service == null || ctrl == null || _controller == null) return;
    if (!ctrl.hasApiKey) return;

    final requestVersion = _documentVersion;
    _ghostTimer = Timer(const Duration(milliseconds: 550), () async {
      if (!mounted || _documentVersion != requestVersion || _controller == null) {
        return;
      }
      final flatOffset = _getFlatOffset(line, col);
      final full = _controller!.text;
      if (flatOffset < 0 || flatOffset > full.length) return;
      final prefixStart = max(0, flatOffset - 1500);
      final suffixEnd = min(full.length, flatOffset + 500);
      final prefix = full.substring(prefixStart, flatOffset);
      final suffix = full.substring(flatOffset, suffixEnd);

      final suggestion = await service.completeAtCursor(
        config: ctrl.config,
        filePath: widget.filePath,
        languageId: _langSpec.id,
        prefix: prefix,
        suffix: suffix,
      );
      if (!mounted || _documentVersion != requestVersion) return;
      if (suggestion == null || suggestion.isEmpty) return;
      setState(() {
        _ghostText = suggestion;
        _ghostLine = line;
        _ghostCol = col;
      });
    });
  }

  void _acceptGhostText() {
    final ghost = _ghostText;
    if (ghost == null || ghost.isEmpty || _controller == null) return;
    setState(() => _ghostText = null);
    _controller!.replaceSelection(ghost);
    _focusNode.requestFocus();
  }

  Offset _cursorOverlayCoords(int line, int col) {
    double gutterWidth = 56.0;
    double topOffset = 0.0;
    if (_gutterKey.currentContext != null) {
      final box = _gutterKey.currentContext!.findRenderObject() as RenderBox?;
      final editorBox = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        gutterWidth = box.size.width;
      }
      if (box != null &&
          editorBox != null &&
          box.attached &&
          editorBox.attached &&
          box.hasSize &&
          editorBox.hasSize) {
        try {
          topOffset =
              box.localToGlobal(Offset.zero).dy -
              editorBox.localToGlobal(Offset.zero).dy;
        } catch (_) {}
      }
    }
    final scrollX = _scrollController.horizontalScroller.hasClients
        ? _scrollController.horizontalScroller.offset
        : 0.0;
    final scrollY = _scrollController.verticalScroller.hasClients
        ? _scrollController.verticalScroller.offset
        : 0.0;
    final dx = gutterWidth + (col * _charWidth) - scrollX;
    final dy = (line * _lineHeight) - scrollY + topOffset;
    return Offset(dx, dy);
  }

  @override
  void didUpdateWidget(covariant CodeEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _saveCache(oldWidget.filePath);
      _ghostText = null;
      _signatureText = null;
      _lspPrompts = [];
      _diagnostics = LspSessionManager.instance.diagnosticsForFile(
        widget.filePath,
      );
      _langSpec = LanguageRegistry.detect(widget.filePath);
      _loadFile().then((_) => _initLsp());
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
    savedContentCache[path] = _savedContent;
  }

  void _markDirtyIfNeeded() {
    if (_controller == null) return;
    final dirtyNow = _controller!.text != _savedContent;
    if (dirtyNow != _isDirty) {
      _isDirty = dirtyNow;
      widget.onDirtyChanged?.call(widget.filePath, dirtyNow);
    }
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
        _savedContent = savedContentCache[widget.filePath] ?? content;
      } else {
        final file = File(widget.filePath);
        if (await file.exists()) {
          content = await file.readAsString();
          _lastDiskContent = content;
          _lastDiskModified = (await file.stat()).modified;
        } else {
          content = '// File not found';
        }
        content = content
            .replaceAll('\r\n', '\n')
            .replaceAll('\t', ' ' * widget.tabWidth);
        _savedContent = content;
        savedContentCache[widget.filePath] = content;
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
        _isDirty = content != _savedContent;
        _isLoading = false;
      });
      widget.onDirtyChanged?.call(widget.filePath, _isDirty);

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

    if (_langSpec.hasLsp &&
        _lspClient != null &&
        !_lspClient!.isDisposed &&
        !_lspTrackedFiles.contains(widget.filePath)) {
      _lspClient!.notifyFileOpened(
        widget.filePath,
        _fileContent,
        languageId: _langSpec.id,
      );
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

    // Snapshot current disk state for external-change detection
    final diskFile = File(widget.filePath);
    if (await diskFile.exists()) {
      _lastDiskModified = (await diskFile.stat()).modified;
      _lastDiskContent = await diskFile.readAsString();
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
    _markDirtyIfNeeded();
    if (_ghostText != null) {
      setState(() => _ghostText = null);
    }
    _ghostTimer?.cancel();
    _inlineCompletionService?.cancel();

    final isLspSupported =
        _langSpec.hasLsp && _lspClient != null && !_lspClient!.isDisposed;
    if (isLspSupported) {
      _lspSyncTimer?.cancel();
      _lspSyncTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          _lspClient?.notifyDidChange(
            widget.filePath,
            _fileContent,
            _documentVersion,
          );
        }
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

        if (isLspSupported &&
            (textBefore.endsWith('(') || textBefore.endsWith(','))) {
          _syncLsp();
          _triggerSignatureHelp(line, col);
        } else if (textBefore.endsWith(')') || textBefore.trim().isEmpty) {
          if (_signatureText != null && mounted) {
            setState(() => _signatureText = null);
          }
        }

        if (isLspSupported && (isJustDot || isTypingWord)) {
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

        final afterCursor = currentLineText.substring(col);
        if (widget.agentController?.config.inlineCompletionsEnabled == true &&
            afterCursor.trim().isEmpty &&
            textBefore.trim().isNotEmpty) {
          _scheduleGhostCompletion(line, col);
        }
      }
    } else {
      if (mounted) setState(() => _lspPrompts = []);
    }
  }

  void _syncLsp() {
    final isLspSupported =
        _langSpec.hasLsp && _lspClient != null && !_lspClient!.isDisposed;
    if (_controller == null || !isLspSupported) return;
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
      var appliedLspFormat = false;
      if (_langSpec.hasLsp && _lspClient != null && !_lspClient!.isDisposed) {
        try {
          final edits = await _lspClient!
              .format(widget.filePath)
              .timeout(const Duration(seconds: 2));
          if (edits != null && edits.isNotEmpty) {
            _applyLspEdits(edits);
            appliedLspFormat = true;
          }
        } catch (_) {}
      }

      final file = File(widget.filePath);
      await file.writeAsString(_controller!.text);

      final cliFormatter = _langSpec.cliFormatter;
      if (!appliedLspFormat && cliFormatter != null && cliFormatter.isNotEmpty) {
        final exe = await LanguageRegistry.findExecutable(cliFormatter.first);
        if (exe != null) {
          final args = [...cliFormatter.skip(1), widget.filePath];
          await Process.run(exe, args);
          final formatted = (await file.readAsString()).replaceAll('\r\n', '\n');
          if (formatted != _controller!.text) {
            final currentSelection = _controller!.selection;
            _controller!.value = _controller!.value.copyWith(
              codeLines: CodeLines.fromText(formatted),
              selection: currentSelection,
            );
            _fileContent = formatted;
          }
        }
      }

      _savedContent = _controller!.text;
      savedContentCache[widget.filePath] = _savedContent;
      _lastDiskContent = _savedContent;
      if (await file.exists()) {
        _lastDiskModified = (await file.stat()).modified;
      }
      _markDirtyIfNeeded();

      if (_langSpec.hasLsp && _lspClient != null && !_lspClient!.isDisposed) {
        _lspClient!.notifyDidSave(widget.filePath);
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
    final isLspSupported =
        _langSpec.hasLsp && _lspClient != null && !_lspClient!.isDisposed;
    if (_lspClient == null || _controller == null || !isLspSupported) return;

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
    _lspDiagnosticsSub?.cancel();
    _lspSyncTimer?.cancel();
    _autoSaveTimer?.cancel();
    _debounceCompletionTimer?.cancel();
    _ghostTimer?.cancel();
    _inlineCompletionService?.cancel();
    _fileWatchTimer?.cancel();
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
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                // Calculate line and column from the click position
                                final offset = details.localPosition;
                                
                                double gutterWidth = 56.0;
                                if (_gutterKey.currentContext != null) {
                                  final RenderBox? box = _gutterKey.currentContext!.findRenderObject() as RenderBox?;
                                  if (box != null && box.hasSize) {
                                    gutterWidth = box.size.width;
                                  }
                                }

                                final scrollX = _scrollController.horizontalScroller.hasClients ? _scrollController.horizontalScroller.offset : 0;
                                final scrollY = _scrollController.verticalScroller.hasClients ? _scrollController.verticalScroller.offset : 0;

                                // We need to account for the same topOffset as in hover
                                double topOffset = 0.0;
                                if (_gutterKey.currentContext != null) {
                                  final RenderBox? box = _gutterKey.currentContext!.findRenderObject() as RenderBox?;
                                  final RenderBox? editorBox = context.findRenderObject() as RenderBox?;
                                  if (box != null && editorBox != null && box.attached && editorBox.attached && box.hasSize && editorBox.hasSize) {
                                    try {
                                      final globalBox = box.localToGlobal(Offset.zero);
                                      final globalEditor = editorBox.localToGlobal(Offset.zero);
                                      topOffset = globalBox.dy - globalEditor.dy;
                                    } catch (_) {}
                                  }
                                }

                                final x = offset.dx - gutterWidth + scrollX;
                                final y = (offset.dy - topOffset) + scrollY;

                                final line = (y / _lineHeight).floor();
                                final col = (x / _charWidth).floor();

                                if (line >= 0 && line < _controller!.codeLines.length) {
                                  final lineText = _controller!.codeLines[line].text;
                                  final safeCol = col.clamp(0, lineText.length);
                                  
                                  setState(() {
                                    _controller!.selection = CodeLineSelection.collapsed(
                                      index: line,
                                      offset: safeCol,
                                    );
                                  });
                                  
                                  // The re_editor should now show the toolbar automatically 
                                  // because the selection changed via secondary tap.
                                  // If it doesn't, we might need more aggressive measures,
                                  // but this is the standard Flutter-friendly way.
                                }
                              },
                              child: CodeEditor(
                              padding: EdgeInsets.zero,
                              key: ValueKey(widget.filePath),
                              controller: _controller!,
                              focusNode: _focusNode,
                              scrollController: _scrollController,
                              findController: _findController,
                              toolbarController: LspSelectionToolbarController(
                        getCodeActions: (startLine, startCol, endLine, endCol, _) async {
                          // Filter diagnostics that overlap with the requested range
                          final relevantDiagnostics = _diagnostics.where((diag) {
                            final range = diag['range'];
                            if (range == null) return false;
                            final dStartLine = range['start']['line'] as int;
                            final dEndLine = range['end']['line'] as int;
                            // Simple line-based overlap check
                            return (dStartLine <= endLine && dEndLine >= startLine);
                          }).toList();

                          return await _lspClient?.getCodeActions(
                                widget.filePath,
                                startLine,
                                startCol,
                                endLine,
                                endCol,
                                diagnostics: relevantDiagnostics,
                              ) ??
                              [];
                        },
                        onCodeActionSelected: _handleCodeAction,
                        onAiEdit: widget.agentController != null
                            ? openInlineEdit
                            : null,
                        onAskAi: widget.onAskAiAboutSelection != null
                            ? () {
                                final info = getCurrentSelectionInfo();
                                final text = info.selectedText;
                                if (text != null && text.isNotEmpty) {
                                  widget.onAskAiAboutSelection!(
                                    text,
                                    info.startLine,
                                    info.endLine,
                                  );
                                }
                              }
                            : null,
                      ),
                          wordWrap: false,
                          style: CodeEditorStyle(
                            fontSize: widget.fontSize,
                            fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                            codeTheme: CodeHighlightTheme(
                              languages: _langSpec.highlightMode != null
                                  ? {
                                      _langSpec.highlightKey:
                                          CodeHighlightThemeMode(
                                        mode: _langSpec.highlightMode!,
                                      ),
                                    }
                                  : const {},
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
          if (_ghostText != null && _ghostText!.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _scrollController.verticalScroller,
                    _scrollController.horizontalScroller,
                  ]),
                  builder: (context, _) {
                    final coords = _cursorOverlayCoords(_ghostLine, _ghostCol);
                    return Stack(
                      children: [
                        Positioned(
                          left: coords.dx,
                          top: coords.dy,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ghostText!.split('\n').first,
                                style: _editorTextStyle.copyWith(
                                  color: FyrTheme.textColorMuted.withValues(
                                    alpha: 0.65,
                                  ),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: FyrTheme.cardColor.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: FyrTheme.dividerColor,
                                  ),
                                ),
                                child: Text(
                                  'Tab',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          if (_signatureText != null && _signatureText!.isNotEmpty)
            Positioned(
              left: 64,
              bottom: 14,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FyrTheme.dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _signatureText!,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: GoogleFonts.jetBrainsMono(
                            color: FyrTheme.textColor,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => setState(() => _signatureText = null),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showInlineEdit && widget.agentController != null)
            Positioned(
              top: 16,
              right: 24,
              child: InlineEditOverlay(
                agentController: widget.agentController!,
                filePath: widget.filePath,
                fullFileContent: _controller!.text,
                startLine: _inlineEditStartLine,
                endLine: _inlineEditEndLine,
                targetText: _inlineEditTargetText,
                onAccept: _applyInlineEditReplacement,
                onClose: () {
                  setState(() => _showInlineEdit = false);
                  _focusNode.requestFocus();
                },
                onOpenSettings: () {
                  AiSettingsDialog.show(context, widget.agentController!);
                },
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
