import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // Added for tab styling
import 'package:fyrcode/file_tree.dart';
import 'package:fyrcode/code_editor_pane.dart';
import 'package:fyrcode/global_search_view.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
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
  late String _currentDirectory;

  bool _autoSave = false;
  bool _smartTabs = true;
  int _tabWidth = 2;
  double _fontSize = 14.0;

  final GlobalKey<CodeEditorPaneState> _editorKey =
      GlobalKey<CodeEditorPaneState>();

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.initialDirectory;
    _loadSettings();
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

  void _onFileSelected(String path) {
    setState(() {
      if (!_openFiles.contains(path)) {
        _openFiles.add(path);
      }
      _activeFile = path;
    });
  }

  void _closeTab(String path) {
    setState(() {
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

  Widget _buildTrafficLightButton(Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Icon(Icons.circle, color: color, size: 16),
    );
  }

  Future<void> _openFile() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
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
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _currentDirectory = selectedDirectory;
        _openFiles.clear();
        _activeFile = null;
      });
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
                          const Spacer(),
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
                        // Left Pane: File Tree
                        SizedBox(
                          width: 250,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: FileTree(
                              rootDirectory: _currentDirectory,
                              onFileSelected: _onFileSelected,
                            ),
                          ),
                        ),
                        // Vertical Divider
                        Container(width: 1, color: FyrTheme.dividerColor),
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
                                                onTap: () => _closeTab(path),
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
                                          'Select a file to edit',
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
                                        onNavigateToDefinition:
                                            _handleNavigateToDefinition,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
}
