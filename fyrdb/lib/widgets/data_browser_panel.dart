import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

class DataBrowserPanel extends StatefulWidget {
  const DataBrowserPanel({super.key});

  @override
  State<DataBrowserPanel> createState() => _DataBrowserPanelState();
}

class _DataBrowserPanelState extends State<DataBrowserPanel> {
  final TextEditingController _whereCtrl = TextEditingController();
  String? _editingCellKey;
  final TextEditingController _cellEditCtrl = TextEditingController();

  @override
  void dispose() {
    _whereCtrl.dispose();
    _cellEditCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final table = ctrl.selectedTable;
    final accent = FyrTheme.accentColor;

    if (table == null) {
      return Center(
        child: Text(
          'Select a table in the Database Navigator.',
          style: TextStyle(fontSize: 13, color: FyrTheme.textColorMuted),
        ),
      );
    }

    final rows = ctrl.getFilteredDataGridRows();

    return Column(
      children: [
        // Table Toolbar: Table name, WHERE filter bar, Insert/Delete/Commit/Rollback
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(
                table.isView
                    ? Icons.visibility_rounded
                    : Icons.grid_on_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                '${table.schemaName}.${table.name}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: FyrTheme.textColor,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'WHERE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD040FF),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 27,
                  child: TextField(
                    controller: _whereCtrl,
                    onSubmitted: ctrl.setDataGridFilter,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: FyrTheme.textColor,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          "e.g. status = 'HEALTHY' AND replicas >= 3 (Press Enter)",
                      hintStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: FyrTheme.textColorMuted.withValues(alpha: 0.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      filled: true,
                      fillColor: FyrTheme.bgColor,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: FyrTheme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _toolbarBtn(
                icon: Icons.filter_alt_rounded,
                label: 'Apply',
                onTap: () => ctrl.setDataGridFilter(_whereCtrl.text),
              ),
              const SizedBox(width: 10),
              if (!table.isView) ...[
                _toolbarBtn(
                  icon: Icons.add_rounded,
                  label: '+ Insert Row',
                  onTap: ctrl.insertBlankRow,
                ),
                const SizedBox(width: 6),
                _toolbarBtn(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete Row',
                  onTap: ctrl.deleteSelectedRow,
                ),
                const SizedBox(width: 10),
              ],
              if (ctrl.pendingEditCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${ctrl.pendingEditCount} pending',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 27),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: ctrl.commitPendingChanges,
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text(
                    'Commit (Ctrl+S)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                _toolbarBtn(
                  icon: Icons.undo_rounded,
                  label: 'Rollback',
                  onTap: ctrl.rollbackPendingChanges,
                ),
              ],
            ],
          ),
        ),
        // Column Header Row (click to sort)
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor.withValues(alpha: 0.8),
            border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                alignment: Alignment.center,
                child: Text(
                  '#',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ),
              for (final col in table.columns)
                Expanded(
                  child: InkWell(
                    onTap: () => ctrl.toggleDataGridSort(col.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: FyrTheme.dividerColor),
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          if (col.isPrimaryKey)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.key_rounded,
                                size: 12,
                                color: Color(0xFFFBBF24),
                              ),
                            )
                          else if (col.isForeignKey)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.link_rounded,
                                size: 12,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              col.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: FyrTheme.textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ctrl.dataGridSortColumn == col.name)
                            Icon(
                              ctrl.dataGridSortAsc
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 12,
                              color: accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Editable Data Rows
        Expanded(
          child: Container(
            color: FyrTheme.bgColor,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, rIdx) {
                final row = rows[rIdx];
                final isSelected = ctrl.selectedDataRowIndex == rIdx;
                return GestureDetector(
                  onTap: () => ctrl.selectDataRow(rIdx),
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accent.withValues(alpha: 0.14)
                          : (rIdx.isEven
                              ? FyrTheme.bgColor
                              : FyrTheme.surfaceColor.withValues(alpha: 0.4)),
                      border: Border(
                        bottom: BorderSide(
                          color: FyrTheme.dividerColor.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          alignment: Alignment.center,
                          child: Text(
                            '${rIdx + 1}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ),
                        for (final col in table.columns)
                          Expanded(
                            child: _buildEditableCell(
                              ctrl,
                              table,
                              rIdx,
                              col,
                              row[col.name],
                              accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Footer
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Text(
                'Showing ${rows.length} of ${table.rows.length} rows • ${table.columns.length} columns • Size: ${table.formattedSize}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const Spacer(),
              Text(
                'Double-click any cell to inline edit • Ctrl+S to commit',
                style: TextStyle(
                  fontSize: 10.5,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableCell(
    DbController ctrl,
    DbTableSchema table,
    int rowIndex,
    DbColumnSchema col,
    dynamic val,
    Color accent,
  ) {
    final cellKey = '${table.name}:$rowIndex:${col.name}';
    final isEditing = _editingCellKey == cellKey;
    final isDirty = ctrl.isCellDirty(table.name, rowIndex, col.name);

    return GestureDetector(
      onDoubleTap: table.isView
          ? null
          : () {
              setState(() {
                _editingCellKey = cellKey;
                _cellEditCtrl.text = val?.toString() ?? '';
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isDirty
              ? const Color(0xFFF59E0B).withValues(alpha: 0.16)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: FyrTheme.dividerColor.withValues(alpha: 0.45),
            ),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: isEditing
            ? TextField(
                controller: _cellEditCtrl,
                autofocus: true,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: FyrTheme.textColor,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (newText) {
                  final parsed = int.tryParse(newText) ??
                      double.tryParse(newText) ??
                      newText;
                  ctrl.stageCellEdit(table.name, rowIndex, col.name, parsed);
                  setState(() => _editingCellKey = null);
                },
              )
            : Text(
                val == null ? 'NULL' : val.toString(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: isDirty ? FontWeight.w700 : FontWeight.w400,
                  color: isDirty
                      ? const Color(0xFFFBBF24)
                      : (val == null
                          ? FyrTheme.textColorMuted
                          : FyrTheme.textColor),
                ),
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: FyrTheme.textColorMuted),
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
