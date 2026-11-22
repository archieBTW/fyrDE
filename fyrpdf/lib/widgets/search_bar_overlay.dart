import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/pdf_app_controller.dart';

/// Sleek floating search bar overlay for searching text inside the active PDF.
class SearchBarOverlay extends StatefulWidget {
  const SearchBarOverlay({super.key});

  @override
  State<SearchBarOverlay> createState() => _SearchBarOverlayState();
}

class _SearchBarOverlayState extends State<SearchBarOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _lastTabId;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = context.read<PdfAppController>();
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ctrl.closeSearchBar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        ctrl.prevSearchMatch();
      } else {
        ctrl.nextSearchMatch();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final tab = ctrl.activeTab;
    if (tab == null || !tab.showSearchBar) return const SizedBox.shrink();

    if (_lastTabId != tab.id) {
      _lastTabId = tab.id;
      _controller.text = tab.searchQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }

    final searcher = tab.textSearcher;
    final total = searcher?.matches.length ?? 0;
    final current = (searcher?.currentIndex != null)
        ? searcher!.currentIndex! + 1
        : 0;

    final String matchLabel;
    if (tab.searchQuery.trim().isEmpty) {
      matchLabel = '';
    } else if ((searcher?.isSearching ?? false) && total == 0) {
      matchLabel = '...';
    } else if (total == 0) {
      matchLabel = '0 / 0';
    } else {
      matchLabel = '$current / $total';
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 390,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: FyrTheme.surfaceColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: FyrTheme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: FyrTheme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Find in document...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                  onChanged: ctrl.updateSearchQuery,
                ),
              ),
              if (searcher?.isSearching ?? false)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                ),
              if (matchLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    matchLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: total == 0 && !(searcher?.isSearching ?? false)
                          ? Colors.redAccent
                          : FyrTheme.textColorMuted,
                    ),
                  ),
                ),
              Tooltip(
                message: 'Match Case',
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: ctrl.toggleSearchCaseSensitive,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(
                      color: tab.searchCaseSensitive
                          ? FyrTheme.accentColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: tab.searchCaseSensitive
                          ? Border.all(
                              color:
                                  FyrTheme.accentColor.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tab.searchCaseSensitive
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _SearchActionButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Previous Match (Shift+Enter)',
                onPressed:
                    (searcher?.hasMatches ?? false) ? ctrl.prevSearchMatch : null,
              ),
              _SearchActionButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Next Match (Enter)',
                onPressed:
                    (searcher?.hasMatches ?? false) ? ctrl.nextSearchMatch : null,
              ),
              _SearchActionButton(
                icon: Icons.close_rounded,
                tooltip: 'Close (Escape)',
                onPressed: ctrl.closeSearchBar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SearchActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 17,
            color: onPressed != null
                ? FyrTheme.textColor
                : FyrTheme.textColorMuted.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
