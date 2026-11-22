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
    final subtitle = item.iconAccessibleDesc.isNotEmpty &&
            item.iconAccessibleDesc.toLowerCase() !=
                item.displayTitle.toLowerCase()
        ? item.iconAccessibleDesc
        : null;

    final opaqueBg = FyrTheme.panelBgColor.withValues(alpha: 1.0);
    final opaqueBorder = Color.alphaBlend(
      FyrTheme.textColor.withValues(alpha: 0.14),
      opaqueBg,
    );

    return Container(
      width: 248,
      constraints: const BoxConstraints(maxHeight: 440),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        // Fully opaque with no BoxShadow so SwayFX's blur_ignore_transparent
        // layer effect on fyrtaskbar never blurs behind or around this popup.
        color: opaqueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: opaqueBorder,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayTitle,
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Divider(
              height: 1,
              color: FyrTheme.textColor.withValues(alpha: 0.12),
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                'No menu actions',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 12,
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildEntries(entries, 0),
                ),
              ),
            ),
        ],
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
              color: FyrTheme.textColor.withValues(alpha: 0.12),
            ),
          ),
        );
        continue;
      }

      widgets.add(
        _TrayMenuRow(
          entry: entry,
          depth: depth,
          onTap: entry.enabled
              ? () {
                  TrayService.triggerMenuItem(item, entry.id);
                  onClose();
                }
              : null,
        ),
      );

      if (entry.children.isNotEmpty) {
        widgets.addAll(_buildEntries(entry.children, depth + 1));
      }
    }
    return widgets;
  }
}

class _TrayMenuRow extends StatefulWidget {
  final TrayMenuEntry entry;
  final int depth;
  final VoidCallback? onTap;

  const _TrayMenuRow({
    required this.entry,
    required this.depth,
    required this.onTap,
  });

  @override
  State<_TrayMenuRow> createState() => _TrayMenuRowState();
}

class _TrayMenuRowState extends State<_TrayMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final activeHover = enabled && _hovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: EdgeInsets.fromLTRB(
              10.0 + widget.depth * 12.0,
              7,
              10,
              7,
            ),
            decoration: BoxDecoration(
              color: activeHover
                  ? FyrTheme.accentColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (widget.entry.checked != null) ...[
                  Icon(
                    widget.entry.checked!
                        ? Icons.check_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 14,
                    color: widget.entry.checked!
                        ? FyrTheme.accentColor
                        : FyrTheme.textColorMuted,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.entry.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          activeHover ? FontWeight.w500 : FontWeight.normal,
                      color: enabled
                          ? FyrTheme.textColor
                          : FyrTheme.textColorMuted.withValues(alpha: 0.55),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
