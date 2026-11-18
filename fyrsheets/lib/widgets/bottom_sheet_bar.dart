import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/sheet_models.dart';
import '../state/sheets_controller.dart';

class BottomSheetBar extends StatelessWidget {
  const BottomSheetBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SheetsController>();
    final wb = ctrl.workbook;
    final summary = ctrl.selectionSummary;
    const currencyFmt = CellStyle(
      numberFormat: NumberFormatType.currency,
      decimals: 2,
    );

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          // Add Sheet button
          Tooltip(
            message: 'Add New Sheet',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => ctrl.addSheet(),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: FyrTheme.accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Sheet Tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(wb.sheets.length, (i) {
                  final sheet = wb.sheets[i];
                  final active = i == wb.activeSheetIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => ctrl.switchSheet(i),
                      onSecondaryTapDown: (d) => _showSheetContextMenu(
                        context,
                        ctrl,
                        i,
                        d.globalPosition,
                      ),
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          color: active
                              ? FyrTheme.accentColor.withValues(alpha: 0.2)
                              : FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: active
                                ? FyrTheme.accentColor
                                : FyrTheme.dividerColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.grid_on_rounded,
                              size: 12,
                              color: active
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColorMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              sheet.name,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Live Selection Aggregate Telemetry Pills
          if (summary.numericCount > 0) ...[
            _statPill('COUNT: ${summary.count}'),
            const SizedBox(width: 6),
            _statPill(
              'MIN: ${currencyFmt.formatValue(summary.min, "")}',
            ),
            const SizedBox(width: 6),
            _statPill(
              'AVG: ${currencyFmt.formatValue(summary.average, "")}',
            ),
            const SizedBox(width: 6),
            _statPill(
              'MAX: ${currencyFmt.formatValue(summary.max, "")}',
            ),
            const SizedBox(width: 6),
            _statPill(
              'SUM: ${currencyFmt.formatValue(summary.sum, "")}',
              accent: true,
            ),
          ] else
            _statPill('COUNT: ${summary.count}'),
        ],
      ),
    );
  }

  Widget _statPill(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? FyrTheme.accentColor.withValues(alpha: 0.16)
            : FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: accent
              ? FyrTheme.accentColor.withValues(alpha: 0.45)
              : FyrTheme.dividerColor,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
          color: accent ? FyrTheme.accentColor : FyrTheme.textColorMuted,
        ),
      ),
    );
  }

  void _showSheetContextMenu(
    BuildContext context,
    SheetsController ctrl,
    int index,
    Offset globalPos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy - 110,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: Text('Rename Sheet', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Text('Duplicate Sheet', style: TextStyle(fontSize: 12)),
        ),
        if (ctrl.workbook.sheets.length > 1)
          const PopupMenuItem(
            value: 'delete',
            child: Text(
              'Delete Sheet',
              style: TextStyle(fontSize: 12, color: Color(0xFFFF5F56)),
            ),
          ),
      ],
    );

    if (result == 'duplicate') {
      ctrl.duplicateSheet(index);
    } else if (result == 'delete') {
      ctrl.deleteSheet(index);
    } else if (result == 'rename' && context.mounted) {
      final tc = TextEditingController(text: ctrl.workbook.sheets[index].name);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text(
            'Rename Worksheet',
            style: TextStyle(fontSize: 15, color: FyrTheme.textColor),
          ),
          content: TextField(
            controller: tc,
            autofocus: true,
            style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                ctrl.renameSheet(index, tc.text);
                Navigator.pop(ctx);
              },
              child: const Text('Rename'),
            ),
          ],
        ),
      );
    }
  }
}
