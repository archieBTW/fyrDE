import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // Added for tab styling
import 'package:fyrcode/bottom_panel.dart';
import 'package:fyrcode/file_tree.dart';
import 'package:fyrcode/code_editor_pane.dart';
import 'package:fyrcode/global_search_view.dart';
import 'package:fyrcode/language_support.dart';
import 'package:fyrcode/quick_open_dialog.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'ai/agent_controller.dart';
import 'ai/ai_agent_panel.dart';
import 'ai/ai_models.dart';
import 'ai/ai_settings_dialog.dart';
import 'fyr_theme.dart';

class EditorScreen extends StatefulWidget {
  final String initialDirectory;
  const EditorScreen({super.key, required this.initialDirectory});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // Replace single selected file with a list and an active tracker
  final List<String> _openFiles = [];
  String? _activeFile;

  bool _showGlobalSearch = false;
  bool _showFileTree = true;
  double _fileTreeWidth = 250.0;
  bool _showAiPanel = true;
  double _aiPanelWidth = 400.0;
  late String _currentDirectory;

  bool _autoSave = false;
  bool _smartTabs = true;
  int _tabWidth = 2;
  double _fontSize = 14.0;

  final Map<String, int> _fileErrorCounts = {};
  final Map<String, List<dynamic>> _fileDiagnosticsDetail = {};
  final Set<String> _dirtyFiles = {};

  bool _showBottomPanel = false;
  double _bottomPanelHeight = 230.0;
  BottomPanelTab _bottomPanelTab = BottomPanelTab.terminal;
  List<ReferenceLocation> _references = [];

  final GlobalKey<CodeEditorPaneState> _editorKey =
      GlobalKey<CodeEditorPaneState>();
  final GlobalKey<AiAgentPanelState> _aiPanelKey =
      GlobalKey<AiAgentPanelState>();
  late final AgentController _agentController;

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.initialDirectory;
    _agentController = AgentController(
      projectRoot: _currentDirectory,
      diagnosticsProvider: () => _fileDiagnosticsDetail,
      onFileMutated: _handleAiFileMutated,
      activeEditorContextProvider: _getActiveEditorContext,
    );
    _agentController.initialize();
    _loadSettings();
  }

  @override
  void dispose() {
    LspSessionManager.instance.disposeWorkspace(_currentDirectory);
    _agentController.dispose();
    super.dispose();
  }

  ActiveEditorContext _getActiveEditorContext() {
    final selInfo = _editorKey.currentState?.getCurrentSelectionInfo();
    return ActiveEditorContext(
      activeFile: _activeFile,
      openFiles: List<String>.from(_openFiles),
      selectedText: selInfo?.selectedText,
      selectionStartLine: selInfo?.startLine,
      selectionEndLine: selInfo?.endLine,
    );
  }

  Future<void> _handleAiFileMutated(
    String filePath, {
    bool deleted = false,
  }) async {
    if (deleted) {
      CodeEditorPaneState.openFilesCache.remove(filePath);
      if (mounted && _openFiles.contains(filePath)) {
        _closeTab(filePath);
      }
      return;
    }

    // Update cached tab content if inactive, and live-reload if active.
    if (CodeEditorPaneState.openFilesCache.containsKey(filePath)) {
      final f = File(filePath);
      if (await f.exists()) {
        final content = await f.readAsString();
        final prev = CodeEditorPaneState.openFilesCache[filePath]!;
        CodeEditorPaneState.openFilesCache[filePath] = FileStateCache(
          content: content,
          selection: prev.selection,
          scrollOffset: prev.scrollOffset,
          documentVersion: prev.documentVersion + 1,
        );
      }
    }

    if (mounted && _activeFile == filePath) {
      await _editorKey.currentState?.reloadFromDiskNow();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSave = prefs.getBool('autoSave') ?? false;
      _smartTabs = prefs.getBool('smartTabs') ?? true;
      _tabWidth = prefs.getInt('tabWidth') ?? 2;
      _fontSize = prefs.getDouble('fontSize') ?? 14.0;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (value is double) await prefs.setDouble(key, value);
  }

  Future<void> _handleNavigateToDefinition(
    String targetPath,
    int line,
    int col,
  ) async {
    String content;
    if (_activeFile == targetPath) {
      // FIX: Tell the existing editor pane to jump directly
      _editorKey.currentState?.jumpToLine(line, col);
      return;
    }
    // Check if we already have it in memory, otherwise read from disk
    if (CodeEditorPaneState.openFilesCache.containsKey(targetPath)) {
      content = CodeEditorPaneState.openFilesCache[targetPath]!.content;
    } else {
      final file = File(targetPath);
      if (await file.exists()) {
        content = await file.readAsString();
      } else {
        return; // Target file missing
      }
    }

    // Calculate exact string offset
    // Pre-calculate scroll offset so it opens near the definition
    final double lineHeight = _fontSize * 1.2;
    final double scrollOffset = (line * lineHeight) - 50.0;

    // Inject into the static cache
    CodeEditorPaneState.openFilesCache[targetPath] = FileStateCache(
      content: content,
      // Pass the row (index) and column (offset) directly to re_editor!
      selection: CodeLineSelection.collapsed(index: line, offset: col),
      scrollOffset: scrollOffset > 0 ? scrollOffset : 0,
      documentVersion: 1,
    );

    // Switch to the file (opening the tab if necessary)
    setState(() {
      if (!_openFiles.contains(targetPath)) {
        _openFiles.add(targetPath);
      }
      _activeFile = targetPath;
    });
  }

  void _onDiagnosticsChanged(String filePath, int errorCount) {
    setState(() {
      if (errorCount > 0) {
        _fileErrorCounts[filePath] = errorCount;
      } else {
        _fileErrorCounts.remove(filePath);
      }
    });
  }

  void _onDiagnosticsDetailChanged(String filePath, List<dynamic> diagnostics) {
    if (diagnostics.isEmpty) {
      _fileDiagnosticsDetail.remove(filePath);
    } else {
      _fileDiagnosticsDetail[filePath] = diagnostics;
    }
  }

  void _toggleAiPanel({ContextAttachment? attachSelection}) {
    setState(() {
      if (attachSelection != null) {
        _showAiPanel = true;
      } else {
        _showAiPanel = !_showAiPanel;
      }
    });
    if (_showAiPanel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _aiPanelKey.currentState?.focusInput(attachContext: attachSelection);
      });
    }
  }

  void _askAiAboutSelection(String selectedText, int startLine, int endLine) {
    final rel = _activeFile != null
        ? p.relative(_activeFile!, from: _currentDirectory)
        : 'editor';
    _toggleAiPanel(
      attachSelection: ContextAttachment(
        type: ContextAttachmentType.selection,
        label: '$rel (L${startLine + 1}-${endLine + 1})',
        path: _activeFile,
        startLine: startLine,
        endLine: endLine,
        content: selectedText,
      ),
    );
  }

  void _onFileSelected(String path) {
    setState(() {
      if (!_openFiles.contains(path)) {
        _openFiles.add(path);
      }
      _activeFile = path;
    });
  }

  void _onDirtyChanged(String filePath, bool isDirty) {
    if (!mounted) return;
    setState(() {
      if (isDirty) {
        _dirtyFiles.add(filePath);
      } else {
        _dirtyFiles.remove(filePath);
      }
    });
  }

  Future<void> _requestCloseTab(String path) async {
    if (_dirtyFiles.contains(path)) {
      final decision = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text(
            'Unsaved Changes',
            style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
          ),
          content: Text(
            'Save changes to ${p.basename(path)} before closing?',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(
                'Cancel',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text(
                'Discard',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: FyrTheme.getContrastingColor(
                  FyrTheme.accentColor,
                ),
              ),
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save & Close'),
            ),
          ],
        ),
      );
      if (decision == null || decision == 'cancel') return;
      if (decision == 'save') {
        if (_activeFile == path) {
          _editorKey.currentState?.save();
        } else {
          final cached = CodeEditorPaneState.openFilesCache[path]?.content;
          if (cached != null) {
            await File(path).writeAsString(cached);
          }
        }
      }
    }
    _closeTab(path);
  }

  void _closeTab(String path) {
    CodeEditorPaneState.openFilesCache.remove(path);
    CodeEditorPaneState.savedContentCache.remove(path);
    setState(() {
      _dirtyFiles.remove(path);
      final index = _openFiles.indexOf(path);
      _openFiles.remove(path);

      // If we closed the active tab, pick a new one to show
      if (_activeFile == path) {
        if (_openFiles.isNotEmpty) {
          // Default to the tab immediately to the left, or the first one
          _activeFile = _openFiles[index > 0 ? index - 1 : 0];
        } else {
          _activeFile = null;
        }
      }
    });
  }

  void _handleFileRenamed(String oldPath, String newPath) {
    setState(() {
      final idx = _openFiles.indexOf(oldPath);
      if (idx != -1) {
        _openFiles[idx] = newPath;
      }
      if (_activeFile == oldPath) {
        _activeFile = newPath;
      }
      if (_dirtyFiles.remove(oldPath)) {
        _dirtyFiles.add(newPath);
      }
      final errCount = _fileErrorCounts.remove(oldPath);
      if (errCount != null) _fileErrorCounts[newPath] = errCount;
      final diag = _fileDiagnosticsDetail.remove(oldPath);
      if (diag != null) _fileDiagnosticsDetail[newPath] = diag;
    });
    final cache = CodeEditorPaneState.openFilesCache.remove(oldPath);
    if (cache != null) {
      CodeEditorPaneState.openFilesCache[newPath] = cache;
    }
    final saved = CodeEditorPaneState.savedContentCache.remove(oldPath);
    if (saved != null) {
      CodeEditorPaneState.savedContentCache[newPath] = saved;
    }
  }

  void _handleFileDeleted(String deletedPath) {
    final matchingTabs = _openFiles
        .where(
          (f) => f == deletedPath || f.startsWith('$deletedPath${Platform.pathSeparator}'),
        )
        .toList();
    for (final tab in matchingTabs) {
      _closeTab(tab);
    }
    setState(() {
      _fileErrorCounts.removeWhere(
        (k, _) => k == deletedPath || k.startsWith('$deletedPath${Platform.pathSeparator}'),
      );
      _fileDiagnosticsDetail.removeWhere(
        (k, _) => k == deletedPath || k.startsWith('$deletedPath${Platform.pathSeparator}'),
      );
    });
  }

  Future<void> _openQuickOpen() async {
    await QuickOpenDialog.show(
      context,
      projectRoot: _currentDirectory,
      openFiles: List<String>.from(_openFiles),
      loadWorkspaceFiles: () => _agentController.getWorkspaceFiles(),
      onFileSelected: _onFileSelected,
    );
  }

  Future<void> _openCommandPalette() async {
    await CommandPaletteDialog.show(context, [
      PaletteCommand(
        title: 'Go to File...',
        category: 'File',
        shortcut: 'Ctrl+P',
        icon: Icons.insert_drive_file_outlined,
        onExecute: _openQuickOpen,
      ),
      PaletteCommand(
        title: 'Save Current File',
        category: 'File',
        shortcut: 'Ctrl+S',
        icon: Icons.save_outlined,
        onExecute: _save,
      ),
      PaletteCommand(
        title: 'Go to Symbol in File...',
        category: 'Navigation',
        shortcut: 'Ctrl+Shift+O',
        icon: Icons.account_tree_outlined,
        onExecute: () => _editorKey.currentState?.openDocumentSymbols(),
      ),
      PaletteCommand(
        title: 'Rename Symbol',
        category: 'LSP',
        shortcut: 'F2',
        icon: Icons.drive_file_rename_outline,
        onExecute: () => _editorKey.currentState?.renameSymbolAtCursor(),
      ),
      PaletteCommand(
        title: 'Find All References',
        category: 'LSP',
        shortcut: 'Shift+F12',
        icon: Icons.find_in_page_outlined,
        onExecute: () => _editorKey.currentState?.findReferencesAtCursor(),
      ),
      PaletteCommand(
        title: 'Toggle File Explorer',
        category: 'View',
        shortcut: 'Ctrl+B',
        icon: Icons.folder_outlined,
        onExecute: _toggleFileTree,
      ),
      PaletteCommand(
        title: 'Toggle Integrated Terminal',
        category: 'View',
        shortcut: 'Ctrl+`',
        icon: Icons.terminal,
        onExecute: () => _toggleBottomPanel(BottomPanelTab.terminal),
      ),
      PaletteCommand(
        title: 'Focus Problems Panel',
        category: 'View',
        icon: Icons.error_outline,
        onExecute: () => setState(() {
          _showBottomPanel = true;
          _bottomPanelTab = BottomPanelTab.problems;
        }),
      ),
      PaletteCommand(
        title: 'Toggle AI Agent Panel',
        category: 'AI',
        shortcut: 'Ctrl+L',
        icon: Icons.auto_awesome,
        onExecute: () => _toggleAiPanel(),
      ),
      PaletteCommand(
        title: 'Inline AI Edit at Cursor',
        category: 'AI',
        shortcut: 'Ctrl+K',
        icon: Icons.edit_note,
        onExecute: () => _editorKey.currentState?.openInlineEdit(),
      ),
      PaletteCommand(
        title: 'Find in Files (Global Search)',
        category: 'Search',
        shortcut: 'Ctrl+Shift+F',
        icon: Icons.search,
        onExecute: () => setState(() => _showGlobalSearch = true),
      ),
      PaletteCommand(
        title: 'AI & BYOK / MCP Settings...',
        category: 'Preferences',
        icon: Icons.tune,
        onExecute: () => AiSettingsDialog.show(context, _agentController),
      ),
      PaletteCommand(
        title: 'Editor Settings...',
        category: 'Preferences',
        icon: Icons.settings_outlined,
        onExecute: _showSettingsDialog,
      ),
    ]);
  }

  void _toggleFileTree() {
    setState(() => _showFileTree = !_showFileTree);
  }

  void _toggleBottomPanel([BottomPanelTab? tab]) {
    setState(() {
      if (tab != null && (!_showBottomPanel || _bottomPanelTab != tab)) {
        _showBottomPanel = true;
        _bottomPanelTab = tab;
      } else {
        _showBottomPanel = !_showBottomPanel;
      }
    });
  }

  void _handleShowReferences(List<ReferenceLocation> refs, String symbolName) {
    setState(() {
      _references = refs;
      _showBottomPanel = true;
      _bottomPanelTab = BottomPanelTab.references;
    });
  }

  Widget _buildTrafficLightButton(Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Icon(Icons.circle, color: color, size: 16),
    );
  }

  Future<String?> _pickFileOrDirectory({
    String? title,
    String? initialDirectory,
    bool pickDirectory = false,
  }) async {
    final home = Platform.environment['HOME'] ?? '';
    final fyrfilesCandidates = [
      if (home.isNotEmpty) p.join(home, '.local/bin/fyrfiles'),
      if (home.isNotEmpty) p.join(home, '.local/share/fyrDE/fyrfiles/fyrfiles'),
      '/usr/local/bin/fyrfiles',
      '/usr/bin/fyrfiles',
    ];

    String? fyrfilesPath;
    for (final c in fyrfilesCandidates) {
      if (File(c).existsSync()) {
        fyrfilesPath = c;
        break;
      }
    }

    if (fyrfilesPath != null) {
      try {
        final startDir = (initialDirectory != null && (Directory(initialDirectory).existsSync() || File(initialDirectory).existsSync()))
            ? (File(initialDirectory).existsSync() ? p.dirname(initialDirectory) : initialDirectory)
            : (home.isNotEmpty ? home : '.');

        final args = <String>['--picker'];
        if (title != null && title.isNotEmpty) {
          args.add('--title=$title');
        }
        args.add(startDir);

        final res = await Process.run(fyrfilesPath, args);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            final picked = out.split('\n').first.trim();
            if (pickDirectory) {
              if (Directory(picked).existsSync()) {
                return picked;
              } else if (File(picked).existsSync()) {
                return p.dirname(picked);
              }
            } else {
              if (File(picked).existsSync()) {
                return picked;
              }
            }
          }
        }
        return null;
      } catch (_) {}
    }

    try {
      if (pickDirectory) {
        return await FilePicker.getDirectoryPath(
          dialogTitle: title,
          initialDirectory: initialDirectory,
        );
      } else {
        final result = await FilePicker.pickFiles(
          dialogTitle: title,
          initialDirectory: initialDirectory,
        );
        if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
          return result.files.single.path;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _openFile() async {
    final path = await _pickFileOrDirectory(
      title: 'Open File',
      initialDirectory: _currentDirectory,
      pickDirectory: false,
    );
    if (path != null) {
      setState(() {
        if (!_openFiles.contains(path)) {
          _openFiles.add(path);
        }
        _activeFile = path;
        _currentDirectory = File(path).parent.absolute.path;
      });
    }
  }

  Future<void> _openFolder() async {
    String? selectedDirectory = await _pickFileOrDirectory(
      title: 'Open Folder',
      initialDirectory: _currentDirectory,
      pickDirectory: true,
    );
    if (selectedDirectory != null) {
      final oldDir = _currentDirectory;
      LspSessionManager.instance.disposeWorkspace(oldDir);
      setState(() {
        _currentDirectory = selectedDirectory;
        _openFiles.clear();
        _activeFile = null;
        _dirtyFiles.clear();
        _references = [];
        _fileErrorCounts.clear();
        _fileDiagnosticsDetail.clear();
      });
      await _agentController.setProjectRoot(selectedDirectory);
    }
  }

  void _save() {
    _editorKey.currentState?.save();
  }

  Future<void> _saveAs() async {
    if (_activeFile == null) return;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save As',
      fileName: _activeFile!.split(Platform.pathSeparator).last,
    );

    if (outputFile != null) {
      try {
        final content = await File(_activeFile!).readAsString();
        await File(outputFile).writeAsString(content);
        setState(() {
          final index = _openFiles.indexOf(_activeFile!);
          if (index != -1) {
            _openFiles[index] = outputFile;
          } else {
            _openFiles.add(outputFile);
          }
          _activeFile = outputFile;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved to new location')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Save As failed: $e')));
        }
      }
    }
  }

  // Settings dialog remains unchanged
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: FyrTheme.cardColor,
              title: Text(
                'Settings',
                style: TextStyle(color: FyrTheme.textColor),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: Text(
                        'Auto Save',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: _autoSave,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (val) {
                        setState(() => _autoSave = val);
                        setDialogState(() => _autoSave = val);
                        _saveSetting('autoSave', val);
                      },
                    ),
                    SwitchListTile(
                      title: Text(
                        'Smart Tabs',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Automatically manage indentation',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      value: _smartTabs,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (val) {
                        setState(() => _smartTabs = val);
                        setDialogState(() => _smartTabs = val);
                        _saveSetting('smartTabs', val);
                      },
                    ),
                    ListTile(
                      title: Text(
                        'Tab Width',
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: DropdownButton<int>(
                        value: _tabWidth,
                        dropdownColor: FyrTheme.bgColor,
                        style: TextStyle(color: Colors.white),
                        items: [2, 4, 8]
                            .map(
                              (w) => DropdownMenuItem(
                                value: w,
                                child: Text(w.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _tabWidth = val);
                            setDialogState(() => _tabWidth = val);
                            _saveSetting('tabWidth', val);
                          }
                        },
                      ),
                    ),
                    ListTile(
                      title: Text(
                        'Font Size',
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.remove,
                              color: FyrTheme.accentColor,
                            ),
                            onPressed: () {
                              if (_fontSize > 8) {
                                final newSize = _fontSize - 1;
                                setState(() => _fontSize = newSize);
                                setDialogState(() => _fontSize = newSize);
                                _saveSetting('fontSize', newSize);
                              }
                            },
                          ),
                          Text(
                            _fontSize.toInt().toString(),
                            style: TextStyle(color: Colors.white),
                          ),
                          IconButton(
                            icon: Icon(Icons.add, color: FyrTheme.accentColor),
                            onPressed: () {
                              if (_fontSize < 36) {
                                final newSize = _fontSize + 1;
                                setState(() => _fontSize = newSize);
                                setDialogState(() => _fontSize = newSize);
                                _saveSetting('fontSize', newSize);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: FyrTheme.accentColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FyrTheme.bgColor,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): () {
            setState(() => _showGlobalSearch = true);
          },
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            shift: true,
          ): () {
            setState(() => _showGlobalSearch = true);
          },
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            control: true,
          ): () => _toggleFileTree(),
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            meta: true,
          ): () => _toggleFileTree(),
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            control: true,
          ): () => _toggleAiPanel(),
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            meta: true,
          ): () => _toggleAiPanel(),
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            control: true,
          ): () => _openQuickOpen(),
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
          ): () => _openQuickOpen(),
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            control: true,
            shift: true,
          ): () => _openCommandPalette(),
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
            shift: true,
          ): () => _openCommandPalette(),
          const SingleActivator(
            LogicalKeyboardKey.backquote,
            control: true,
          ): () => _toggleBottomPanel(),
          const SingleActivator(
            LogicalKeyboardKey.backquote,
            meta: true,
          ): () => _toggleBottomPanel(),
          const SingleActivator(
            LogicalKeyboardKey.keyO,
            control: true,
            shift: true,
          ): () => _editorKey.currentState?.openDocumentSymbols(),
          const SingleActivator(
            LogicalKeyboardKey.keyO,
            meta: true,
            shift: true,
          ): () => _editorKey.currentState?.openDocumentSymbols(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Column(
                children: [
                  // Custom Window Bar
                  DragToMoveArea(
                    child: Container(
                      height: 40,
                      color: FyrTheme.cardColor,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          _buildTrafficLightButton(
                            Colors.red.shade300,
                            () async => await windowManager.close(),
                          ),
                          const SizedBox(width: 8),
                          _buildTrafficLightButton(
                            Colors.amber.shade300,
                            () async => await windowManager.minimize(),
                          ),
                          const SizedBox(width: 8),
                          _buildTrafficLightButton(
                            Colors.green.shade300,
                            () async {
                              if (await windowManager.isMaximized()) {
                                await windowManager.unmaximize();
                              } else {
                                await windowManager.maximize();
                              }
                            },
                          ),
                          const SizedBox(width: 20),
                          Text(
                            'FyrCode',
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'Toggle File Explorer (Ctrl+B)',
                            child: InkWell(
                              onTap: _toggleFileTree,
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _showFileTree
                                      ? FyrTheme.bgColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _showFileTree
                                        ? FyrTheme.dividerColor
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.view_sidebar_outlined,
                                      size: 13,
                                      color: _showFileTree
                                          ? FyrTheme.accentColor
                                          : FyrTheme.textColorMuted,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Files',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: _showFileTree
                                            ? FyrTheme.textColor
                                            : FyrTheme.textColorMuted,
                                        fontSize: 11.5,
                                        fontWeight: _showFileTree
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Toggle AI Agent Panel (Ctrl+L)',
                            child: InkWell(
                              onTap: () => _toggleAiPanel(),
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _showAiPanel
                                      ? FyrTheme.bgColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _showAiPanel
                                        ? FyrTheme.dividerColor
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 13,
                                      color: _showAiPanel
                                          ? FyrTheme.accentColor
                                          : FyrTheme.textColorMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Agent',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: _showAiPanel
                                            ? FyrTheme.textColor
                                            : FyrTheme.textColorMuted,
                                        fontSize: 11.5,
                                        fontWeight: _showAiPanel
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.menu, color: FyrTheme.textColor),
                            color: FyrTheme.bgColor,
                            onSelected: (value) {
                              switch (value) {
                                case 'open_file':
                                  _openFile();
                                  break;
                                case 'open_folder':
                                  _openFolder();
                                  break;
                                case 'save':
                                  _save();
                                  break;
                                case 'save_as':
                                  _saveAs();
                                  break;
                                case 'ai_settings':
                                  AiSettingsDialog.show(
                                    context,
                                    _agentController,
                                  );
                                  break;
                                case 'settings':
                                  _showSettingsDialog();
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'open_file',
                                child: Text(
                                  'Open File...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'open_folder',
                                child: Text(
                                  'Open Folder...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'save',
                                enabled: _activeFile != null,
                                child: Text(
                                  'Save',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'save_as',
                                enabled: _activeFile != null,
                                child: Text(
                                  'Save As...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'ai_settings',
                                child: Text(
                                  'AI & BYOK Providers...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'settings',
                                child: Text(
                                  'Settings...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Main Body
                  Expanded(
                    child: Row(
                      children: [
                        // Left Pane: Collapsible & Resizable File Tree
                        if (_showFileTree) ...[
                          SizedBox(
                            width: _fileTreeWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: FileTree(
                                rootDirectory: _currentDirectory,
                                onFileSelected: _onFileSelected,
                                fileErrorCounts: _fileErrorCounts,
                                onFileRenamed: _handleFileRenamed,
                                onFileDeleted: _handleFileDeleted,
                                onCollapse: _toggleFileTree,
                              ),
                            ),
                          ),
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragUpdate: (details) {
                                setState(() {
                                  _fileTreeWidth =
                                      (_fileTreeWidth + details.delta.dx).clamp(
                                        170.0,
                                        460.0,
                                      );
                                });
                              },
                              child: Container(
                                width: 4,
                                color: Colors.transparent,
                                child: Center(
                                  child: Container(
                                    width: 1,
                                    color: FyrTheme.dividerColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        // Right Pane: Tabs & Editor
                        Expanded(
                          child: Column(
                            children: [
                              // --- The New Tab Bar ---
                              if (_openFiles.isNotEmpty)
                                Container(
                                  height: 36,
                                  color: FyrTheme.cardColor,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _openFiles.length,
                                    itemBuilder: (context, index) {
                                      final path = _openFiles[index];
                                      final filename = path
                                          .split(Platform.pathSeparator)
                                          .last;
                                      final isActive = path == _activeFile;
                                      final isDirty = _dirtyFiles.contains(path);

                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _activeFile = path;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? FyrTheme.bgColor
                                                : FyrTheme.cardColor,
                                            border: Border(
                                              top: BorderSide(
                                                color: isActive
                                                    ? FyrTheme.accentColor
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                              right: BorderSide(
                                                color: FyrTheme.cardColor,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              if (isDirty) ...[
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  margin: const EdgeInsets.only(
                                                    right: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: FyrTheme.accentColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                              Text(
                                                filename,
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                      color: isActive
                                                          ? FyrTheme.textColor
                                                          : FyrTheme
                                                                .textColorMuted,
                                                      fontSize: 13,
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: () =>
                                                    _requestCloseTab(path),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 4.0,
                                                      ),
                                                  child: Icon(
                                                    Icons.close,
                                                    size: 14,
                                                    color: isActive
                                                        ? FyrTheme.textColor
                                                        : FyrTheme
                                                              .textColorMuted,
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

                              // --- The Editor ---
                              Expanded(
                                child: _activeFile == null
                                    ? Center(
                                        child: Text(
                                          'Select a file to edit  •  Ctrl+P Quick Open  •  Ctrl+Shift+P Commands',
                                          style: TextStyle(
                                            color: FyrTheme.textColorMuted,
                                          ),
                                        ),
                                      )
                                    : CodeEditorPane(
                                        key: _editorKey,
                                        filePath: _activeFile!,
                                        projectRoot: _currentDirectory,
                                        autoSave: _autoSave,
                                        smartTabs: _smartTabs,
                                        tabWidth: _tabWidth,
                                        fontSize: _fontSize,
                                        agentController: _agentController,
                                        onNavigateToDefinition:
                                            _handleNavigateToDefinition,
                                        onDiagnosticsChanged:
                                            _onDiagnosticsChanged,
                                        onDiagnosticsDetailChanged:
                                            _onDiagnosticsDetailChanged,
                                        onAskAiAboutSelection:
                                            _askAiAboutSelection,
                                        onDirtyChanged: _onDirtyChanged,
                                        onShowReferences: _handleShowReferences,
                                      ),
                              ),
                              if (_showBottomPanel) ...[
                                MouseRegion(
                                  cursor: SystemMouseCursors.resizeUpDown,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onVerticalDragUpdate: (details) {
                                      setState(() {
                                        _bottomPanelHeight =
                                            (_bottomPanelHeight -
                                                    details.delta.dy)
                                                .clamp(120.0, 480.0);
                                      });
                                    },
                                    child: Container(
                                      height: 4,
                                      color: Colors.transparent,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Container(
                                          height: 1,
                                          color: FyrTheme.dividerColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: _bottomPanelHeight,
                                  child: BottomPanel(
                                    projectRoot: _currentDirectory,
                                    activeTab: _bottomPanelTab,
                                    onTabChanged: (t) =>
                                        setState(() => _bottomPanelTab = t),
                                    onClose: () => setState(
                                      () => _showBottomPanel = false,
                                    ),
                                    diagnosticsByFile: _fileDiagnosticsDetail,
                                    references: _references,
                                    onNavigate: (path, line, col) =>
                                        _handleNavigateToDefinition(
                                          path,
                                          line,
                                          col,
                                        ),
                                    onAskAi: (prompt) {
                                      setState(() => _showAiPanel = true);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            _aiPanelKey.currentState
                                                ?.sendQuickPrompt(prompt);
                                          });
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_showAiPanel) ...[
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragUpdate: (details) {
                                setState(() {
                                  _aiPanelWidth =
                                      (_aiPanelWidth - details.delta.dx).clamp(
                                        320.0,
                                        700.0,
                                      );
                                });
                              },
                              child: Container(
                                width: 4,
                                color: Colors.transparent,
                                child: Center(
                                  child: Container(
                                    width: 1,
                                    color: FyrTheme.dividerColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _aiPanelWidth,
                            child: AiAgentPanel(
                              key: _aiPanelKey,
                              controller: _agentController,
                              onClose: () =>
                                  setState(() => _showAiPanel = false),
                              onOpenFile: (path) => _onFileSelected(path),
                              onInsertCode: (code, _) {
                                if (_activeFile != null) {
                                  _editorKey.currentState
                                      ?.insertTextAtCursor(code);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStatusBar(),
                ],
              ),
              if (_showGlobalSearch)
                Container(
                  color: Colors.black54,
                  child: GlobalSearchView(
                    projectRoot: _currentDirectory,
                    onClose: () => setState(() => _showGlobalSearch = false),
                    onResultSelected: (path, line) {
                      setState(() => _showGlobalSearch = false);
                      _handleNavigateToDefinition(path, line, 0);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final totalErrors = _fileErrorCounts.values.fold<int>(0, (a, b) => a + b);
    final relFile = _activeFile != null
        ? p.relative(_activeFile!, from: _currentDirectory)
        : p.basename(_currentDirectory);
    final activeLang = _activeFile != null
        ? LanguageRegistry.detect(_activeFile!).displayName
        : null;

    return AnimatedBuilder(
      animation: _agentController,
      builder: (context, _) {
        final modelName = _agentController.activeModel.displayName;
        final isRunning = _agentController.isRunning;
        final hasKey = _agentController.hasApiKey;

        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Text(
                relFile,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11,
                ),
              ),
              if (activeLang != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.bgColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    activeLang,
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.accentColor,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _toggleBottomPanel(BottomPanelTab.terminal),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal,
                      size: 12,
                      color: _showBottomPanel &&
                              _bottomPanelTab == BottomPanelTab.terminal
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Terminal',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => _toggleBottomPanel(BottomPanelTab.problems),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 13,
                      color: totalErrors > 0
                          ? Colors.redAccent
                          : FyrTheme.textColorMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$totalErrors problem${totalErrors == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: totalErrors > 0
                            ? Colors.redAccent
                            : FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalErrors > 0) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() => _showAiPanel = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _aiPanelKey.currentState?.sendQuickPrompt(
                        'Inspect @problems and fix the $totalErrors error(s).',
                      );
                    });
                  },
                  child: Text(
                    '• Fix with AI',
                    style: TextStyle(
                      color: FyrTheme.accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'Ctrl+P Open • Ctrl+Shift+P Cmds • Ctrl+` Term • Ctrl+L AI',
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 10.5),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () => _toggleAiPanel(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: isRunning
                          ? FyrTheme.accentColor
                          : (hasKey ? Colors.greenAccent : Colors.orangeAccent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? '$modelName • Running...' : modelName,
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
