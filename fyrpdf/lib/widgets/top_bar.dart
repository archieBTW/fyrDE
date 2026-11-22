import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../state/pdf_app_controller.dart';
import 'document_info_dialog.dart';
import 'traffic_lights.dart';

/// Helper to launch the native file picker for selecting PDF files.
Future<void> pickAndOpenPdfFiles(PdfAppController ctrl) async {
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Open PDF Document',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: true,
  );
  if (result == null) return;
  for (final file in result.files) {
    if (file.path != null) {
      await ctrl.openFile(file.path!);
    }
  }
}

/// Frameless top title bar with Fyr traffic lights, app identity, document tabs,
/// and quick actions.
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    final activeTab = ctrl.activeTab;

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
                    FyrTheme.accentColor.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrPDF',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                letterSpacing: -0.2,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 12),
            if (ctrl.tabs.isNotEmpty) ...[
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ctrl.tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final tab = ctrl.tabs[index];
                      final isActive = index == ctrl.activeTabIndex;
                      return _DocumentTabChip(
                        title: tab.fileName,
                        fullPath: tab.filePath,
                        isActive: isActive,
                        onSelect: () => ctrl.selectTab(index),
                        onClose: () => ctrl.closeTab(index),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (ctrl.statusMessage != null) ...[
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
              ),
            ] else ...[
              const Spacer(),
            ],
            if (ctrl.tabs.isNotEmpty && ctrl.statusMessage != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  ctrl.statusMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    color: FyrTheme.accentColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (activeTab != null) ...[
              IconButton(
                tooltip: 'Document Info',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: FyrTheme.textColorMuted,
                ),
                onPressed: () => showDocumentInfoDialog(
                  context,
                  tab: activeTab,
                  bookmarkCount: ctrl.activeBookmarks.length,
                ),
              ),
              const SizedBox(width: 4),
            ],
            _TopBarPillButton(
              icon: Icons.folder_open_rounded,
              label: 'Open PDF',
              accent: !ctrl.hasOpenDocument,
              onTap: () => pickAndOpenPdfFiles(ctrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTabChip extends StatelessWidget {
  final String title;
  final String fullPath;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _DocumentTabChip({
    required this.title,
    required this.fullPath,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: fullPath,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onSelect,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 210, minWidth: 96),
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(
            color: isActive
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isActive
                  ? FyrTheme.accentColor.withValues(alpha: 0.6)
                  : FyrTheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 13,
                color: isActive ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: FyrTheme.textColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _TopBarPillButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accent ? FyrTheme.accentColor : FyrTheme.cardColor;
    final fg = accent
        ? FyrTheme.getContrastingColor(FyrTheme.accentColor)
        : FyrTheme.textColor;

    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: accent ? null : Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
