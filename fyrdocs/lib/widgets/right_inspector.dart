import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/doc_models.dart';
import '../state/docs_controller.dart';

class RightInspector extends StatefulWidget {
  const RightInspector({super.key});

  @override
  State<RightInspector> createState() => _RightInspectorState();
}

class _RightInspectorState extends State<RightInspector> {
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DocsController>();
    if (!ctrl.showRightPanel) return const SizedBox.shrink();

    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _tabPill(
                  label: 'Inspector',
                  selected: ctrl.rightTabIndex == 0,
                  onTap: () {
                    ctrl.rightTabIndex = 0;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 6),
                _tabPill(
                  label: 'Comments (${ctrl.document.comments.length})',
                  selected: ctrl.rightTabIndex == 1,
                  onTap: () {
                    ctrl.rightTabIndex = 1;
                    ctrl.refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ctrl.rightTabIndex == 0
                ? _buildInspectorContent(ctrl)
                : _buildCommentsContent(ctrl),
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: selected
                ? FyrTheme.accentColor.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: selected
                ? Border.all(
                    color: FyrTheme.accentColor.withValues(alpha: 0.45))
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color:
                    selected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorContent(DocsController ctrl) {
    final doc = ctrl.document;
    final blk = ctrl.selectedBlock;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('DOCUMENT METRICS'),
        Row(
          children: [
            Expanded(
              child: _metricCard('Words', '${doc.wordCount}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricCard('Characters', '${doc.charCount}'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _metricCard('Paragraphs', '${doc.paragraphCount}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricCard('Read Time', '${doc.readingTimeMinutes} min'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionHeader('PAGE SETUP & FORMAT'),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Paper Size',
                      style: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted)),
                  DropdownButton<PageSizePreset>(
                    value: doc.pageSize,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: FyrTheme.surfaceColor,
                    items: PageSizePreset.presets
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.name,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: FyrTheme.textColor)),
                            ))
                        .toList(),
                    onChanged: (p) {
                      if (p != null) ctrl.updateDocumentMeta(pageSize: p);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Line Spacing',
                      style: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted)),
                  Text('${doc.lineSpacing.toStringAsFixed(2)}x',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.accentColor)),
                ],
              ),
              Slider(
                value: doc.lineSpacing.clamp(1.0, 2.5),
                min: 1.0,
                max: 2.5,
                divisions: 15,
                activeColor: FyrTheme.accentColor,
                onChanged: (v) => ctrl.updateDocumentMeta(lineSpacing: v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Show Horizontal Ruler',
                    style:
                        TextStyle(fontSize: 11.5, color: FyrTheme.textColor)),
                value: doc.showRuler,
                activeThumbColor: FyrTheme.accentColor,
                onChanged: (v) => ctrl.updateDocumentMeta(showRuler: v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Page Numbers in Footer',
                    style:
                        TextStyle(fontSize: 11.5, color: FyrTheme.textColor)),
                value: doc.showPageNumbers,
                activeThumbColor: FyrTheme.accentColor,
                onChanged: (v) => ctrl.updateDocumentMeta(showPageNumbers: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (blk != null) ...[
          _sectionHeader('SELECTED BLOCK ACTIONS'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${blk.type.label} • ${blk.fontFamily} ${blk.fontSize.round()}pt',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColor,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ctrl.moveBlockUp(blk.id),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 13),
                        label:
                            const Text('Up', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ctrl.moveBlockDown(blk.id),
                        icon:
                            const Icon(Icons.arrow_downward_rounded, size: 13),
                        label:
                            const Text('Down', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ctrl.duplicateBlock(blk.id),
                        icon: const Icon(Icons.copy_rounded, size: 13),
                        label:
                            const Text('Clone', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ctrl.deleteBlock(blk.id),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 13, color: Colors.redAccent),
                        label: const Text('Delete',
                            style: TextStyle(
                                fontSize: 11, color: Colors.redAccent)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCommentsContent(DocsController ctrl) {
    final comments = ctrl.document.comments;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: comments.length,
            itemBuilder: (context, index) {
              final c = comments[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: c.resolved
                        ? Colors.greenAccent.withValues(alpha: 0.35)
                        : FyrTheme.dividerColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '@${c.author}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: FyrTheme.accentColor,
                          ),
                        ),
                        InkWell(
                          onTap: () => ctrl.toggleResolveComment(c.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.resolved
                                  ? Colors.greenAccent.withValues(alpha: 0.16)
                                  : FyrTheme.cardColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              c.resolved ? 'Resolved' : 'Resolve',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.resolved
                                    ? Colors.greenAccent
                                    : FyrTheme.textColorMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.text,
                      style: TextStyle(
                        fontSize: 12,
                        color: FyrTheme.textColor,
                        decoration:
                            c.resolved ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _commentCtrl,
                    style:
                        TextStyle(fontSize: 12, color: FyrTheme.textColor),
                    decoration: InputDecoration(
                      hintText: 'Add review note...',
                      hintStyle: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      filled: true,
                      fillColor: FyrTheme.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: FyrTheme.dividerColor),
                      ),
                    ),
                    onSubmitted: (v) {
                      ctrl.addComment(v);
                      _commentCtrl.clear();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.send_rounded,
                    size: 16, color: FyrTheme.accentColor),
                onPressed: () {
                  ctrl.addComment(_commentCtrl.text);
                  _commentCtrl.clear();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: FyrTheme.textColorMuted,
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: FyrTheme.accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
          ),
        ],
      ),
    );
  }
}
