import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pdf_models.dart';
import '../state/pdf_app_controller.dart';
import 'top_bar.dart';

/// Inviting empty state shown when no PDF document is open.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final recent = ctrl.recentFiles;

    return Container(
      color: FyrTheme.contentColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hero icon badge
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        FyrTheme.accentColor,
                        FyrTheme.accentColor.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: FyrTheme.accentColor.withValues(alpha: 0.28),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 36,
                    color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'fyrPDF',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: FyrTheme.textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fast, native PDF reader with search, outlines, bookmarks, and dark reading mode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const SizedBox(height: 24),

                // Primary CTA + Drag-and-drop hint
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: FyrTheme.accentColor,
                        foregroundColor:
                            FyrTheme.getContrastingColor(FyrTheme.accentColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => pickAndOpenPdfFiles(ctrl),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text(
                        'Open PDF',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.file_upload_outlined,
                        size: 18,
                        color: FyrTheme.accentColor,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Drag and drop any .pdf file anywhere on this window to open',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Recent Files
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        'Recent Files',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: FyrTheme.textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: FyrTheme.accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${recent.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: FyrTheme.accentColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: FyrTheme.textColorMuted,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: ctrl.clearRecentFiles,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                        label: const Text(
                          'Clear History',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: FyrTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: recent.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: FyrTheme.dividerColor,
                      ),
                      itemBuilder: (context, index) => _RecentFileTile(
                        entry: recent[index],
                        onOpen: () => ctrl.openFile(recent[index].path),
                        onRemove: () =>
                            ctrl.removeRecentFile(recent[index].path),
                      ),
                    ),
                  ),
                ],

                // Keyboard shortcuts strip
                const SizedBox(height: 24),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: const [
                    _ShortcutHint(keys: 'Ctrl+O', label: 'Open'),
                    _ShortcutHint(keys: 'Ctrl+F', label: 'Search'),
                    _ShortcutHint(keys: 'Ctrl+/-', label: 'Zoom'),
                    _ShortcutHint(keys: 'Ctrl+I', label: 'Dark Read'),
                    _ShortcutHint(keys: 'Ctrl+D', label: 'Bookmark'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentFileTile extends StatelessWidget {
  final RecentPdfEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _RecentFileTile({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                size: 16,
                color: FyrTheme.accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.directoryPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (entry.pageCount != null && entry.pageCount! > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Text(
                  '${entry.pageCount} pp',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Remove from Recent',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 15,
                color: FyrTheme.textColorMuted,
              ),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  final String keys;
  final String label;

  const _ShortcutHint({required this.keys, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Text(
            keys,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: FyrTheme.textColorMuted,
          ),
        ),
      ],
    );
  }
}
