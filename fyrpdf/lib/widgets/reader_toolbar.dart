import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/pdf_app_controller.dart';

/// Main PDF reader toolbar with sidebar toggle, page navigation, zoom,
/// rotation, dark reading mode, bookmarks, and text search toggle.
class ReaderToolbar extends StatefulWidget {
  const ReaderToolbar({super.key});

  @override
  State<ReaderToolbar> createState() => _ReaderToolbarState();
}

class _ReaderToolbarState extends State<ReaderToolbar> {
  final TextEditingController _pageController = TextEditingController();
  final FocusNode _pageFocusNode = FocusNode();
  int _lastSyncedPage = -1;

  @override
  void dispose() {
    _pageController.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  void _syncPageField(int currentPage) {
    if (!_pageFocusNode.hasFocus && _lastSyncedPage != currentPage) {
      _lastSyncedPage = currentPage;
      _pageController.text = '$currentPage';
    }
  }

  void _submitPageJump(PdfAppController ctrl) {
    final parsed = int.tryParse(_pageController.text.trim());
    if (parsed != null) {
      ctrl.goToPage(parsed);
    } else if (ctrl.activeTab != null) {
      _pageController.text = '${ctrl.activeTab!.currentPage}';
    }
    _pageFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final tab = ctrl.activeTab;
    if (tab == null) return const SizedBox.shrink();

    _syncPageField(tab.currentPage);
    final zoomPercent = (tab.currentZoom * 100).round();
    final isBookmarked = ctrl.isCurrentPageBookmarked;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          _ToolbarIconButton(
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Toggle Sidebar (Ctrl+B)',
            active: ctrl.sidebarVisible,
            onPressed: ctrl.toggleSidebar,
          ),
          _verticalDivider(),

          // Page navigation
          _ToolbarIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous Page (PageUp)',
            onPressed: tab.currentPage > 1 ? ctrl.previousPage : null,
          ),
          const SizedBox(width: 4),
          Text(
            'Page',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 26,
            child: TextField(
              controller: _pageController,
              focusNode: _pageFocusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
              onSubmitted: (_) => _submitPageJump(ctrl),
              onTapOutside: (_) {
                if (_pageFocusNode.hasFocus) {
                  _submitPageJump(ctrl);
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '/ ${tab.pageCount > 0 ? tab.pageCount : '-'}',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next Page (PageDown)',
            onPressed:
                tab.pageCount > 0 && tab.currentPage < tab.pageCount
                    ? ctrl.nextPage
                    : null,
          ),

          const Spacer(),

          // Zoom controls
          _ToolbarIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom Out (Ctrl+-)',
            onPressed: tab.isReady ? ctrl.zoomOut : null,
          ),
          Tooltip(
            message: 'Reset Zoom to 100% (Ctrl+0)',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: tab.isReady ? ctrl.resetZoom : null,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FyrTheme.bgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Text(
                  '$zoomPercent%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColor,
                  ),
                ),
              ),
            ),
          ),
          _ToolbarIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom In (Ctrl++)',
            onPressed: tab.isReady ? ctrl.zoomIn : null,
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Fit Width',
            onPressed: tab.isReady ? ctrl.fitWidth : null,
          ),
          _ToolbarIconButton(
            icon: Icons.fullscreen_exit_rounded,
            tooltip: 'Fit Whole Page',
            onPressed: tab.isReady ? ctrl.fitPage : null,
          ),

          const Spacer(),

          // Rotation controls
          _ToolbarIconButton(
            icon: Icons.rotate_left_rounded,
            tooltip: 'Rotate Counter-Clockwise 90°',
            onPressed: ctrl.rotateCounterClockwise,
          ),
          _ToolbarIconButton(
            icon: Icons.rotate_right_rounded,
            tooltip: 'Rotate Clockwise 90°',
            onPressed: ctrl.rotateClockwise,
          ),
          _verticalDivider(),

          // Dark Reading / Smart Invert Mode
          _ToolbarIconButton(
            icon: ctrl.darkReadingMode
                ? Icons.invert_colors_rounded
                : Icons.invert_colors_off_outlined,
            tooltip: 'Dark Reading / Invert Mode (Ctrl+I)',
            active: ctrl.darkReadingMode,
            onPressed: ctrl.toggleDarkReadingMode,
          ),
          const SizedBox(width: 2),

          // Bookmark current page
          _ToolbarIconButton(
            icon: isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            tooltip: isBookmarked
                ? 'Remove Bookmark for Page ${tab.currentPage} (Ctrl+D)'
                : 'Bookmark Page ${tab.currentPage} (Ctrl+D)',
            active: isBookmarked,
            onPressed: () => ctrl.toggleBookmarkForCurrentPage(),
          ),
          const SizedBox(width: 2),

          // Find in document
          _ToolbarIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Find in Document (Ctrl+F)',
            active: tab.showSearchBar,
            onPressed: ctrl.toggleSearchBar,
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: FyrTheme.dividerColor,
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    this.active = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = active
        ? FyrTheme.accentColor
        : enabled
            ? FyrTheme.textColor
            : FyrTheme.textColorMuted.withValues(alpha: 0.35);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          width: 30,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active
                ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.45))
                : null,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
