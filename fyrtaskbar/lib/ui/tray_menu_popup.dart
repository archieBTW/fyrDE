import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/services/tray_service.dart';

class TrayMenuPopup extends StatelessWidget {
  final TrayItem item;
  final List<TrayMenuEntry> entries;
  final VoidCallback onClose;

  const TrayMenuPopup({
    super.key,
    required this.item,
    required this.entries,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: FyrTheme.panelBgColor.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FyrTheme.cardColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                item.displayLabel,
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 12,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildEntries(entries, 0),
              ),
            ),
    );
  }

  List<Widget> _buildEntries(List<TrayMenuEntry> list, int depth) {
    final widgets = <Widget>[];
    for (final entry in list) {
      if (entry.isSeparator) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Divider(
              height: 1,
              color: FyrTheme.textColor.withOpacity(0.12),
            ),
          ),
        );
        continue;
      }

      widgets.add(
        InkWell(
          onTap: entry.enabled
              ? () {
                  TrayService.triggerMenuItem(item, entry.id);
                  onClose();
                }
              : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12.0 + depth * 12.0, 8, 12, 8),
            child: Row(
              children: [
                if (entry.checked != null) ...[
                  Icon(
                    entry.checked!
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 14,
                    color: entry.checked!
                        ? FyrTheme.accentColor
                        : FyrTheme.textColorMuted,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: entry.enabled
                          ? FyrTheme.textColor
                          : FyrTheme.textColorMuted.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (entry.children.isNotEmpty) {
        widgets.addAll(_buildEntries(entry.children, depth + 1));
      }
    }
    return widgets;
  }
}
