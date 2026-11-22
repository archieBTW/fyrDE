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
import 'connection_wizard.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final activeConn = ctrl.activeConnection;
    final hasConn = activeConn != null;
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
            if (!hasConn) ...[
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
            ],
            // Active Connection selector pill
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildConnectionSelector(context, ctrl, activeConn),
                    if (hasConn) ...[
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
                                  ? const Color(0xFF22C55E)
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.5),
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
                      const SizedBox(width: 10),
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
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
                                      color: active
                                          ? accent
                                          : FyrTheme.textColorMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      mode.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: active
                                            ? FontWeight.w600
                                            : FontWeight.w500,
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
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!hasConn) ...[
              _pillBtn(
                icon: Icons.add_link_rounded,
                label: 'New Connection',
                onTap: () => ConnectionWizard.showModal(context),
              ),
              const SizedBox(width: 6),
              _pillBtn(
                icon: Icons.folder_open_rounded,
                label: 'Open .sqlite',
                onTap: () async {
                  final res = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: [
                      'sqlite',
                      'sqlite3',
                      'db',
                      'duckdb',
                      'sql',
                    ],
                  );
                  if (res != null && res.files.single.path != null) {
                    await ctrl.openFiles([res.files.single.path!]);
                  }
                },
              ),
            ] else ...[
              Tooltip(
                message: 'New Connection',
                child: _pillBtn(
                  icon: Icons.add_link_rounded,
                  label: 'New',
                  onTap: () => ConnectionWizard.showModal(context),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Open .sqlite / .db / .sql',
                child: _pillBtn(
                  icon: Icons.folder_open_rounded,
                  label: 'Open',
                  onTap: () async {
                    final res = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: [
                        'sqlite',
                        'sqlite3',
                        'db',
                        'duckdb',
                        'sql',
                      ],
                    );
                    if (res != null && res.files.single.path != null) {
                      await ctrl.openFiles([res.files.single.path!]);
                    }
                  },
                ),
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
                  if (exported.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: exported));
                  try {
                    final baseName = ctrl.selectedTableName ?? 'query_result';
                    final out = await FilePicker.saveFile(
                      dialogTitle: 'Export Query Result as .$fmt',
                      fileName: '${baseName}_export.$fmt',
                    );
                    if (out != null) {
                      await File(out).writeAsString(exported);
                    }
                  } catch (_) {}
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'csv',
                    child: Text('Export as CSV (.csv)',
                        style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuItem(
                    value: 'json',
                    child: Text('Export as JSON (.json)',
                        style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuItem(
                    value: 'sql',
                    child: Text('Export as SQL INSERTs (.sql)',
                        style: TextStyle(fontSize: 12)),
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
                        Icons.file_download_outlined,
                        size: 13.5,
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
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSelector(
    BuildContext context,
    DbController ctrl,
    DbConnectionProfile? activeConn,
  ) {
    if (activeConn == null && ctrl.connections.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => ConnectionWizard.showModal(context),
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
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: FyrTheme.textColorMuted.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Not Connected',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Switch or Disconnect Database Connection',
      onSelected: (value) {
        if (value == '__disconnect__') {
          ctrl.disconnectActive();
        } else if (value == '__new__') {
          ConnectionWizard.showModal(context);
        } else {
          ctrl.selectConnection(value);
        }
      },
      itemBuilder: (_) => [
        ...ctrl.connections.map((c) {
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
        }),
        const PopupMenuDivider(),
        if (activeConn != null)
          const PopupMenuItem<String>(
            value: '__disconnect__',
            child: Row(
              children: [
                Icon(Icons.link_off_rounded, size: 15, color: Color(0xFFF87171)),
                SizedBox(width: 8),
                Text('Disconnect Active', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: '__new__',
          child: Row(
            children: [
              Icon(Icons.add_link_rounded, size: 15),
              SizedBox(width: 8),
              Text('New Connection Wizard...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: activeConn != null
              ? activeConn.driver.badgeColor.withValues(alpha: 0.14)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: activeConn != null
                ? activeConn.driver.badgeColor.withValues(alpha: 0.45)
                : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: activeConn != null
                    ? const Color(0xFF22C55E)
                    : FyrTheme.textColorMuted.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              activeConn != null
                  ? '${activeConn.name} (${activeConn.driver.shortTag})'
                  : 'Select Saved Connection',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: activeConn != null
                    ? FyrTheme.textColor
                    : FyrTheme.textColorMuted,
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
