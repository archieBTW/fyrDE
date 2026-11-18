import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../models/doc_models.dart';

class DocIO {
  static const String odtMimeType = 'application/vnd.oasis.opendocument.text';

  // ===========================================================================
  // FILE DISPATCHER
  // ===========================================================================

  static Future<FyrDocument> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Document file does not exist', filePath);
    }

    final ext = p.extension(filePath).toLowerCase();
    final baseTitle = p.basenameWithoutExtension(filePath);

    if (ext == '.odt') {
      final doc = await loadOdt(filePath);
      doc.filePath = filePath;
      doc.format = 'odt';
      if (doc.title.isEmpty || doc.title == 'Untitled Document') {
        doc.title = baseTitle;
      }
      return doc;
    } else if (ext == '.docx') {
      final doc = await loadDocx(filePath);
      doc.filePath = filePath;
      doc.format = 'docx';
      if (doc.title.isEmpty || doc.title == 'Untitled Document') {
        doc.title = baseTitle;
      }
      return doc;
    } else if (ext == '.md' || ext == '.markdown') {
      final raw = await file.readAsString();
      final doc = fromMarkdown(raw, title: baseTitle);
      doc.filePath = filePath;
      doc.format = 'md';
      return doc;
    } else if (ext == '.html' || ext == '.htm') {
      final raw = await file.readAsString();
      final doc = fromHtml(raw, title: baseTitle);
      doc.filePath = filePath;
      doc.format = 'html';
      return doc;
    } else if (ext == '.doc' || ext == '.rtf') {
      final converted = await _tryLibreOfficeConvertToOdt(filePath);
      if (converted != null) {
        converted.filePath = filePath;
        converted.title = baseTitle;
        return converted;
      }
      final raw = await file.readAsString(encoding: latin1);
      final doc = fromPlainText(raw, title: baseTitle);
      doc.filePath = filePath;
      doc.format = 'txt';
      return doc;
    } else {
      final raw = await file.readAsString();
      final doc = fromPlainText(raw, title: baseTitle);
      doc.filePath = filePath;
      doc.format = 'txt';
      return doc;
    }
  }

  static Future<void> saveToFile(FyrDocument doc, String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }

    if (ext == '.odt') {
      doc.format = 'odt';
      doc.filePath = filePath;
      await saveOdt(doc, filePath);
    } else if (ext == '.docx') {
      doc.format = 'docx';
      doc.filePath = filePath;
      await saveDocx(doc, filePath);
    } else if (ext == '.md' || ext == '.markdown') {
      doc.format = 'md';
      doc.filePath = filePath;
      await file.writeAsString(toMarkdown(doc));
    } else if (ext == '.html' || ext == '.htm') {
      doc.format = 'html';
      doc.filePath = filePath;
      await file.writeAsString(toHtml(doc));
    } else if (ext == '.pdf') {
      final bytes = encodePdfBytes(doc);
      await file.writeAsBytes(bytes, flush: true);
    } else {
      doc.format = 'txt';
      doc.filePath = filePath;
      await file.writeAsString(toPlainText(doc));
    }
  }

  static Future<FyrDocument?> _tryLibreOfficeConvertToOdt(
      String inputPath) async {
    try {
      final tmpDir =
          await Directory.systemTemp.createTemp('fyrdocs_lo_import_');
      try {
        final res = await Process.run('libreoffice', [
          '--headless',
          '--convert-to',
          'odt',
          '--outdir',
          tmpDir.path,
          inputPath,
        ]);
        if (res.exitCode == 0) {
          final outName = '${p.basenameWithoutExtension(inputPath)}.odt';
          final outFile = File(p.join(tmpDir.path, outName));
          if (outFile.existsSync()) {
            return await loadOdt(outFile.path);
          }
        }
      } finally {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {
      // LibreOffice not installed or sandboxed.
    }
    return null;
  }

  // ===========================================================================
  // OPENDOCUMENT TEXT (.ODT) READER & WRITER
  // ===========================================================================

  static Future<void> saveOdt(FyrDocument doc, String filePath) async {
    final bytes = encodeOdtBytes(doc);
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  static Future<FyrDocument> loadOdt(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return decodeOdtBytes(bytes,
        fallbackTitle: p.basenameWithoutExtension(filePath));
  }

  static Uint8List encodeOdtBytes(FyrDocument doc) {
    final archive = Archive();

    // 1. Uncompressed mimetype must be first entry per ODF 1.2 specification
    final mimeBytes = utf8.encode(odtMimeType);
    archive.add(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    // 2. META-INF/manifest.xml
    const manifestXml = '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.text"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>''';
    archive.add(ArchiveFile.string('META-INF/manifest.xml', manifestXml));

    // 3. meta.xml
    final metaBuilder = XmlBuilder();
    metaBuilder.processing('xml', 'version="1.0" encoding="UTF-8"');
    metaBuilder.element(
      'office:document-meta',
      namespaces: {
        'urn:oasis:names:tc:opendocument:xmlns:office:1.0': 'office',
        'http://purl.org/dc/elements/1.1/': 'dc',
        'urn:oasis:names:tc:opendocument:xmlns:meta:1.0': 'meta',
        'https://fyrde.dev/ns/fyrdocs/1.0': 'fyr',
      },
      attributes: {'office:version': '1.2'},
      nest: () {
        metaBuilder.element('office:meta', nest: () {
          metaBuilder.element('dc:title', nest: doc.title);
          metaBuilder.element('dc:date',
              nest: doc.modifiedAt.toUtc().toIso8601String());
          metaBuilder.element('meta:generator', nest: 'fyrDocs/1.0 (fyrOffice)');
          metaBuilder.element('fyr:page-size', nest: doc.pageSize.name);
          metaBuilder.element('fyr:header', nest: doc.headerText);
          metaBuilder.element('fyr:footer', nest: doc.footerText);
          metaBuilder.element('fyr:line-spacing',
              nest: doc.lineSpacing.toString());
        });
      },
    );
    archive.add(ArchiveFile.string(
      'meta.xml',
      metaBuilder.buildDocument().toXmlString(pretty: true),
    ));

    // 4. styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.2">
  <office:styles>
    <style:default-style style:family="paragraph">
      <style:paragraph-properties fo:line-height="145%"/>
      <style:text-properties style:font-name="Inter" fo:font-size="14pt"/>
    </style:default-style>
  </office:styles>
</office:document-styles>''';
    archive.add(ArchiveFile.string('styles.xml', stylesXml));

    // 5. content.xml
    final contentBuilder = XmlBuilder();
    contentBuilder.processing('xml', 'version="1.0" encoding="UTF-8"');
    contentBuilder.element(
      'office:document-content',
      namespaces: {
        'urn:oasis:names:tc:opendocument:xmlns:office:1.0': 'office',
        'urn:oasis:names:tc:opendocument:xmlns:text:1.0': 'text',
        'urn:oasis:names:tc:opendocument:xmlns:table:1.0': 'table',
        'urn:oasis:names:tc:opendocument:xmlns:style:1.0': 'style',
        'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0': 'fo',
        'https://fyrde.dev/ns/fyrdocs/1.0': 'fyr',
      },
      attributes: {'office:version': '1.2'},
      nest: () {
        // Automatic styles for each block
        contentBuilder.element('office:automatic-styles', nest: () {
          for (var i = 0; i < doc.blocks.length; i++) {
            final blk = doc.blocks[i];
            final styleName = 'P_${i + 1}';
            contentBuilder.element(
              'style:style',
              attributes: {
                'style:name': styleName,
                'style:family': 'paragraph',
              },
              nest: () {
                contentBuilder.element(
                  'style:paragraph-properties',
                  attributes: {
                    'fo:text-align': blk.align.name,
                  },
                );
                contentBuilder.element(
                  'style:text-properties',
                  attributes: {
                    'style:font-name': blk.fontFamily,
                    'fo:font-size': '${blk.fontSize}pt',
                    if (blk.bold) 'fo:font-weight': 'bold',
                    if (blk.italic) 'fo:font-style': 'italic',
                    if (blk.underline) 'style:text-underline-style': 'solid',
                    if (blk.strikethrough)
                      'style:text-line-through-style': 'solid',
                    'fo:color': blk.textColorHex,
                    if (blk.highlightColorHex.isNotEmpty)
                      'fo:background-color': blk.highlightColorHex,
                  },
                );
              },
            );
          }
        });

        contentBuilder.element('office:body', nest: () {
          contentBuilder.element('office:text', nest: () {
            for (var i = 0; i < doc.blocks.length; i++) {
              final blk = doc.blocks[i];
              final styleName = 'P_${i + 1}';
              final commonAttrs = <String, String>{
                'text:style-name': styleName,
                'fyr:id': blk.id,
                'fyr:block-type': blk.type.name,
                'fyr:font-family': blk.fontFamily,
                'fyr:font-size': blk.fontSize.toString(),
                'fyr:bold': blk.bold.toString(),
                'fyr:italic': blk.italic.toString(),
                'fyr:underline': blk.underline.toString(),
                'fyr:strikethrough': blk.strikethrough.toString(),
                'fyr:color': blk.textColorHex,
                'fyr:highlight': blk.highlightColorHex,
                'fyr:align': blk.align.name,
                'fyr:indent': blk.indentLevel.toString(),
              };

              switch (blk.type) {
                case DocBlockType.title:
                case DocBlockType.heading1:
                case DocBlockType.heading2:
                case DocBlockType.heading3:
                  final level = blk.type == DocBlockType.title
                      ? '1'
                      : blk.type.outlineLevel.toString();
                  contentBuilder.element(
                    'text:h',
                    attributes: {
                      ...commonAttrs,
                      'text:outline-level': level,
                    },
                    nest: blk.text,
                  );
                  break;

                case DocBlockType.bulletList:
                case DocBlockType.numberedList:
                  final items = blk.listItems.isNotEmpty
                      ? blk.listItems
                      : blk.text
                          .split('\n')
                          .where((s) => s.trim().isNotEmpty)
                          .toList();
                  contentBuilder.element(
                    'text:list',
                    attributes: commonAttrs,
                    nest: () {
                      for (final item in items) {
                        contentBuilder.element('text:list-item', nest: () {
                          contentBuilder.element('text:p', nest: item);
                        });
                      }
                    },
                  );
                  break;

                case DocBlockType.table:
                  contentBuilder.element(
                    'table:table',
                    attributes: {
                      'table:name': 'Table_${i + 1}',
                      ...commonAttrs,
                    },
                    nest: () {
                      for (final row in blk.tableRows) {
                        contentBuilder.element('table:table-row', nest: () {
                          for (final cell in row) {
                            contentBuilder.element(
                              'table:table-cell',
                              attributes: {'office:value-type': 'string'},
                              nest: () {
                                contentBuilder.element('text:p', nest: cell);
                              },
                            );
                          }
                        });
                      }
                    },
                  );
                  break;

                case DocBlockType.checklist:
                  contentBuilder.element(
                    'text:p',
                    attributes: {
                      ...commonAttrs,
                      'fyr:checked': blk.checked.toString(),
                    },
                    nest: blk.text,
                  );
                  break;

                case DocBlockType.codeBlock:
                  contentBuilder.element(
                    'text:p',
                    attributes: {
                      ...commonAttrs,
                      'fyr:code-lang': blk.codeLanguage,
                    },
                    nest: blk.text,
                  );
                  break;

                case DocBlockType.callout:
                  contentBuilder.element(
                    'text:p',
                    attributes: {
                      ...commonAttrs,
                      'fyr:callout-icon': blk.calloutIcon,
                    },
                    nest: blk.text,
                  );
                  break;

                default:
                  contentBuilder.element(
                    'text:p',
                    attributes: commonAttrs,
                    nest: blk.text,
                  );
                  break;
              }
            }
          });
        });
      },
    );

    archive.add(ArchiveFile.string(
      'content.xml',
      contentBuilder.buildDocument().toXmlString(pretty: true),
    ));

    return ZipEncoder().encodeBytes(archive);
  }

  static FyrDocument decodeOdtBytes(
    Uint8List bytes, {
    String fallbackTitle = 'Untitled Document',
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);

    var title = fallbackTitle;
    var pageSize = PageSizePreset.a4;
    var headerText = 'fyrDE Engineering • OpenDocument';
    var footerText = 'fyrOffice OpenDocument Processor';
    var lineSpacing = 1.45;

    // Parse meta.xml if present
    final metaEntry = archive.find('meta.xml');
    if (metaEntry != null) {
      final metaXmlStr = utf8.decode(metaEntry.content, allowMalformed: true);
      try {
        final metaDoc = XmlDocument.parse(metaXmlStr);
        final dcTitle = metaDoc.findAllElements('dc:title').firstOrNull ??
            metaDoc
                .findAllElements('title', namespace: '*')
                .firstOrNull;
        if (dcTitle != null && dcTitle.innerText.trim().isNotEmpty) {
          title = dcTitle.innerText.trim();
        }
        final psEl = metaDoc.findAllElements('fyr:page-size').firstOrNull;
        if (psEl != null) {
          pageSize = PageSizePreset.fromName(psEl.innerText.trim());
        }
        final hdrEl = metaDoc.findAllElements('fyr:header').firstOrNull;
        if (hdrEl != null) headerText = hdrEl.innerText;
        final ftrEl = metaDoc.findAllElements('fyr:footer').firstOrNull;
        if (ftrEl != null) footerText = ftrEl.innerText;
        final lsEl = metaDoc.findAllElements('fyr:line-spacing').firstOrNull;
        if (lsEl != null) {
          lineSpacing = double.tryParse(lsEl.innerText) ?? 1.45;
        }
      } catch (_) {}
    }

    final contentEntry = archive.find('content.xml');
    if (contentEntry == null) {
      throw const FormatException('Invalid .odt archive: missing content.xml');
    }

    final contentXmlStr =
        utf8.decode(contentEntry.content, allowMalformed: true);
    final xmlDoc = XmlDocument.parse(contentXmlStr);

    // Parse automatic styles map so external LibreOffice .odt files also preserve formatting
    final styleMap = <String, Map<String, String>>{};
    for (final styleEl in xmlDoc.findAllElements('style', namespace: '*')) {
      final name = styleEl.getAttribute('style:name') ??
          styleEl.getAttribute('name', namespace: '*');
      if (name == null) continue;
      final props = <String, String>{};
      for (final child in styleEl.children.whereType<XmlElement>()) {
        for (final attr in child.attributes) {
          props[attr.name.qualified] = attr.value;
          props[attr.name.local] = attr.value;
        }
      }
      styleMap[name] = props;
    }

    final officeText = xmlDoc
            .findAllElements('text',
                namespace: 'urn:oasis:names:tc:opendocument:xmlns:office:1.0')
            .firstOrNull ??
        xmlDoc.findAllElements('office:text').firstOrNull;

    final blocks = <DocBlock>[];
    var idx = 0;

    if (officeText != null) {
      for (final node in officeText.children.whereType<XmlElement>()) {
        idx++;
        final local = node.name.local;
        final styleName = node.getAttribute('text:style-name') ??
            node.getAttribute('style-name', namespace: '*') ??
            '';
        final styleProps = styleMap[styleName] ?? const {};

        final id = node.getAttribute('fyr:id') ?? 'odt_blk_$idx';
        final explicitTypeStr = node.getAttribute('fyr:block-type');

        final fontFamily = node.getAttribute('fyr:font-family') ??
            styleProps['style:font-name'] ??
            styleProps['font-name'] ??
            'Inter';
        final rawSizeStr = node.getAttribute('fyr:font-size') ??
            (styleProps['fo:font-size'] ?? styleProps['font-size'] ?? '14')
                .replaceAll('pt', '');
        final fontSize = double.tryParse(rawSizeStr) ?? 14.0;

        final bold = node.getAttribute('fyr:bold') == 'true' ||
            styleProps['fo:font-weight'] == 'bold' ||
            styleProps['font-weight'] == 'bold';
        final italic = node.getAttribute('fyr:italic') == 'true' ||
            styleProps['fo:font-style'] == 'italic' ||
            styleProps['font-style'] == 'italic';
        final underline = node.getAttribute('fyr:underline') == 'true' ||
            (styleProps['style:text-underline-style'] != null &&
                styleProps['style:text-underline-style'] != 'none');
        final strikethrough =
            node.getAttribute('fyr:strikethrough') == 'true' ||
                (styleProps['style:text-line-through-style'] != null &&
                    styleProps['style:text-line-through-style'] != 'none');

        final colorHex = node.getAttribute('fyr:color') ??
            styleProps['fo:color'] ??
            styleProps['color'] ??
            '#FFFFFF';
        final highlightHex = node.getAttribute('fyr:highlight') ??
            styleProps['fo:background-color'] ??
            '';
        final alignStr = node.getAttribute('fyr:align') ??
            styleProps['fo:text-align'] ??
            'left';
        final align = TextAlignOption.values.firstWhere(
          (a) => a.name == alignStr,
          orElse: () => TextAlignOption.left,
        );
        final indent =
            int.tryParse(node.getAttribute('fyr:indent') ?? '0') ?? 0;

        if (local == 'h') {
          final outlineLevel = int.tryParse(
                  node.getAttribute('text:outline-level') ??
                      node.getAttribute('outline-level', namespace: '*') ??
                      '1') ??
              1;
          DocBlockType hType;
          if (explicitTypeStr != null) {
            hType = DocBlockType.values.firstWhere(
              (t) => t.name == explicitTypeStr,
              orElse: () => DocBlockType.heading1,
            );
          } else if (outlineLevel <= 1) {
            hType = DocBlockType.heading1;
          } else if (outlineLevel == 2) {
            hType = DocBlockType.heading2;
          } else {
            hType = DocBlockType.heading3;
          }
          blocks.add(DocBlock(
            id: id,
            type: hType,
            text: node.innerText,
            fontFamily: fontFamily,
            fontSize: fontSize,
            bold: bold || true,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            textColorHex: colorHex,
            highlightColorHex: highlightHex,
            align: align,
            indentLevel: indent,
          ));
        } else if (local == 'list') {
          final items = <String>[];
          for (final li
              in node.findAllElements('list-item', namespace: '*')) {
            final t = li.innerText.trim();
            if (t.isNotEmpty) items.add(t);
          }
          final lType = explicitTypeStr == 'numberedList'
              ? DocBlockType.numberedList
              : DocBlockType.bulletList;
          blocks.add(DocBlock(
            id: id,
            type: lType,
            text: items.join('\n'),
            listItems: items,
            fontFamily: fontFamily,
            fontSize: fontSize,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            textColorHex: colorHex,
            highlightColorHex: highlightHex,
            align: align,
            indentLevel: indent,
          ));
        } else if (local == 'table') {
          final rows = <List<String>>[];
          for (final rEl in node.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'table-row')) {
            final rowCells = <String>[];
            for (final cEl in rEl.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'table-cell')) {
              rowCells.add(cEl.innerText.trim());
            }
            if (rowCells.isNotEmpty) {
              rows.add(rowCells);
            }
          }
          blocks.add(DocBlock(
            id: id,
            type: DocBlockType.table,
            tableRows: rows,
            fontFamily: fontFamily,
            fontSize: fontSize,
          ));
        } else if (local == 'p') {
          final bType = explicitTypeStr != null
              ? DocBlockType.values.firstWhere(
                  (t) => t.name == explicitTypeStr,
                  orElse: () => DocBlockType.paragraph,
                )
              : DocBlockType.paragraph;
          blocks.add(DocBlock(
            id: id,
            type: bType,
            text: node.innerText,
            fontFamily: fontFamily,
            fontSize: fontSize,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            textColorHex: colorHex,
            highlightColorHex: highlightHex,
            align: align,
            indentLevel: indent,
            checked: node.getAttribute('fyr:checked') == 'true',
            codeLanguage: node.getAttribute('fyr:code-lang') ?? 'dart',
            calloutIcon: node.getAttribute('fyr:callout-icon') ?? 'info',
          ));
        }
      }
    }

    if (blocks.isEmpty) {
      blocks.add(DocBlock(id: 'odt_blk_1', text: ''));
    }

    return FyrDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: 'odt',
      pageSize: pageSize,
      headerText: headerText,
      footerText: footerText,
      lineSpacing: lineSpacing,
      blocks: blocks,
    );
  }

  // ===========================================================================
  // MICROSOFT WORD OPENXML (.DOCX) READER & WRITER
  // ===========================================================================

  static Future<void> saveDocx(FyrDocument doc, String filePath) async {
    final bytes = encodeDocxBytes(doc);
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  static Future<FyrDocument> loadDocx(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return decodeDocxBytes(bytes,
        fallbackTitle: p.basenameWithoutExtension(filePath));
  }

  static Uint8List encodeDocxBytes(FyrDocument doc) {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>''';
    archive.add(ArchiveFile.string('[Content_Types].xml', contentTypesXml));

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''';
    archive.add(ArchiveFile.string('_rels/.rels', rootRelsXml));

    // 3. word/_rels/document.xml.rels
    const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';
    archive.add(ArchiveFile.string('word/_rels/document.xml.rels', docRelsXml));

    // 4. docProps/core.xml
    final coreBuilder = XmlBuilder();
    coreBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    coreBuilder.element(
      'cp:coreProperties',
      namespaces: {
        'http://schemas.openxmlformats.org/package/2006/metadata/core-properties':
            'cp',
        'http://purl.org/dc/elements/1.1/': 'dc',
        'http://purl.org/dc/terms/': 'dcterms',
      },
      nest: () {
        coreBuilder.element('dc:title', nest: doc.title);
        coreBuilder.element('dc:creator', nest: 'fyrDocs (fyrOffice)');
      },
    );
    archive.add(ArchiveFile.string(
      'docProps/core.xml',
      coreBuilder.buildDocument().toXmlString(pretty: true),
    ));

    // 5. word/styles.xml
    const wordStylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="ListBullet">
    <w:name w:val="List Bullet"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="ListNumber">
    <w:name w:val="List Number"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Quote">
    <w:name w:val="Quote"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="CodeBlock">
    <w:name w:val="Code Block"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Callout">
    <w:name w:val="Callout"/>
  </w:style>
</w:styles>''';
    archive.add(ArchiveFile.string('word/styles.xml', wordStylesXml));

    // 6. word/document.xml
    final docBuilder = XmlBuilder();
    docBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    docBuilder.element(
      'w:document',
      namespaces: {
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main': 'w',
        'https://fyrde.dev/ns/fyrdocs/1.0': 'fyr',
      },
      nest: () {
        docBuilder.element('w:body', nest: () {
          for (final blk in doc.blocks) {
            if (blk.type == DocBlockType.table) {
              docBuilder.element(
                'w:tbl',
                attributes: {'fyr:id': blk.id},
                nest: () {
                  for (final row in blk.tableRows) {
                    docBuilder.element('w:tr', nest: () {
                      for (final cell in row) {
                        docBuilder.element('w:tc', nest: () {
                          docBuilder.element('w:p', nest: () {
                            docBuilder.element('w:r', nest: () {
                              docBuilder.element(
                                'w:t',
                                attributes: {'xml:space': 'preserve'},
                                nest: cell,
                              );
                            });
                          });
                        });
                      }
                    });
                  }
                },
              );
            } else if (blk.type == DocBlockType.bulletList ||
                blk.type == DocBlockType.numberedList) {
              final items = blk.listItems.isNotEmpty
                  ? blk.listItems
                  : blk.text
                      .split('\n')
                      .where((s) => s.trim().isNotEmpty)
                      .toList();
              final pStyle = blk.type == DocBlockType.numberedList
                  ? 'ListNumber'
                  : 'ListBullet';
              for (var idx = 0; idx < items.length; idx++) {
                docBuilder.element(
                  'w:p',
                  attributes: {
                    'fyr:id': '${blk.id}_$idx',
                    'fyr:list-group': blk.id,
                    'fyr:block-type': blk.type.name,
                  },
                  nest: () {
                    docBuilder.element('w:pPr', nest: () {
                      docBuilder.element('w:pStyle',
                          attributes: {'w:val': pStyle});
                      docBuilder.element('w:numPr', nest: () {
                        docBuilder.element('w:ilvl',
                            attributes: {'w:val': blk.indentLevel.toString()});
                        docBuilder.element('w:numId',
                            attributes: {
                              'w:val': blk.type == DocBlockType.numberedList
                                  ? '2'
                                  : '1'
                            });
                      });
                    });
                    _buildDocxRun(docBuilder, blk, items[idx]);
                  },
                );
              }
            } else {
              docBuilder.element(
                'w:p',
                attributes: {
                  'fyr:id': blk.id,
                  'fyr:block-type': blk.type.name,
                  if (blk.type == DocBlockType.checklist)
                    'fyr:checked': blk.checked.toString(),
                  if (blk.type == DocBlockType.codeBlock)
                    'fyr:code-lang': blk.codeLanguage,
                  if (blk.type == DocBlockType.callout)
                    'fyr:callout-icon': blk.calloutIcon,
                },
                nest: () {
                  docBuilder.element('w:pPr', nest: () {
                    final styleId = _docxStyleIdForType(blk.type);
                    docBuilder.element('w:pStyle',
                        attributes: {'w:val': styleId});
                    final jcVal = blk.align == TextAlignOption.justify
                        ? 'both'
                        : blk.align.name;
                    docBuilder.element('w:jc', attributes: {'w:val': jcVal});
                  });
                  _buildDocxRun(docBuilder, blk, blk.text);
                },
              );
            }
          }
        });
      },
    );

    archive.add(ArchiveFile.string(
      'word/document.xml',
      docBuilder.buildDocument().toXmlString(pretty: true),
    ));

    return ZipEncoder().encodeBytes(archive);
  }

  static String _docxStyleIdForType(DocBlockType type) {
    switch (type) {
      case DocBlockType.title:
        return 'Title';
      case DocBlockType.heading1:
        return 'Heading1';
      case DocBlockType.heading2:
        return 'Heading2';
      case DocBlockType.heading3:
        return 'Heading3';
      case DocBlockType.blockquote:
        return 'Quote';
      case DocBlockType.codeBlock:
        return 'CodeBlock';
      case DocBlockType.callout:
        return 'Callout';
      default:
        return 'Normal';
    }
  }

  static void _buildDocxRun(XmlBuilder builder, DocBlock blk, String text) {
    final cleanColor = blk.textColorHex.replaceFirst('#', '');
    final halfPts = (blk.fontSize * 2).round().toString();
    builder.element('w:r', nest: () {
      builder.element('w:rPr', nest: () {
        builder.element('w:rFonts', attributes: {
          'w:ascii': blk.fontFamily,
          'w:hAnsi': blk.fontFamily,
        });
        if (blk.bold) builder.element('w:b');
        if (blk.italic) builder.element('w:i');
        if (blk.underline) {
          builder.element('w:u', attributes: {'w:val': 'single'});
        }
        if (blk.strikethrough) builder.element('w:strike');
        builder.element('w:color', attributes: {'w:val': cleanColor});
        builder.element('w:sz', attributes: {'w:val': halfPts});
      });
      builder.element(
        'w:t',
        attributes: {'xml:space': 'preserve'},
        nest: text,
      );
    });
  }

  static FyrDocument decodeDocxBytes(
    Uint8List bytes, {
    String fallbackTitle = 'Untitled Document',
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);

    var title = fallbackTitle;
    final coreEntry = archive.find('docProps/core.xml');
    if (coreEntry != null) {
      try {
        final coreDoc = XmlDocument.parse(
            utf8.decode(coreEntry.content, allowMalformed: true));
        final tEl = coreDoc
            .findAllElements('title', namespace: '*')
            .firstOrNull;
        if (tEl != null && tEl.innerText.trim().isNotEmpty) {
          title = tEl.innerText.trim();
        }
      } catch (_) {}
    }

    final docEntry = archive.find('word/document.xml');
    if (docEntry == null) {
      throw const FormatException(
          'Invalid .docx archive: missing word/document.xml');
    }

    final docXml =
        XmlDocument.parse(utf8.decode(docEntry.content, allowMalformed: true));
    final body = docXml.findAllElements('body', namespace: '*').firstOrNull;
    final blocks = <DocBlock>[];

    if (body != null) {
      String? activeListGroupId;
      DocBlock? activeListBlock;
      var idx = 0;

      for (final node in body.children.whereType<XmlElement>()) {
        idx++;
        final local = node.name.local;

        if (local == 'tbl') {
          activeListGroupId = null;
          activeListBlock = null;
          final rows = <List<String>>[];
          for (final tr in node.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'tr')) {
            final cells = <String>[];
            for (final tc in tr.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'tc')) {
              final cellText = tc
                  .findAllElements('t', namespace: '*')
                  .map((e) => e.innerText)
                  .join();
              cells.add(cellText);
            }
            if (cells.isNotEmpty) rows.add(cells);
          }
          blocks.add(DocBlock(
            id: node.getAttribute('fyr:id') ?? 'docx_tbl_$idx',
            type: DocBlockType.table,
            tableRows: rows,
          ));
        } else if (local == 'p') {
          final explicitTypeStr = node.getAttribute('fyr:block-type');
          final listGroup = node.getAttribute('fyr:list-group');

          // Inspect w:pPr
          final pPr = node.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'pPr')
              .firstOrNull;
          final pStyleEl =
              pPr?.findAllElements('pStyle', namespace: '*').firstOrNull;
          final pStyleVal = pStyleEl?.getAttribute('w:val') ??
              pStyleEl?.getAttribute('val', namespace: '*') ??
              '';
          final jcEl = pPr?.findAllElements('jc', namespace: '*').firstOrNull;
          final jcVal = jcEl?.getAttribute('w:val') ??
              jcEl?.getAttribute('val', namespace: '*') ??
              'left';
          final numPrEl =
              pPr?.findAllElements('numPr', namespace: '*').firstOrNull;

          final align = jcVal == 'both'
              ? TextAlignOption.justify
              : TextAlignOption.values.firstWhere(
                  (a) => a.name == jcVal,
                  orElse: () => TextAlignOption.left,
                );

          // Inspect runs (w:r)
          var bold = false;
          var italic = false;
          var underline = false;
          var strikethrough = false;
          var fontFamily = 'Inter';
          var fontSize = 14.0;
          var colorHex = '#FFFFFF';
          final textBuffer = StringBuffer();

          for (final r in node.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'r')) {
            final rPr = r.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'rPr')
                .firstOrNull;
            if (rPr != null) {
              if (rPr.findAllElements('b', namespace: '*').isNotEmpty) {
                bold = true;
              }
              if (rPr.findAllElements('i', namespace: '*').isNotEmpty) {
                italic = true;
              }
              if (rPr.findAllElements('u', namespace: '*').isNotEmpty) {
                underline = true;
              }
              if (rPr.findAllElements('strike', namespace: '*').isNotEmpty) {
                strikethrough = true;
              }
              final fontEl =
                  rPr.findAllElements('rFonts', namespace: '*').firstOrNull;
              final asciiFont = fontEl?.getAttribute('w:ascii') ??
                  fontEl?.getAttribute('ascii', namespace: '*');
              if (asciiFont != null && asciiFont.isNotEmpty) {
                fontFamily = asciiFont;
              }
              final szEl =
                  rPr.findAllElements('sz', namespace: '*').firstOrNull;
              final szVal = szEl?.getAttribute('w:val') ??
                  szEl?.getAttribute('val', namespace: '*');
              if (szVal != null) {
                final halfPts = double.tryParse(szVal);
                if (halfPts != null && halfPts > 0) {
                  fontSize = halfPts / 2.0;
                }
              }
              final colEl =
                  rPr.findAllElements('color', namespace: '*').firstOrNull;
              final colVal = colEl?.getAttribute('w:val') ??
                  colEl?.getAttribute('val', namespace: '*');
              if (colVal != null &&
                  colVal.isNotEmpty &&
                  colVal.toLowerCase() != 'auto') {
                colorHex = colVal.startsWith('#') ? colVal : '#$colVal';
              }
            }
            for (final t in r.findAllElements('t', namespace: '*')) {
              textBuffer.write(t.innerText);
            }
          }

          final text = textBuffer.toString();

          // Determine block type
          DocBlockType blockType = DocBlockType.paragraph;
          if (explicitTypeStr != null) {
            blockType = DocBlockType.values.firstWhere(
              (t) => t.name == explicitTypeStr,
              orElse: () => DocBlockType.paragraph,
            );
          } else {
            final lowerStyle = pStyleVal.toLowerCase();
            if (lowerStyle == 'title') {
              blockType = DocBlockType.title;
            } else if (lowerStyle.contains('heading1') ||
                lowerStyle == 'heading 1') {
              blockType = DocBlockType.heading1;
            } else if (lowerStyle.contains('heading2') ||
                lowerStyle == 'heading 2') {
              blockType = DocBlockType.heading2;
            } else if (lowerStyle.contains('heading3') ||
                lowerStyle == 'heading 3') {
              blockType = DocBlockType.heading3;
            } else if (lowerStyle.contains('listnumber')) {
              blockType = DocBlockType.numberedList;
            } else if (lowerStyle.contains('listbullet') || numPrEl != null) {
              blockType = DocBlockType.bulletList;
            } else if (lowerStyle.contains('quote')) {
              blockType = DocBlockType.blockquote;
            } else if (lowerStyle.contains('code')) {
              blockType = DocBlockType.codeBlock;
            } else if (lowerStyle.contains('callout')) {
              blockType = DocBlockType.callout;
            }
          }

          if (blockType == DocBlockType.bulletList ||
              blockType == DocBlockType.numberedList) {
            final groupKey = listGroup ?? 'list_${blockType.name}';
            if (activeListGroupId == groupKey &&
                activeListBlock != null &&
                activeListBlock.type == blockType) {
              activeListBlock.listItems.add(text);
              activeListBlock.text = activeListBlock.listItems.join('\n');
              continue;
            } else {
              final listBlk = DocBlock(
                id: listGroup ?? 'docx_list_$idx',
                type: blockType,
                text: text,
                listItems: [text],
                fontFamily: fontFamily,
                fontSize: fontSize,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough,
                textColorHex: colorHex,
                align: align,
              );
              blocks.add(listBlk);
              activeListGroupId = groupKey;
              activeListBlock = listBlk;
              continue;
            }
          }

          activeListGroupId = null;
          activeListBlock = null;

          blocks.add(DocBlock(
            id: node.getAttribute('fyr:id') ?? 'docx_p_$idx',
            type: blockType,
            text: text,
            fontFamily: fontFamily,
            fontSize: fontSize,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            textColorHex: colorHex,
            align: align,
            checked: node.getAttribute('fyr:checked') == 'true',
            codeLanguage: node.getAttribute('fyr:code-lang') ?? 'dart',
            calloutIcon: node.getAttribute('fyr:callout-icon') ?? 'info',
          ));
        }
      }
    }

    if (blocks.isEmpty) {
      blocks.add(DocBlock(id: 'docx_p_1', text: ''));
    }

    return FyrDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: 'docx',
      blocks: blocks,
    );
  }

  // ===========================================================================
  // MARKDOWN (.MD) READER & WRITER
  // ===========================================================================

  static String toMarkdown(FyrDocument doc) {
    final sb = StringBuffer();
    for (final blk in doc.blocks) {
      switch (blk.type) {
        case DocBlockType.title:
          sb.writeln('# ${blk.text}\n');
          break;
        case DocBlockType.heading1:
          sb.writeln('## ${blk.text}\n');
          break;
        case DocBlockType.heading2:
          sb.writeln('### ${blk.text}\n');
          break;
        case DocBlockType.heading3:
          sb.writeln('#### ${blk.text}\n');
          break;
        case DocBlockType.blockquote:
          sb.writeln('> ${blk.text}\n');
          break;
        case DocBlockType.callout:
          sb.writeln('> [!NOTE] ${blk.text}\n');
          break;
        case DocBlockType.codeBlock:
          sb.writeln('```${blk.codeLanguage}');
          sb.writeln(blk.text);
          sb.writeln('```\n');
          break;
        case DocBlockType.bulletList:
          final items = blk.listItems.isNotEmpty
              ? blk.listItems
              : blk.text.split('\n');
          for (final item in items) {
            sb.writeln('- $item');
          }
          sb.writeln();
          break;
        case DocBlockType.numberedList:
          final items = blk.listItems.isNotEmpty
              ? blk.listItems
              : blk.text.split('\n');
          for (var i = 0; i < items.length; i++) {
            sb.writeln('${i + 1}. ${items[i]}');
          }
          sb.writeln();
          break;
        case DocBlockType.checklist:
          sb.writeln('- [${blk.checked ? "x" : " "}] ${blk.text}\n');
          break;
        case DocBlockType.table:
          if (blk.tableRows.isNotEmpty) {
            final header = blk.tableRows.first;
            sb.writeln('| ${header.join(" | ")} |');
            sb.writeln('| ${header.map((_) => "---").join(" | ")} |');
            for (var r = 1; r < blk.tableRows.length; r++) {
              sb.writeln('| ${blk.tableRows[r].join(" | ")} |');
            }
            sb.writeln();
          }
          break;
        case DocBlockType.divider:
          sb.writeln('---\n');
          break;
        case DocBlockType.pageBreak:
          sb.writeln('\n<!-- pagebreak -->\n');
          break;
        case DocBlockType.paragraph:
          var line = blk.text;
          if (blk.bold) line = '**$line**';
          if (blk.italic) line = '*$line*';
          sb.writeln('$line\n');
          break;
      }
    }
    return sb.toString().trimRight();
  }

  static FyrDocument fromMarkdown(
    String raw, {
    String title = 'Untitled Document',
  }) {
    final lines = raw.split('\n');
    final blocks = <DocBlock>[];
    var idx = 0;
    var inCode = false;
    var codeLang = 'dart';
    final codeBuf = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().startsWith('```')) {
        if (!inCode) {
          inCode = true;
          codeLang = line.trim().substring(3).trim();
          if (codeLang.isEmpty) codeLang = 'dart';
          codeBuf.clear();
        } else {
          inCode = false;
          idx++;
          blocks.add(DocBlock(
            id: 'md_$idx',
            type: DocBlockType.codeBlock,
            text: codeBuf.toString().trimRight(),
            fontFamily: 'JetBrains Mono',
            fontSize: 12.5,
            codeLanguage: codeLang,
          ));
        }
        continue;
      }
      if (inCode) {
        codeBuf.writeln(line);
        continue;
      }

      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      idx++;
      if (trimmed == '---' || trimmed == '***') {
        blocks.add(DocBlock(id: 'md_$idx', type: DocBlockType.divider));
      } else if (trimmed.startsWith('# ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.title,
          text: trimmed.substring(2).trim(),
          fontSize: 26,
          bold: true,
        ));
      } else if (trimmed.startsWith('## ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.heading1,
          text: trimmed.substring(3).trim(),
          fontSize: 20,
          bold: true,
        ));
      } else if (trimmed.startsWith('### ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.heading2,
          text: trimmed.substring(4).trim(),
          fontSize: 17,
          bold: true,
        ));
      } else if (trimmed.startsWith('#### ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.heading3,
          text: trimmed.substring(5).trim(),
          fontSize: 15,
          bold: true,
        ));
      } else if (trimmed.startsWith('- [x] ') ||
          trimmed.startsWith('- [ ] ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.checklist,
          checked: trimmed.startsWith('- [x] '),
          text: trimmed.substring(6).trim(),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final item = trimmed.substring(2).trim();
        if (blocks.isNotEmpty && blocks.last.type == DocBlockType.bulletList) {
          blocks.last.listItems.add(item);
          blocks.last.text = blocks.last.listItems.join('\n');
        } else {
          blocks.add(DocBlock(
            id: 'md_$idx',
            type: DocBlockType.bulletList,
            text: item,
            listItems: [item],
          ));
        }
      } else if (trimmed.startsWith('> ')) {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.blockquote,
          text: trimmed.substring(2).trim(),
          italic: true,
        ));
      } else {
        blocks.add(DocBlock(
          id: 'md_$idx',
          type: DocBlockType.paragraph,
          text: trimmed,
        ));
      }
    }

    if (blocks.isEmpty) {
      blocks.add(DocBlock(id: 'md_1', text: ''));
    }

    return FyrDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: 'md',
      blocks: blocks,
    );
  }

  // ===========================================================================
  // HTML (.HTML) & PLAIN TEXT (.TXT) READER & WRITER
  // ===========================================================================

  static String toHtml(FyrDocument doc) {
    final sb = StringBuffer();
    sb.writeln('<!DOCTYPE html>');
    sb.writeln('<html lang="en">');
    sb.writeln('<head>');
    sb.writeln('  <meta charset="UTF-8"/>');
    sb.writeln('  <title>${_escapeHtml(doc.title)}</title>');
    sb.writeln('  <style>');
    sb.writeln(
        '    body { font-family: Inter, sans-serif; max-width: 800px; margin: 40px auto; line-height: ${doc.lineSpacing}; color: #111; }');
    sb.writeln(
        '    table { width: 100%; border-collapse: collapse; margin: 16px 0; }');
    sb.writeln(
        '    th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }');
    sb.writeln(
        '    pre { background: #16161e; color: #f8f8f2; padding: 14px; border-radius: 8px; overflow-x: auto; }');
    sb.writeln(
        '    blockquote { border-left: 4px solid #D040FF; margin: 12px 0; padding: 8px 16px; background: #f8f0ff; }');
    sb.writeln('  </style>');
    sb.writeln('</head>');
    sb.writeln('<body>');

    for (final blk in doc.blocks) {
      final escaped = _escapeHtml(blk.text);
      switch (blk.type) {
        case DocBlockType.title:
          sb.writeln('  <h1 class="doc-title">$escaped</h1>');
          break;
        case DocBlockType.heading1:
          sb.writeln('  <h1>$escaped</h1>');
          break;
        case DocBlockType.heading2:
          sb.writeln('  <h2>$escaped</h2>');
          break;
        case DocBlockType.heading3:
          sb.writeln('  <h3>$escaped</h3>');
          break;
        case DocBlockType.blockquote:
        case DocBlockType.callout:
          sb.writeln('  <blockquote>$escaped</blockquote>');
          break;
        case DocBlockType.codeBlock:
          sb.writeln('  <pre><code>$escaped</code></pre>');
          break;
        case DocBlockType.bulletList:
          sb.writeln('  <ul>');
          for (final item in (blk.listItems.isNotEmpty
              ? blk.listItems
              : blk.text.split('\n'))) {
            sb.writeln('    <li>${_escapeHtml(item)}</li>');
          }
          sb.writeln('  </ul>');
          break;
        case DocBlockType.numberedList:
          sb.writeln('  <ol>');
          for (final item in (blk.listItems.isNotEmpty
              ? blk.listItems
              : blk.text.split('\n'))) {
            sb.writeln('    <li>${_escapeHtml(item)}</li>');
          }
          sb.writeln('  </ol>');
          break;
        case DocBlockType.table:
          sb.writeln('  <table>');
          for (var r = 0; r < blk.tableRows.length; r++) {
            sb.writeln('    <tr>');
            final tag = r == 0 ? 'th' : 'td';
            for (final cell in blk.tableRows[r]) {
              sb.writeln('      <$tag>${_escapeHtml(cell)}</$tag>');
            }
            sb.writeln('    </tr>');
          }
          sb.writeln('  </table>');
          break;
        case DocBlockType.divider:
          sb.writeln('  <hr/>');
          break;
        default:
          sb.writeln('  <p>$escaped</p>');
          break;
      }
    }

    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  static FyrDocument fromHtml(
    String raw, {
    String title = 'Untitled Document',
  }) {
    final stripped = raw
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>'), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>'), '')
        .replaceAll(RegExp(r'</(p|h1|h2|h3|li|tr|div|blockquote|pre)>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    final doc = fromPlainText(stripped, title: title);
    doc.format = 'html';
    return doc;
  }

  static String toPlainText(FyrDocument doc) {
    final sb = StringBuffer();
    for (final blk in doc.blocks) {
      if (blk.type == DocBlockType.divider) {
        sb.writeln('----------------------------------------');
      } else if (blk.type == DocBlockType.table) {
        for (final row in blk.tableRows) {
          sb.writeln(row.join('\t'));
        }
      } else {
        sb.writeln(blk.plainContent);
      }
      sb.writeln();
    }
    return sb.toString().trimRight();
  }

  static FyrDocument fromPlainText(
    String raw, {
    String title = 'Untitled Document',
  }) {
    final paragraphs = raw.split(RegExp(r'\n\s*\n'));
    final blocks = <DocBlock>[];
    var idx = 0;
    for (final pText in paragraphs) {
      final trimmed = pText.trim();
      if (trimmed.isEmpty) continue;
      idx++;
      blocks.add(DocBlock(
        id: 'txt_$idx',
        type: idx == 1 && trimmed.length < 80
            ? DocBlockType.heading1
            : DocBlockType.paragraph,
        text: trimmed,
        fontSize: idx == 1 && trimmed.length < 80 ? 20 : 14,
        bold: idx == 1 && trimmed.length < 80,
      ));
    }
    if (blocks.isEmpty) {
      blocks.add(DocBlock(id: 'txt_1', text: ''));
    }
    return FyrDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: 'txt',
      blocks: blocks,
    );
  }

  static String _escapeHtml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ===========================================================================
  // PURE-DART PDF 1.4 GENERATOR
  // ===========================================================================

  static Uint8List encodePdfBytes(FyrDocument doc) {
    // Build paginated text streams in standard PDF 1.4 format
    final pageStreams = <String>[];
    var currentStream = StringBuffer();
    var cursorY = 770.0;

    void startNewPage() {
      if (currentStream.isNotEmpty) {
        pageStreams.add(currentStream.toString());
      }
      currentStream = StringBuffer();
      cursorY = 770.0;
      if (doc.headerText.trim().isNotEmpty) {
        currentStream.writeln('BT /F1 9 Tf 54 805 Td (${_escapePdf(doc.headerText)}) Tj ET');
      }
    }

    startNewPage();

    for (final blk in doc.blocks) {
      if (blk.type == DocBlockType.pageBreak || cursorY < 90) {
        startNewPage();
        if (blk.type == DocBlockType.pageBreak) continue;
      }

      if (blk.type == DocBlockType.divider) {
        currentStream.writeln('0.75 G 54 ${cursorY.toStringAsFixed(1)} m 540 ${cursorY.toStringAsFixed(1)} l S');
        cursorY -= 18;
        continue;
      }

      final fontKey = (blk.bold || blk.type.isHeading) ? '/F2' : '/F1';
      final ptSize = blk.type == DocBlockType.title
          ? 22.0
          : blk.type == DocBlockType.heading1
              ? 17.0
              : blk.type == DocBlockType.heading2
                  ? 14.5
                  : blk.fontSize.clamp(9.0, 24.0);

      final rawLines = <String>[];
      if (blk.type == DocBlockType.table) {
        for (final row in blk.tableRows) {
          rawLines.add(row.join('  |  '));
        }
      } else if (blk.type == DocBlockType.bulletList) {
        final items =
            blk.listItems.isNotEmpty ? blk.listItems : blk.text.split('\n');
        for (final item in items) {
          rawLines.add('  * $item');
        }
      } else if (blk.type == DocBlockType.numberedList) {
        final items =
            blk.listItems.isNotEmpty ? blk.listItems : blk.text.split('\n');
        for (var i = 0; i < items.length; i++) {
          rawLines.add('  ${i + 1}. ${items[i]}');
        }
      } else {
        for (final paragraphLine in blk.text.split('\n')) {
          rawLines.addAll(_wrapPdfText(paragraphLine, 82));
        }
      }

      for (final line in rawLines) {
        if (cursorY < 75) {
          startNewPage();
        }
        currentStream.writeln(
            'BT $fontKey ${ptSize.toStringAsFixed(1)} Tf 54 ${cursorY.toStringAsFixed(1)} Td (${_escapePdf(line)}) Tj ET');
        cursorY -= (ptSize * doc.lineSpacing);
      }
      cursorY -= 8;
    }

    if (currentStream.isNotEmpty) {
      pageStreams.add(currentStream.toString());
    }
    if (pageStreams.isEmpty) {
      pageStreams.add('BT /F1 12 Tf 54 760 Td () Tj ET\n');
    }

    // Assemble PDF objects:
    // 1: Catalog
    // 2: Pages
    // 3: Font Helvetica (/F1)
    // 4: Font Helvetica-Bold (/F2)
    // For each page i: Page object + Content stream object
    final objects = <String>[];
    final pageCount = pageStreams.length;
    final pageObjIds = <int>[];

    objects.add('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj');
    // Placeholder for 2 0 obj (Pages)
    objects.add('');
    objects.add(
        '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj');
    objects.add(
        '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj');

    var nextId = 5;
    for (var i = 0; i < pageCount; i++) {
      final pageId = nextId++;
      final contentId = nextId++;
      pageObjIds.add(pageId);

      var streamData = pageStreams[i];
      if (doc.showPageNumbers) {
        streamData +=
            '\nBT /F1 9 Tf 270 36 Td (Page ${i + 1} of $pageCount) Tj ET\n';
      }
      final streamBytesLen = utf8.encode(streamData).length;

      objects.add(
        '$pageId 0 obj\n'
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents $contentId 0 R >>\n'
        'endobj',
      );
      objects.add(
        '$contentId 0 obj\n'
        '<< /Length $streamBytesLen >>\n'
        'stream\n'
        '$streamData'
        'endstream\n'
        'endobj',
      );
    }

    final kidsStr = pageObjIds.map((id) => '$id 0 R').join(' ');
    objects[1] =
        '2 0 obj\n<< /Type /Pages /Kids [$kidsStr] /Count $pageCount >>\nendobj';

    final pdfBuf = StringBuffer();
    pdfBuf.writeln('%PDF-1.4');
    final offsets = <int>[0];
    for (final obj in objects) {
      offsets.add(utf8.encode(pdfBuf.toString()).length);
      pdfBuf.writeln(obj);
    }
    final xrefOffset = utf8.encode(pdfBuf.toString()).length;
    pdfBuf.writeln('xref');
    pdfBuf.writeln('0 ${objects.length + 1}');
    pdfBuf.writeln('0000000000 65535 f ');
    for (var i = 1; i < offsets.length; i++) {
      pdfBuf.writeln('${offsets[i].toString().padLeft(10, "0")} 00000 n ');
    }
    pdfBuf.writeln('trailer');
    pdfBuf.writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>');
    pdfBuf.writeln('startxref');
    pdfBuf.writeln('$xrefOffset');
    pdfBuf.write('%%EOF');

    return Uint8List.fromList(utf8.encode(pdfBuf.toString()));
  }

  static List<String> _wrapPdfText(String text, int maxChars) {
    if (text.length <= maxChars) return [text];
    final words = text.split(' ');
    final lines = <String>[];
    var current = StringBuffer();
    for (final w in words) {
      if (current.isEmpty) {
        current.write(w);
      } else if (current.length + 1 + w.length <= maxChars) {
        current.write(' $w');
      } else {
        lines.add(current.toString());
        current = StringBuffer(w);
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());
    return lines;
  }

  static String _escapePdf(String input) {
    final asciiSafe = input
        .replaceAll('•', '-')
        .replaceAll('—', '--')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)');
    return asciiSafe.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }
}
