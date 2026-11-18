import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/doc_models.dart';
import '../state/docs_controller.dart';

class FormattingRibbon extends StatelessWidget {
  const FormattingRibbon({super.key});

  static const List<String> _fonts = [
    'Inter',
    'Outfit',
    'JetBrains Mono',
    'Serif',
  ];

  static const List<MapEntry<String, Color>> _colorPalette = [
    MapEntry('#FFFFFF', Colors.white),
    MapEntry('#E040FB', Color(0xFFE040FB)),
    MapEntry('#00E5FF', Color(0xFF00E5FF)),
    MapEntry('#69F0AE', Color(0xFF69F0AE)),
    MapEntry('#FFD740', Color(0xFFFFD740)),
    MapEntry('#FF5252', Color(0xFFFF5252)),
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DocsController>();
    final blk = ctrl.selectedBlock;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Block Style Picker
            PopupMenuButton<DocBlockType>(
              tooltip: 'Block Style',
              onSelected: ctrl.changeSelectedBlockType,
              itemBuilder: (_) => [
                DocBlockType.title,
                DocBlockType.heading1,
                DocBlockType.heading2,
                DocBlockType.heading3,
                DocBlockType.paragraph,
                DocBlockType.blockquote,
                DocBlockType.codeBlock,
                DocBlockType.callout,
              ]
                  .map((t) => PopupMenuItem(
                        value: t,
                        child: Text(t.label,
                            style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      blk?.type.label ?? 'Paragraph',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.unfold_more_rounded,
                        size: 14, color: FyrTheme.textColorMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Font Family Picker
            PopupMenuButton<String>(
              tooltip: 'Font Family',
              onSelected: ctrl.setFontFamily,
              itemBuilder: (_) => _fonts
                  .map((f) => PopupMenuItem(
                        value: f,
                        child: Text(f, style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      blk?.fontFamily ?? 'Inter',
                      style: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColor),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down_rounded,
                        size: 14, color: FyrTheme.textColorMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Font Size - / +
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () =>
                        ctrl.setFontSize((blk?.fontSize ?? 14) - 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.remove,
                          size: 13, color: FyrTheme.textColorMuted),
                    ),
                  ),
                  Text(
                    '${(blk?.fontSize ?? 14).round()}pt',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        ctrl.setFontSize((blk?.fontSize ?? 14) + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.add,
                          size: 13, color: FyrTheme.textColorMuted),
                    ),
                  ),
                ],
              ),
            ),
            _vDivider(),
            // B / I / U / S toggles
            _toggleIcon(
              icon: Icons.format_bold_rounded,
              tooltip: 'Bold (Ctrl+B)',
              active: blk?.bold ?? false,
              onTap: ctrl.toggleBold,
            ),
            _toggleIcon(
              icon: Icons.format_italic_rounded,
              tooltip: 'Italic (Ctrl+I)',
              active: blk?.italic ?? false,
              onTap: ctrl.toggleItalic,
            ),
            _toggleIcon(
              icon: Icons.format_underlined_rounded,
              tooltip: 'Underline (Ctrl+U)',
              active: blk?.underline ?? false,
              onTap: ctrl.toggleUnderline,
            ),
            _toggleIcon(
              icon: Icons.strikethrough_s_rounded,
              tooltip: 'Strikethrough',
              active: blk?.strikethrough ?? false,
              onTap: ctrl.toggleStrikethrough,
            ),
            const SizedBox(width: 4),
            // Quick Color Swatches
            ..._colorPalette.map((entry) {
              final selected = (blk?.textColorHex.toUpperCase() ?? '#FFFFFF') ==
                  entry.key;
              return GestureDetector(
                onTap: () => ctrl.setTextColor(entry.key),
                child: Container(
                  width: 15,
                  height: 15,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? FyrTheme.accentColor
                          : Colors.white.withValues(alpha: 0.25),
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }),
            _vDivider(),
            // Alignment
            _toggleIcon(
              icon: Icons.format_align_left_rounded,
              tooltip: 'Align Left',
              active: (blk?.align ?? TextAlignOption.left) ==
                  TextAlignOption.left,
              onTap: () => ctrl.setAlignment(TextAlignOption.left),
            ),
            _toggleIcon(
              icon: Icons.format_align_center_rounded,
              tooltip: 'Align Center',
              active: blk?.align == TextAlignOption.center,
              onTap: () => ctrl.setAlignment(TextAlignOption.center),
            ),
            _toggleIcon(
              icon: Icons.format_align_right_rounded,
              tooltip: 'Align Right',
              active: blk?.align == TextAlignOption.right,
              onTap: () => ctrl.setAlignment(TextAlignOption.right),
            ),
            _toggleIcon(
              icon: Icons.format_align_justify_rounded,
              tooltip: 'Justify',
              active: blk?.align == TextAlignOption.justify,
              onTap: () => ctrl.setAlignment(TextAlignOption.justify),
            ),
            _vDivider(),
            // Insert Blocks
            _insertChip(
              icon: Icons.format_list_bulleted_rounded,
              label: 'List',
              onTap: () => ctrl.addBlock(type: DocBlockType.bulletList),
            ),
            const SizedBox(width: 4),
            _insertChip(
              icon: Icons.checklist_rounded,
              label: 'Task',
              onTap: () => ctrl.addBlock(type: DocBlockType.checklist),
            ),
            const SizedBox(width: 4),
            _insertChip(
              icon: Icons.table_chart_outlined,
              label: 'Table',
              onTap: () => ctrl.addBlock(type: DocBlockType.table),
            ),
            const SizedBox(width: 4),
            _insertChip(
              icon: Icons.code_rounded,
              label: 'Code',
              onTap: () => ctrl.addBlock(type: DocBlockType.codeBlock),
            ),
            const SizedBox(width: 4),
            _insertChip(
              icon: Icons.campaign_outlined,
              label: 'Callout',
              onTap: () => ctrl.addBlock(type: DocBlockType.callout),
            ),
            const SizedBox(width: 4),
            _insertChip(
              icon: Icons.horizontal_rule_rounded,
              label: 'Divider',
              onTap: () => ctrl.addBlock(type: DocBlockType.divider),
            ),
            _vDivider(),
            _toggleIcon(
              icon: Icons.find_replace_rounded,
              tooltip: 'Find & Replace (Ctrl+F)',
              active: ctrl.showFindBar,
              onTap: () {
                ctrl.showFindBar = !ctrl.showFindBar;
                ctrl.refresh();
              },
            ),
            _toggleIcon(
              icon: Icons.contrast_rounded,
              tooltip: 'Toggle Dark / Light Paper Sheet',
              active: !ctrl.darkPaperSurface,
              onTap: () {
                ctrl.darkPaperSurface = !ctrl.darkPaperSurface;
                ctrl.refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: FyrTheme.dividerColor,
    );
  }

  Widget _toggleIcon({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active
                ? Border.all(
                    color: FyrTheme.accentColor.withValues(alpha: 0.5))
                : null,
          ),
          child: Icon(
            icon,
            size: 15,
            color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }

  Widget _insertChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: FyrTheme.accentColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
            ),
          ],
        ),
      ),
    );
  }
}
