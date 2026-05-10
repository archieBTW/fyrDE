import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fyr_theme.dart';

class LspSelectionToolbarController implements SelectionToolbarController {
  final Future<List<dynamic>> Function(
    int startLine,
    int startCol,
    int endLine,
    int endCol,
    List<dynamic> diagnostics,
  ) getCodeActions;
  final Function(dynamic action) onCodeActionSelected;

  LspSelectionToolbarController({
    required this.getCodeActions,
    required this.onCodeActionSelected,
  });

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) async {
    final selection = controller.selection;
    
    // Sort selection range to ensure start <= end for LSP
    final int startLine = selection.baseIndex;
    final int startCol = selection.baseOffset;
    final int endLine = selection.extentIndex;
    final int endCol = selection.extentOffset;

    final List<int> start = [startLine, startCol];
    final List<int> end = [endLine, endCol];
    
    // Simple comparison for ordering
    bool isBaseFirst = startLine < endLine || (startLine == endLine && startCol <= endCol);
    
    final actions = await getCodeActions(
      isBaseFirst ? startLine : endLine,
      isBaseFirst ? startCol : endCol,
      isBaseFirst ? endLine : startLine,
      isBaseFirst ? endCol : startCol,
      [], // Placeholder, will be populated by the callback in code_editor_pane
    );
    
    if (!context.mounted) return;

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset anchor = anchors.primaryAnchor;

    // Filter for refactorings and quickfixes (including imports)
    final refactors = actions.where((a) {
      final kind = a['kind']?.toString() ?? '';
      final title = a['title']?.toString().toLowerCase() ?? '';
      return kind.startsWith('refactor') || 
             kind.startsWith('quickfix') || 
             title.contains('wrap') || 
             title.contains('extract') ||
             title.contains('move') ||
             title.contains('import');
    }).toList();

    showMenu(
      context: context,
      color: FyrTheme.bgColor,
      constraints: const BoxConstraints(
        minWidth: 250,
        maxWidth: 800, // Allow it to grow up to 800px
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FyrTheme.dividerColor, width: 1),
      ),
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          onTap: () {
            controller.copy();
          },
          child: Row(
            children: [
              Icon(Icons.copy, size: 16, color: FyrTheme.dividerColor),
              const SizedBox(width: 8),
              Text(
                'Copy',
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () {
            controller.paste();
          },
          child: Row(
            children: [
              Icon(Icons.paste, size: 16, color: FyrTheme.dividerColor),
              const SizedBox(width: 8),
              Text(
                'Paste',
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(
            'ACTIONS',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ),
        if (refactors.isEmpty)
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'No actions available',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          )
        else
          ...refactors.map((action) => PopupMenuItem(
            value: action,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high, size: 16, color: FyrTheme.accentColor),
                const SizedBox(width: 8),
                Text(
                  action['title'],
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                  ),
                  softWrap: false,
                ),
              ],
            ),
          )),
      ],
    ).then((selectedAction) {
      if (selectedAction != null) {
        onCodeActionSelected(selectedAction);
      }
    });
  }

  @override
  void hide(BuildContext context) {
  }
}
