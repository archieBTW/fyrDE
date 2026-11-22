import 'dart:io';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        onKeyEvent: _handleKey,
        child: Container(
          decoration: BoxDecoration(
            color: FyrTheme.panelBgColor.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FyrTheme.cardColor, width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header + Search bar
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: FyrTheme.dividerColor),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.content_paste_rounded,
                          size: 18,
                          color: FyrTheme.accentColor,
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
                              fontSize: 14,
                            ),
                            cursorColor: FyrTheme.accentColor,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search clipboard history...',
                              hintStyle: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: FyrTheme.textColorMuted,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                                _selectedIndex = 0;
                              });
                              _searchFocusNode.requestFocus();
                            },
                          ),
                        Tooltip(
                          message: 'Clear unpinned items',
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            icon: Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                              color: FyrTheme.textColorMuted,
                            ),
                            onPressed: () => _store.clearUnpinned(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                          'Enter to copy',
                          style: TextStyle(
                            fontSize: 10,
                            color: FyrTheme.textColorMuted.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
                      padding: const EdgeInsets.all(10),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final entry = items[index];
                        final isSelected = index == safeSelected;
                        return _ClipboardItemCard(
                          entry: entry,
                          isSelected: isSelected,
                          relativeTime: _formatRelativeTime(entry.timestamp),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? FyrTheme.accentColor.withValues(alpha: 0.22)
              : FyrTheme.cardColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? FyrTheme.accentColor
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _ClipboardItemCard extends StatelessWidget {
  final ClipboardEntry entry;
  final bool isSelected;
  final String relativeTime;
  final String sizeLabel;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _ClipboardItemCard({
    required this.entry,
    required this.isSelected,
    required this.relativeTime,
    required this.sizeLabel,
    required this.onTap,
    required this.onHover,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : FyrTheme.cardColor.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? FyrTheme.accentColor.withValues(alpha: 0.75)
                  : FyrTheme.dividerColor,
            ),
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
                        borderRadius: BorderRadius.circular(8),
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
                          height: 1.35,
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
                          color: FyrTheme.textColorMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.type == ClipboardEntryType.image
                              ? 'Image • $sizeLabel'
                              : '${entry.text.length} chars',
                          style: TextStyle(
                            fontSize: 10,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          relativeTime,
                          style: TextStyle(
                            fontSize: 10,
                            color: FyrTheme.textColorMuted.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                        if (entry.pinned) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.push_pin,
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
                      entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 15,
                      color: entry.pinned
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
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
                      Icons.close,
                      size: 15,
                      color: FyrTheme.textColorMuted,
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
