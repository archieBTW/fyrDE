import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/doc_models.dart';
import '../state/docs_controller.dart';

class DocumentCanvas extends StatefulWidget {
  const DocumentCanvas({super.key});

  @override
  State<DocumentCanvas> createState() => _DocumentCanvasState();
}

class _DocumentCanvasState extends State<DocumentCanvas> {
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();

  @override
  void dispose() {
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DocsController>();
    final doc = ctrl.document;
    final scale = (ctrl.zoomPercent / 100.0).clamp(0.5, 2.0);
    final sheetWidth = (doc.pageSize.widthPt * scale).clamp(480.0, 1180.0);

    final paperBg = ctrl.darkPaperSurface
        ? const Color(0xFF13131A)
        : const Color(0xFFFAFAFC);
    final paperBorder = ctrl.darkPaperSurface
        ? FyrTheme.accentColor.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.15);
    final defaultTextColor =
        ctrl.darkPaperSurface ? Colors.white : const Color(0xFF16161D);

    return Expanded(
      child: Container(
        color: FyrTheme.contentColor,
        child: Column(
          children: [
            if (ctrl.showFindBar) _buildFindReplaceBar(ctrl),
            if (doc.showRuler) _buildHorizontalRuler(sheetWidth),
            // Main Scrollable Page Sheet
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Center(
                  child: Container(
                    width: sheetWidth,
                    constraints: const BoxConstraints(minHeight: 820),
                    padding: EdgeInsets.symmetric(
                      horizontal: doc.showPageMargins
                          ? doc.pageSize.marginHorizontal
                          : 24,
                      vertical: doc.showPageMargins
                          ? doc.pageSize.marginVertical
                          : 24,
                    ),
                    decoration: BoxDecoration(
                      color: paperBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: paperBorder, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Running Page Header
                        if (doc.headerText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.only(bottom: 12),
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: defaultTextColor.withValues(
                                      alpha: 0.1),
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  doc.headerText,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    color: defaultTextColor.withValues(
                                        alpha: 0.45),
                                  ),
                                ),
                                Text(
                                  '${doc.pageSize.name} • .${doc.format.toUpperCase()}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    color: FyrTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Document Blocks
                        ...doc.blocks.map(
                          (blk) => _DocBlockItemWidget(
                            key: ValueKey(blk.id),
                            block: blk,
                            isSelected: ctrl.selectedBlockId == blk.id,
                            defaultTextColor: defaultTextColor,
                            lineSpacing: doc.lineSpacing,
                          ),
                        ),

                        const SizedBox(height: 36),
                        // Running Page Footer
                        Container(
                          padding: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color:
                                    defaultTextColor.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                doc.footerText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: defaultTextColor.withValues(
                                      alpha: 0.45),
                                ),
                              ),
                              if (doc.showPageNumbers)
                                Text(
                                  'Page 1 of ${doc.estimatedPageCount}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    color: defaultTextColor.withValues(
                                        alpha: 0.55),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom Status Bar
            _buildStatusBar(ctrl, doc),
          ],
        ),
      ),
    );
  }

  Widget _buildFindReplaceBar(DocsController ctrl) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: FyrTheme.accentColor),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            height: 26,
            child: TextField(
              controller: _findCtrl,
              style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
              decoration: InputDecoration(
                hintText: 'Find in document...',
                hintStyle:
                    TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: FyrTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              onChanged: (v) {
                ctrl.searchQuery = v;
                ctrl.refresh();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            height: 26,
            child: TextField(
              controller: _replaceCtrl,
              style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
              decoration: InputDecoration(
                hintText: 'Replace with...',
                hintStyle:
                    TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: FyrTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              onChanged: (v) => ctrl.replaceQuery = v,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${ctrl.searchMatchCount} matches',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                ctrl.replaceAll(_findCtrl.text, _replaceCtrl.text),
            child: Text(
              'Replace All',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.accentColor,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, size: 15, color: FyrTheme.textColorMuted),
            onPressed: () {
              ctrl.showFindBar = false;
              ctrl.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalRuler(double width) {
    return Container(
      height: 20,
      width: double.infinity,
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Center(
        child: SizedBox(
          width: width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              15,
              (i) => Text(
                '${i * 10}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8.5,
                  color: FyrTheme.textColorMuted.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(DocsController ctrl, FyrDocument doc) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            'Page 1 of ${doc.estimatedPageCount}',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          ),
          _dot(),
          Text(
            '${doc.wordCount} words',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
          _dot(),
          Text(
            '${doc.charCount} chars',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          ),
          _dot(),
          Text(
            '~${doc.readingTimeMinutes} min read',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              doc.format == 'odt'
                  ? 'OASIS OpenDocument Text (.ODT)'
                  : doc.format == 'docx'
                      ? 'Microsoft Word OpenXML (.DOCX)'
                      : 'Format: .${doc.format.toUpperCase()}',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.accentColor,
              ),
            ),
          ),
          _dot(),
          InkWell(
            onTap: () => ctrl.setZoom(ctrl.zoomPercent - 10),
            child: Icon(Icons.remove, size: 13, color: FyrTheme.textColorMuted),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${ctrl.zoomPercent.round()}%',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5, color: FyrTheme.textColor),
            ),
          ),
          InkWell(
            onTap: () => ctrl.setZoom(ctrl.zoomPercent + 10),
            child: Icon(Icons.add, size: 13, color: FyrTheme.textColorMuted),
          ),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('•',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
      );
}

class _DocBlockItemWidget extends StatefulWidget {
  final DocBlock block;
  final bool isSelected;
  final Color defaultTextColor;
  final double lineSpacing;

  const _DocBlockItemWidget({
    super.key,
    required this.block,
    required this.isSelected,
    required this.defaultTextColor,
    required this.lineSpacing,
  });

  @override
  State<_DocBlockItemWidget> createState() => _DocBlockItemWidgetState();
}

class _DocBlockItemWidgetState extends State<_DocBlockItemWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant _DocBlockItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.text != _textController.text) {
      _textController.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(offset: widget.block.text.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Color _resolveBlockColor() {
    final hex = widget.block.textColorHex.trim();
    if (hex.isEmpty || hex.toUpperCase() == '#FFFFFF') {
      return widget.defaultTextColor;
    }
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return widget.defaultTextColor;
    }
  }

  TextStyle _buildBlockTextStyle() {
    final b = widget.block;
    final color = _resolveBlockColor();
    final decoration = TextDecoration.combine([
      if (b.underline) TextDecoration.underline,
      if (b.strikethrough) TextDecoration.lineThrough,
    ]);

    final base = TextStyle(
      fontSize: b.fontSize,
      fontWeight:
          b.bold || b.type.isHeading ? FontWeight.w700 : FontWeight.w400,
      fontStyle: b.italic ? FontStyle.italic : FontStyle.normal,
      decoration: decoration,
      color: color,
      height: widget.lineSpacing,
    );

    switch (b.fontFamily) {
      case 'Outfit':
        return GoogleFonts.outfit(textStyle: base);
      case 'JetBrains Mono':
        return GoogleFonts.jetBrainsMono(textStyle: base);
      case 'Serif':
        return GoogleFonts.merriweather(textStyle: base);
      default:
        return GoogleFonts.inter(textStyle: base);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<DocsController>();
    final blk = widget.block;

    return GestureDetector(
      onTap: () => ctrl.selectBlock(blk.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isSelected
                ? FyrTheme.accentColor.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1,
          ),
          color: widget.isSelected
              ? FyrTheme.accentColor.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: _buildBlockContent(ctrl, blk),
      ),
    );
  }

  Widget _buildBlockContent(DocsController ctrl, DocBlock blk) {
    switch (blk.type) {
      case DocBlockType.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(
            color: FyrTheme.accentColor.withValues(alpha: 0.4),
            thickness: 1.2,
          ),
        );

      case DocBlockType.pageBreak:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          child: Text(
            '— PAGE BREAK —',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: FyrTheme.accentColor,
              letterSpacing: 2,
            ),
          ),
        );

      case DocBlockType.callout:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FyrTheme.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(color: FyrTheme.accentColor, width: 3.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_rounded,
                  size: 17, color: FyrTheme.accentColor),
              const SizedBox(width: 10),
              Expanded(child: _editableTextField(ctrl, blk)),
            ],
          ),
        );

      case DocBlockType.blockquote:
        return Container(
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0xFF00E5FF), width: 3),
            ),
          ),
          child: _editableTextField(ctrl, blk),
        );

      case DocBlockType.codeBlock:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0B10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    blk.codeLanguage.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF00E5FF),
                    ),
                  ),
                  Text(
                    'CODE BLOCK',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _editableTextField(ctrl, blk),
            ],
          ),
        );

      case DocBlockType.checklist:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: blk.checked,
              activeColor: FyrTheme.accentColor,
              onChanged: (_) => ctrl.toggleChecklist(blk.id),
            ),
            Expanded(child: _editableTextField(ctrl, blk)),
          ],
        );

      case DocBlockType.table:
        return _buildTableWidget(ctrl, blk);

      default:
        return _editableTextField(ctrl, blk);
    }
  }

  Widget _editableTextField(DocsController ctrl, DocBlock blk) {
    return TextField(
      controller: _textController,
      maxLines: null,
      textAlign: blk.align.toFlutterAlign,
      style: _buildBlockTextStyle(),
      onTap: () => ctrl.selectBlock(blk.id),
      onChanged: (v) => ctrl.updateBlockText(blk.id, v),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: blk.type == DocBlockType.paragraph ? 'Start typing...' : null,
        hintStyle: TextStyle(
          color: widget.defaultTextColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildTableWidget(DocsController ctrl, DocBlock blk) {
    final rows = blk.tableRows;
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: FyrTheme.accentColor.withValues(alpha: 0.35)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            border: TableBorder.symmetric(
              inside: BorderSide(color: FyrTheme.dividerColor),
            ),
            children: List.generate(rows.length, (rIdx) {
              final isHeader = rIdx == 0;
              return TableRow(
                decoration: BoxDecoration(
                  color: isHeader
                      ? FyrTheme.accentColor.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.02),
                ),
                children: List.generate(rows[rIdx].length, (cIdx) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: TextFormField(
                      initialValue: rows[rIdx][cIdx],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            isHeader ? FontWeight.w700 : FontWeight.w400,
                        color: isHeader
                            ? FyrTheme.accentColor
                            : widget.defaultTextColor,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) =>
                          ctrl.updateTableCell(blk.id, rIdx, cIdx, val),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
        if (widget.isSelected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => ctrl.addTableRow(blk.id),
                  icon: const Icon(Icons.add, size: 13),
                  label:
                      const Text('+ Row', style: TextStyle(fontSize: 11)),
                ),
                TextButton.icon(
                  onPressed: () => ctrl.addTableColumn(blk.id),
                  icon: const Icon(Icons.add, size: 13),
                  label:
                      const Text('+ Column', style: TextStyle(fontSize: 11)),
                ),
                TextButton.icon(
                  onPressed: () => ctrl.removeTableRow(blk.id),
                  icon: const Icon(Icons.remove, size: 13),
                  label: const Text('- Row', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
