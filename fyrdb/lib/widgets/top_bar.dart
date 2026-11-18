import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';
import 'connection_dialog.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final activeConn = ctrl.activeConnection;
    final accent = FyrTheme.accentColor;

    return DragToMoveArea(
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 12),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent,
                    accent.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.storage_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(accent),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrDB',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Text(
                'Universal Database IDE',
                style: TextStyle(
                  fontSize: 11,
                  color: FyrTheme.textColorMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Active Connection selector pill
            PopupMenuButton<String>(
              tooltip: 'Switch Active Database Connection',
              onSelected: ctrl.selectConnection,
              itemBuilder: (_) => ctrl.connections.map((c) {
                return PopupMenuItem<String>(
                  value: c.id,
                  child: Row(
                    children: [
                      Icon(c.driver.icon, size: 15, color: c.driver.badgeColor),
                      const SizedBox(width: 8),
                      Text(
                        '${c.name} (${c.driver.label})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: activeConn.driver.badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: activeConn.driver.badgeColor.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${activeConn.name} (${activeConn.driver.shortTag})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: FyrTheme.textColorMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Transaction Mode Toggle
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: ctrl.toggleAutoCommit,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ctrl.autoCommit
                      ? const Color(0xFF22C55E).withValues(alpha: 0.14)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: ctrl.autoCommit
                        ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ctrl.autoCommit
                          ? Icons.bolt_rounded
                          : Icons.lock_clock_rounded,
                      size: 13,
                      color: ctrl.autoCommit
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ctrl.autoCommit ? 'Auto-Commit' : 'Manual Tx',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ctrl.autoCommit
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFFBBF24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Workspace view switcher
            Container(
              height: 30,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: FyrTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: DbWorkspaceMode.values.map((mode) {
                  final active = ctrl.workspaceMode == mode;
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => ctrl.setWorkspaceMode(mode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: active
                            ? accent.withValues(alpha: 0.22)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            mode.icon,
                            size: 13,
                            color: active ? accent : FyrTheme.textColorMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            mode.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: active
                                  ? FyrTheme.textColor
                                  : FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Spacer(),
            _pillBtn(
              icon: Icons.add_link_rounded,
              label: 'New Connection',
              onTap: () => ConnectionDialog.show(context),
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.folder_open_rounded,
              label: 'Open .sqlite',
              onTap: () async {
                final res = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['sqlite', 'sqlite3', 'db', 'sql'],
                );
                if (res != null && res.files.single.path != null) {
                  await ctrl.openFiles([res.files.single.path!]);
                }
              },
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.account_tree_outlined,
              label: 'Explain',
              onTap: () {
                ctrl.setWorkspaceMode(DbWorkspaceMode.sqlEditor);
                ctrl.explainActiveQuery();
              },
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FyrTheme.getContrastingColor(accent),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 29),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              onPressed: () {
                ctrl.setWorkspaceMode(DbWorkspaceMode.sqlEditor);
                ctrl.runActiveQuery();
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 15),
              label: const Text(
                'Run SQL',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Export Result Set (.csv, .json, .sql)',
              onSelected: (fmt) async {
                final exported = ctrl.exportResultAs(fmt);
                await Clipboard.setData(ClipboardData(text: exported));
                try {
                  final out = await FilePicker.saveFile(
                    dialogTitle: 'Export Query Result as .$fmt',
                    fileName: '${ctrl.selectedTableName}_export.$fmt',
                  );
                  if (out != null) {
                    await File(out).writeAsString(exported);
                  }
                } catch (_) {}
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'csv',
                  child: Text('Export as CSV (.csv)', style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'json',
                  child: Text('Export as JSON (.json)', style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'sql',
                  child: Text('Export as SQL INSERTs (.sql)', style: TextStyle(fontSize: 12)),
                ),
              ],
              child: Container(
                height: 29,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ios_share_rounded,
                      size: 13,
                      color: FyrTheme.textColorMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: FyrTheme.textColor,
                      ),
                    ),
                  ],
                ),
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
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: FyrTheme.textColorMuted),
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
