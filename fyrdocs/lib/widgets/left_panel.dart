import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/doc_models.dart';
import '../state/docs_controller.dart';

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DocsController>();
    if (!ctrl.showLeftPanel) return const SizedBox.shrink();

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tab switcher: Outline | Templates | Pages
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _tabPill(
                  label: 'Outline',
                  selected: ctrl.leftTabIndex == 0,
                  onTap: () {
                    ctrl.leftTabIndex = 0;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _tabPill(
                  label: 'Templates',
                  selected: ctrl.leftTabIndex == 1,
                  onTap: () {
                    ctrl.leftTabIndex = 1;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _tabPill(
                  label: 'Pages',
                  selected: ctrl.leftTabIndex == 2,
                  onTap: () {
                    ctrl.leftTabIndex = 2;
                    ctrl.refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ctrl.leftTabIndex == 0
                ? _buildOutlineView(ctrl)
                : ctrl.leftTabIndex == 1
                    ? _buildTemplatesView(ctrl)
                    : _buildPagesView(ctrl),
          ),
          // Quick Add Block Footer
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => ctrl.addBlock(type: DocBlockType.heading1),
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Center(
                        child: Text(
                          '+ Section',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => ctrl.addBlock(type: DocBlockType.paragraph),
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: FyrTheme.accentColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color:
                                FyrTheme.accentColor.withValues(alpha: 0.4)),
                      ),
                      child: Center(
                        child: Text(
                          '+ Paragraph',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: selected
                ? FyrTheme.accentColor.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: selected
                ? Border.all(
                    color: FyrTheme.accentColor.withValues(alpha: 0.45))
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color:
                    selected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineView(DocsController ctrl) {
    final headings = ctrl.document.outlineHeadings;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'DOCUMENT OUTLINE (${headings.length})',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ),
        if (headings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Add Title or Heading blocks to build a navigable outline.',
              style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
            ),
          ),
        ...headings.map((blk) {
          final isSelected = ctrl.selectedBlockId == blk.id;
          final indent = (blk.type.outlineLevel * 10.0).clamp(0.0, 30.0);
          return Padding(
            padding: EdgeInsets.only(left: indent, bottom: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => ctrl.selectBlock(blk.id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? FyrTheme.accentColor.withValues(alpha: 0.16)
                      : FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isSelected
                        ? FyrTheme.accentColor.withValues(alpha: 0.5)
                        : FyrTheme.dividerColor,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blk.text.isEmpty ? '(Untitled Section)' : blk.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: blk.type == DocBlockType.title ? 12.5 : 12,
                          fontWeight: isSelected ||
                                  blk.type == DocBlockType.title
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? FyrTheme.accentColor
                              : FyrTheme.textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTemplatesView(DocsController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'FYROFFICE TEMPLATES',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ),
        ...DocsController.templates.map((tpl) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => ctrl.loadTemplate(tpl.builder()),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: FyrTheme.accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(tpl.icon,
                          size: 16, color: FyrTheme.accentColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpl.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: FyrTheme.textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tpl.subtitle,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPagesView(DocsController ctrl) {
    final pages = ctrl.document.estimatedPageCount;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pages,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: index == 0
                  ? FyrTheme.accentColor.withValues(alpha: 0.5)
                  : FyrTheme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  Text(
                    ctrl.document.pageSize.name,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ctrl.document.headerText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
