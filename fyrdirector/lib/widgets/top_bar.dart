import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';
import 'export_dialog.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();

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
                Icons.movie_filter_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrDirector',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Text(
                ctrl.projectTitle,
                style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
              ),
            ),
            const SizedBox(width: 8),
            // Sequence Aspect Preset Switcher
            PopupMenuButton<SequencePreset>(
              tooltip: 'Sequence Aspect & FPS',
              onSelected: (p) {
                ctrl.sequence = p;
                ctrl.refresh();
              },
              itemBuilder: (_) => kSequencePresets
                  .map((p) => PopupMenuItem(
                        value: p,
                        child: Text(
                            '${p.name} (${p.width}×${p.height} • ${p.fps.round()}fps)',
                            style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '${ctrl.sequence.width}×${ctrl.sequence.height} • ${ctrl.sequence.fps.round()}fps',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.accentColor,
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
              icon: Icon(Icons.undo_rounded,
                  size: 17,
                  color: ctrl.canUndo
                      ? FyrTheme.textColor
                      : FyrTheme.textColorMuted.withValues(alpha: 0.35)),
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: ctrl.canUndo ? ctrl.undo : null,
            ),
            IconButton(
              icon: Icon(Icons.redo_rounded,
                  size: 17,
                  color: ctrl.canRedo
                      ? FyrTheme.textColor
                      : FyrTheme.textColorMuted.withValues(alpha: 0.35)),
              tooltip: 'Redo (Ctrl+Y)',
              onPressed: ctrl.canRedo ? ctrl.redo : null,
            ),
            const SizedBox(width: 4),
            _pillBtn(
              icon: Icons.note_add_outlined,
              label: 'New',
              onTap: ctrl.newProject,
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.folder_open_rounded,
              label: 'Open',
              onTap: () async {
                final res = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['fyrd'],
                );
                if (res != null && res.files.single.path != null) {
                  await ctrl.openProject(res.files.single.path!);
                }
              },
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.save_outlined,
              label: 'Save',
              onTap: () async {
                if (ctrl.projectFilePath != null) {
                  await ctrl.saveProject(ctrl.projectFilePath!);
                } else {
                  final out = await FilePicker.saveFile(
                    dialogTitle: 'Save fyrDirector Project',
                    fileName: '${ctrl.projectTitle}.fyrd',
                    type: FileType.custom,
                    allowedExtensions: ['fyrd'],
                  );
                  if (out != null) await ctrl.saveProject(out);
                }
              },
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
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => ExportDialog.show(context),
              icon: const Icon(Icons.ios_share_rounded, size: 14),
              label: const Text('Export',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
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
