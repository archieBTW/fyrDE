import 'dart:convert';
import 'package:flutter/material.dart';

enum DocBlockType {
  title,
  heading1,
  heading2,
  heading3,
  paragraph,
  blockquote,
  codeBlock,
  bulletList,
  numberedList,
  checklist,
  table,
  callout,
  divider,
  pageBreak,
}

extension DocBlockTypeExt on DocBlockType {
  String get label {
    switch (this) {
      case DocBlockType.title:
        return 'Title';
      case DocBlockType.heading1:
        return 'Heading 1';
      case DocBlockType.heading2:
        return 'Heading 2';
      case DocBlockType.heading3:
        return 'Heading 3';
      case DocBlockType.paragraph:
        return 'Paragraph';
      case DocBlockType.blockquote:
        return 'Quote';
      case DocBlockType.codeBlock:
        return 'Code Block';
      case DocBlockType.bulletList:
        return 'Bullet List';
      case DocBlockType.numberedList:
        return 'Numbered List';
      case DocBlockType.checklist:
        return 'Checklist';
      case DocBlockType.table:
        return 'Table';
      case DocBlockType.callout:
        return 'Callout';
      case DocBlockType.divider:
        return 'Divider';
      case DocBlockType.pageBreak:
        return 'Page Break';
    }
  }

  bool get isHeading =>
      this == DocBlockType.title ||
      this == DocBlockType.heading1 ||
      this == DocBlockType.heading2 ||
      this == DocBlockType.heading3;

  int get outlineLevel {
    switch (this) {
      case DocBlockType.title:
        return 0;
      case DocBlockType.heading1:
        return 1;
      case DocBlockType.heading2:
        return 2;
      case DocBlockType.heading3:
        return 3;
      default:
        return 4;
    }
  }
}

enum TextAlignOption {
  left,
  center,
  right,
  justify,
}

extension TextAlignOptionExt on TextAlignOption {
  TextAlign get toFlutterAlign {
    switch (this) {
      case TextAlignOption.left:
        return TextAlign.left;
      case TextAlignOption.center:
        return TextAlign.center;
      case TextAlignOption.right:
        return TextAlign.right;
      case TextAlignOption.justify:
        return TextAlign.justify;
    }
  }

  String get label {
    switch (this) {
      case TextAlignOption.left:
        return 'Left';
      case TextAlignOption.center:
        return 'Center';
      case TextAlignOption.right:
        return 'Right';
      case TextAlignOption.justify:
        return 'Justify';
    }
  }
}

class PageSizePreset {
  final String name;
  final double widthPt;
  final double heightPt;
  final double marginHorizontal;
  final double marginVertical;

  const PageSizePreset({
    required this.name,
    required this.widthPt,
    required this.heightPt,
    required this.marginHorizontal,
    required this.marginVertical,
  });

  static const PageSizePreset a4 = PageSizePreset(
    name: 'A4',
    widthPt: 760,
    heightPt: 1075,
    marginHorizontal: 56,
    marginVertical: 52,
  );

  static const PageSizePreset usLetter = PageSizePreset(
    name: 'US Letter',
    widthPt: 768,
    heightPt: 994,
    marginHorizontal: 56,
    marginVertical: 52,
  );

  static const PageSizePreset legal = PageSizePreset(
    name: 'Legal',
    widthPt: 768,
    heightPt: 1248,
    marginHorizontal: 56,
    marginVertical: 52,
  );

  static const PageSizePreset wideCanvas = PageSizePreset(
    name: 'Wide Canvas',
    widthPt: 920,
    heightPt: 1080,
    marginHorizontal: 48,
    marginVertical: 44,
  );

  static const List<PageSizePreset> presets = [
    a4,
    usLetter,
    legal,
    wideCanvas,
  ];

  static PageSizePreset fromName(String name) {
    return presets.firstWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase(),
      orElse: () => a4,
    );
  }
}

class DocBlock {
  String id;
  DocBlockType type;
  String text;
  String fontFamily;
  double fontSize;
  bool bold;
  bool italic;
  bool underline;
  bool strikethrough;
  String textColorHex;
  String highlightColorHex;
  TextAlignOption align;
  int indentLevel;
  bool checked;
  List<String> listItems;
  List<List<String>> tableRows;
  String codeLanguage;
  String calloutIcon;

  DocBlock({
    required this.id,
    this.type = DocBlockType.paragraph,
    this.text = '',
    this.fontFamily = 'Inter',
    this.fontSize = 14.0,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.textColorHex = '#FFFFFF',
    this.highlightColorHex = '',
    this.align = TextAlignOption.left,
    this.indentLevel = 0,
    this.checked = false,
    List<String>? listItems,
    List<List<String>>? tableRows,
    this.codeLanguage = 'dart',
    this.calloutIcon = 'info',
  })  : listItems = listItems ?? <String>[],
        tableRows = tableRows ?? <List<String>>[];

  DocBlock copyWith({
    String? id,
    DocBlockType? type,
    String? text,
    String? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    String? textColorHex,
    String? highlightColorHex,
    TextAlignOption? align,
    int? indentLevel,
    bool? checked,
    List<String>? listItems,
    List<List<String>>? tableRows,
    String? codeLanguage,
    String? calloutIcon,
  }) {
    return DocBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      textColorHex: textColorHex ?? this.textColorHex,
      highlightColorHex: highlightColorHex ?? this.highlightColorHex,
      align: align ?? this.align,
      indentLevel: indentLevel ?? this.indentLevel,
      checked: checked ?? this.checked,
      listItems: listItems ?? List<String>.from(this.listItems),
      tableRows: tableRows ??
          this.tableRows.map((r) => List<String>.from(r)).toList(),
      codeLanguage: codeLanguage ?? this.codeLanguage,
      calloutIcon: calloutIcon ?? this.calloutIcon,
    );
  }

  String get plainContent {
    if (type == DocBlockType.bulletList ||
        type == DocBlockType.numberedList) {
      if (listItems.isNotEmpty) {
        return listItems.join('\n');
      }
    }
    if (type == DocBlockType.table) {
      return tableRows.map((r) => r.join(' ')).join('\n');
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'strikethrough': strikethrough,
        'textColorHex': textColorHex,
        'highlightColorHex': highlightColorHex,
        'align': align.name,
        'indentLevel': indentLevel,
        'checked': checked,
        'listItems': listItems,
        'tableRows': tableRows,
        'codeLanguage': codeLanguage,
        'calloutIcon': calloutIcon,
      };

  factory DocBlock.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? 'paragraph';
    final alignStr = (json['align'] as String?) ?? 'left';
    final rawList = (json['listItems'] as List<dynamic>?) ?? const [];
    final rawTable = (json['tableRows'] as List<dynamic>?) ?? const [];

    return DocBlock(
      id: (json['id'] as String?) ?? 'blk_0',
      type: DocBlockType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => DocBlockType.paragraph,
      ),
      text: (json['text'] as String?) ?? '',
      fontFamily: (json['fontFamily'] as String?) ?? 'Inter',
      fontSize: ((json['fontSize'] as num?) ?? 14.0).toDouble(),
      bold: (json['bold'] as bool?) ?? false,
      italic: (json['italic'] as bool?) ?? false,
      underline: (json['underline'] as bool?) ?? false,
      strikethrough: (json['strikethrough'] as bool?) ?? false,
      textColorHex: (json['textColorHex'] as String?) ?? '#FFFFFF',
      highlightColorHex: (json['highlightColorHex'] as String?) ?? '',
      align: TextAlignOption.values.firstWhere(
        (e) => e.name == alignStr,
        orElse: () => TextAlignOption.left,
      ),
      indentLevel: (json['indentLevel'] as int?) ?? 0,
      checked: (json['checked'] as bool?) ?? false,
      listItems: rawList.map((e) => e.toString()).toList(),
      tableRows: rawTable
          .map((row) =>
              (row as List<dynamic>).map((cell) => cell.toString()).toList())
          .toList(),
      codeLanguage: (json['codeLanguage'] as String?) ?? 'dart',
      calloutIcon: (json['calloutIcon'] as String?) ?? 'info',
    );
  }
}

class DocComment {
  String id;
  String author;
  String text;
  DateTime createdAt;
  String? blockId;
  bool resolved;

  DocComment({
    required this.id,
    required this.author,
    required this.text,
    DateTime? createdAt,
    this.blockId,
    this.resolved = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'blockId': blockId,
        'resolved': resolved,
      };

  factory DocComment.fromJson(Map<String, dynamic> json) => DocComment(
        id: (json['id'] as String?) ?? 'cmt_0',
        author: (json['author'] as String?) ?? 'archer',
        text: (json['text'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.now(),
        blockId: json['blockId'] as String?,
        resolved: (json['resolved'] as bool?) ?? false,
      );
}

class FyrDocument {
  String id;
  String title;
  String? filePath;
  String format; // 'odt', 'docx', 'md', 'html', 'txt'
  PageSizePreset pageSize;
  bool showRuler;
  bool showPageMargins;
  String headerText;
  String footerText;
  bool showPageNumbers;
  double lineSpacing;
  List<DocBlock> blocks;
  List<DocComment> comments;
  DateTime modifiedAt;

  FyrDocument({
    required this.id,
    required this.title,
    this.filePath,
    this.format = 'odt',
    this.pageSize = PageSizePreset.a4,
    this.showRuler = true,
    this.showPageMargins = true,
    this.headerText = 'fyrDE Engineering • Confidential RFC',
    this.footerText = 'fyrOffice OpenDocument Processor',
    this.showPageNumbers = true,
    this.lineSpacing = 1.45,
    List<DocBlock>? blocks,
    List<DocComment>? comments,
    DateTime? modifiedAt,
  })  : blocks = blocks ?? <DocBlock>[],
        comments = comments ?? <DocComment>[],
        modifiedAt = modifiedAt ?? DateTime.now();

  String get fullPlainText =>
      blocks.map((b) => b.plainContent).where((s) => s.isNotEmpty).join('\n');

  int get wordCount {
    final content = fullPlainText.trim();
    if (content.isEmpty) return 0;
    return content
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .length;
  }

  int get charCount => fullPlainText.length;

  int get charCountNoSpaces =>
      fullPlainText.replaceAll(RegExp(r'\s+'), '').length;

  int get paragraphCount => blocks
      .where((b) =>
          b.type != DocBlockType.divider && b.type != DocBlockType.pageBreak)
      .length;

  int get readingTimeMinutes {
    final words = wordCount;
    if (words == 0) return 0;
    final mins = (words / 200).ceil();
    return mins < 1 ? 1 : mins;
  }

  int get estimatedPageCount {
    final pageBreaks =
        blocks.where((b) => b.type == DocBlockType.pageBreak).length;
    final wordsPages = (wordCount / 320).ceil().clamp(1, 99);
    return (wordsPages + pageBreaks).clamp(1, 99);
  }

  List<DocBlock> get outlineHeadings =>
      blocks.where((b) => b.type.isHeading).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'format': format,
        'pageSize': pageSize.name,
        'showRuler': showRuler,
        'showPageMargins': showPageMargins,
        'headerText': headerText,
        'footerText': footerText,
        'showPageNumbers': showPageNumbers,
        'lineSpacing': lineSpacing,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'comments': comments.map((c) => c.toJson()).toList(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory FyrDocument.fromJson(Map<String, dynamic> json) {
    final rawBlocks = (json['blocks'] as List<dynamic>?) ?? const [];
    final rawComments = (json['comments'] as List<dynamic>?) ?? const [];
    return FyrDocument(
      id: (json['id'] as String?) ?? 'doc_1',
      title: (json['title'] as String?) ?? 'Untitled Document',
      filePath: json['filePath'] as String?,
      format: (json['format'] as String?) ?? 'odt',
      pageSize:
          PageSizePreset.fromName((json['pageSize'] as String?) ?? 'A4'),
      showRuler: (json['showRuler'] as bool?) ?? true,
      showPageMargins: (json['showPageMargins'] as bool?) ?? true,
      headerText: (json['headerText'] as String?) ?? '',
      footerText: (json['footerText'] as String?) ?? '',
      showPageNumbers: (json['showPageNumbers'] as bool?) ?? true,
      lineSpacing: ((json['lineSpacing'] as num?) ?? 1.45).toDouble(),
      blocks: rawBlocks
          .map((b) => DocBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      comments: rawComments
          .map((c) => DocComment.fromJson(c as Map<String, dynamic>))
          .toList(),
      modifiedAt: DateTime.tryParse((json['modifiedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  factory FyrDocument.fromJsonString(String raw) =>
      FyrDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
