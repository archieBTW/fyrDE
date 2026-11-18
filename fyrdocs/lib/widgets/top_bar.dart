import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../state/docs_controller.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DocsController>();
    final doc = ctrl.document;

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
                Icons.description_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrDocs',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 8),
            // fyrOffice Suite Switcher
            PopupMenuButton<String>(
              tooltip: 'fyrOffice Suite Switcher',
              onSelected: (app) {
                if (app != 'fyrdocs') {
                  ctrl.launchSuiteApp(app);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'fyrdocs',
                  child: Text('fyrDocs — Word & OpenDocument (.odt / .docx)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'fyrsheets',
                  child: Text('fyrSheets — Spreadsheets (.ods / .xlsx)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'fyrslides',
                  child: Text('fyrSlides — Presentations (.odp / .pptx)',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'fyrOffice',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 13, color: FyrTheme.accentColor),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Document Title & Format Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${doc.title}.${doc.format}',
                    style:
                        TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: doc.format == 'odt'
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.16)
                          : FyrTheme.accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      doc.format.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: doc.format == 'odt'
                            ? const Color(0xFF00E5FF)
                            : FyrTheme.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
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
              onTap: ctrl.newBlankDocument,
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.folder_open_rounded,
              label: 'Open',
              onTap: () async {
                final res = await FilePicker.pickFiles(
                  dialogTitle: 'Open Document (.odt, .docx, .md, .html, .txt)',
                  type: FileType.custom,
                  allowedExtensions: [
                    'odt',
                    'docx',
                    'doc',
                    'rtf',
                    'md',
                    'html',
                    'txt',
                  ],
                );
                if (res != null && res.files.single.path != null) {
                  await ctrl.openDocumentFile(res.files.single.path!);
                }
              },
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Save Document in Format',
              onSelected: (ext) async {
                final out = await FilePicker.saveFile(
                  dialogTitle: 'Save Document As .$ext',
                  fileName: '${doc.title}.$ext',
                  type: FileType.custom,
                  allowedExtensions: [ext],
                );
                if (out != null) {
                  final target =
                      out.toLowerCase().endsWith('.$ext') ? out : '$out.$ext';
                  await ctrl.saveDocumentFile(target);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'odt',
                  child: Text('Save as OpenDocument Text (.odt)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'docx',
                  child: Text('Save as Microsoft Word (.docx)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'md',
                  child: Text('Save as Markdown (.md)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'html',
                  child: Text('Save as Web Page (.html)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'txt',
                  child: Text('Save as Plain Text (.txt)',
                      style: TextStyle(fontSize: 12)),
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
                    Icon(Icons.save_outlined,
                        size: 14, color: FyrTheme.textColorMuted),
                    const SizedBox(width: 5),
                    Text('Save',
                        style: TextStyle(
                            fontSize: 11.5, color: FyrTheme.textColor)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down_rounded,
                        size: 14, color: FyrTheme.textColorMuted),
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
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: const Size(0, 30),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final out = await FilePicker.saveFile(
                  dialogTitle: 'Export Document to PDF',
                  fileName: '${doc.title}.pdf',
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                );
                if (out != null) {
                  await ctrl.exportPdfFile(out);
                }
              },
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
              label: const Text(
                'Export PDF',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
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
            Text(label,
                style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor)),
          ],
        ),
      ),
    );
  }
}
