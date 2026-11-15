import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

import 'fyr_theme.dart';

/// Fuzzy file switcher dialog (`Ctrl+P`).
class QuickOpenDialog extends StatefulWidget {
  final String projectRoot;
  final List<String> openFiles;
  final Future<List<String>> Function() loadWorkspaceFiles;
  final void Function(String absolutePath) onFileSelected;

  const QuickOpenDialog({
    super.key,
    required this.projectRoot,
    required this.openFiles,
    required this.loadWorkspaceFiles,
    required this.onFileSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String projectRoot,
    required List<String> openFiles,
    required Future<List<String>> Function() loadWorkspaceFiles,
    required void Function(String absolutePath) onFileSelected,
  }) {
    return showDialog(
      context: context,
      builder: (_) => QuickOpenDialog(
        projectRoot: projectRoot,
        openFiles: openFiles,
        loadWorkspaceFiles: loadWorkspaceFiles,
        onFileSelected: onFileSelected,
      ),
    );
  }

  @override
  State<QuickOpenDialog> createState() => _QuickOpenDialogState();
}

class _QuickOpenDialogState extends State<QuickOpenDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _allFiles = [];
  bool _loading = true;
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _load() async {
    final files = await widget.loadWorkspaceFiles();
    if (!mounted) return;
    final openRel = widget.openFiles
        .map((f) => p.relative(f, from: widget.projectRoot))
        .toSet();
    final sorted = [
      ...files.where(openRel.contains),
      ...files.where((f) => !openRel.contains(f)),
    ];
    setState(() {
      _allFiles = sorted;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _allFiles.take(50).toList();
    return _allFiles
        .where((f) => _fuzzyMatches(f.toLowerCase(), q))
        .take(50)
        .toList();
  }

  static bool _fuzzyMatches(String candidate, String query) {
    if (candidate.contains(query)) return true;
    var qi = 0;
    for (var i = 0; i < candidate.length && qi < query.length; i++) {
      if (candidate[i] == query[qi]) qi++;
    }
    return qi == query.length;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final safeIdx = items.isEmpty ? 0 : _selectedIdx.clamp(0, items.length - 1);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, left: 24, right: 24),
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 560,
        height: 400,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                items.isNotEmpty) {
              setState(() => _selectedIdx = (safeIdx + 1) % items.length);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                items.isNotEmpty) {
              setState(
                () =>
                    _selectedIdx = (safeIdx - 1 + items.length) % items.length,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                items.isNotEmpty) {
              final chosen = items[safeIdx];
              Navigator.pop(context);
              widget.onFileSelected(p.join(widget.projectRoot, chosen));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _queryCtrl,
                  focusNode: _focusNode,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                  ),
                  onChanged: (_) => setState(() => _selectedIdx = 0),
                  decoration: InputDecoration(
                    hintText: 'Quick Open file by name...',
                    hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                    prefixIcon: Icon(
                      Icons.insert_drive_file_outlined,
                      size: 18,
                      color: FyrTheme.accentColor,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: FyrTheme.bgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.accentColor),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: FyrTheme.dividerColor),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? Center(
                            child: Text(
                              'No matching files',
                              style: TextStyle(color: FyrTheme.textColorMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (ctx, idx) {
                              final rel = items[idx];
                              final selected = idx == safeIdx;
                              return InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                  widget.onFileSelected(
                                    p.join(widget.projectRoot, rel),
                                  );
                                },
                                child: Container(
                                  color: selected
                                      ? FyrTheme.accentColor.withValues(
                                          alpha: 0.16,
                                        )
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.description_outlined,
                                        size: 15,
                                        color: selected
                                            ? FyrTheme.accentColor
                                            : FyrTheme.textColorMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        p.basename(rel),
                                        style: GoogleFonts.jetBrainsMono(
                                          color: FyrTheme.textColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p.dirname(rel) == '.'
                                              ? ''
                                              : p.dirname(rel),
                                          overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ),
    );
  }
}

class PaletteCommand {
  final String title;
  final String category;
  final String? shortcut;
  final IconData icon;
  final VoidCallback onExecute;

  const PaletteCommand({
    required this.title,
    required this.category,
    this.shortcut,
    required this.icon,
    required this.onExecute,
  });
}

/// Command Palette (`Ctrl+Shift+P`).
class CommandPaletteDialog extends StatefulWidget {
  final List<PaletteCommand> commands;

  const CommandPaletteDialog({super.key, required this.commands});

  static Future<void> show(
    BuildContext context,
    List<PaletteCommand> commands,
  ) {
    return showDialog(
      context: context,
      builder: (_) => CommandPaletteDialog(commands: commands),
    );
  }

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<PaletteCommand> get _filtered {
    final q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.commands;
    return widget.commands
        .where(
          (c) =>
              c.title.toLowerCase().contains(q) ||
              c.category.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final safeIdx = items.isEmpty ? 0 : _selectedIdx.clamp(0, items.length - 1);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, left: 24, right: 24),
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 560,
        height: 400,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                items.isNotEmpty) {
              setState(() => _selectedIdx = (safeIdx + 1) % items.length);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                items.isNotEmpty) {
              setState(
                () =>
                    _selectedIdx = (safeIdx - 1 + items.length) % items.length,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                items.isNotEmpty) {
              final cmd = items[safeIdx];
              Navigator.pop(context);
              cmd.onExecute();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _queryCtrl,
                  focusNode: _focusNode,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                  ),
                  onChanged: (_) => setState(() => _selectedIdx = 0),
                  decoration: InputDecoration(
                    hintText: 'Type a command...',
                    hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                    prefixIcon: Icon(
                      Icons.terminal,
                      size: 18,
                      color: FyrTheme.accentColor,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: FyrTheme.bgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.accentColor),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: FyrTheme.dividerColor),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (ctx, idx) {
                    final cmd = items[idx];
                    final selected = idx == safeIdx;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        cmd.onExecute();
                      },
                      child: Container(
                        color: selected
                            ? FyrTheme.accentColor.withValues(alpha: 0.16)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cmd.icon,
                              size: 16,
                              color: selected
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColorMuted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${cmd.category}: ${cmd.title}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            if (cmd.shortcut != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: FyrTheme.bgColor,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: FyrTheme.dividerColor,
                                  ),
                                ),
                                child: Text(
                                  cmd.shortcut!,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 10.5,
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
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentSymbolEntry {
  final String name;
  final int kind;
  final int line;
  final int col;
  final int depth;

  const DocumentSymbolEntry({
    required this.name,
    required this.kind,
    required this.line,
    required this.col,
    this.depth = 0,
  });

  static List<DocumentSymbolEntry> flatten(
    List<dynamic> raw, {
    int depth = 0,
  }) {
    final out = <DocumentSymbolEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      final kind = (item['kind'] as int?) ?? 13;
      if (item['selectionRange'] is Map || item['range'] is Map) {
        final range =
            (item['selectionRange'] ?? item['range']) as Map<dynamic, dynamic>;
        final start = range['start'] as Map<dynamic, dynamic>?;
        out.add(
          DocumentSymbolEntry(
            name: name,
            kind: kind,
            line: (start?['line'] as int?) ?? 0,
            col: (start?['character'] as int?) ?? 0,
            depth: depth,
          ),
        );
        if (item['children'] is List) {
          out.addAll(flatten(item['children'] as List, depth: depth + 1));
        }
      } else if (item['location'] is Map) {
        final loc = item['location'] as Map<dynamic, dynamic>;
        final range = loc['range'] as Map<dynamic, dynamic>?;
        final start = range?['start'] as Map<dynamic, dynamic>?;
        out.add(
          DocumentSymbolEntry(
            name: name,
            kind: kind,
            line: (start?['line'] as int?) ?? 0,
            col: (start?['character'] as int?) ?? 0,
            depth: depth,
          ),
        );
      }
    }
    return out;
  }
}

/// Go to Symbol in File (`Ctrl+Shift+O`).
class DocumentSymbolsDialog extends StatefulWidget {
  final List<DocumentSymbolEntry> symbols;
  final void Function(int line, int col) onSymbolSelected;

  const DocumentSymbolsDialog({
    super.key,
    required this.symbols,
    required this.onSymbolSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<DocumentSymbolEntry> symbols,
    required void Function(int line, int col) onSymbolSelected,
  }) {
    return showDialog(
      context: context,
      builder: (_) => DocumentSymbolsDialog(
        symbols: symbols,
        onSymbolSelected: onSymbolSelected,
      ),
    );
  }

  @override
  State<DocumentSymbolsDialog> createState() => _DocumentSymbolsDialogState();
}

class _DocumentSymbolsDialogState extends State<DocumentSymbolsDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<DocumentSymbolEntry> get _filtered {
    final q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.symbols;
    return widget.symbols
        .where((s) => s.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final safeIdx = items.isEmpty ? 0 : _selectedIdx.clamp(0, items.length - 1);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, left: 24, right: 24),
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 520,
        height: 380,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                items.isNotEmpty) {
              setState(() => _selectedIdx = (safeIdx + 1) % items.length);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                items.isNotEmpty) {
              setState(
                () =>
                    _selectedIdx = (safeIdx - 1 + items.length) % items.length,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                items.isNotEmpty) {
              final chosen = items[safeIdx];
              Navigator.pop(context);
              widget.onSymbolSelected(chosen.line, chosen.col);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _queryCtrl,
                  focusNode: _focusNode,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                  ),
                  onChanged: (_) => setState(() => _selectedIdx = 0),
                  decoration: InputDecoration(
                    hintText: 'Go to Symbol in File...',
                    hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                    prefixIcon: Icon(
                      Icons.account_tree_outlined,
                      size: 18,
                      color: FyrTheme.accentColor,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: FyrTheme.bgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: FyrTheme.accentColor),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: FyrTheme.dividerColor),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No symbols found',
                          style: TextStyle(color: FyrTheme.textColorMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (ctx, idx) {
                          final sym = items[idx];
                          final selected = idx == safeIdx;
                          return InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              widget.onSymbolSelected(sym.line, sym.col);
                            },
                            child: Container(
                              color: selected
                                  ? FyrTheme.accentColor.withValues(alpha: 0.16)
                                  : Colors.transparent,
                              padding: EdgeInsets.fromLTRB(
                                12.0 + (sym.depth * 14.0),
                                7,
                                12,
                                7,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _iconForSymbolKind(sym.kind),
                                    size: 15,
                                    color: FyrTheme.accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      sym.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: FyrTheme.textColor,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'L${sym.line + 1}',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: FyrTheme.textColorMuted,
                                      fontSize: 11,
                                    ),
                                  ),
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
      ),
    );
  }

  static IconData _iconForSymbolKind(int kind) {
    return switch (kind) {
      5 || 23 => Icons.class_outlined,
      6 || 12 => Icons.functions,
      7 || 8 => Icons.data_object,
      10 || 22 => Icons.format_list_numbered,
      11 => Icons.integration_instructions_outlined,
      _ => Icons.code,
    };
  }
}
