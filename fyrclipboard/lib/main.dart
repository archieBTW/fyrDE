import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clipboard_store.dart';
import 'fyr_theme.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  runApp(FyrClipboardApp(initiallyVisible: args.contains('--show')));
}

class FyrClipboardApp extends StatelessWidget {
  final bool initiallyVisible;
  const FyrClipboardApp({super.key, this.initiallyVisible = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'fyrClipboard',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor),
        ),
        theme: ThemeData.light().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
        ),
        home: ClipboardOverlayScreen(initiallyVisible: initiallyVisible),
      ),
    );
  }
}

enum _ClipboardFilter { all, pinned, text, images }

class ClipboardOverlayScreen extends StatefulWidget {
  final bool initiallyVisible;
  final ClipboardStore? store;

  const ClipboardOverlayScreen({
    super.key,
    this.initiallyVisible = false,
    this.store,
  });

  @override
  State<ClipboardOverlayScreen> createState() => _ClipboardOverlayScreenState();
}

class _ClipboardOverlayScreenState extends State<ClipboardOverlayScreen> {
  late final ClipboardStore _store;
  late final bool _ownsStore;
  late final OverlayWindowController _overlayController;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  _ClipboardFilter _filter = _ClipboardFilter.all;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    _store = widget.store ?? ClipboardStore();
    _store.init(startWatcher: _ownsStore);

    _overlayController = OverlayWindowController(
      appName: 'fyrclipboard',
      onShow: () {
        if (!mounted) return;
        setState(() {
          _query = '';
          _searchController.clear();
          _selectedIndex = 0;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      },
      onHide: () {
        if (mounted) {
          _searchController.clear();
          setState(() {
            _query = '';
            _selectedIndex = 0;
          });
        }
      },
    );
    _overlayController.start(initiallyVisible: widget.initiallyVisible);
  }

  @override
  void dispose() {
    _overlayController.stop();
    if (_ownsStore) _store.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ClipboardEntry> _filteredEntries(List<ClipboardEntry> all) {
    final q = _query.trim().toLowerCase();
    return all.where((e) {
      switch (_filter) {
        case _ClipboardFilter.pinned:
          if (!e.pinned) return false;
          break;
        case _ClipboardFilter.text:
          if (e.type != ClipboardEntryType.text) return false;
          break;
        case _ClipboardFilter.images:
          if (e.type != ClipboardEntryType.image) return false;
          break;
        case _ClipboardFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      if (e.type == ClipboardEntryType.text) {
        return e.text.toLowerCase().contains(q);
      }
      return 'image png screenshot'.contains(q) ||
          (e.imagePath?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _selectEntry(ClipboardEntry entry) async {
    await _store.copyEntryToClipboard(entry);
    await _overlayController.hide();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final items = _filteredEntries(_store.entries.value);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _overlayController.hide();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (items.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % items.length;
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (items.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + items.length) % items.length;
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (items.isNotEmpty) {
        final idx = _selectedIndex.clamp(0, items.length - 1);
        _selectEntry(items[idx]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        HardwareKeyboard.instance.isShiftPressed) {
      if (items.isNotEmpty) {
        final idx = _selectedIndex.clamp(0, items.length - 1);
        _store.deleteEntry(items[idx].id);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _formatRelativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.isDark;
    final glassBg = isDark
        ? const Color(0xFF18171D).withValues(alpha: 0.60)
        : Colors.white.withValues(alpha: 0.72);
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.10);
    final searchFill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.05);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        onKeyEvent: _handleKey,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: glassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: rimColor, width: 1.0),
              ),
              child: Column(
                children: [
                  // Header + Search pill
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: searchFill,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 17,
                                      color: FyrTheme.textColorMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        autofocus: true,
                                        onChanged: (val) => setState(() {
                                          _query = val;
                                          _selectedIndex = 0;
                                        }),
                                        style: TextStyle(
                                          color: FyrTheme.textColor,
                                          fontSize: 13.5,
                                        ),
                                        cursorColor: FyrTheme.accentColor,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          hintText: 'Search clipboard...',
                                          hintStyle: TextStyle(
                                            color: FyrTheme.textColorMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_query.isNotEmpty)
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          _searchController.clear();
                                          setState(() {
                                            _query = '';
                                            _selectedIndex = 0;
                                          });
                                          _searchFocusNode.requestFocus();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 15,
                                            color: FyrTheme.textColorMuted,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Clear unpinned items',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _store.clearUnpinned(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: searchFill,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 17,
                                    color: FyrTheme.textColorMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _FilterChip(
                              label: 'All',
                              selected: _filter == _ClipboardFilter.all,
                              onTap: () => setState(() {
                                _filter = _ClipboardFilter.all;
                                _selectedIndex = 0;
                              }),
                            ),
                            const SizedBox(width: 6),
                            _FilterChip(
                              label: 'Pinned',
                              selected: _filter == _ClipboardFilter.pinned,
                              onTap: () => setState(() {
                                _filter = _ClipboardFilter.pinned;
                                _selectedIndex = 0;
                              }),
                            ),
                            const SizedBox(width: 6),
                            _FilterChip(
                              label: 'Text',
                              selected: _filter == _ClipboardFilter.text,
                              onTap: () => setState(() {
                                _filter = _ClipboardFilter.text;
                                _selectedIndex = 0;
                              }),
                            ),
                            const SizedBox(width: 6),
                            _FilterChip(
                              label: 'Images',
                              selected: _filter == _ClipboardFilter.images,
                              onTap: () => setState(() {
                                _filter = _ClipboardFilter.images;
                                _selectedIndex = 0;
                              }),
                            ),
                            const Spacer(),
                            Text(
                              '↵ Copy',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: FyrTheme.textColorMuted.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.07),
                  ),
                  // Entries list
                  Expanded(
                    child: ValueListenableBuilder<List<ClipboardEntry>>(
                      valueListenable: _store.entries,
                      builder: (context, allEntries, _) {
                        final items = _filteredEntries(allEntries);
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.content_paste_off_outlined,
                                  size: 36,
                                  color: FyrTheme.textColorMuted.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _query.isNotEmpty
                                      ? 'No matching clipboard items'
                                      : 'Clipboard history is empty',
                                  style: TextStyle(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final safeSelected =
                            _selectedIndex.clamp(0, items.length - 1);

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final entry = items[index];
                            final isHighlighted = index == safeSelected;
                            return _ClipboardItemCard(
                              entry: entry,
                              isHighlighted: isHighlighted,
                              relativeTime: _formatRelativeTime(
                                entry.timestamp,
                              ),
                              sizeLabel: _formatBytes(entry.byteSize),
                              onTap: () => _selectEntry(entry),
                              onHover: () {
                                if (_selectedIndex != index) {
                                  setState(() => _selectedIndex = index);
                                }
                              },
                              onPin: () => _store.togglePin(entry.id),
                              onDelete: () => _store.deleteEntry(entry.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.isDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: selected ? 0.10 : 0.04)
              : Colors.black.withValues(alpha: selected ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? FyrTheme.accentColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? FyrTheme.textColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _ClipboardItemCard extends StatelessWidget {
  final ClipboardEntry entry;
  final bool isHighlighted;
  final String relativeTime;
  final String sizeLabel;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _ClipboardItemCard({
    required this.entry,
    required this.isHighlighted,
    required this.relativeTime,
    required this.sizeLabel,
    required this.onTap,
    required this.onHover,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.isDark;
    final cardSurface = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.black.withValues(alpha: 0.04);
    final subtleBorder = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.07);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHighlighted ? FyrTheme.accentColor : subtleBorder,
              width: isHighlighted ? 1.6 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: FyrTheme.accentColor.withValues(alpha: 0.16),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.type == ClipboardEntryType.image &&
                        entry.imagePath != null &&
                        File(entry.imagePath!).existsSync())
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(entry.imagePath!),
                          height: 88,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          cacheWidth: 420,
                        ),
                      )
                    else
                      Text(
                        entry.text.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.38,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          entry.type == ClipboardEntryType.image
                              ? Icons.image_outlined
                              : Icons.notes_rounded,
                          size: 12,
                          color: FyrTheme.textColorMuted.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.type == ClipboardEntryType.image
                              ? 'Image • $sizeLabel'
                              : '${entry.text.length} chars',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: FyrTheme.textColorMuted.withValues(
                              alpha: 0.85,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          relativeTime,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: FyrTheme.textColorMuted.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        if (entry.pinned) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.push_pin_rounded,
                            size: 11,
                            color: FyrTheme.accentColor,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    tooltip: entry.pinned ? 'Unpin' : 'Pin',
                    icon: Icon(
                      entry.pinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 14,
                      color: entry.pinned
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted.withValues(
                              alpha: isHighlighted ? 0.9 : 0.55,
                            ),
                    ),
                    onPressed: onPin,
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    tooltip: 'Delete',
                    icon: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: FyrTheme.textColorMuted.withValues(
                        alpha: isHighlighted ? 0.9 : 0.55,
                      ),
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
