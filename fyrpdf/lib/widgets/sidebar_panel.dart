import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pdf_models.dart';
import '../state/pdf_app_controller.dart';
import 'pdf_canvas_view.dart';

/// Collapsible left sidebar with Pages (thumbnails), Outline (table of contents),
/// and user-saved Bookmarks.
class SidebarPanel extends StatelessWidget {
  const SidebarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final tab = ctrl.activeTab;
    if (tab == null || !ctrl.sidebarVisible) return const SizedBox.shrink();

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: FyrTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                children: [
                  _SidebarSegment(
                    label: 'Pages',
                    icon: Icons.grid_view_rounded,
                    selected: ctrl.sidebarTab == SidebarTab.thumbnails,
                    onTap: () => ctrl.setSidebarTab(SidebarTab.thumbnails),
                  ),
                  _SidebarSegment(
                    label: 'Outline',
                    icon: Icons.format_list_bulleted_rounded,
                    selected: ctrl.sidebarTab == SidebarTab.outline,
                    onTap: () => ctrl.setSidebarTab(SidebarTab.outline),
                  ),
                  _SidebarSegment(
                    label: 'Saved',
                    icon: Icons.bookmarks_outlined,
                    selected: ctrl.sidebarTab == SidebarTab.bookmarks,
                    onTap: () => ctrl.setSidebarTab(SidebarTab.bookmarks),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (ctrl.sidebarTab) {
              SidebarTab.thumbnails => _ThumbnailsTab(tab: tab),
              SidebarTab.outline => _OutlineTab(tab: tab),
              SidebarTab.bookmarks => _BookmarksTab(tab: tab),
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? FyrTheme.accentColor.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailsTab extends StatelessWidget {
  final PdfTabState tab;
  const _ThumbnailsTab({required this.tab});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final doc = tab.document;
    if (doc == null || tab.pageCount == 0) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: FyrTheme.accentColor,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
      itemCount: tab.pageCount,
      itemBuilder: (context, index) {
        final pageNum = index + 1;
        final isActive = tab.currentPage == pageNum;

        Widget thumb = PdfPageView(
          document: doc,
          pageNumber: pageNum,
          maximumDpi: 72,
          rotationOverride: tab.pdfPageRotation,
          alignment: Alignment.center,
        );

        if (ctrl.darkReadingMode) {
          thumb = ColorFiltered(
            colorFilter: const ColorFilter.matrix(kDarkReadingColorMatrix),
            child: thumb,
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => ctrl.goToPage(pageNum),
            child: Column(
              children: [
                Container(
                  height: 190,
                  width: double.infinity,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: FyrTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? FyrTheme.accentColor
                          : FyrTheme.dividerColor,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: thumb,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$pageNum',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color:
                        isActive ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OutlineTab extends StatelessWidget {
  final PdfTabState tab;
  const _OutlineTab({required this.tab});

  @override
  Widget build(BuildContext context) {
    if (!tab.outlineLoaded) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: FyrTheme.accentColor,
          ),
        ),
      );
    }

    if (tab.outline.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.toc_rounded,
                size: 32,
                color: FyrTheme.textColorMuted.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 10),
              Text(
                'No Table of Contents',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This PDF does not define an embedded document outline.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      itemCount: tab.outline.length,
      itemBuilder: (context, index) =>
          _OutlineNodeTile(node: tab.outline[index], depth: 0),
    );
  }
}

class _OutlineNodeTile extends StatefulWidget {
  final PdfOutlineNode node;
  final int depth;

  const _OutlineNodeTile({required this.node, required this.depth});

  @override
  State<_OutlineNodeTile> createState() => _OutlineNodeTileState();
}

class _OutlineNodeTileState extends State<_OutlineNodeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PdfAppController>();
    final hasChildren = widget.node.children.isNotEmpty;
    final leftPad = 8.0 + widget.depth * 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (widget.node.dest != null) {
              ctrl.goToDest(widget.node.dest);
            } else if (hasChildren) {
              setState(() => _expanded = !_expanded);
            }
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(leftPad, 6, 8, 6),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 16,
                      color: FyrTheme.textColorMuted,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.node.title.isEmpty ? 'Untitled' : widget.node.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: FyrTheme.textColor,
                    ),
                  ),
                ),
                if (widget.node.dest != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${widget.node.dest!.pageNumber}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: FyrTheme.textColorMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          for (final child in widget.node.children)
            _OutlineNodeTile(node: child, depth: widget.depth + 1),
      ],
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  final PdfTabState tab;
  const _BookmarksTab({required this.tab});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final bookmarks = ctrl.activeBookmarks;
    final isCurrentSaved = ctrl.isCurrentPageBookmarked;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    isCurrentSaved ? FyrTheme.accentColor : FyrTheme.textColor,
                side: BorderSide(
                  color: isCurrentSaved
                      ? FyrTheme.accentColor
                      : FyrTheme.dividerColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => ctrl.toggleBookmarkForCurrentPage(),
              icon: Icon(
                isCurrentSaved
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
                size: 15,
              ),
              label: Text(
                isCurrentSaved
                    ? 'Remove Page ${tab.currentPage}'
                    : 'Bookmark Page ${tab.currentPage}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        Expanded(
          child: bookmarks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_border_rounded,
                          size: 32,
                          color: FyrTheme.textColorMuted.withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No Bookmarks Yet',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Press Ctrl+D or click above to save pages for quick access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 14),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final bm = bookmarks[index];
                    final isCurrent = bm.pageNumber == tab.currentPage;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => ctrl.goToPage(bm.pageNumber),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? FyrTheme.accentColor.withValues(alpha: 0.14)
                              : FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent
                                ? FyrTheme.accentColor.withValues(alpha: 0.5)
                                : FyrTheme.dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bookmark_rounded,
                              size: 15,
                              color: FyrTheme.accentColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bm.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: FyrTheme.textColor,
                                    ),
                                  ),
                                  Text(
                                    'Page ${bm.pageNumber}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: FyrTheme.textColorMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete Bookmark',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 15,
                                color: FyrTheme.textColorMuted,
                              ),
                              onPressed: () =>
                                  ctrl.removeBookmark(tab.filePath, bm.pageNumber),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
