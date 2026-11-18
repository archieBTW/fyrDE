import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../models/sheet_models.dart';
import '../state/sheets_controller.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SheetsController>();
    final wb = ctrl.workbook;

    return DragToMoveArea(
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 14),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FyrTheme.accentColor,
                    FyrTheme.accentColor.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.grid_on_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrSheets',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 10),
            _buildSuiteSwitcher(context),
            const SizedBox(width: 10),
            // Workbook title pill
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showRenameWorkbookDialog(context, ctrl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.table_chart_outlined,
                      size: 13,
                      color: FyrTheme.accentColor,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: Text(
                        wb.title,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: FyrTheme.textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Format badge (.ODS / .XLSX / .CSV)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: FyrTheme.accentColor.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '.${wb.format.badgeLabel}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: FyrTheme.accentColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (ctrl.statusMessage != null)
              Expanded(
                child: Text(
                  ctrl.statusMessage!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: FyrTheme.accentColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            IconButton(
              icon: Icon(
                Icons.undo_rounded,
                size: 17,
                color: ctrl.canUndo
                    ? FyrTheme.textColor
                    : FyrTheme.textColorMuted.withValues(alpha: 0.35),
              ),
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: ctrl.canUndo ? ctrl.undo : null,
            ),
            IconButton(
              icon: Icon(
                Icons.redo_rounded,
                size: 17,
                color: ctrl.canRedo
                    ? FyrTheme.textColor
                    : FyrTheme.textColorMuted.withValues(alpha: 0.35),
              ),
              tooltip: 'Redo (Ctrl+Y)',
              onPressed: ctrl.canRedo ? ctrl.redo : null,
            ),
            const SizedBox(width: 4),
            _pillBtn(
              icon: Icons.note_add_outlined,
              label: 'New',
              onTap: ctrl.newWorkbook,
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.folder_open_rounded,
              label: 'Open',
              onTap: () => _openFileDialog(ctrl),
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.save_outlined,
              label: 'Save',
              onTap: () => _saveFile(ctrl),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<WorkbookFormat>(
              tooltip: 'Save As Format (.ods, .xlsx, .csv, .tsv)',
              onSelected: (fmt) => _saveAsFormat(ctrl, fmt),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: WorkbookFormat.ods,
                  child: Text(
                    'OpenDocument Spreadsheet (.ods)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                PopupMenuItem(
                  value: WorkbookFormat.xlsx,
                  child: Text(
                    'Microsoft Excel Workbook (.xlsx)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                PopupMenuItem(
                  value: WorkbookFormat.csv,
                  child: Text(
                    'Comma-Separated Values (.csv)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                PopupMenuItem(
                  value: WorkbookFormat.tsv,
                  child: Text(
                    'Tab-Separated Values (.tsv)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.save_as_outlined,
                      size: 14,
                      color: FyrTheme.textColorMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Save As',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 14,
                      color: FyrTheme.textColorMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                minimumSize: const Size(0, 30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _showExportModal(context, ctrl),
              icon: const Icon(Icons.ios_share_rounded, size: 14),
              label: const Text(
                'Export',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuiteSwitcher(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'fyrOffice Suite Switcher',
      onSelected: (binary) async {
        try {
          await Process.start(binary, [], mode: ProcessStartMode.detached);
        } catch (_) {}
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'fyrdocs',
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 15),
              SizedBox(width: 8),
              Text('fyrDocs — Document Studio (.odt / .docx)',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'fyrsheets',
          child: Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 15),
              SizedBox(width: 8),
              Text('fyrSheets — Spreadsheet Studio (.ods / .xlsx)',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'fyrdemos',
          child: Row(
            children: [
              Icon(Icons.slideshow_rounded, size: 15),
              SizedBox(width: 8),
              Text('fyrDemos — Presentation Studio (.odp / .pptx)',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'fyrOffice',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColorMuted,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.unfold_more_rounded,
              size: 12,
              color: FyrTheme.textColorMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFileDialog(SheetsController ctrl) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ods', 'xlsx', 'csv', 'tsv', 'json'],
    );
    if (res != null && res.files.single.path != null) {
      await ctrl.openWorkbookFromFile(res.files.single.path!);
    }
  }

  Future<void> _saveFile(SheetsController ctrl) async {
    if (ctrl.workbook.filePath != null) {
      await ctrl.saveWorkbookToFile(ctrl.workbook.filePath!);
    } else {
      await _saveAsFormat(ctrl, ctrl.workbook.format);
    }
  }

  Future<void> _saveAsFormat(
    SheetsController ctrl,
    WorkbookFormat fmt,
  ) async {
    final base = p.basenameWithoutExtension(ctrl.workbook.title);
    final out = await FilePicker.saveFile(
      dialogTitle: 'Save fyrSheets Workbook (.${fmt.extension})',
      fileName: '$base.${fmt.extension}',
      type: FileType.custom,
      allowedExtensions: [fmt.extension],
    );
    if (out != null) {
      await ctrl.saveWorkbookToFile(out);
    }
  }

  void _showRenameWorkbookDialog(
    BuildContext context,
    SheetsController ctrl,
  ) {
    final tc = TextEditingController(text: ctrl.workbook.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(
          'Rename Workbook',
          style: TextStyle(fontSize: 15, color: FyrTheme.textColor),
        ),
        content: TextField(
          controller: tc,
          autofocus: true,
          style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
          decoration: const InputDecoration(
            labelText: 'Workbook Filename',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final next = tc.text.trim();
              if (next.isNotEmpty) {
                ctrl.workbook.title = next;
                ctrl.workbook.format = WorkbookFormat.fromPath(next);
                ctrl.statusMessage = 'Renamed workbook to $next';
                // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
                ctrl.notifyListeners();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showExportModal(BuildContext context, SheetsController ctrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Row(
          children: [
            Icon(Icons.ios_share_rounded,
                size: 18, color: FyrTheme.accentColor),
            const SizedBox(width: 8),
            Text(
              'Export Spreadsheet Workbook',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _exportOptionTile(
                ctx,
                ctrl,
                WorkbookFormat.ods,
                'OpenDocument Spreadsheet (.ods)',
                'ISO/IEC 26300 native format compatible with LibreOffice Calc',
                Icons.table_view_rounded,
              ),
              const SizedBox(height: 8),
              _exportOptionTile(
                ctx,
                ctrl,
                WorkbookFormat.xlsx,
                'Microsoft Excel OpenXML (.xlsx)',
                'Full multi-sheet workbook with sharedStrings & formulas',
                Icons.grid_on_rounded,
              ),
              const SizedBox(height: 8),
              _exportOptionTile(
                ctx,
                ctrl,
                WorkbookFormat.csv,
                'RFC-4180 Comma-Separated (.csv)',
                'Export active worksheet values for data pipelines',
                Icons.data_array_rounded,
              ),
              const SizedBox(height: 8),
              _exportOptionTile(
                ctx,
                ctrl,
                WorkbookFormat.tsv,
                'Tab-Separated Values (.tsv)',
                'Clean tab-delimited table export',
                Icons.view_column_outlined,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _exportOptionTile(
    BuildContext dialogCtx,
    SheetsController ctrl,
    WorkbookFormat fmt,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.pop(dialogCtx);
        _saveAsFormat(ctrl, fmt);
      },
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 18, color: FyrTheme.accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: FyrTheme.textColorMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: FyrTheme.textColorMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
            ),
          ],
        ),
      ),
    );
  }
}
