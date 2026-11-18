import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../models/sheet_models.dart';
import 'formula_engine.dart';

class SheetIO {
  static const String odsMimeType =
      'application/vnd.oasis.opendocument.spreadsheet';

  // ===========================================================================
  // Unified Save / Load
  // ===========================================================================

  static Future<void> saveWorkbook(
    SpreadsheetWorkbook workbook,
    String filePath,
  ) async {
    final fmt = WorkbookFormat.fromPath(filePath);
    workbook.filePath = filePath;
    workbook.format = fmt;
    workbook.title = p.basename(filePath);

    switch (fmt) {
      case WorkbookFormat.ods:
        await saveOds(workbook, filePath);
        break;
      case WorkbookFormat.xlsx:
        await saveXlsx(workbook, filePath);
        break;
      case WorkbookFormat.csv:
        final csvText = toCsv(workbook.activeSheet, delimiter: ',');
        await File(filePath).writeAsString(csvText);
        break;
      case WorkbookFormat.tsv:
        final tsvText = toCsv(workbook.activeSheet, delimiter: '\t');
        await File(filePath).writeAsString(tsvText);
        break;
    }
  }

  static Future<SpreadsheetWorkbook> loadWorkbook(String filePath) async {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      return loadXlsx(filePath);
    } else if (lower.endsWith('.csv')) {
      final content = await File(filePath).readAsString();
      final sheet = fromCsv(
        content,
        sheetName: p.basenameWithoutExtension(filePath),
        delimiter: ',',
      );
      final wb = SpreadsheetWorkbook(
        id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
        title: p.basename(filePath),
        filePath: filePath,
        format: WorkbookFormat.csv,
        sheets: [sheet],
      );
      FormulaEngine.recalculateWorkbook(wb);
      return wb;
    } else if (lower.endsWith('.tsv')) {
      final content = await File(filePath).readAsString();
      final sheet = fromCsv(
        content,
        sheetName: p.basenameWithoutExtension(filePath),
        delimiter: '\t',
      );
      final wb = SpreadsheetWorkbook(
        id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
        title: p.basename(filePath),
        filePath: filePath,
        format: WorkbookFormat.tsv,
        sheets: [sheet],
      );
      FormulaEngine.recalculateWorkbook(wb);
      return wb;
    } else if (lower.endsWith('.json')) {
      final content = await File(filePath).readAsString();
      final wb = SpreadsheetWorkbook.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      wb.filePath = filePath;
      FormulaEngine.recalculateWorkbook(wb);
      return wb;
    } else {
      return loadOds(filePath);
    }
  }

  // ===========================================================================
  // OpenDocument Spreadsheet (.ods) Reader & Writer
  // ===========================================================================

  static Future<void> saveOds(
    SpreadsheetWorkbook workbook,
    String filePath,
  ) async {
    final bytes = encodeOdsBytes(workbook);
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  static Future<SpreadsheetWorkbook> loadOds(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final wb = decodeOdsBytes(bytes, title: p.basename(filePath));
    wb.filePath = filePath;
    wb.format = WorkbookFormat.ods;
    return wb;
  }

  static Uint8List encodeOdsBytes(SpreadsheetWorkbook workbook) {
    FormulaEngine.recalculateWorkbook(workbook);
    final archive = Archive();

    // 1. mimetype (must be first and uncompressed per ODF 1.2 package spec)
    final mimeBytes = utf8.encode(odsMimeType);
    archive.add(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    // 2. META-INF/manifest.xml
    const manifestXml = '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>''';
    archive.add(ArchiveFile.string('META-INF/manifest.xml', manifestXml));

    // 3. styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.2">
  <office:styles/>
  <office:automatic-styles/>
  <office:master-styles/>
</office:document-styles>''';
    archive.add(ArchiveFile.string('styles.xml', stylesXml));

    // 4. content.xml
    final contentBuilder = XmlBuilder();
    contentBuilder.processing('xml', 'version="1.0" encoding="UTF-8"');
    contentBuilder.element(
      'office:document-content',
      attributes: {
        'xmlns:office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
        'xmlns:table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
        'xmlns:text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
        'xmlns:style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
        'xmlns:fo':
            'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
        'xmlns:of': 'urn:oasis:names:tc:opendocument:xmlns:of:1.2',
        'xmlns:fyr': 'https://fyrde.io/ns/fyrsheets/1.0',
        'office:version': '1.2',
      },
      nest: () {
        contentBuilder.element('office:automatic-styles');
        contentBuilder.element(
          'office:body',
          nest: () {
            contentBuilder.element(
              'office:spreadsheet',
              nest: () {
                for (final sheet in workbook.sheets) {
                  final bounds = _usedBounds(sheet);
                  final maxR = bounds.$1;
                  final maxC = bounds.$2;

                  contentBuilder.element(
                    'table:table',
                    attributes: {
                      'table:name': sheet.name,
                      'fyr:frozen-rows': sheet.frozenRows.toString(),
                      if (sheet.charts.isNotEmpty)
                        'fyr:charts': jsonEncode(
                          sheet.charts.map((c) => c.toJson()).toList(),
                        ),
                      if (sheet.conditionalRules.isNotEmpty)
                        'fyr:rules': jsonEncode(
                          sheet.conditionalRules.map((r) => r.toJson()).toList(),
                        ),
                    },
                    nest: () {
                      for (var r = 0; r <= maxR; r++) {
                        contentBuilder.element(
                          'table:table-row',
                          nest: () {
                            for (var c = 0; c <= maxC; c++) {
                              final cell = sheet.getCell(r, c);
                              final attrs = <String, String>{};
                              if (cell.isFormula) {
                                attrs['table:formula'] =
                                    'of:${cell.rawInput.trim()}';
                              }
                              final val = cell.computedValue;
                              if (val is num &&
                                  !val.isNaN &&
                                  !val.isInfinite) {
                                attrs['office:value-type'] = 'float';
                                attrs['office:value'] = val.toString();
                              } else if (val is bool) {
                                attrs['office:value-type'] = 'boolean';
                                attrs['office:boolean-value'] =
                                    val ? 'true' : 'false';
                              } else if (!cell.isEmpty) {
                                attrs['office:value-type'] = 'string';
                              }

                              // Preserve style attributes cleanly
                              final st = cell.style;
                              if (st.bold) attrs['fyr:bold'] = 'true';
                              if (st.italic) attrs['fyr:italic'] = 'true';
                              if (st.underline) attrs['fyr:underline'] = 'true';
                              if (st.textColorHex != null) {
                                attrs['fyr:color'] = st.textColorHex!;
                              }
                              if (st.fillColorHex != null) {
                                attrs['fyr:fill'] = st.fillColorHex!;
                              }
                              if (st.align != null) {
                                attrs['fyr:align'] = st.align!.name;
                              }
                              if (st.numberFormat != NumberFormatType.general) {
                                attrs['fyr:numfmt'] = st.numberFormat.name;
                                attrs['fyr:decimals'] = st.decimals.toString();
                              }

                              contentBuilder.element(
                                'table:table-cell',
                                attributes: attrs,
                                nest: () {
                                  final textVal = cell.displayValue.isNotEmpty
                                      ? cell.displayValue
                                      : (val?.toString() ?? '');
                                  if (textVal.isNotEmpty) {
                                    contentBuilder.element(
                                      'text:p',
                                      nest: textVal,
                                    );
                                  }
                                },
                              );
                            }
                          },
                        );
                      }
                    },
                  );
                }
              },
            );
          },
        );
      },
    );

    final contentXmlStr = contentBuilder.buildDocument().toXmlString(pretty: true);
    archive.add(ArchiveFile.string('content.xml', contentXmlStr));

    return ZipEncoder().encodeBytes(archive);
  }

  static SpreadsheetWorkbook decodeOdsBytes(
    List<int> bytes, {
    String title = 'Workbook.ods',
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final contentFile = archive.findFile('content.xml');
    if (contentFile == null) {
      throw const FormatException('Invalid .ods file: missing content.xml');
    }

    final xmlStr = utf8.decode(contentFile.content, allowMalformed: true);
    final doc = XmlDocument.parse(xmlStr);

    final sheets = <Worksheet>[];
    final tableElements = doc.findAllElements('table:table').isNotEmpty
        ? doc.findAllElements('table:table')
        : doc.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'table');

    var sheetIdx = 0;
    for (final tableEl in tableElements) {
      sheetIdx++;
      final name = tableEl.getAttribute('table:name') ??
          tableEl.getAttribute('name') ??
          'Sheet $sheetIdx';
      final frozen =
          int.tryParse(tableEl.getAttribute('fyr:frozen-rows') ?? '') ?? 1;

      final charts = <SheetChartConfig>[];
      final chartsAttr = tableEl.getAttribute('fyr:charts');
      if (chartsAttr != null && chartsAttr.isNotEmpty) {
        try {
          final decoded = jsonDecode(chartsAttr) as List;
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              charts.add(SheetChartConfig.fromJson(item));
            }
          }
        } catch (_) {}
      }

      final rules = <ConditionalRule>[];
      final rulesAttr = tableEl.getAttribute('fyr:rules');
      if (rulesAttr != null && rulesAttr.isNotEmpty) {
        try {
          final decoded = jsonDecode(rulesAttr) as List;
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              rules.add(ConditionalRule.fromJson(item));
            }
          }
        } catch (_) {}
      }

      final sheet = Worksheet(
        id: 'sheet_$sheetIdx',
        name: name,
        frozenRows: frozen,
        charts: charts,
        conditionalRules: rules,
      );

      final rowElements = tableEl.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'table-row');

      var rowIdx = 0;
      for (final rowEl in rowElements) {
        final rowRepeat = int.tryParse(
              rowEl.getAttribute('table:number-rows-repeated') ?? '1',
            ) ??
            1;
        final effectiveRowRepeat = rowRepeat > 100 ? 1 : rowRepeat;

        for (var rr = 0; rr < effectiveRowRepeat; rr++) {
          var colIdx = 0;
          final cellElements = rowEl.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'table-cell');

          for (final cellEl in cellElements) {
            final colRepeat = int.tryParse(
                  cellEl.getAttribute('table:number-columns-repeated') ?? '1',
                ) ??
                1;
            final effectiveColRepeat = colRepeat > 64 ? 1 : colRepeat;

            final formulaAttr = cellEl.getAttribute('table:formula') ??
                cellEl.getAttribute('formula');
            final valType = cellEl.getAttribute('office:value-type') ??
                cellEl.getAttribute('value-type');
            final floatAttr = cellEl.getAttribute('office:value') ??
                cellEl.getAttribute('value');
            final boolAttr = cellEl.getAttribute('office:boolean-value') ??
                cellEl.getAttribute('boolean-value');

            final textParagraphs = cellEl.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'p')
                .map((e) => e.innerText)
                .toList();
            final textVal = textParagraphs.join('\n');

            String rawInput = '';
            if (formulaAttr != null && formulaAttr.trim().isNotEmpty) {
              rawInput = FormulaEngine.normalizeFormulaString(formulaAttr);
            } else if (valType == 'float' && floatAttr != null) {
              rawInput = floatAttr;
            } else if (valType == 'boolean' && boolAttr != null) {
              rawInput = boolAttr.toUpperCase();
            } else if (textVal.isNotEmpty) {
              rawInput = textVal;
            }

            final style = CellStyle(
              bold: cellEl.getAttribute('fyr:bold') == 'true',
              italic: cellEl.getAttribute('fyr:italic') == 'true',
              underline: cellEl.getAttribute('fyr:underline') == 'true',
              textColorHex: cellEl.getAttribute('fyr:color'),
              fillColorHex: cellEl.getAttribute('fyr:fill'),
              align: cellEl.getAttribute('fyr:align') != null
                  ? CellAlign.values.firstWhere(
                      (a) => a.name == cellEl.getAttribute('fyr:align'),
                      orElse: () => CellAlign.left,
                    )
                  : null,
              numberFormat: cellEl.getAttribute('fyr:numfmt') != null
                  ? NumberFormatType.values.firstWhere(
                      (n) => n.name == cellEl.getAttribute('fyr:numfmt'),
                      orElse: () => NumberFormatType.general,
                    )
                  : NumberFormatType.general,
              decimals:
                  int.tryParse(cellEl.getAttribute('fyr:decimals') ?? '') ?? 2,
            );

            for (var cr = 0; cr < effectiveColRepeat; cr++) {
              if (rawInput.isNotEmpty ||
                  style.bold ||
                  style.fillColorHex != null ||
                  style.textColorHex != null) {
                sheet.setCell(
                  rowIdx,
                  colIdx,
                  SheetCell(
                    rawInput: rawInput,
                    displayValue: textVal,
                    style: style,
                  ),
                );
              }
              colIdx++;
            }
          }
          rowIdx++;
        }
      }

      sheets.add(sheet);
    }

    if (sheets.isEmpty) {
      sheets.add(Worksheet(id: 'sheet_1', name: 'Sheet 1'));
    }

    final workbook = SpreadsheetWorkbook(
      id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: WorkbookFormat.ods,
      sheets: sheets,
    );
    FormulaEngine.recalculateWorkbook(workbook);
    return workbook;
  }

  // ===========================================================================
  // Microsoft Excel OpenXML (.xlsx) Reader & Writer
  // ===========================================================================

  static Future<void> saveXlsx(
    SpreadsheetWorkbook workbook,
    String filePath,
  ) async {
    final bytes = encodeXlsxBytes(workbook);
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  static Future<SpreadsheetWorkbook> loadXlsx(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final wb = decodeXlsxBytes(bytes, title: p.basename(filePath));
    wb.filePath = filePath;
    wb.format = WorkbookFormat.xlsx;
    return wb;
  }

  static Uint8List encodeXlsxBytes(SpreadsheetWorkbook workbook) {
    FormulaEngine.recalculateWorkbook(workbook);
    final archive = Archive();

    final sharedStrings = <String>[];
    final sharedStringIndex = <String, int>{};

    int internString(String s) {
      final existing = sharedStringIndex[s];
      if (existing != null) return existing;
      final idx = sharedStrings.length;
      sharedStrings.add(s);
      sharedStringIndex[s] = idx;
      return idx;
    }

    // 1. Build worksheets first so sharedStrings table is populated
    for (var i = 0; i < workbook.sheets.length; i++) {
      final sheet = workbook.sheets[i];
      final sheetNum = i + 1;
      final bounds = _usedBounds(sheet);
      final maxR = bounds.$1;
      final maxC = bounds.$2;

      final sb = XmlBuilder();
      sb.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
      sb.element(
        'worksheet',
        attributes: {
          'xmlns':
              'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
          'xmlns:r':
              'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        },
        nest: () {
          sb.element(
            'sheetData',
            nest: () {
              for (var r = 0; r <= maxR; r++) {
                final rowCells = <(int, SheetCell)>[];
                for (var c = 0; c <= maxC; c++) {
                  final cell = sheet.getCell(r, c);
                  if (!cell.isEmpty) {
                    rowCells.add((c, cell));
                  }
                }
                if (rowCells.isEmpty) continue;

                sb.element(
                  'row',
                  attributes: {'r': (r + 1).toString()},
                  nest: () {
                    for (final entry in rowCells) {
                      final c = entry.$1;
                      final cell = entry.$2;
                      final a1 = CellCoordinate(r, c).a1;
                      final val = cell.computedValue;

                      if (cell.isFormula) {
                        final cleanFormula = cell.rawInput.trim().startsWith('=')
                            ? cell.rawInput.trim().substring(1)
                            : cell.rawInput.trim();
                        final isStrResult = val is String;
                        sb.element(
                          'c',
                          attributes: {
                            'r': a1,
                            if (isStrResult) 't': 'str',
                          },
                          nest: () {
                            sb.element('f', nest: cleanFormula);
                            if (val != null) {
                              sb.element('v', nest: val.toString());
                            }
                          },
                        );
                      } else if (val is num &&
                          !val.isNaN &&
                          !val.isInfinite) {
                        sb.element(
                          'c',
                          attributes: {'r': a1, 't': 'n'},
                          nest: () {
                            sb.element('v', nest: val.toString());
                          },
                        );
                      } else if (val is bool) {
                        sb.element(
                          'c',
                          attributes: {'r': a1, 't': 'b'},
                          nest: () {
                            sb.element('v', nest: val ? '1' : '0');
                          },
                        );
                      } else {
                        final sIdx = internString(cell.rawInput);
                        sb.element(
                          'c',
                          attributes: {'r': a1, 't': 's'},
                          nest: () {
                            sb.element('v', nest: sIdx.toString());
                          },
                        );
                      }
                    }
                  },
                );
              }
            },
          );
        },
      );

      archive.add(
        ArchiveFile.string(
          'xl/worksheets/sheet$sheetNum.xml',
          sb.buildDocument().toXmlString(pretty: true),
        ),
      );
    }

    // 2. [Content_Types].xml
    final ctBuilder = XmlBuilder();
    ctBuilder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    ctBuilder.element(
      'Types',
      attributes: {
        'xmlns': 'http://schemas.openxmlformats.org/package/2006/content-types',
      },
      nest: () {
        ctBuilder.element(
          'Default',
          attributes: {
            'Extension': 'rels',
            'ContentType':
                'application/vnd.openxmlformats-package.relationships+xml',
          },
        );
        ctBuilder.element(
          'Default',
          attributes: {'Extension': 'xml', 'ContentType': 'application/xml'},
        );
        ctBuilder.element(
          'Override',
          attributes: {
            'PartName': '/xl/workbook.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
          },
        );
        ctBuilder.element(
          'Override',
          attributes: {
            'PartName': '/xl/sharedStrings.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml',
          },
        );
        ctBuilder.element(
          'Override',
          attributes: {
            'PartName': '/xl/styles.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml',
          },
        );
        for (var i = 0; i < workbook.sheets.length; i++) {
          ctBuilder.element(
            'Override',
            attributes: {
              'PartName': '/xl/worksheets/sheet${i + 1}.xml',
              'ContentType':
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
            },
          );
        }
      },
    );
    archive.add(
      ArchiveFile.string(
        '[Content_Types].xml',
        ctBuilder.buildDocument().toXmlString(pretty: true),
      ),
    );

    // 3. _rels/.rels
    const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    archive.add(ArchiveFile.string('_rels/.rels', rootRels));

    // 4. xl/workbook.xml
    final wbBuilder = XmlBuilder();
    wbBuilder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    wbBuilder.element(
      'workbook',
      attributes: {
        'xmlns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
        'xmlns:r':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
      },
      nest: () {
        wbBuilder.element(
          'sheets',
          nest: () {
            for (var i = 0; i < workbook.sheets.length; i++) {
              wbBuilder.element(
                'sheet',
                attributes: {
                  'name': workbook.sheets[i].name,
                  'sheetId': (i + 1).toString(),
                  'r:id': 'rId${i + 1}',
                },
              );
            }
          },
        );
      },
    );
    archive.add(
      ArchiveFile.string(
        'xl/workbook.xml',
        wbBuilder.buildDocument().toXmlString(pretty: true),
      ),
    );

    // 5. xl/_rels/workbook.xml.rels
    final wbRelsBuilder = XmlBuilder();
    wbRelsBuilder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    wbRelsBuilder.element(
      'Relationships',
      attributes: {
        'xmlns': 'http://schemas.openxmlformats.org/package/2006/relationships',
      },
      nest: () {
        for (var i = 0; i < workbook.sheets.length; i++) {
          wbRelsBuilder.element(
            'Relationship',
            attributes: {
              'Id': 'rId${i + 1}',
              'Type':
                  'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet',
              'Target': 'worksheets/sheet${i + 1}.xml',
            },
          );
        }
        wbRelsBuilder.element(
          'Relationship',
          attributes: {
            'Id': 'rIdSharedStrings',
            'Type':
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings',
            'Target': 'sharedStrings.xml',
          },
        );
        wbRelsBuilder.element(
          'Relationship',
          attributes: {
            'Id': 'rIdStyles',
            'Type':
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles',
            'Target': 'styles.xml',
          },
        );
      },
    );
    archive.add(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        wbRelsBuilder.buildDocument().toXmlString(pretty: true),
      ),
    );

    // 6. xl/sharedStrings.xml
    final ssBuilder = XmlBuilder();
    ssBuilder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    ssBuilder.element(
      'sst',
      attributes: {
        'xmlns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
        'count': sharedStrings.length.toString(),
        'uniqueCount': sharedStrings.length.toString(),
      },
      nest: () {
        for (final s in sharedStrings) {
          ssBuilder.element(
            'si',
            nest: () {
              ssBuilder.element('t', nest: s);
            },
          );
        }
      },
    );
    archive.add(
      ArchiveFile.string(
        'xl/sharedStrings.xml',
        ssBuilder.buildDocument().toXmlString(pretty: true),
      ),
    );

    // 7. xl/styles.xml
    const xlStyles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Inter"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''';
    archive.add(ArchiveFile.string('xl/styles.xml', xlStyles));

    return ZipEncoder().encodeBytes(archive);
  }

  static SpreadsheetWorkbook decodeXlsxBytes(
    List<int> bytes, {
    String title = 'Workbook.xlsx',
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Parse sharedStrings.xml if present
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final ssDoc = XmlDocument.parse(
        utf8.decode(ssFile.content, allowMalformed: true),
      );
      final siElements = ssDoc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'si');
      for (final si in siElements) {
        final tTexts = si.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText)
            .join();
        sharedStrings.add(tTexts);
      }
    }

    // 2. Parse xl/_rels/workbook.xml.rels to map rId -> target worksheet path
    final relTargets = <String, String>{};
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsFile != null) {
      final relsDoc = XmlDocument.parse(
        utf8.decode(relsFile.content, allowMalformed: true),
      );
      final relEls = relsDoc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'Relationship');
      for (final rel in relEls) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) {
          relTargets[id] = target.startsWith('xl/') ? target : 'xl/$target';
        }
      }
    }

    // 3. Parse xl/workbook.xml for sheet names and order
    final sheetDefs = <(String, String)>[]; // (name, archivePath)
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      final wbDoc = XmlDocument.parse(
        utf8.decode(wbFile.content, allowMalformed: true),
      );
      final sheetEls = wbDoc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'sheet');
      var idx = 0;
      for (final sEl in sheetEls) {
        idx++;
        final name = sEl.getAttribute('name') ?? 'Sheet $idx';
        final rId = sEl.getAttribute('r:id') ?? sEl.getAttribute('id');
        final path = (rId != null && relTargets.containsKey(rId))
            ? relTargets[rId]!
            : 'xl/worksheets/sheet$idx.xml';
        sheetDefs.add((name, path));
      }
    }

    if (sheetDefs.isEmpty) {
      sheetDefs.add(('Sheet 1', 'xl/worksheets/sheet1.xml'));
    }

    final sheets = <Worksheet>[];
    var sCounter = 0;
    for (final def in sheetDefs) {
      sCounter++;
      final sheetName = def.$1;
      final sheetPath = def.$2;
      final sheetFile = archive.findFile(sheetPath);
      final worksheet = Worksheet(id: 'sheet_$sCounter', name: sheetName);

      if (sheetFile != null) {
        final sDoc = XmlDocument.parse(
          utf8.decode(sheetFile.content, allowMalformed: true),
        );
        final rowEls = sDoc.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'row');

        var fallbackRow = 0;
        for (final rowEl in rowEls) {
          final rAttr = int.tryParse(rowEl.getAttribute('r') ?? '');
          final rowIdx = rAttr != null && rAttr > 0 ? rAttr - 1 : fallbackRow;
          fallbackRow = rowIdx + 1;

          final cellEls = rowEl.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'c');

          var fallbackCol = 0;
          for (final cEl in cellEls) {
            final rCoordAttr = cEl.getAttribute('r');
            final coord = rCoordAttr != null
                ? CellCoordinate.tryParse(rCoordAttr)
                : CellCoordinate(rowIdx, fallbackCol);
            final r = coord?.row ?? rowIdx;
            final c = coord?.col ?? fallbackCol;
            fallbackCol = c + 1;

            final tAttr = cEl.getAttribute('t');
            final fEl = cEl.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'f')
                .firstOrNull;
            final vEl = cEl.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'v')
                .firstOrNull;
            final isEl = cEl.children
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'is')
                .firstOrNull;

            String rawInput = '';
            if (fEl != null && fEl.innerText.trim().isNotEmpty) {
              final fText = fEl.innerText.trim();
              rawInput = fText.startsWith('=') ? fText : '=$fText';
            } else if (tAttr == 's' && vEl != null) {
              final sIdx = int.tryParse(vEl.innerText.trim());
              if (sIdx != null &&
                  sIdx >= 0 &&
                  sIdx < sharedStrings.length) {
                rawInput = sharedStrings[sIdx];
              }
            } else if (tAttr == 'inlineStr' && isEl != null) {
              rawInput = isEl.innerText;
            } else if (tAttr == 'b' && vEl != null) {
              rawInput = vEl.innerText.trim() == '1' ? 'TRUE' : 'FALSE';
            } else if (vEl != null) {
              rawInput = vEl.innerText.trim();
            }

            if (rawInput.isNotEmpty) {
              worksheet.setCell(
                r,
                c,
                SheetCell(rawInput: rawInput, displayValue: rawInput),
              );
            }
          }
        }
      }

      sheets.add(worksheet);
    }

    final workbook = SpreadsheetWorkbook(
      id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      format: WorkbookFormat.xlsx,
      sheets: sheets,
    );
    FormulaEngine.recalculateWorkbook(workbook);
    return workbook;
  }

  // ===========================================================================
  // RFC-4180 CSV & TSV Serializer / Parser
  // ===========================================================================

  static String toCsv(Worksheet sheet, {String delimiter = ','}) {
    FormulaEngine.recalculateWorksheet(sheet);
    final bounds = _usedBounds(sheet);
    final maxR = bounds.$1;
    final maxC = bounds.$2;
    final sb = StringBuffer();

    for (var r = 0; r <= maxR; r++) {
      for (var c = 0; c <= maxC; c++) {
        if (c > 0) sb.write(delimiter);
        final cell = sheet.getCell(r, c);
        final text = cell.isFormula
            ? (cell.computedValue?.toString() ?? cell.displayValue)
            : cell.rawInput;
        sb.write(_escapeCsvField(text, delimiter));
      }
      if (r < maxR) sb.write('\n');
    }
    return sb.toString();
  }

  static Worksheet fromCsv(
    String csvContent, {
    String sheetName = 'Sheet 1',
    String delimiter = ',',
  }) {
    final rows = parseCsvRows(csvContent, delimiter: delimiter);
    final sheet = Worksheet(
      id: 'sheet_1',
      name: sheetName,
      rowCount: math.max(50, rows.length + 10),
      colCount: math.max(
        16,
        rows.fold<int>(0, (m, r) => math.max(m, r.length)) + 4,
      ),
    );

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final raw = row[c];
        if (raw.isNotEmpty) {
          sheet.setCell(r, c, SheetCell(rawInput: raw, displayValue: raw));
        }
      }
    }
    FormulaEngine.recalculateWorksheet(sheet);
    return sheet;
  }

  static List<List<String>> parseCsvRows(
    String input, {
    String delimiter = ',',
  }) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    final len = input.length;

    while (i < len) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < len && input[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          } else {
            inQuotes = false;
            i++;
            continue;
          }
        } else {
          field.write(ch);
          i++;
          continue;
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
          i++;
          continue;
        }
        if (ch == delimiter) {
          currentRow.add(field.toString());
          field.clear();
          i++;
          continue;
        }
        if (ch == '\r') {
          if (i + 1 < len && input[i + 1] == '\n') {
            i++;
          }
          currentRow.add(field.toString());
          field.clear();
          rows.add(currentRow);
          currentRow = <String>[];
          i++;
          continue;
        }
        if (ch == '\n') {
          currentRow.add(field.toString());
          field.clear();
          rows.add(currentRow);
          currentRow = <String>[];
          i++;
          continue;
        }
        field.write(ch);
        i++;
      }
    }

    if (field.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(field.toString());
      rows.add(currentRow);
    }

    return rows;
  }

  static String _escapeCsvField(String value, String delimiter) {
    final needsQuotes = value.contains(delimiter) ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  static (int, int) _usedBounds(Worksheet sheet) {
    var maxR = 0;
    var maxC = 0;
    for (final key in sheet.cells.keys) {
      final coord = CellCoordinate.tryParse(key);
      if (coord != null) {
        if (coord.row > maxR) maxR = coord.row;
        if (coord.col > maxC) maxC = coord.col;
      }
    }
    return (maxR, maxC);
  }
}
