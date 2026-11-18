import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/slide_models.dart';

class SlidesIO {
  // ODP uses 28.0cm x 15.75cm for 16:9 widescreen pages (1600x900 canvas).
  static const double _odpWidthCm = 28.0;
  static const double _odpHeightCm = 15.75;

  // PPTX uses 12,192,000 x 6,858,000 EMUs for 16:9 widescreen slides (7620 EMUs per logical px on 1600x900).
  static const int _emuPerUnit = 7620;
  static const int _pptxWidthEmu = 12192000;
  static const int _pptxHeightEmu = 6858000;

  static double _xToCm(double x) => (x / SlideElement.canvasWidth) * _odpWidthCm;
  static double _yToCm(double y) => (y / SlideElement.canvasHeight) * _odpHeightCm;
  static double _cmToX(String? raw) {
    final cm = _parseDimensionCm(raw);
    return (cm / _odpWidthCm) * SlideElement.canvasWidth;
  }

  static double _cmToY(String? raw) {
    final cm = _parseDimensionCm(raw);
    return (cm / _odpHeightCm) * SlideElement.canvasHeight;
  }

  static double _parseDimensionCm(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 2.0;
    final s = raw.trim().toLowerCase();
    if (s.endsWith('cm')) {
      return double.tryParse(s.substring(0, s.length - 2).trim()) ?? 2.0;
    }
    if (s.endsWith('mm')) {
      final mm = double.tryParse(s.substring(0, s.length - 2).trim()) ?? 20.0;
      return mm / 10.0;
    }
    if (s.endsWith('in')) {
      final inches = double.tryParse(s.substring(0, s.length - 2).trim()) ?? 1.0;
      return inches * 2.54;
    }
    if (s.endsWith('pt')) {
      final pt = double.tryParse(s.substring(0, s.length - 2).trim()) ?? 72.0;
      return (pt / 72.0) * 2.54;
    }
    return double.tryParse(s) ?? 2.0;
  }

  // ===========================================================================
  // ODP (OpenDocument Presentation .odp) Reader & Writer
  // ===========================================================================

  static Uint8List encodeOdpBytes(PresentationDeck deck) {
    final archive = Archive();

    // 1. mimetype (uncompressed first entry per ODF spec)
    const mimeStr = 'application/vnd.oasis.opendocument.presentation';
    final mimeBytes = utf8.encode(mimeStr);
    archive.addFile(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    // 2. META-INF/manifest.xml
    const manifestXml = '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>''';
    archive.addFile(ArchiveFile.string('META-INF/manifest.xml', manifestXml));

    // 3. styles.xml
    final stylesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  office:version="1.2">
  <office:automatic-styles>
    <style:page-layout style:name="PM1">
      <style:page-layout-properties fo:page-width="${_odpWidthCm}cm" fo:page-height="${_odpHeightCm}cm" style:print-orientation="landscape"/>
    </style:page-layout>
  </office:automatic-styles>
  <office:master-styles>
    <style:master-page style:name="Default" style:page-layout-name="PM1"/>
  </office:master-styles>
</office:document-styles>''';
    archive.addFile(ArchiveFile.string('styles.xml', stylesXml));

    // 4. content.xml
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'office:document-content',
      namespaces: {
        'urn:oasis:names:tc:opendocument:xmlns:office:1.0': 'office',
        'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0': 'draw',
        'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0': 'presentation',
        'urn:oasis:names:tc:opendocument:xmlns:text:1.0': 'text',
        'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0': 'svg',
        'urn:oasis:names:tc:opendocument:xmlns:style:1.0': 'style',
        'https://fyrde.dev/ns/fyrslides/1.0': 'fyr',
      },
      attributes: {'office:version': '1.2'},
      nest: () {
        builder.element('office:body', nest: () {
          builder.element(
            'office:presentation',
            attributes: {
              'fyr:id': deck.id,
              'fyr:title': deck.title,
              'fyr:author': deck.author,
              'fyr:aspectRatio': deck.aspectRatio,
              'fyr:themeId': deck.theme.id,
            },
            nest: () {
              for (var i = 0; i < deck.slides.length; i++) {
                final slide = deck.slides[i];
                builder.element(
                  'draw:page',
                  attributes: {
                    'draw:name': slide.title.isEmpty ? 'page${i + 1}' : slide.title,
                    'draw:master-page-name': 'Default',
                    'fyr:id': slide.id,
                    'fyr:layout': slide.layout.name,
                    'fyr:transition': slide.transition.name,
                    'fyr:transitionDurationMs': slide.transitionDurationMs.toString(),
                    if (slide.bgOverrideHex != null)
                      'fyr:bgOverrideHex': slide.bgOverrideHex!,
                  },
                  nest: () {
                    for (final el in slide.elements) {
                      final xCm = _xToCm(el.x).toStringAsFixed(4);
                      final yCm = _yToCm(el.y).toStringAsFixed(4);
                      final wCm = _xToCm(el.width).toStringAsFixed(4);
                      final hCm = _yToCm(el.height).toStringAsFixed(4);

                      builder.element(
                        'draw:frame',
                        attributes: {
                          'draw:name': el.id,
                          'svg:x': '${xCm}cm',
                          'svg:y': '${yCm}cm',
                          'svg:width': '${wCm}cm',
                          'svg:height': '${hCm}cm',
                          'fyr:type': el.type.name,
                          'fyr:x': el.x.toString(),
                          'fyr:y': el.y.toString(),
                          'fyr:width': el.width.toString(),
                          'fyr:height': el.height.toString(),
                          'fyr:subtitle': el.subtitle,
                          'fyr:fontSize': el.fontSize.toString(),
                          'fyr:bold': el.bold.toString(),
                          'fyr:italic': el.italic.toString(),
                          'fyr:align': el.align,
                          'fyr:textColorHex': el.textColorHex,
                          'fyr:fillColorHex': el.fillColorHex,
                          'fyr:borderColorHex': el.borderColorHex,
                          'fyr:borderRadius': el.borderRadius.toString(),
                          'fyr:opacity': el.opacity.toString(),
                          'fyr:shapeKind': el.shapeKind.name,
                          'fyr:codeLanguage': el.codeLanguage,
                          if (el.chartValues.isNotEmpty)
                            'fyr:chartValues': el.chartValues.join(','),
                          if (el.chartLabels.isNotEmpty)
                            'fyr:chartLabels': el.chartLabels.join('|'),
                        },
                        nest: () {
                          if (el.type == SlideElementType.shape) {
                            builder.element('draw:custom-shape', nest: () {
                              if (el.text.isNotEmpty) {
                                builder.element('text:p', nest: el.text);
                              }
                            });
                          } else {
                            builder.element('draw:text-box', nest: () {
                              if (el.text.isNotEmpty) {
                                for (final line in el.text.split('\n')) {
                                  builder.element('text:p', nest: line);
                                }
                              }
                              if (el.bulletItems.isNotEmpty) {
                                builder.element('text:list', nest: () {
                                  for (final item in el.bulletItems) {
                                    builder.element('text:list-item', nest: () {
                                      builder.element('text:p', nest: item);
                                    });
                                  }
                                });
                              }
                            });
                          }
                        },
                      );
                    }

                    // Speaker notes
                    if (slide.speakerNotes.isNotEmpty) {
                      builder.element('presentation:notes', nest: () {
                        builder.element(
                          'draw:frame',
                          attributes: {
                            'presentation:class': 'notes',
                            'svg:x': '2.0cm',
                            'svg:y': '11.0cm',
                            'svg:width': '24.0cm',
                            'svg:height': '4.0cm',
                          },
                          nest: () {
                            builder.element('draw:text-box', nest: () {
                              for (final line in slide.speakerNotes.split('\n')) {
                                builder.element('text:p', nest: line);
                              }
                            });
                          },
                        );
                      });
                    }
                  },
                );
              }
            },
          );
        });
      },
    );

    final contentXmlStr = builder.buildDocument().toXmlString(pretty: true);
    archive.addFile(ArchiveFile.string('content.xml', contentXmlStr));

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static PresentationDeck decodeOdpBytes(
    Uint8List bytes, {
    String? filePath,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? contentFile;
    for (final file in archive) {
      if (file.name == 'content.xml') {
        contentFile = file;
        break;
      }
    }
    if (contentFile == null) {
      throw const FormatException('Invalid .odp file: missing content.xml');
    }

    final xmlStr = utf8.decode(contentFile.content, allowMalformed: true);
    final doc = XmlDocument.parse(xmlStr);

    final presEl = doc
        .findAllElements('presentation', namespace: '*')
        .cast<XmlElement?>()
        .firstWhere((e) => e != null, orElse: () => null);

    final deckId = _attr(presEl, 'id') ?? 'deck_odp';
    final deckTitle = _attr(presEl, 'title') ??
        (filePath != null
            ? filePath.split('/').last.replaceAll(RegExp(r'\.odp$', caseSensitive: false), '')
            : 'Imported Presentation');
    final deckAuthor = _attr(presEl, 'author') ?? 'FyrDE Studio';
    final aspectRatio = _attr(presEl, 'aspectRatio') ?? '16:9';
    final themeId = _attr(presEl, 'themeId') ?? 'fyr_cyber_purple';
    final theme = kDeckThemePresets.firstWhere(
      (t) => t.id == themeId,
      orElse: () => kDeckThemePresets.first,
    );

    final slides = <SlidePage>[];
    final pageElements = (presEl ?? doc.rootElement)
        .findAllElements('page', namespace: '*')
        .toList();

    for (var i = 0; i < pageElements.length; i++) {
      final pageEl = pageElements[i];
      final slideTitle = _attr(pageEl, 'name') ?? 'Slide ${i + 1}';
      final slideId = _attr(pageEl, 'id') ?? 'slide_${i + 1}';
      final layoutName = _attr(pageEl, 'layout') ?? 'titleAndContent';
      final transitionName = _attr(pageEl, 'transition') ?? 'fade';
      final durationMs =
          int.tryParse(_attr(pageEl, 'transitionDurationMs') ?? '380') ?? 380;
      final bgOverride = _attr(pageEl, 'bgOverrideHex');

      final elements = <SlideElement>[];
      var speakerNotes = '';

      for (final child in pageEl.children.whereType<XmlElement>()) {
        if (child.name.local == 'notes') {
          final noteParas = child
              .findAllElements('p', namespace: '*')
              .map((p) => p.innerText.trim())
              .where((t) => t.isNotEmpty)
              .toList();
          speakerNotes = noteParas.join('\n');
          continue;
        }
        if (child.name.local != 'frame') continue;
        if (_attr(child, 'class') == 'notes') continue;

        final elId = _attr(child, 'name') ?? 'el_${elements.length + 1}';
        final x = double.tryParse(_attr(child, 'x', nsPrefix: 'fyr') ?? '') ??
            _cmToX(_attr(child, 'x', nsPrefix: 'svg') ?? _attr(child, 'x'));
        final y = double.tryParse(_attr(child, 'y', nsPrefix: 'fyr') ?? '') ??
            _cmToY(_attr(child, 'y', nsPrefix: 'svg') ?? _attr(child, 'y'));
        final w = double.tryParse(_attr(child, 'width', nsPrefix: 'fyr') ?? '') ??
            _cmToX(_attr(child, 'width', nsPrefix: 'svg') ?? _attr(child, 'width'));
        final h = double.tryParse(_attr(child, 'height', nsPrefix: 'fyr') ?? '') ??
            _cmToY(_attr(child, 'height', nsPrefix: 'svg') ?? _attr(child, 'height'));

        final hasCustomShape =
            child.findElements('custom-shape', namespace: '*').isNotEmpty;
        final listEl = child
            .findAllElements('list', namespace: '*')
            .cast<XmlElement?>()
            .firstWhere((e) => e != null, orElse: () => null);

        final bulletItems = <String>[];
        if (listEl != null) {
          for (final item in listEl.findAllElements('list-item', namespace: '*')) {
            final itemText = item.innerText.trim();
            if (itemText.isNotEmpty) bulletItems.add(itemText);
          }
        }

        // Direct paragraphs (excluding list-item paragraphs)
        final textBox = child
            .findElements('text-box', namespace: '*')
            .cast<XmlElement?>()
            .firstWhere((e) => e != null, orElse: () => null);
        final paraLines = <String>[];
        if (textBox != null) {
          for (final p in textBox.children.whereType<XmlElement>()) {
            if (p.name.local == 'p') {
              paraLines.add(p.innerText);
            }
          }
        } else {
          for (final p in child.findAllElements('p', namespace: '*')) {
            paraLines.add(p.innerText);
          }
        }

        final typeStr = _attr(child, 'type', nsPrefix: 'fyr');
        final type = SlideElementType.values.firstWhere(
          (t) => t.name == typeStr,
          orElse: () {
            if (hasCustomShape) return SlideElementType.shape;
            if (bulletItems.isNotEmpty && paraLines.isEmpty) {
              return SlideElementType.bulletList;
            }
            return SlideElementType.text;
          },
        );

        final chartValStr = _attr(child, 'chartValues', nsPrefix: 'fyr') ?? '';
        final chartLblStr = _attr(child, 'chartLabels', nsPrefix: 'fyr') ?? '';

        elements.add(
          SlideElement(
            id: elId,
            type: type,
            x: x,
            y: y,
            width: w,
            height: h,
            text: paraLines.join('\n'),
            subtitle: _attr(child, 'subtitle', nsPrefix: 'fyr') ?? '',
            bulletItems: bulletItems,
            fontSize: double.tryParse(_attr(child, 'fontSize', nsPrefix: 'fyr') ?? '') ?? 28.0,
            bold: (_attr(child, 'bold', nsPrefix: 'fyr') ?? 'false') == 'true',
            italic: (_attr(child, 'italic', nsPrefix: 'fyr') ?? 'false') == 'true',
            align: _attr(child, 'align', nsPrefix: 'fyr') ?? 'left',
            textColorHex: _attr(child, 'textColorHex', nsPrefix: 'fyr') ?? theme.textHex,
            fillColorHex: _attr(child, 'fillColorHex', nsPrefix: 'fyr') ?? theme.cardBgHex,
            borderColorHex: _attr(child, 'borderColorHex', nsPrefix: 'fyr') ?? theme.accentHex,
            borderRadius:
                double.tryParse(_attr(child, 'borderRadius', nsPrefix: 'fyr') ?? '') ?? 14.0,
            opacity: double.tryParse(_attr(child, 'opacity', nsPrefix: 'fyr') ?? '') ?? 1.0,
            shapeKind: ShapeKind.values.firstWhere(
              (k) => k.name == _attr(child, 'shapeKind', nsPrefix: 'fyr'),
              orElse: () => ShapeKind.roundedRect,
            ),
            codeLanguage: _attr(child, 'codeLanguage', nsPrefix: 'fyr') ?? 'dart',
            chartValues: chartValStr.isEmpty
                ? const []
                : chartValStr
                    .split(',')
                    .map((s) => double.tryParse(s) ?? 0.0)
                    .toList(),
            chartLabels: chartLblStr.isEmpty ? const [] : chartLblStr.split('|'),
          ),
        );
      }

      slides.add(
        SlidePage(
          id: slideId,
          title: slideTitle,
          layout: SlideLayoutType.values.firstWhere(
            (l) => l.name == layoutName,
            orElse: () => SlideLayoutType.titleAndContent,
          ),
          elements: elements,
          speakerNotes: speakerNotes,
          transition: SlideTransitionType.values.firstWhere(
            (t) => t.name == transitionName,
            orElse: () => SlideTransitionType.fade,
          ),
          transitionDurationMs: durationMs,
          bgOverrideHex: bgOverride,
        ),
      );
    }

    return PresentationDeck(
      id: deckId,
      title: deckTitle,
      author: deckAuthor,
      filePath: filePath,
      format: 'odp',
      aspectRatio: aspectRatio,
      theme: theme,
      slides: slides,
    );
  }

  static Future<void> saveOdp(PresentationDeck deck, String path) async {
    final bytes = encodeOdpBytes(deck);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static Future<PresentationDeck> loadOdp(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodeOdpBytes(bytes, filePath: path);
  }

  // ===========================================================================
  // PPTX (PowerPoint OpenXML .pptx) Reader & Writer
  // ===========================================================================

  static Uint8List encodePptxBytes(PresentationDeck deck) {
    final archive = Archive();

    // 1. [Content_Types].xml
    final ctBuffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..writeln(
          '  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..writeln('  <Default Extension="xml" ContentType="application/xml"/>')
      ..writeln(
          '  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');
    for (var i = 0; i < deck.slides.length; i++) {
      final idx = i + 1;
      ctBuffer.writeln(
          '  <Override PartName="/ppt/slides/slide$idx.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
      ctBuffer.writeln(
          '  <Override PartName="/ppt/notesSlides/notesSlide$idx.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>');
    }
    ctBuffer.writeln('</Types>');
    archive.addFile(ArchiveFile.string('[Content_Types].xml', ctBuffer.toString()));

    // 2. _rels/.rels
    const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';
    archive.addFile(ArchiveFile.string('_rels/.rels', rootRels));

    // 3. ppt/presentation.xml & ppt/_rels/presentation.xml.rels
    final presRelsBuf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < deck.slides.length; i++) {
      final idx = i + 1;
      presRelsBuf.writeln(
          '  <Relationship Id="rId$idx" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$idx.xml"/>');
    }
    presRelsBuf.writeln('</Relationships>');
    archive.addFile(
        ArchiveFile.string('ppt/_rels/presentation.xml.rels', presRelsBuf.toString()));

    final presBuilder = XmlBuilder();
    presBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    presBuilder.element(
      'p:presentation',
      namespaces: {
        'http://schemas.openxmlformats.org/presentationml/2006/main': 'p',
        'http://schemas.openxmlformats.org/drawingml/2006/main': 'a',
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships': 'r',
        'https://fyrde.dev/ns/fyrslides/1.0': 'fyr',
      },
      attributes: {
        'fyr:id': deck.id,
        'fyr:title': deck.title,
        'fyr:author': deck.author,
        'fyr:aspectRatio': deck.aspectRatio,
        'fyr:themeId': deck.theme.id,
      },
      nest: () {
        presBuilder.element('p:sldIdLst', nest: () {
          for (var i = 0; i < deck.slides.length; i++) {
            presBuilder.element('p:sldId', attributes: {
              'id': '${256 + i}',
              'r:id': 'rId${i + 1}',
            });
          }
        });
        presBuilder.element('p:sldSz', attributes: {
          'cx': _pptxWidthEmu.toString(),
          'cy': _pptxHeightEmu.toString(),
        });
      },
    );
    archive.addFile(ArchiveFile.string(
      'ppt/presentation.xml',
      presBuilder.buildDocument().toXmlString(pretty: true),
    ));

    // 4. Individual slides & notesSlides
    for (var i = 0; i < deck.slides.length; i++) {
      final idx = i + 1;
      final slide = deck.slides[i];

      // Slide relationships to notesSlide
      final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide$idx.xml"/>
</Relationships>''';
      archive.addFile(
          ArchiveFile.string('ppt/slides/_rels/slide$idx.xml.rels', slideRels));

      final sldBuilder = XmlBuilder();
      sldBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
      sldBuilder.element(
        'p:sld',
        namespaces: {
          'http://schemas.openxmlformats.org/presentationml/2006/main': 'p',
          'http://schemas.openxmlformats.org/drawingml/2006/main': 'a',
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships': 'r',
          'https://fyrde.dev/ns/fyrslides/1.0': 'fyr',
        },
        attributes: {
          'fyr:id': slide.id,
          'fyr:title': slide.title,
          'fyr:layout': slide.layout.name,
          'fyr:transition': slide.transition.name,
          'fyr:transitionDurationMs': slide.transitionDurationMs.toString(),
          if (slide.bgOverrideHex != null) 'fyr:bgOverrideHex': slide.bgOverrideHex!,
        },
        nest: () {
          sldBuilder.element('p:cSld', attributes: {'name': slide.title}, nest: () {
            sldBuilder.element('p:spTree', nest: () {
              for (var eIdx = 0; eIdx < slide.elements.length; eIdx++) {
                final el = slide.elements[eIdx];
                final offX = (el.x * _emuPerUnit).round();
                final offY = (el.y * _emuPerUnit).round();
                final extCx = (el.width * _emuPerUnit).round();
                final extCy = (el.height * _emuPerUnit).round();
                final metaJson = jsonEncode(el.toJson());

                sldBuilder.element('p:sp', nest: () {
                  sldBuilder.element('p:nvSpPr', nest: () {
                    sldBuilder.element('p:cNvPr', attributes: {
                      'id': '${eIdx + 2}',
                      'name': el.id,
                      'descr': metaJson,
                    });
                    sldBuilder.element('p:cNvSpPr');
                    sldBuilder.element('p:nvPr');
                  });
                  sldBuilder.element('p:spPr', nest: () {
                    sldBuilder.element('a:xfrm', nest: () {
                      sldBuilder.element('a:off', attributes: {
                        'x': offX.toString(),
                        'y': offY.toString(),
                      });
                      sldBuilder.element('a:ext', attributes: {
                        'cx': extCx.toString(),
                        'cy': extCy.toString(),
                      });
                    });
                    sldBuilder.element('a:prstGeom',
                        attributes: {'prst': 'rect'}, nest: () {
                      sldBuilder.element('a:avLst');
                    });
                  });
                  sldBuilder.element('p:txBody', nest: () {
                    sldBuilder.element('a:bodyPr');
                    sldBuilder.element('a:lstStyle');
                    if (el.text.isNotEmpty) {
                      for (final line in el.text.split('\n')) {
                        sldBuilder.element('a:p', nest: () {
                          sldBuilder.element('a:r', nest: () {
                            sldBuilder.element('a:rPr', attributes: {
                              'sz': '${(el.fontSize * 100).round()}',
                              if (el.bold) 'b': '1',
                              if (el.italic) 'i': '1',
                            });
                            sldBuilder.element('a:t', nest: line);
                          });
                        });
                      }
                    }
                    for (final bullet in el.bulletItems) {
                      sldBuilder.element('a:p', nest: () {
                        sldBuilder.element('a:pPr', nest: () {
                          sldBuilder.element('a:buChar', attributes: {'char': '•'});
                        });
                        sldBuilder.element('a:r', nest: () {
                          sldBuilder.element('a:t', nest: bullet);
                        });
                      });
                    }
                  });
                });
              }
            });
          });
        },
      );

      archive.addFile(ArchiveFile.string(
        'ppt/slides/slide$idx.xml',
        sldBuilder.buildDocument().toXmlString(pretty: true),
      ));

      // Notes slide
      final notesBuilder = XmlBuilder();
      notesBuilder.processing(
          'xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
      notesBuilder.element(
        'p:notes',
        namespaces: {
          'http://schemas.openxmlformats.org/presentationml/2006/main': 'p',
          'http://schemas.openxmlformats.org/drawingml/2006/main': 'a',
        },
        nest: () {
          notesBuilder.element('p:cSld', nest: () {
            notesBuilder.element('p:spTree', nest: () {
              notesBuilder.element('p:sp', nest: () {
                notesBuilder.element('p:txBody', nest: () {
                  for (final line in slide.speakerNotes.split('\n')) {
                    notesBuilder.element('a:p', nest: () {
                      notesBuilder.element('a:r', nest: () {
                        notesBuilder.element('a:t', nest: line);
                      });
                    });
                  }
                });
              });
            });
          });
        },
      );
      archive.addFile(ArchiveFile.string(
        'ppt/notesSlides/notesSlide$idx.xml',
        notesBuilder.buildDocument().toXmlString(pretty: true),
      ));
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static PresentationDeck decodePptxBytes(
    Uint8List bytes, {
    String? filePath,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final fileMap = <String, ArchiveFile>{};
    for (final f in archive) {
      fileMap[f.name] = f;
    }

    var deckId = 'deck_pptx';
    var deckTitle = filePath != null
        ? filePath.split('/').last.replaceAll(RegExp(r'\.pptx$', caseSensitive: false), '')
        : 'PowerPoint Presentation';
    var deckAuthor = 'FyrDE Studio';
    var aspectRatio = '16:9';
    var themeId = 'fyr_cyber_purple';

    final presFile = fileMap['ppt/presentation.xml'];
    if (presFile != null) {
      final presDoc = XmlDocument.parse(
        utf8.decode(presFile.content, allowMalformed: true),
      );
      final root = presDoc.rootElement;
      deckId = _attr(root, 'id', nsPrefix: 'fyr') ?? deckId;
      deckTitle = _attr(root, 'title', nsPrefix: 'fyr') ?? deckTitle;
      deckAuthor = _attr(root, 'author', nsPrefix: 'fyr') ?? deckAuthor;
      aspectRatio = _attr(root, 'aspectRatio', nsPrefix: 'fyr') ?? aspectRatio;
      themeId = _attr(root, 'themeId', nsPrefix: 'fyr') ?? themeId;
    }

    final theme = kDeckThemePresets.firstWhere(
      (t) => t.id == themeId,
      orElse: () => kDeckThemePresets.first,
    );

    // Collect slide files sorted by index (ppt/slides/slide1.xml, slide2.xml, ...)
    final slideEntries = fileMap.entries
        .where((e) => RegExp(r'^ppt/slides/slide(\d+)\.xml$').hasMatch(e.key))
        .toList();
    slideEntries.sort((a, b) {
      final na = int.parse(RegExp(r'slide(\d+)\.xml$').firstMatch(a.key)!.group(1)!);
      final nb = int.parse(RegExp(r'slide(\d+)\.xml$').firstMatch(b.key)!.group(1)!);
      return na.compareTo(nb);
    });

    final slides = <SlidePage>[];
    for (var i = 0; i < slideEntries.length; i++) {
      final slideIdx =
          int.parse(RegExp(r'slide(\d+)\.xml$').firstMatch(slideEntries[i].key)!.group(1)!);
      final sldDoc = XmlDocument.parse(
        utf8.decode(slideEntries[i].value.content, allowMalformed: true),
      );
      final sldRoot = sldDoc.rootElement;
      final cSld = sldRoot
          .findAllElements('cSld', namespace: '*')
          .cast<XmlElement?>()
          .firstWhere((e) => e != null, orElse: () => null);

      final slideId = _attr(sldRoot, 'id', nsPrefix: 'fyr') ?? 'slide_$slideIdx';
      final slideTitle = _attr(sldRoot, 'title', nsPrefix: 'fyr') ??
          _attr(cSld, 'name') ??
          'Slide $slideIdx';
      final layoutName = _attr(sldRoot, 'layout', nsPrefix: 'fyr') ?? 'titleAndContent';
      final transitionName = _attr(sldRoot, 'transition', nsPrefix: 'fyr') ?? 'fade';
      final durationMs =
          int.tryParse(_attr(sldRoot, 'transitionDurationMs', nsPrefix: 'fyr') ?? '380') ??
              380;
      final bgOverride = _attr(sldRoot, 'bgOverrideHex', nsPrefix: 'fyr');

      final elements = <SlideElement>[];
      for (final sp in sldRoot.findAllElements('sp', namespace: '*')) {
        final cNvPr = sp
            .findAllElements('cNvPr', namespace: '*')
            .cast<XmlElement?>()
            .firstWhere((e) => e != null, orElse: () => null);
        final offEl = sp
            .findAllElements('off', namespace: '*')
            .cast<XmlElement?>()
            .firstWhere((e) => e != null, orElse: () => null);
        final extEl = sp
            .findAllElements('ext', namespace: '*')
            .cast<XmlElement?>()
            .firstWhere((e) => e != null, orElse: () => null);

        final offX = int.tryParse(_attr(offEl, 'x') ?? '0') ?? 120 * _emuPerUnit;
        final offY = int.tryParse(_attr(offEl, 'y') ?? '0') ?? 120 * _emuPerUnit;
        final extCx = int.tryParse(_attr(extEl, 'cx') ?? '0') ?? 480 * _emuPerUnit;
        final extCy = int.tryParse(_attr(extEl, 'cy') ?? '0') ?? 140 * _emuPerUnit;

        final x = offX / _emuPerUnit;
        final y = offY / _emuPerUnit;
        final w = extCx / _emuPerUnit;
        final h = extCy / _emuPerUnit;

        // Check if rich fyrSlides metadata is stored in descr
        final descr = _attr(cNvPr, 'descr');
        if (descr != null && descr.trim().startsWith('{')) {
          try {
            final parsed = jsonDecode(descr) as Map<String, dynamic>;
            elements.add(
              SlideElement.fromJson(parsed).copyWith(
                x: x,
                y: y,
                width: w,
                height: h,
              ),
            );
            continue;
          } catch (_) {
            // Fall through to standard OpenXML shape parsing
          }
        }

        final paraLines = <String>[];
        final bulletLines = <String>[];
        var fontSize = 28.0;
        var isBold = false;
        var isItalic = false;

        for (final p in sp.findAllElements('p', namespace: '*')) {
          final hasBullet = p.findAllElements('buChar', namespace: '*').isNotEmpty;
          final rPr = p
              .findAllElements('rPr', namespace: '*')
              .cast<XmlElement?>()
              .firstWhere((e) => e != null, orElse: () => null);
          if (rPr != null) {
            final sz = int.tryParse(_attr(rPr, 'sz') ?? '');
            if (sz != null && sz > 0) fontSize = sz / 100.0;
            if (_attr(rPr, 'b') == '1') isBold = true;
            if (_attr(rPr, 'i') == '1') isItalic = true;
          }
          final runs = p
              .findAllElements('t', namespace: '*')
              .map((t) => t.innerText)
              .join();
          if (runs.isEmpty) continue;
          if (hasBullet) {
            bulletLines.add(runs);
          } else {
            paraLines.add(runs);
          }
        }

        elements.add(
          SlideElement(
            id: _attr(cNvPr, 'name') ?? 'el_${elements.length + 1}',
            type: bulletLines.isNotEmpty && paraLines.isEmpty
                ? SlideElementType.bulletList
                : SlideElementType.text,
            x: x,
            y: y,
            width: w,
            height: h,
            text: paraLines.join('\n'),
            bulletItems: bulletLines,
            fontSize: fontSize,
            bold: isBold,
            italic: isItalic,
            textColorHex: theme.textHex,
            fillColorHex: theme.cardBgHex,
            borderColorHex: theme.accentHex,
          ),
        );
      }

      // Parse speaker notes from ppt/notesSlides/notesSlideN.xml
      var speakerNotes = '';
      final notesFile = fileMap['ppt/notesSlides/notesSlide$slideIdx.xml'];
      if (notesFile != null) {
        final notesDoc = XmlDocument.parse(
          utf8.decode(notesFile.content, allowMalformed: true),
        );
        final lines = notesDoc
            .findAllElements('t', namespace: '*')
            .map((t) => t.innerText.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        speakerNotes = lines.join('\n');
      }

      slides.add(
        SlidePage(
          id: slideId,
          title: slideTitle,
          layout: SlideLayoutType.values.firstWhere(
            (l) => l.name == layoutName,
            orElse: () => SlideLayoutType.titleAndContent,
          ),
          elements: elements,
          speakerNotes: speakerNotes,
          transition: SlideTransitionType.values.firstWhere(
            (t) => t.name == transitionName,
            orElse: () => SlideTransitionType.fade,
          ),
          transitionDurationMs: durationMs,
          bgOverrideHex: bgOverride,
        ),
      );
    }

    return PresentationDeck(
      id: deckId,
      title: deckTitle,
      author: deckAuthor,
      filePath: filePath,
      format: 'pptx',
      aspectRatio: aspectRatio,
      theme: theme,
      slides: slides,
    );
  }

  static Future<void> savePptx(PresentationDeck deck, String path) async {
    final bytes = encodePptxBytes(deck);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static Future<PresentationDeck> loadPptx(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodePptxBytes(bytes, filePath: path);
  }

  // ===========================================================================
  // HTML5 Interactive Presentation Deck Exporter (.html)
  // ===========================================================================

  static String toHtmlDeck(PresentationDeck deck) {
    final theme = deck.theme;
    final slidesHtml = StringBuffer();

    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final activeClass = i == 0 ? ' active' : '';
      slidesHtml.writeln(
          '    <section class="slide$activeClass" data-index="$i" data-notes="${_esc(slide.speakerNotes)}">');
      for (final el in slide.elements) {
        final leftPct = (el.x / SlideElement.canvasWidth * 100.0).toStringAsFixed(2);
        final topPct = (el.y / SlideElement.canvasHeight * 100.0).toStringAsFixed(2);
        final widthPct =
            (el.width / SlideElement.canvasWidth * 100.0).toStringAsFixed(2);
        final heightPct =
            (el.height / SlideElement.canvasHeight * 100.0).toStringAsFixed(2);

        slidesHtml.writeln(
            '      <div class="el el-${el.type.name}" style="left:$leftPct%;top:$topPct%;width:$widthPct%;height:$heightPct%;color:${el.textColorHex};text-align:${el.align};">');
        if (el.type == SlideElementType.metricCard) {
          slidesHtml.writeln(
              '        <div class="metric-card" style="background:${el.fillColorHex};border-color:${el.borderColorHex};">');
          slidesHtml.writeln(
              '          <div class="metric-value" style="color:${el.borderColorHex};">${_esc(el.text)}</div>');
          slidesHtml.writeln(
              '          <div class="metric-sub">${_esc(el.subtitle)}</div>');
          slidesHtml.writeln('        </div>');
        } else if (el.type == SlideElementType.bulletList) {
          if (el.text.isNotEmpty) {
            slidesHtml.writeln('        <h3>${_esc(el.text)}</h3>');
          }
          slidesHtml.writeln('        <ul>');
          for (final item in el.bulletItems) {
            slidesHtml.writeln('          <li>${_esc(item)}</li>');
          }
          slidesHtml.writeln('        </ul>');
        } else if (el.type == SlideElementType.codeBlock) {
          slidesHtml.writeln(
              '        <pre class="code-box"><code>${_esc(el.text)}</code></pre>');
        } else {
          slidesHtml.writeln(
              '        <div style="font-size:${(el.fontSize * 0.72).toStringAsFixed(1)}px;font-weight:${el.bold ? '700' : '400'};">${_esc(el.text)}</div>');
          if (el.subtitle.isNotEmpty) {
            slidesHtml.writeln(
                '        <div class="sub">${_esc(el.subtitle)}</div>');
          }
        }
        slidesHtml.writeln('      </div>');
      }
      slidesHtml.writeln('    </section>');
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>${_esc(deck.title)} — fyrSlides Deck</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #05030A;
      color: ${theme.textHex};
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }
    .stage {
      position: relative;
      width: min(94vw, calc(88vh * 16 / 9));
      aspect-ratio: 16 / 9;
      background: linear-gradient(135deg, ${theme.bgStartHex}, ${theme.bgEndHex});
      border: 1px solid ${theme.accentHex}55;
      border-radius: 14px;
      overflow: hidden;
      box-shadow: 0 24px 70px rgba(0,0,0,0.75);
    }
    .slide {
      position: absolute;
      inset: 0;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.35s ease, transform 0.35s ease;
      transform: translateX(18px);
    }
    .slide.active {
      opacity: 1;
      pointer-events: auto;
      transform: translateX(0);
    }
    .el { position: absolute; padding: 8px; }
    .metric-card {
      height: 100%;
      border-radius: 14px;
      border: 1.5px solid ${theme.accentHex};
      padding: 18px;
      display: flex;
      flex-direction: column;
      justify-content: center;
    }
    .metric-value { font-size: 2.2rem; font-weight: 800; margin-bottom: 6px; }
    .metric-sub { font-size: 0.95rem; opacity: 0.85; }
    .code-box {
      height: 100%;
      background: #090612;
      border: 1px solid ${theme.accentHex}66;
      border-radius: 12px;
      padding: 16px;
      font-family: monospace;
      font-size: 0.9rem;
      overflow: auto;
    }
    ul { padding-left: 22px; line-height: 1.75; }
    .hud {
      margin-top: 12px;
      display: flex;
      gap: 14px;
      align-items: center;
      font-size: 13px;
      opacity: 0.85;
    }
    button {
      background: ${theme.cardBgHex};
      color: ${theme.textHex};
      border: 1px solid ${theme.accentHex}66;
      border-radius: 6px;
      padding: 5px 12px;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="stage" id="stage">
$slidesHtml  </div>
  <div class="hud">
    <button onclick="step(-1)">Prev</button>
    <span id="counter">1 / ${deck.slides.length}</span>
    <button onclick="step(1)">Next</button>
  </div>
  <script>
    let idx = 0;
    const slides = document.querySelectorAll('.slide');
    function show(n) {
      idx = Math.max(0, Math.min(slides.length - 1, n));
      slides.forEach((s, i) => s.classList.toggle('active', i === idx));
      document.getElementById('counter').textContent = (idx + 1) + ' / ' + slides.length;
    }
    function step(d) { show(idx + d); }
    window.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === ' ') step(1);
      if (e.key === 'ArrowLeft') step(-1);
    });
  </script>
</body>
</html>''';
  }

  static Future<void> exportHtml(PresentationDeck deck, String path) async {
    final html = toHtmlDeck(deck);
    await File(path).writeAsString(html, flush: true);
  }

  static String _esc(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String? _attr(XmlElement? el, String localName, {String? nsPrefix}) {
    if (el == null) return null;
    for (final a in el.attributes) {
      if (a.name.local == localName) {
        if (nsPrefix == null || a.name.prefix == nsPrefix) {
          return a.value;
        }
      }
    }
    return null;
  }
}
