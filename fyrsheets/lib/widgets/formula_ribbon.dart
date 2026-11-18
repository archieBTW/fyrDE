import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/sheet_models.dart';
import '../state/sheets_controller.dart';

class FormulaRibbon extends StatelessWidget {
  const FormulaRibbon({super.key});

  static const List<(String, String?)> _colorSwatches = [
    ('Default', null),
    ('Purple Accent', '#D040FF'),
    ('Cyan Glow', '#00E5FF'),
    ('Emerald', '#27C93F'),
    ('Amber', '#FFBD2E'),
    ('Coral Red', '#FF5F56'),
    ('Pure White', '#FFFFFF'),
  ];

  static const List<(String, String?)> _fillSwatches = [
    ('None', null),
    ('Deep Violet', '#1F182B'),
    ('Midnight Purple', '#2E1A47'),
    ('Dark Teal', '#0E2A33'),
    ('Dark Emerald', '#122E1E'),
    ('Dark Amber', '#332610'),
    ('Dark Crimson', '#361518'),
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SheetsController>();
    final style = ctrl.currentCell.style;
    final range = ctrl.selectionRange;

    return Container(
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Formatting & Data Toolbar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Number Format Picker
                  _buildNumberFormatMenu(ctrl, style),
                  const SizedBox(width: 6),
                  _toolBtn(
                    label: r'$',
                    tooltip: 'Currency Format',
                    active: style.numberFormat == NumberFormatType.currency,
                    onTap: () => ctrl.setNumberFormat(
                      style.numberFormat == NumberFormatType.currency
                          ? NumberFormatType.general
                          : NumberFormatType.currency,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _toolBtn(
                    label: '%',
                    tooltip: 'Percentage Format',
                    active: style.numberFormat == NumberFormatType.percent,
                    onTap: () => ctrl.setNumberFormat(
                      style.numberFormat == NumberFormatType.percent
                          ? NumberFormatType.general
                          : NumberFormatType.percent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _toolBtn(
                    label: '.00',
                    tooltip: 'Increase Decimals',
                    onTap: () => ctrl.adjustDecimals(1),
                  ),
                  const SizedBox(width: 4),
                  _toolBtn(
                    label: '.0',
                    tooltip: 'Decrease Decimals',
                    onTap: () => ctrl.adjustDecimals(-1),
                  ),
                  _divider(),
                  // Bold / Italic / Underline
                  _iconBtn(
                    icon: Icons.format_bold_rounded,
                    tooltip: 'Bold (Ctrl+B)',
                    active: style.bold,
                    onTap: ctrl.toggleBold,
                  ),
                  const SizedBox(width: 3),
                  _iconBtn(
                    icon: Icons.format_italic_rounded,
                    tooltip: 'Italic (Ctrl+I)',
                    active: style.italic,
                    onTap: ctrl.toggleItalic,
                  ),
                  const SizedBox(width: 3),
                  _iconBtn(
                    icon: Icons.format_underlined_rounded,
                    tooltip: 'Underline (Ctrl+U)',
                    active: style.underline,
                    onTap: ctrl.toggleUnderline,
                  ),
                  const SizedBox(width: 6),
                  _buildColorMenu(
                    icon: Icons.format_color_text_rounded,
                    tooltip: 'Text Color',
                    swatches: _colorSwatches,
                    onSelected: ctrl.setTextColor,
                  ),
                  const SizedBox(width: 4),
                  _buildColorMenu(
                    icon: Icons.format_color_fill_rounded,
                    tooltip: 'Cell Fill Color',
                    swatches: _fillSwatches,
                    onSelected: ctrl.setFillColor,
                  ),
                  _divider(),
                  // Alignment
                  _iconBtn(
                    icon: Icons.format_align_left_rounded,
                    tooltip: 'Align Left',
                    active: style.align == CellAlign.left,
                    onTap: () => ctrl.setAlignment(CellAlign.left),
                  ),
                  const SizedBox(width: 3),
                  _iconBtn(
                    icon: Icons.format_align_center_rounded,
                    tooltip: 'Align Center',
                    active: style.align == CellAlign.center,
                    onTap: () => ctrl.setAlignment(CellAlign.center),
                  ),
                  const SizedBox(width: 3),
                  _iconBtn(
                    icon: Icons.format_align_right_rounded,
                    tooltip: 'Align Right',
                    active: style.align == CellAlign.right,
                    onTap: () => ctrl.setAlignment(CellAlign.right),
                  ),
                  _divider(),
                  // Row / Column Operations
                  _actionPill(
                    icon: Icons.add_box_outlined,
                    label: '+Row',
                    tooltip: 'Insert Row Above',
                    onTap: ctrl.insertRowAbove,
                  ),
                  const SizedBox(width: 4),
                  _actionPill(
                    icon: Icons.indeterminate_check_box_outlined,
                    label: '-Row',
                    tooltip: 'Delete Active Row',
                    onTap: ctrl.deleteActiveRow,
                  ),
                  const SizedBox(width: 4),
                  _actionPill(
                    icon: Icons.view_column_outlined,
                    label: '+Col',
                    tooltip: 'Insert Column Left',
                    onTap: ctrl.insertColumnLeft,
                  ),
                  const SizedBox(width: 4),
                  _actionPill(
                    icon: Icons.delete_sweep_outlined,
                    label: '-Col',
                    tooltip: 'Delete Active Column',
                    onTap: ctrl.deleteActiveColumn,
                  ),
                  _divider(),
                  // Sort A->Z / Z->A
                  _actionPill(
                    icon: Icons.north_rounded,
                    label: 'Sort A→Z',
                    tooltip: 'Sort Active Column Ascending',
                    onTap: () => ctrl.sortActiveColumn(ascending: true),
                  ),
                  const SizedBox(width: 4),
                  _actionPill(
                    icon: Icons.south_rounded,
                    label: 'Sort Z→A',
                    tooltip: 'Sort Active Column Descending',
                    onTap: () => ctrl.sortActiveColumn(ascending: false),
                  ),
                  _divider(),
                  // Toggle Right Analytics & Inspector Panel
                  _actionPill(
                    icon: Icons.leaderboard_rounded,
                    label: 'Charts & Rules',
                    tooltip: 'Toggle Charts & Inspector Dock',
                    active: ctrl.showRightPanel,
                    onTap: () => ctrl.toggleRightPanel(),
                  ),
                ],
              ),
            ),
          ),

          // Row 2: Active Coordinate Badge + fx Formula Bar + Quick Functions
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Coordinate Badge (e.g. E8 or E2:E7)
                Container(
                  width: 68,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FyrTheme.accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    range.isSingleCell ? ctrl.activeCell.a1 : range.toA1(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // fx badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Text(
                    'fx',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Commit / Cancel buttons
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: ctrl.commitFormulaBarValue,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Color(0xFF27C93F),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: ctrl.cancelFormulaBarEdit,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Color(0xFFFF5F56),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Formula Input Field
                Expanded(
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: FyrTheme.bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: TextField(
                      controller: ctrl.formulaController,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: FyrTheme.textColor,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText:
                            'Enter value or formula (e.g. =SUM(E2:E7), =AVERAGE(B2:B10), =IF(E2>5000,"High","Normal"))',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color:
                              FyrTheme.textColorMuted.withValues(alpha: 0.45),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      ),
                      onSubmitted: (val) {
                        ctrl.commitFormulaBarValue(val);
                        ctrl.moveSelection(1, 0);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Quick Function Insert Pills
                for (final fn in const ['SUM', 'AVERAGE', 'IF', 'MIN', 'MAX'])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => ctrl.insertQuickFunction(fn),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: FyrTheme.dividerColor),
                        ),
                        child: Text(
                          'ƒ $fn',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.textColorMuted,
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

  Widget _buildNumberFormatMenu(SheetsController ctrl, CellStyle style) {
    return PopupMenuButton<NumberFormatType>(
      tooltip: 'Number Format',
      onSelected: ctrl.setNumberFormat,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: NumberFormatType.general,
          child: Text('General', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: NumberFormatType.number,
          child: Text('Number (1,234.56)', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: NumberFormatType.currency,
          child: Text('Currency (\$1,234.56)', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: NumberFormatType.percent,
          child: Text('Percentage (12.5%)', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: NumberFormatType.scientific,
          child: Text('Scientific (1.23e+4)', style: TextStyle(fontSize: 12)),
        ),
      ],
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
            Text(
              style.numberFormat.name.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: FyrTheme.textColorMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorMenu({
    required IconData icon,
    required String tooltip,
    required List<(String, String?)> swatches,
    required void Function(String?) onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: (val) => onSelected(val == '__none__' ? null : val),
      itemBuilder: (_) => swatches
          .map(
            (s) => PopupMenuItem<String>(
              value: s.$2 ?? '__none__',
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: s.$2 != null
                          ? _parseHexColor(s.$2!)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white38),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(s.$1, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Icon(icon, size: 14, color: FyrTheme.textColorMuted),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: FyrTheme.dividerColor,
    );
  }

  Widget _toolBtn({
    required String label,
    required String tooltip,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.22)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? FyrTheme.accentColor : FyrTheme.textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.22)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
            ),
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

  Widget _actionPill({
    required IconData icon,
    required String label,
    required String tooltip,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.2)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return FyrTheme.accentColor;
  }
}
