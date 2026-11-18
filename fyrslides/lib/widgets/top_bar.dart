import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../state/slides_controller.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final deck = ctrl.deck;

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
                Icons.slideshow_rounded,
                size: 15,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrSlides',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 10),
            // fyrOffice Suite Switcher Pill
            PopupMenuButton<String>(
              tooltip: 'Switch fyrOffice App',
              onSelected: (binary) {
                try {
                  Process.start(binary, const [], mode: ProcessStartMode.detached);
                } catch (_) {}
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'fyrdocs',
                  child: Text('fyrDocs — Word Processor (.odt / .docx)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'fyrsheets',
                  child: Text('fyrSheets — Spreadsheet Studio (.ods / .xlsx)',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'fyrOffice',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.accentColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Deck Title + Format Badge
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
                    '${deck.title}.${deck.format}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: FyrTheme.accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      deck.format.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Aspect Ratio Switcher
            PopupMenuButton<String>(
              tooltip: 'Slide Aspect Ratio',
              onSelected: ctrl.setAspectRatio,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: '16:9',
                  child: Text('16:9 Widescreen (1600×900)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: '16:10',
                  child: Text('16:10 Studio (1600×1000)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: '4:3',
                  child: Text('4:3 Classic (1200×900)',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Text(
                  deck.aspectRatio,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColorMuted,
                  ),
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
            IconButton(
              icon: Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: ctrl.isGridView
                    ? FyrTheme.accentColor
                    : FyrTheme.textColorMuted,
              ),
              tooltip: 'Slide Sorter Grid View',
              onPressed: ctrl.toggleGridView,
            ),
            const SizedBox(width: 4),
            _pillBtn(
              icon: Icons.note_add_outlined,
              label: 'New',
              onTap: ctrl.newDeck,
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.folder_open_rounded,
              label: 'Open',
              onTap: () async {
                final res = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['odp', 'pptx'],
                );
                if (res != null && res.files.single.path != null) {
                  await ctrl.openDeck(res.files.single.path!);
                }
              },
            ),
            const SizedBox(width: 6),
            // Save / Export Format Menu
            PopupMenuButton<String>(
              tooltip: 'Save or Export Presentation',
              onSelected: (ext) async {
                final out = await FilePicker.saveFile(
                  dialogTitle: 'Save fyrSlides Presentation (.$ext)',
                  fileName: '${deck.title}.$ext',
                  type: FileType.custom,
                  allowedExtensions: [ext],
                );
                if (out != null) {
                  final normalized =
                      out.toLowerCase().endsWith('.$ext') ? out : '$out.$ext';
                  await ctrl.saveDeck(normalized);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'odp',
                  child: Text('Save as OpenDocument (.odp)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'pptx',
                  child: Text('Save as PowerPoint (.pptx)',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'html',
                  child: Text('Export HTML5 Web Deck (.html)',
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
                        style:
                            TextStyle(fontSize: 11.5, color: FyrTheme.textColor)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down_rounded,
                        size: 15, color: FyrTheme.textColorMuted),
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
              onPressed: () => ctrl.startPresentation(),
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: const Text(
                'Present',
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
