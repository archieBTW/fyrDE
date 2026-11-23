import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browser_models.dart';
import 'fyr_theme.dart';

class UrlSuggestion {
  final String title;
  final String url;
  final bool isBookmark;

  const UrlSuggestion({
    required this.title,
    required this.url,
    required this.isBookmark,
  });
}

/// Builds ranked autocomplete suggestions from bookmarks and browsing history.
List<UrlSuggestion> buildUrlSuggestions({
  required String query,
  required List<Map<String, String>> bookmarks,
  required List<Map<String, String>> history,
  String? currentUrl,
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  final currentLower = (currentUrl ?? '').trim().toLowerCase();
  final showRecent = q.isEmpty || (currentLower.isNotEmpty && q == currentLower);

  final seen = <String>{};
  final primary = <UrlSuggestion>[];
  final secondary = <UrlSuggestion>[];

  void addFrom(List<Map<String, String>> source, {required bool isBookmark}) {
    for (final item in source) {
      final url = (item['url'] ?? '').trim();
      final title = (item['title'] ?? '').trim();
      if (url.isEmpty || isInternalUrl(url) || seen.contains(url)) continue;

      final urlLower = url.toLowerCase();
      final titleLower = title.toLowerCase();
      if (showRecent) {
        if (urlLower == currentLower) continue;
        seen.add(url);
        primary.add(
          UrlSuggestion(title: title, url: url, isBookmark: isBookmark),
        );
      } else if (urlLower.contains(q) || titleLower.contains(q)) {
        seen.add(url);
        final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
        final isPrefix = host.startsWith(q) ||
            host.replaceFirst('www.', '').startsWith(q) ||
            titleLower.startsWith(q);
        final entry =
            UrlSuggestion(title: title, url: url, isBookmark: isBookmark);
        if (isPrefix) {
          primary.add(entry);
        } else {
          secondary.add(entry);
        }
      }
      if (primary.length + secondary.length >= limit * 2) break;
    }
  }

  addFrom(bookmarks, isBookmark: true);
  addFrom(history, isBookmark: false);

  final combined = [...primary, ...secondary];
  if (combined.length > limit) {
    return combined.sublist(0, limit);
  }
  return combined;
}

class FyrUrlBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String currentUrl;
  final String searchEngineLabel;
  final bool isError;
  final bool isBookmarked;
  final bool showInstallPwa;
  final List<Map<String, String>> bookmarks;
  final List<Map<String, String>> history;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onFocusGained;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onInstallPwa;

  const FyrUrlBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.currentUrl,
    required this.searchEngineLabel,
    required this.isError,
    required this.isBookmarked,
    required this.showInstallPwa,
    required this.bookmarks,
    required this.history,
    required this.onSubmit,
    this.onFocusGained,
    this.onToggleBookmark,
    this.onInstallPwa,
  });

  @override
  State<FyrUrlBar> createState() => _FyrUrlBarState();
}

class _FyrUrlBarState extends State<FyrUrlBar> {
  final LayerLink _urlBarLink = LayerLink();
  final GlobalKey _urlBarKey = GlobalKey();
  final Object _tapRegionGroupId = Object();

  OverlayEntry? _autocompleteOverlay;
  List<UrlSuggestion> _suggestions = const [];
  int _selectedIndex = -1;
  bool _suppressTextListener = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _handleKeyEvent;
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant FyrUrlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      oldWidget.focusNode.onKeyEvent = null;
      widget.focusNode.onKeyEvent = _handleKeyEvent;
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode.onKeyEvent == _handleKeyEvent) {
      widget.focusNode.onKeyEvent = null;
    }
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.focusNode.hasFocus) {
      widget.onFocusGained?.call();
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
      _refreshSuggestions(resetSelection: true);
    } else {
      _removeOverlay();
      if (widget.controller.text != widget.currentUrl) {
        _suppressTextListener = true;
        widget.controller.text = widget.currentUrl;
        _suppressTextListener = false;
      }
    }
  }

  void _onTextChanged() {
    if (_suppressTextListener || !widget.focusNode.hasFocus) return;
    _refreshSuggestions(resetSelection: true);
  }

  void _refreshSuggestions({required bool resetSelection}) {
    if (!mounted || !widget.focusNode.hasFocus) {
      _removeOverlay();
      return;
    }

    final next = buildUrlSuggestions(
      query: widget.controller.text,
      bookmarks: widget.bookmarks,
      history: widget.history,
      currentUrl: widget.currentUrl,
    );

    _suggestions = next;
    if (resetSelection || _selectedIndex >= _suggestions.length) {
      _selectedIndex = -1;
    }

    if (_suggestions.isEmpty) {
      _removeOverlay();
      return;
    }

    if (_autocompleteOverlay == null) {
      _insertOverlay();
    } else {
      _autocompleteOverlay!.markNeedsBuild();
    }
  }

  void _selectAndNavigate(String url) {
    _selectedIndex = -1;
    _removeOverlay();
    widget.focusNode.unfocus();
    widget.onSubmit(url);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_suggestions.isEmpty) {
        _refreshSuggestions(resetSelection: true);
      }
      if (_suggestions.isEmpty) return KeyEventResult.ignored;
      _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      if (_autocompleteOverlay == null) {
        _insertOverlay();
      } else {
        _autocompleteOverlay!.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_suggestions.isEmpty) return KeyEventResult.ignored;
      _selectedIndex =
          _selectedIndex <= 0 ? _suggestions.length - 1 : _selectedIndex - 1;
      if (_autocompleteOverlay == null) {
        _insertOverlay();
      } else {
        _autocompleteOverlay!.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.tab && _suggestions.isNotEmpty) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift) {
        _selectedIndex =
            _selectedIndex <= 0 ? _suggestions.length - 1 : _selectedIndex - 1;
      } else {
        _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      }
      _autocompleteOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIndex >= 0 && _selectedIndex < _suggestions.length) {
        _selectAndNavigate(_suggestions[_selectedIndex].url);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_autocompleteOverlay != null) {
        _removeOverlay();
        return KeyEventResult.handled;
      }
      widget.focusNode.unfocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _insertOverlay() {
    _removeOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _autocompleteOverlay = OverlayEntry(
      builder: (overlayContext) {
        final box =
            _urlBarKey.currentContext?.findRenderObject() as RenderBox?;
        final targetWidth =
            (box != null && box.hasSize) ? box.size.width : 520.0;

        return Positioned(
          width: targetWidth.clamp(280.0, 900.0),
          child: CompositedTransformFollower(
            link: _urlBarLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 42),
            child: TapRegion(
              groupId: _tapRegionGroupId,
              child: FocusScope(
                canRequestFocus: false,
                child: Material(
                  elevation: 10,
                  color: FyrTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: FyrTheme.dividerColor.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_suggestions.length, (index) {
                        final item = _suggestions[index];
                        final isSelected = index == _selectedIndex;
                        return InkWell(
                          key: Key('url-suggestion-$index'),
                          canRequestFocus: false,
                          onHover: (hovered) {
                            if (hovered && _selectedIndex != index) {
                              _selectedIndex = index;
                              _autocompleteOverlay?.markNeedsBuild();
                            }
                          },
                          onTap: () => _selectAndNavigate(item.url),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? FyrTheme.accentColor.withValues(alpha: 0.16)
                                  : Colors.transparent,
                              border: Border(
                                left: BorderSide(
                                  color: isSelected
                                      ? FyrTheme.accentColor
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.isBookmark
                                      ? Icons.star_rounded
                                      : Icons.history_rounded,
                                  size: 15,
                                  color: item.isBookmark
                                      ? FyrTheme.accentColor
                                      : (isSelected
                                          ? FyrTheme.textColor
                                          : FyrTheme.textColor
                                              .withValues(alpha: 0.55)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.title.isNotEmpty
                                        ? item.title
                                        : item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: FyrTheme.textColor,
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: FyrTheme.accentColor
                                          .withValues(alpha: isSelected ? 1.0 : 0.85),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_autocompleteOverlay!);
  }

  void _removeOverlay() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
    _selectedIndex = -1;
  }

  @override
  Widget build(BuildContext context) {
    final isSecure = widget.currentUrl.startsWith('https://');

    return CompositedTransformTarget(
      link: _urlBarLink,
      child: Container(
        key: _urlBarKey,
        height: 36,
        decoration: BoxDecoration(
          color: FyrTheme.isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: widget.focusNode.hasFocus
              ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.6))
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              widget.isError
                  ? Icons.warning_amber_rounded
                  : isSecure
                      ? Icons.lock_outline
                      : Icons.lock_open,
              size: 14,
              color: widget.isError
                  ? Colors.orangeAccent
                  : isSecure
                      ? Colors.greenAccent
                      : FyrTheme.textColor.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('browser-url-field'),
                controller: widget.controller,
                focusNode: widget.focusNode,
                groupId: _tapRegionGroupId,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText:
                      'Search with ${widget.searchEngineLabel} or enter URL',
                  hintStyle: TextStyle(
                    color: FyrTheme.textColor.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (value) {
                  if (_selectedIndex >= 0 &&
                      _selectedIndex < _suggestions.length) {
                    _selectAndNavigate(_suggestions[_selectedIndex].url);
                  } else {
                    _selectAndNavigate(value);
                  }
                },
              ),
            ),
            if (widget.showInstallPwa && widget.onInstallPwa != null)
              IconButton(
                icon: Icon(
                  Icons.install_desktop,
                  size: 17,
                  color: FyrTheme.accentColor,
                ),
                tooltip: 'Install PWA',
                onPressed: widget.onInstallPwa,
              ),
            if (widget.onToggleBookmark != null)
              IconButton(
                onPressed: widget.onToggleBookmark,
                tooltip: widget.isBookmarked
                    ? 'Remove Bookmark'
                    : 'Bookmark Page',
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  widget.isBookmarked ? Icons.star : Icons.star_border,
                  color: widget.isBookmarked
                      ? FyrTheme.accentColor
                      : FyrTheme.textColor.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
