import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fyr_theme.dart';
import '../models/pdf_models.dart';

/// Displays metadata about the currently active PDF document.
Future<void> showDocumentInfoDialog(
  BuildContext context, {
  required PdfTabState tab,
  required int bookmarkCount,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: FyrTheme.dividerColor),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                size: 16,
                color: FyrTheme.accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Document Info',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: FyrTheme.textColor,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('File Name', tab.fileName),
              _infoRow('Location', tab.filePath, copyable: true, context: dialogContext),
              _infoRow('File Size', tab.formattedFileSize),
              _infoRow(
                'Page Count',
                tab.pageCount > 0 ? '${tab.pageCount} pages' : 'Loading...',
              ),
              _infoRow('Current Page', '${tab.currentPage}'),
              _infoRow('Zoom', '${(tab.currentZoom * 100).round()}%'),
              _infoRow('Rotation', '${tab.rotationDegrees}°'),
              _infoRow('Bookmarks', '$bookmarkCount saved'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor: FyrTheme.getContrastingColor(FyrTheme.accentColor),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Widget _infoRow(
  String label,
  String value, {
  bool copyable = false,
  BuildContext? context,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: FyrTheme.textColor,
            ),
          ),
        ),
        if (copyable && context != null)
          IconButton(
            tooltip: 'Copy Path',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: Icon(Icons.copy_rounded, size: 14, color: FyrTheme.textColorMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('File path copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
      ],
    ),
  );
}
