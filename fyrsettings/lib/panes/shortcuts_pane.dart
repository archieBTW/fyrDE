import 'dart:io';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

/// Represents a parsed Sway `bindsym` or `bindgesture` binding.
class SwayShortcutEntry {
  final String kind; // 'bindsym' or 'bindgesture'
  final String trigger; // e.g. '$mod+space' or 'swipe:3:down'
  final String action; // e.g. 'exec ~/.config/fyr/launcher_toggle.sh'
  final String sourceFile; // e.g. 'config' or '50-shortcuts.conf'
  final bool isCustom;

  const SwayShortcutEntry({
    required this.kind,
    required this.trigger,
    required this.action,
    required this.sourceFile,
    this.isCustom = false,
  });

  String get formattedTrigger => trigger
      .replaceAll('\$mod', 'Super')
      .replaceAll('Mod1', 'Alt')
      .replaceAll('+', ' + ');

  String toSwayLine() => '$kind $trigger $action';
}

/// Parses and persists Sway shortcuts in `~/.config/sway/conf.d/50-shortcuts.conf`.
class SwayShortcutStore {
  static const String dropInName = '50-shortcuts.conf';

  static List<SwayShortcutEntry> parseLines(
    String content, {
    required String sourceFile,
    required bool isCustom,
  }) {
    final entries = <SwayShortcutEntry>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(
        r'^(bindsym|bindgesture)\s+(?:--\S+\s+)*(\S+)\s+(.+)$',
      ).firstMatch(line);
      if (match != null) {
        entries.add(
          SwayShortcutEntry(
            kind: match.group(1)!,
            trigger: match.group(2)!,
            action: match.group(3)!.trim(),
            sourceFile: sourceFile,
            isCustom: isCustom,
          ),
        );
      }
    }
    return entries;
  }

  static Future<({
    List<SwayShortcutEntry> entries,
    List<String> unbinds,
  })> loadAll({String? homeOverride}) async {
    final basePath = SwayConfD.mainConfigPath(homeOverride: homeOverride);
    final entries = <SwayShortcutEntry>[];

    final baseFile = File(basePath);
    if (await baseFile.exists()) {
      entries.addAll(
        parseLines(
          await baseFile.readAsString(),
          sourceFile: 'config',
          isCustom: false,
        ),
      );
    }

    final confDir = Directory(SwayConfD.confDirPath(homeOverride: homeOverride));
    final unbinds = <String>[];
    if (await confDir.exists()) {
      final files = confDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.conf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final text = await file.readAsString();
        final isCustom = name == dropInName;
        if (isCustom) {
          for (final rawLine in text.split('\n')) {
            final line = rawLine.trim();
            if (line.startsWith('unbindsym ')) {
              unbinds.add(line.substring('unbindsym '.length).trim());
            }
          }
        }
        entries.addAll(
          parseLines(text, sourceFile: name, isCustom: isCustom),
        );
      }
    }

    final hiddenSet = unbinds.toSet();
    final filtered = entries
        .where((e) => e.isCustom || !hiddenSet.contains(e.trigger))
        .toList();

    return (entries: filtered, unbinds: unbinds);
  }

  static Future<void> saveCustomShortcuts(
    List<SwayShortcutEntry> customEntries, {
    List<String> unbinds = const [],
    String? homeOverride,
    bool reload = true,
  }) async {
    final buf = StringBuffer('# USER SHORTCUTS\n');
    for (final key in unbinds) {
      if (key.trim().isNotEmpty) {
        buf.writeln('unbindsym ${key.trim()}');
      }
    }
    for (final entry in customEntries) {
      buf.writeln(entry.toSwayLine());
    }
    buf.writeln('# END USER SHORTCUTS');

    await SwayConfD.writeDropIn(
      dropInName,
      buf.toString(),
      homeOverride: homeOverride,
      reload: reload,
    );
  }
}

class ShortcutsPane extends StatefulWidget {
  final Future<({List<SwayShortcutEntry> entries, List<String> unbinds})>
      Function()? loadOverride;
  final Future<void> Function(
    List<SwayShortcutEntry> custom,
    List<String> unbinds,
  )? saveOverride;

  const ShortcutsPane({
    super.key,
    this.loadOverride,
    this.saveOverride,
  });

  @override
  State<ShortcutsPane> createState() => _ShortcutsPaneState();
}

class _ShortcutsPaneState extends State<ShortcutsPane> {
  final TextEditingController _searchController = TextEditingController();
  List<SwayShortcutEntry> _entries = const [];
  List<String> _unbinds = const [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    try {
      final result = widget.loadOverride != null
          ? await widget.loadOverride!()
          : await SwayShortcutStore.loadAll();
      if (!mounted) return;
      setState(() {
        _entries = result.entries;
        _unbinds = result.unbinds;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistCustom(
    List<SwayShortcutEntry> customEntries,
    List<String> unbinds,
  ) async {
    if (widget.saveOverride != null) {
      await widget.saveOverride!(customEntries, unbinds);
    } else {
      await SwayShortcutStore.saveCustomShortcuts(
        customEntries,
        unbinds: unbinds,
        reload: true,
      );
    }
    await _loadShortcuts();
  }

  List<SwayShortcutEntry> get _customEntries =>
      _entries.where((e) => e.isCustom).toList();

  Future<void> _deleteCustomEntry(SwayShortcutEntry target) async {
    final nextCustom = List<SwayShortcutEntry>.from(_customEntries)
      ..removeWhere(
        (e) => e.kind == target.kind && e.trigger == target.trigger,
      );
    await _persistCustom(nextCustom, _unbinds);
  }

  Future<void> _showShortcutDialog({SwayShortcutEntry? editing}) async {
    String kind = editing?.kind ?? 'bindsym';
    final triggerCtrl = TextEditingController(
      text: editing?.trigger ?? '\$mod+',
    );
    final actionCtrl = TextEditingController(
      text: editing?.action ?? 'exec ',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text(
            editing == null ? 'Add Custom Shortcut' : 'Edit Shortcut',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: kind,
                  dropdownColor: FyrTheme.surfaceColor,
                  style: TextStyle(color: FyrTheme.textColor),
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'bindsym',
                      child: Text('Keyboard Shortcut (bindsym)'),
                    ),
                    DropdownMenuItem(
                      value: 'bindgesture',
                      child: Text('Trackpad Gesture (bindgesture)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => kind = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: triggerCtrl,
                  style: TextStyle(color: FyrTheme.textColor),
                  decoration: InputDecoration(
                    labelText: kind == 'bindsym'
                        ? 'Key Combo (e.g. \$mod+Shift+t)'
                        : 'Gesture (e.g. swipe:3:left)',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: actionCtrl,
                  style: TextStyle(color: FyrTheme.textColor),
                  decoration: InputDecoration(
                    labelText: 'Sway Command (e.g. exec /opt/fyrterm/fyrterm)',
                    labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  ),
                ),
              ],
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
              onPressed: () async {
                final trigger = triggerCtrl.text.trim();
                final action = actionCtrl.text.trim();
                if (trigger.isEmpty || action.isEmpty) return;

                final nextCustom = List<SwayShortcutEntry>.from(_customEntries);
                final nextUnbinds = List<String>.from(_unbinds);

                if (editing != null &&
                    !editing.isCustom &&
                    editing.kind == 'bindsym' &&
                    !nextUnbinds.contains(editing.trigger)) {
                  nextUnbinds.add(editing.trigger);
                }

                nextCustom.removeWhere(
                  (e) =>
                      e.kind == kind &&
                      (e.trigger == trigger ||
                          (editing != null &&
                              editing.isCustom &&
                              e.trigger == editing.trigger)),
                );
                nextCustom.add(
                  SwayShortcutEntry(
                    kind: kind,
                    trigger: trigger,
                    action: action,
                    sourceFile: SwayShortcutStore.dropInName,
                    isCustom: true,
                  ),
                );
                Navigator.pop(ctx);
                await _persistCustom(nextCustom, nextUnbinds);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  List<SwayShortcutEntry> get _filteredEntries {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries.where((e) {
      return e.trigger.toLowerCase().contains(q) ||
          e.formattedTrigger.toLowerCase().contains(q) ||
          e.action.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shortcuts & Gestures',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'View Sway keybindings and add persistent overrides in conf.d/50-shortcuts.conf',
                    style: TextStyle(
                      fontSize: 13,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: FyrTheme.getContrastingColor(
                  FyrTheme.accentColor,
                ),
              ),
              onPressed: () => _showShortcutDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Shortcut'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _query = val.trim()),
          style: TextStyle(color: FyrTheme.textColor),
          decoration: InputDecoration(
            hintText: 'Filter shortcuts or commands...',
            hintStyle: TextStyle(color: FyrTheme.textColorMuted),
            prefixIcon: Icon(Icons.search, color: FyrTheme.textColorMuted),
            filled: true,
            fillColor: FyrTheme.cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: FyrTheme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: FyrTheme.dividerColor),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
                  ? Center(
                      child: Text(
                        'No matching shortcuts found',
                        style: TextStyle(color: FyrTheme.textColorMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = visible[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: FyrTheme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: FyrTheme.dividerColor),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                entry.kind == 'bindgesture'
                                    ? Icons.gesture
                                    : Icons.keyboard,
                                size: 20,
                                color: entry.isCustom
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColorMuted,
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: FyrTheme.hoverColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  entry.formattedTrigger,
                                  style: TextStyle(
                                    color: FyrTheme.textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  entry.action,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (entry.isCustom) ...[
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: FyrTheme.accentColor.withOpacity(
                                      0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Custom',
                                    style: TextStyle(
                                      color: FyrTheme.accentColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              IconButton(
                                tooltip: entry.isCustom
                                    ? 'Edit Shortcut'
                                    : 'Override Shortcut',
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: FyrTheme.textColorMuted,
                                ),
                                onPressed: () =>
                                    _showShortcutDialog(editing: entry),
                              ),
                              if (entry.isCustom)
                                IconButton(
                                  tooltip: 'Remove Custom Shortcut',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _deleteCustomEntry(entry),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
