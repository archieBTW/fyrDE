import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../engine/doc_io.dart';
import '../models/doc_models.dart';

class DocTemplateItem {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final FyrDocument Function() builder;

  const DocTemplateItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });
}

class DocsController extends ChangeNotifier {
  late FyrDocument document;
  String? selectedBlockId;

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  int leftTabIndex = 0; // 0: Outline, 1: Templates, 2: Pages
  int rightTabIndex = 0; // 0: Inspector, 1: Styles, 2: Comments
  bool showLeftPanel = true;
  bool showRightPanel = true;
  bool showFindBar = false;

  String searchQuery = '';
  String replaceQuery = '';
  double zoomPercent = 100.0;
  String viewMode = 'Print Layout'; // 'Print Layout', 'Continuous', 'Focus Mode'
  bool darkPaperSurface = true;
  String? statusMessage;
  int _nextIdCounter = 100;

  DocsController({FyrDocument? initialDocument}) {
    document = initialDocument ?? buildBlankTemplate();
    if (document.blocks.isNotEmpty) {
      selectedBlockId = document.blocks.first.id;
    }
  }

  DocBlock? get selectedBlock {
    if (document.blocks.isEmpty) return null;
    if (selectedBlockId == null) return document.blocks.first;
    return document.blocks.firstWhere(
      (b) => b.id == selectedBlockId,
      orElse: () => document.blocks.first,
    );
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void refresh() => notifyListeners();

  void _recordSnapshot() {
    _undoStack.add(document.toJsonString());
    if (_undoStack.length > 60) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    document.modifiedAt = DateTime.now();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(document.toJsonString());
    final prev = _undoStack.removeLast();
    document = FyrDocument.fromJsonString(prev);
    if (selectedBlockId != null &&
        !document.blocks.any((b) => b.id == selectedBlockId)) {
      selectedBlockId =
          document.blocks.isNotEmpty ? document.blocks.first.id : null;
    }
    statusMessage = 'Undid last edit';
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(document.toJsonString());
    final next = _redoStack.removeLast();
    document = FyrDocument.fromJsonString(next);
    statusMessage = 'Redid edit';
    notifyListeners();
  }

  void selectBlock(String id) {
    if (selectedBlockId == id) return;
    selectedBlockId = id;
    notifyListeners();
  }

  void setZoom(double value) {
    zoomPercent = value.clamp(50.0, 200.0);
    notifyListeners();
  }

  void setViewMode(String mode) {
    viewMode = mode;
    if (mode == 'Focus Mode') {
      showLeftPanel = false;
      showRightPanel = false;
    } else {
      showLeftPanel = true;
      showRightPanel = true;
    }
    notifyListeners();
  }

  void updateDocumentMeta({
    String? title,
    PageSizePreset? pageSize,
    bool? showRuler,
    bool? showPageMargins,
    String? headerText,
    String? footerText,
    bool? showPageNumbers,
    double? lineSpacing,
  }) {
    _recordSnapshot();
    if (title != null) document.title = title;
    if (pageSize != null) document.pageSize = pageSize;
    if (showRuler != null) document.showRuler = showRuler;
    if (showPageMargins != null) document.showPageMargins = showPageMargins;
    if (headerText != null) document.headerText = headerText;
    if (footerText != null) document.footerText = footerText;
    if (showPageNumbers != null) document.showPageNumbers = showPageNumbers;
    if (lineSpacing != null) document.lineSpacing = lineSpacing;
    notifyListeners();
  }

  // ===========================================================================
  // BLOCK MANIPULATION
  // ===========================================================================

  String _genId(String prefix) {
    _nextIdCounter++;
    return '${prefix}_${_nextIdCounter}_${DateTime.now().microsecondsSinceEpoch % 10000}';
  }

  DocBlock addBlock({
    required DocBlockType type,
    String? text,
    int? insertAfterIndex,
  }) {
    _recordSnapshot();
    final id = _genId('blk');
    DocBlock newBlock;

    switch (type) {
      case DocBlockType.title:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Document Title',
          fontFamily: 'Outfit',
          fontSize: 26,
          bold: true,
        );
        break;
      case DocBlockType.heading1:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Section Heading',
          fontFamily: 'Outfit',
          fontSize: 20,
          bold: true,
        );
        break;
      case DocBlockType.heading2:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Subsection Heading',
          fontFamily: 'Outfit',
          fontSize: 17,
          bold: true,
        );
        break;
      case DocBlockType.heading3:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Topic Heading',
          fontFamily: 'Outfit',
          fontSize: 15,
          bold: true,
        );
        break;
      case DocBlockType.codeBlock:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ??
              'void main() {\n  print("fyrOffice OpenDocument Engine");\n}',
          fontFamily: 'JetBrains Mono',
          fontSize: 12.5,
          codeLanguage: 'dart',
        );
        break;
      case DocBlockType.blockquote:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ??
              'Design for clarity, native speed, and zero telemetry across the desktop.',
          italic: true,
          fontSize: 14.5,
        );
        break;
      case DocBlockType.callout:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ??
              'Architecture Note: All fyrOffice documents use standard OASIS OpenDocument and ISO OpenXML ZIP containers.',
          calloutIcon: 'info',
        );
        break;
      case DocBlockType.bulletList:
      case DocBlockType.numberedList:
        final items = text != null && text.isNotEmpty
            ? text.split('\n')
            : ['First action item', 'Second deliverable', 'Third milestone'];
        newBlock = DocBlock(
          id: id,
          type: type,
          text: items.join('\n'),
          listItems: items,
        );
        break;
      case DocBlockType.checklist:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Verify .odt and .docx round-trip integrity',
          checked: false,
        );
        break;
      case DocBlockType.table:
        newBlock = DocBlock(
          id: id,
          type: type,
          tableRows: [
            ['Column 1', 'Column 2', 'Column 3'],
            ['Row 1 A', 'Row 1 B', 'Row 1 C'],
            ['Row 2 A', 'Row 2 B', 'Row 2 C'],
          ],
        );
        break;
      case DocBlockType.divider:
      case DocBlockType.pageBreak:
        newBlock = DocBlock(id: id, type: type);
        break;
      case DocBlockType.paragraph:
        newBlock = DocBlock(
          id: id,
          type: type,
          text: text ?? 'Write your paragraph here...',
        );
        break;
    }

    int targetIdx = document.blocks.length;
    if (insertAfterIndex != null &&
        insertAfterIndex >= 0 &&
        insertAfterIndex < document.blocks.length) {
      targetIdx = insertAfterIndex + 1;
    } else if (selectedBlockId != null) {
      final selIdx =
          document.blocks.indexWhere((b) => b.id == selectedBlockId);
      if (selIdx != -1) targetIdx = selIdx + 1;
    }

    document.blocks.insert(targetIdx, newBlock);
    selectedBlockId = newBlock.id;
    statusMessage = 'Inserted ${type.label}';
    notifyListeners();
    return newBlock;
  }

  void updateBlockText(String blockId, String newText,
      {bool recordUndo = false}) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    if (recordUndo) _recordSnapshot();
    final blk = document.blocks[idx];
    blk.text = newText;
    if (blk.type == DocBlockType.bulletList ||
        blk.type == DocBlockType.numberedList) {
      blk.listItems =
          newText.split('\n').where((s) => s.trim().isNotEmpty).toList();
    }
    document.modifiedAt = DateTime.now();
    notifyListeners();
  }

  void changeSelectedBlockType(DocBlockType newType) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.type = newType;
    if (newType == DocBlockType.title) {
      blk.fontSize = 26;
      blk.bold = true;
      blk.fontFamily = 'Outfit';
    } else if (newType == DocBlockType.heading1) {
      blk.fontSize = 20;
      blk.bold = true;
      blk.fontFamily = 'Outfit';
    } else if (newType == DocBlockType.heading2) {
      blk.fontSize = 17;
      blk.bold = true;
      blk.fontFamily = 'Outfit';
    } else if (newType == DocBlockType.heading3) {
      blk.fontSize = 15;
      blk.bold = true;
      blk.fontFamily = 'Outfit';
    } else if (newType == DocBlockType.codeBlock) {
      blk.fontFamily = 'JetBrains Mono';
      blk.fontSize = 12.5;
    } else if (newType == DocBlockType.bulletList ||
        newType == DocBlockType.numberedList) {
      if (blk.listItems.isEmpty) {
        blk.listItems = blk.text.isNotEmpty
            ? blk.text.split('\n')
            : ['List item 1', 'List item 2'];
        blk.text = blk.listItems.join('\n');
      }
    } else if (newType == DocBlockType.table && blk.tableRows.isEmpty) {
      blk.tableRows = [
        ['Header 1', 'Header 2', 'Header 3'],
        ['Value 1', 'Value 2', 'Value 3'],
      ];
    }
    notifyListeners();
  }

  void toggleBold() {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.bold = !blk.bold;
    notifyListeners();
  }

  void toggleItalic() {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.italic = !blk.italic;
    notifyListeners();
  }

  void toggleUnderline() {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.underline = !blk.underline;
    notifyListeners();
  }

  void toggleStrikethrough() {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.strikethrough = !blk.strikethrough;
    notifyListeners();
  }

  void setFontFamily(String family) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.fontFamily = family;
    notifyListeners();
  }

  void setFontSize(double size) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.fontSize = size.clamp(8.0, 72.0);
    notifyListeners();
  }

  void setAlignment(TextAlignOption align) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.align = align;
    notifyListeners();
  }

  void setTextColor(String hex) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.textColorHex = hex;
    notifyListeners();
  }

  void setHighlightColor(String hex) {
    final blk = selectedBlock;
    if (blk == null) return;
    _recordSnapshot();
    blk.highlightColorHex = hex;
    notifyListeners();
  }

  void toggleChecklist(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    _recordSnapshot();
    document.blocks[idx].checked = !document.blocks[idx].checked;
    notifyListeners();
  }

  void updateTableCell(String blockId, int row, int col, String value) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    final blk = document.blocks[idx];
    if (row >= 0 &&
        row < blk.tableRows.length &&
        col >= 0 &&
        col < blk.tableRows[row].length) {
      blk.tableRows[row][col] = value;
      document.modifiedAt = DateTime.now();
      notifyListeners();
    }
  }

  void addTableRow(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    _recordSnapshot();
    final blk = document.blocks[idx];
    final cols = blk.tableRows.isNotEmpty ? blk.tableRows.first.length : 3;
    blk.tableRows.add(List<String>.filled(cols, ''));
    notifyListeners();
  }

  void addTableColumn(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    _recordSnapshot();
    final blk = document.blocks[idx];
    for (var r = 0; r < blk.tableRows.length; r++) {
      blk.tableRows[r].add(r == 0 ? 'Column ${blk.tableRows[r].length + 1}' : '');
    }
    notifyListeners();
  }

  void removeTableRow(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    final blk = document.blocks[idx];
    if (blk.tableRows.length <= 1) return;
    _recordSnapshot();
    blk.tableRows.removeLast();
    notifyListeners();
  }

  void deleteBlock(String blockId) {
    if (document.blocks.length <= 1) return;
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    _recordSnapshot();
    document.blocks.removeAt(idx);
    if (selectedBlockId == blockId) {
      final newIdx = (idx - 1).clamp(0, document.blocks.length - 1);
      selectedBlockId = document.blocks[newIdx].id;
    }
    statusMessage = 'Deleted block';
    notifyListeners();
  }

  void duplicateBlock(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1) return;
    _recordSnapshot();
    final copy = document.blocks[idx].copyWith(id: _genId('blk'));
    document.blocks.insert(idx + 1, copy);
    selectedBlockId = copy.id;
    statusMessage = 'Duplicated block';
    notifyListeners();
  }

  void moveBlockUp(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx <= 0) return;
    _recordSnapshot();
    final item = document.blocks.removeAt(idx);
    document.blocks.insert(idx - 1, item);
    notifyListeners();
  }

  void moveBlockDown(String blockId) {
    final idx = document.blocks.indexWhere((b) => b.id == blockId);
    if (idx == -1 || idx >= document.blocks.length - 1) return;
    _recordSnapshot();
    final item = document.blocks.removeAt(idx);
    document.blocks.insert(idx + 1, item);
    notifyListeners();
  }

  // ===========================================================================
  // COMMENTS & FIND / REPLACE
  // ===========================================================================

  void addComment(String text, {String author = 'archer'}) {
    if (text.trim().isEmpty) return;
    _recordSnapshot();
    document.comments.add(DocComment(
      id: _genId('cmt'),
      author: author,
      text: text.trim(),
      blockId: selectedBlockId,
    ));
    statusMessage = 'Added review comment';
    notifyListeners();
  }

  void toggleResolveComment(String commentId) {
    final idx = document.comments.indexWhere((c) => c.id == commentId);
    if (idx == -1) return;
    _recordSnapshot();
    document.comments[idx].resolved = !document.comments[idx].resolved;
    notifyListeners();
  }

  void deleteComment(String commentId) {
    _recordSnapshot();
    document.comments.removeWhere((c) => c.id == commentId);
    notifyListeners();
  }

  int get searchMatchCount {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return 0;
    var count = 0;
    for (final blk in document.blocks) {
      final hay = blk.plainContent.toLowerCase();
      var start = 0;
      while (true) {
        final pos = hay.indexOf(q, start);
        if (pos == -1) break;
        count++;
        start = pos + q.length;
      }
    }
    return count;
  }

  int replaceAll(String findStr, String replaceStr) {
    if (findStr.isEmpty) return 0;
    _recordSnapshot();
    var replaced = 0;
    for (final blk in document.blocks) {
      if (blk.text.contains(findStr)) {
        final matches = findStr.allMatches(blk.text).length;
        replaced += matches;
        blk.text = blk.text.replaceAll(findStr, replaceStr);
      }
      for (var i = 0; i < blk.listItems.length; i++) {
        if (blk.listItems[i].contains(findStr)) {
          blk.listItems[i] =
              blk.listItems[i].replaceAll(findStr, replaceStr);
        }
      }
      for (var r = 0; r < blk.tableRows.length; r++) {
        for (var c = 0; c < blk.tableRows[r].length; c++) {
          if (blk.tableRows[r][c].contains(findStr)) {
            replaced += findStr.allMatches(blk.tableRows[r][c]).length;
            blk.tableRows[r][c] =
                blk.tableRows[r][c].replaceAll(findStr, replaceStr);
          }
        }
      }
    }
    statusMessage = 'Replaced $replaced occurrence(s)';
    notifyListeners();
    return replaced;
  }

  // ===========================================================================
  // FILE I/O & TEMPLATES
  // ===========================================================================

  void loadTemplate(FyrDocument templateDoc) {
    _recordSnapshot();
    document = templateDoc;
    selectedBlockId =
        document.blocks.isNotEmpty ? document.blocks.first.id : null;
    statusMessage = 'Loaded template "${document.title}"';
    notifyListeners();
  }

  void newBlankDocument() {
    _recordSnapshot();
    document = buildBlankTemplate();
    selectedBlockId =
        document.blocks.isNotEmpty ? document.blocks.first.id : null;
    statusMessage = 'Created new document';
    notifyListeners();
  }

  void newDocument() => newBlankDocument();

  Future<void> openDocumentFile(String filePath) async {
    try {
      final loaded = await DocIO.loadFromFile(filePath);
      _undoStack.clear();
      _redoStack.clear();
      document = loaded;
      selectedBlockId =
          document.blocks.isNotEmpty ? document.blocks.first.id : null;
      statusMessage =
          'Opened ${p.basename(filePath)} (${document.format.toUpperCase()})';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Failed to open file: $e';
      notifyListeners();
    }
  }

  Future<void> saveDocumentFile(String filePath) async {
    try {
      await DocIO.saveToFile(document, filePath);
      statusMessage =
          'Saved ${p.basename(filePath)} (${document.format.toUpperCase()})';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Save error: $e';
      notifyListeners();
    }
  }

  Future<void> exportPdfFile(String filePath) async {
    try {
      final outPath =
          filePath.toLowerCase().endsWith('.pdf') ? filePath : '$filePath.pdf';
      final bytes = DocIO.encodePdfBytes(document);
      await File(outPath).writeAsBytes(bytes, flush: true);
      statusMessage = 'Exported PDF to ${p.basename(outPath)}';
      notifyListeners();
    } catch (e) {
      statusMessage = 'PDF export failed: $e';
      notifyListeners();
    }
  }

  Future<void> launchSuiteApp(String binaryName) async {
    try {
      await Process.start(binaryName, const [],
          mode: ProcessStartMode.detached);
      statusMessage = 'Launched $binaryName';
      notifyListeners();
    } catch (_) {
      statusMessage = '$binaryName is part of fyrOffice suite';
      notifyListeners();
    }
  }

  // ===========================================================================
  // BUILT-IN DOCUMENT TEMPLATES
  // ===========================================================================

  static List<DocTemplateItem> get templates => [
        DocTemplateItem(
          id: 'rfc',
          name: 'fyrDE Architecture RFC',
          subtitle: 'Technical specification with tables & code',
          icon: Icons.architecture_rounded,
          builder: buildArchitectureRfcTemplate,
        ),
        DocTemplateItem(
          id: 'proposal',
          name: 'Executive Proposal',
          subtitle: 'Product roadmap, milestones & budget table',
          icon: Icons.business_center_rounded,
          builder: buildExecutiveProposalTemplate,
        ),
        DocTemplateItem(
          id: 'resume',
          name: 'Systems Engineer Resume',
          subtitle: 'Clean one-page CV in OpenDocument format',
          icon: Icons.badge_rounded,
          builder: buildResumeTemplate,
        ),
        DocTemplateItem(
          id: 'meeting',
          name: 'Sprint Meeting Notes',
          subtitle: 'Agenda, action checklist & blockers',
          icon: Icons.fact_check_rounded,
          builder: buildMeetingNotesTemplate,
        ),
        DocTemplateItem(
          id: 'blank',
          name: 'Blank Document',
          subtitle: 'Clean A4 OpenDocument sheet',
          icon: Icons.insert_drive_file_outlined,
          builder: buildBlankTemplate,
        ),
      ];

  static FyrDocument buildArchitectureRfcTemplate() {
    return FyrDocument(
      id: 'doc_rfc_01',
      title: 'fyrDE_Architecture_RFC',
      format: 'odt',
      pageSize: PageSizePreset.a4,
      headerText: 'fyrDE Engineering • RFC-2026-09 (OpenDocument .ODT)',
      footerText: 'fyrDocs — Native OpenDocument & Word Processor',
      blocks: [
        DocBlock(
          id: 'b_title',
          type: DocBlockType.title,
          text: 'fyrDE Desktop & fyrOffice Suite Architecture',
          fontFamily: 'Outfit',
          fontSize: 26,
          bold: true,
        ),
        DocBlock(
          id: 'b_callout',
          type: DocBlockType.callout,
          text:
              'RFC Status: Approved for v2.4 Release • Pure-Dart OASIS OpenDocument (.odt / .ods / .odp) and ISO OpenXML (.docx / .xlsx / .pptx) engine with zero external telemetry.',
          calloutIcon: 'verified',
        ),
        DocBlock(
          id: 'b_h1_1',
          type: DocBlockType.heading1,
          text: '1. Executive Summary',
          fontFamily: 'Outfit',
          fontSize: 20,
          bold: true,
        ),
        DocBlock(
          id: 'b_p1',
          type: DocBlockType.paragraph,
          text:
              'fyrDE is a cohesive Wayland desktop environment engineered around SwayFX and a unified Flutter desktop application ecosystem. With the introduction of fyrOffice (fyrDocs, fyrSheets, and fyrSlides), users gain full local compatibility with LibreOffice and Microsoft Office file formats inside a sleek, hardware-accelerated glassmorphic interface.',
          fontSize: 14,
        ),
        DocBlock(
          id: 'b_h1_2',
          type: DocBlockType.heading1,
          text: '2. Wayland Compositor & Shell Integration',
          fontFamily: 'Outfit',
          fontSize: 20,
          bold: true,
        ),
        DocBlock(
          id: 'b_list1',
          type: DocBlockType.bulletList,
          listItems: [
            'Live accent color synchronization via ~/.config/fyr/theme.txt filesystem events',
            'Frameless CSD windows with macOS-inspired traffic lights and 8-edge resize handles',
            'Sub-millisecond ZIP/XML streaming for .odt and .docx documents up to 50,000 words',
            'Built-in PDF 1.4 vector export without external ghostscript dependencies',
          ],
          text:
              'Live accent color synchronization via ~/.config/fyr/theme.txt filesystem events\nFrameless CSD windows with macOS-inspired traffic lights and 8-edge resize handles\nSub-millisecond ZIP/XML streaming for .odt and .docx documents up to 50,000 words\nBuilt-in PDF 1.4 vector export without external ghostscript dependencies',
        ),
        DocBlock(
          id: 'b_h1_3',
          type: DocBlockType.heading1,
          text: '3. fyrOffice Format Matrix',
          fontFamily: 'Outfit',
          fontSize: 20,
          bold: true,
        ),
        DocBlock(
          id: 'b_tbl1',
          type: DocBlockType.table,
          tableRows: [
            ['Application', 'Binary', 'Native Formats', 'Export Targets'],
            ['fyrDocs', 'fyrdocs', '.odt, .docx, .md', '.pdf, .html, .txt'],
            ['fyrSheets', 'fyrsheets', '.ods, .xlsx, .csv', '.tsv, .json, .html'],
            ['fyrSlides', 'fyrslides', '.odp, .pptx, .json', '.pdf, .svg, .html'],
          ],
        ),
        DocBlock(
          id: 'b_code1',
          type: DocBlockType.codeBlock,
          fontFamily: 'JetBrains Mono',
          fontSize: 12.5,
          codeLanguage: 'dart',
          text:
              'final bytes = DocIO.encodeOdtBytes(controller.document);\nawait File("fyrDE_Architecture_RFC.odt").writeAsBytes(bytes);',
        ),
        DocBlock(
          id: 'b_chk1',
          type: DocBlockType.checklist,
          checked: true,
          text: 'Validate OASIS ODF 1.2 mimetype & manifest.xml compliance',
        ),
      ],
      comments: [
        DocComment(
          id: 'c_1',
          author: 'archer',
          text:
              'Verified that LibreOffice Writer 24.8 opens our generated .odt tables and headings cleanly.',
          blockId: 'b_tbl1',
        ),
        DocComment(
          id: 'c_2',
          author: 'maya',
          text: 'Make sure PDF export includes page numbers in the footer.',
          blockId: 'b_h1_3',
          resolved: true,
        ),
      ],
    );
  }

  static FyrDocument buildExecutiveProposalTemplate() {
    return FyrDocument(
      id: 'doc_prop_01',
      title: 'Q4_Product_Proposal',
      format: 'docx',
      blocks: [
        DocBlock(
          id: 'p_t',
          type: DocBlockType.title,
          text: 'Q4 Engineering & Product Expansion Proposal',
          fontFamily: 'Outfit',
          fontSize: 26,
          bold: true,
        ),
        DocBlock(
          id: 'p_h1',
          type: DocBlockType.heading1,
          text: '1. Strategic Objectives',
          fontFamily: 'Outfit',
          fontSize: 20,
          bold: true,
        ),
        DocBlock(
          id: 'p_body',
          type: DocBlockType.paragraph,
          text:
              'Deliver a complete, self-contained workstation suite for Linux engineers and creators with zero cloud lock-in and instant startup.',
        ),
        DocBlock(
          id: 'p_tbl',
          type: DocBlockType.table,
          tableRows: [
            ['Milestone', 'Owner', 'Target Date', 'Budget'],
            ['fyrOffice 1.0 GA', 'Core Desktop Team', 'Nov 2026', '\$45,000'],
            ['Wayland HDR Pipeline', 'Compositor Team', 'Dec 2026', '\$30,000'],
          ],
        ),
      ],
    );
  }

  static FyrDocument buildResumeTemplate() {
    return FyrDocument(
      id: 'doc_cv_01',
      title: 'Alex_Mercer_Systems_CV',
      format: 'odt',
      blocks: [
        DocBlock(
          id: 'cv_t',
          type: DocBlockType.title,
          text: 'Alex Mercer — Principal Systems Architect',
          fontFamily: 'Outfit',
          fontSize: 25,
          bold: true,
        ),
        DocBlock(
          id: 'cv_h1',
          type: DocBlockType.heading1,
          text: 'Experience',
          fontFamily: 'Outfit',
          fontSize: 19,
          bold: true,
        ),
        DocBlock(
          id: 'cv_l1',
          type: DocBlockType.bulletList,
          listItems: [
            'Lead Maintainer, fyrDE Wayland Desktop Environment (2023–Present)',
            'Architected pure-Dart OpenDocument & OpenXML engines for fyrOffice',
            'Reduced compositor frame latency by 38% on integrated GPUs',
          ],
          text:
              'Lead Maintainer, fyrDE Wayland Desktop Environment (2023–Present)\nArchitected pure-Dart OpenDocument & OpenXML engines for fyrOffice\nReduced compositor frame latency by 38% on integrated GPUs',
        ),
      ],
    );
  }

  static FyrDocument buildMeetingNotesTemplate() {
    return FyrDocument(
      id: 'doc_mtg_01',
      title: 'Sprint_42_Sync_Notes',
      format: 'odt',
      blocks: [
        DocBlock(
          id: 'm_t',
          type: DocBlockType.title,
          text: 'Sprint 42 Engineering Sync',
          fontFamily: 'Outfit',
          fontSize: 24,
          bold: true,
        ),
        DocBlock(
          id: 'm_c1',
          type: DocBlockType.checklist,
          checked: true,
          text: 'Ship fyrDocs .odt / .docx round-trip reader & writer',
        ),
        DocBlock(
          id: 'm_c2',
          type: DocBlockType.checklist,
          checked: false,
          text: 'Benchmark 200-page PDF export throughput',
        ),
      ],
    );
  }

  static FyrDocument buildBlankTemplate() {
    return FyrDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Untitled Document',
      format: 'odt',
      headerText: '',
      footerText: '',
      blocks: [
        DocBlock(
          id: 'blk_1',
          type: DocBlockType.paragraph,
          text: '',
        ),
      ],
    );
  }
}
