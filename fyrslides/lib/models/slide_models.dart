import 'package:flutter/material.dart';

enum SlideLayoutType {
  titleSlide('Title Slide', Icons.title_rounded),
  sectionHeader('Section Header', Icons.view_headline_rounded),
  titleAndContent('Title & Content', Icons.article_outlined),
  twoColumn('Two Column', Icons.view_column_rounded),
  metricsCallout('Metrics Callout', Icons.analytics_outlined),
  codeShowcase('Code Showcase', Icons.code_rounded),
  blank('Blank Canvas', Icons.crop_16_9_rounded);

  final String label;
  final IconData icon;
  const SlideLayoutType(this.label, this.icon);
}

enum SlideElementType {
  text('Text Box', Icons.text_fields_rounded),
  bulletList('Bullet List', Icons.format_list_bulleted_rounded),
  shape('Shape', Icons.category_outlined),
  metricCard('Metric Card', Icons.speed_rounded),
  codeBlock('Code Block', Icons.terminal_rounded),
  chartCard('Bar Chart', Icons.bar_chart_rounded),
  badge('Neon Badge', Icons.label_important_outline_rounded);

  final String label;
  final IconData icon;
  const SlideElementType(this.label, this.icon);
}

enum ShapeKind {
  roundedRect('Rounded Box'),
  circle('Circle'),
  pill('Pill Capsule'),
  arrowRight('Arrow Right'),
  line('Accent Line'),
  diamond('Diamond');

  final String label;
  const ShapeKind(this.label);
}

enum SlideTransitionType {
  none('None', Icons.block_rounded),
  fade('Fade', Icons.blur_on_rounded),
  slideLeft('Slide', Icons.swap_horiz_rounded),
  zoomIn('Zoom', Icons.zoom_out_map_rounded),
  flip('3D Flip', Icons.flip_rounded);

  final String label;
  final IconData icon;
  const SlideTransitionType(this.label, this.icon);
}

class DeckThemePreset {
  final String id;
  final String name;
  final String bgStartHex;
  final String bgEndHex;
  final String accentHex;
  final String secondaryAccentHex;
  final String textHex;
  final String cardBgHex;

  const DeckThemePreset({
    required this.id,
    required this.name,
    required this.bgStartHex,
    required this.bgEndHex,
    required this.accentHex,
    required this.secondaryAccentHex,
    required this.textHex,
    required this.cardBgHex,
  });

  Color get bgStart => colorFromHex(bgStartHex);
  Color get bgEnd => colorFromHex(bgEndHex);
  Color get accent => colorFromHex(accentHex);
  Color get secondaryAccent => colorFromHex(secondaryAccentHex);
  Color get textColor => colorFromHex(textHex);
  Color get cardBg => colorFromHex(cardBgHex);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bgStartHex': bgStartHex,
        'bgEndHex': bgEndHex,
        'accentHex': accentHex,
        'secondaryAccentHex': secondaryAccentHex,
        'textHex': textHex,
        'cardBgHex': cardBgHex,
      };

  factory DeckThemePreset.fromJson(Map<String, dynamic> json) {
    return DeckThemePreset(
      id: json['id'] as String? ?? 'fyr_cyber_purple',
      name: json['name'] as String? ?? 'Fyr Cyber Purple',
      bgStartHex: json['bgStartHex'] as String? ?? '#0B0714',
      bgEndHex: json['bgEndHex'] as String? ?? '#170E29',
      accentHex: json['accentHex'] as String? ?? '#D040FF',
      secondaryAccentHex: json['secondaryAccentHex'] as String? ?? '#00E5FF',
      textHex: json['textHex'] as String? ?? '#F6F2FF',
      cardBgHex: json['cardBgHex'] as String? ?? '#1D1433',
    );
  }
}

const List<DeckThemePreset> kDeckThemePresets = [
  DeckThemePreset(
    id: 'fyr_cyber_purple',
    name: 'Fyr Cyber Purple',
    bgStartHex: '#0B0714',
    bgEndHex: '#180E2C',
    accentHex: '#D040FF',
    secondaryAccentHex: '#00E5FF',
    textHex: '#F6F2FF',
    cardBgHex: '#1D1433',
  ),
  DeckThemePreset(
    id: 'midnight_neon',
    name: 'Midnight Neon',
    bgStartHex: '#060D1A',
    bgEndHex: '#0D1F38',
    accentHex: '#00E5FF',
    secondaryAccentHex: '#7C4DFF',
    textHex: '#EDF7FF',
    cardBgHex: '#112542',
  ),
  DeckThemePreset(
    id: 'obsidian_minimal',
    name: 'Obsidian Minimal',
    bgStartHex: '#09090B',
    bgEndHex: '#16161B',
    accentHex: '#A855F7',
    secondaryAccentHex: '#38BDF8',
    textHex: '#FAFAFA',
    cardBgHex: '#1D1D24',
  ),
  DeckThemePreset(
    id: 'emerald_matrix',
    name: 'Emerald Matrix',
    bgStartHex: '#05120E',
    bgEndHex: '#0B241C',
    accentHex: '#10B981',
    secondaryAccentHex: '#34D399',
    textHex: '#ECFDF5',
    cardBgHex: '#103026',
  ),
  DeckThemePreset(
    id: 'solar_flare',
    name: 'Solar Flare',
    bgStartHex: '#160A06',
    bgEndHex: '#28130B',
    accentHex: '#FF6B35',
    secondaryAccentHex: '#FBBF24',
    textHex: '#FFF7ED',
    cardBgHex: '#2F1910',
  ),
  DeckThemePreset(
    id: 'daylight_studio',
    name: 'Daylight Studio',
    bgStartHex: '#F8FAFC',
    bgEndHex: '#EEF2FF',
    accentHex: '#7C3AED',
    secondaryAccentHex: '#0284C7',
    textHex: '#0F172A',
    cardBgHex: '#FFFFFF',
  ),
];

Color colorFromHex(String hex, {Color fallback = const Color(0xFFD040FF)}) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) {
    final val = int.tryParse('FF$cleaned', radix: 16);
    if (val != null) return Color(val);
  } else if (cleaned.length == 8) {
    final val = int.tryParse(cleaned, radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}

String hexFromColor(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
}

/// Logical canvas coordinates are based on a 1600x900 16:9 stage.
class SlideElement {
  static const double canvasWidth = 1600.0;
  static const double canvasHeight = 900.0;

  final String id;
  final SlideElementType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final String subtitle;
  final List<String> bulletItems;
  final double fontSize;
  final bool bold;
  final bool italic;
  final String align; // 'left' | 'center' | 'right'
  final String textColorHex;
  final String fillColorHex;
  final String borderColorHex;
  final double borderRadius;
  final double opacity;
  final ShapeKind shapeKind;
  final String codeLanguage;
  final List<double> chartValues;
  final List<String> chartLabels;

  const SlideElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text = '',
    this.subtitle = '',
    this.bulletItems = const [],
    this.fontSize = 28.0,
    this.bold = false,
    this.italic = false,
    this.align = 'left',
    this.textColorHex = '#F6F2FF',
    this.fillColorHex = '#1D1433',
    this.borderColorHex = '#D040FF',
    this.borderRadius = 14.0,
    this.opacity = 1.0,
    this.shapeKind = ShapeKind.roundedRect,
    this.codeLanguage = 'dart',
    this.chartValues = const [],
    this.chartLabels = const [],
  });

  TextAlign get textAlign {
    switch (align) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  SlideElement copyWith({
    String? id,
    SlideElementType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    String? subtitle,
    List<String>? bulletItems,
    double? fontSize,
    bool? bold,
    bool? italic,
    String? align,
    String? textColorHex,
    String? fillColorHex,
    String? borderColorHex,
    double? borderRadius,
    double? opacity,
    ShapeKind? shapeKind,
    String? codeLanguage,
    List<double>? chartValues,
    List<String>? chartLabels,
  }) {
    return SlideElement(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      text: text ?? this.text,
      subtitle: subtitle ?? this.subtitle,
      bulletItems: bulletItems ?? List<String>.from(this.bulletItems),
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      align: align ?? this.align,
      textColorHex: textColorHex ?? this.textColorHex,
      fillColorHex: fillColorHex ?? this.fillColorHex,
      borderColorHex: borderColorHex ?? this.borderColorHex,
      borderRadius: borderRadius ?? this.borderRadius,
      opacity: opacity ?? this.opacity,
      shapeKind: shapeKind ?? this.shapeKind,
      codeLanguage: codeLanguage ?? this.codeLanguage,
      chartValues: chartValues ?? List<double>.from(this.chartValues),
      chartLabels: chartLabels ?? List<String>.from(this.chartLabels),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': text,
        'subtitle': subtitle,
        'bulletItems': bulletItems,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'align': align,
        'textColorHex': textColorHex,
        'fillColorHex': fillColorHex,
        'borderColorHex': borderColorHex,
        'borderRadius': borderRadius,
        'opacity': opacity,
        'shapeKind': shapeKind.name,
        'codeLanguage': codeLanguage,
        'chartValues': chartValues,
        'chartLabels': chartLabels,
      };

  factory SlideElement.fromJson(Map<String, dynamic> json) {
    return SlideElement(
      id: json['id'] as String? ?? 'el_1',
      type: SlideElementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SlideElementType.text,
      ),
      x: (json['x'] as num?)?.toDouble() ?? 100.0,
      y: (json['y'] as num?)?.toDouble() ?? 100.0,
      width: (json['width'] as num?)?.toDouble() ?? 400.0,
      height: (json['height'] as num?)?.toDouble() ?? 120.0,
      text: json['text'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      bulletItems: (json['bulletItems'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 28.0,
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      align: json['align'] as String? ?? 'left',
      textColorHex: json['textColorHex'] as String? ?? '#F6F2FF',
      fillColorHex: json['fillColorHex'] as String? ?? '#1D1433',
      borderColorHex: json['borderColorHex'] as String? ?? '#D040FF',
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 14.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      shapeKind: ShapeKind.values.firstWhere(
        (k) => k.name == json['shapeKind'],
        orElse: () => ShapeKind.roundedRect,
      ),
      codeLanguage: json['codeLanguage'] as String? ?? 'dart',
      chartValues: (json['chartValues'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      chartLabels: (json['chartLabels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

class SlidePage {
  final String id;
  final String title;
  final SlideLayoutType layout;
  final List<SlideElement> elements;
  final String speakerNotes;
  final SlideTransitionType transition;
  final int transitionDurationMs;
  final String? bgOverrideHex;

  const SlidePage({
    required this.id,
    required this.title,
    this.layout = SlideLayoutType.titleAndContent,
    this.elements = const [],
    this.speakerNotes = '',
    this.transition = SlideTransitionType.fade,
    this.transitionDurationMs = 380,
    this.bgOverrideHex,
  });

  SlidePage copyWith({
    String? id,
    String? title,
    SlideLayoutType? layout,
    List<SlideElement>? elements,
    String? speakerNotes,
    SlideTransitionType? transition,
    int? transitionDurationMs,
    String? bgOverrideHex,
  }) {
    return SlidePage(
      id: id ?? this.id,
      title: title ?? this.title,
      layout: layout ?? this.layout,
      elements: elements ?? this.elements.map((e) => e.copyWith()).toList(),
      speakerNotes: speakerNotes ?? this.speakerNotes,
      transition: transition ?? this.transition,
      transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
      bgOverrideHex: bgOverrideHex ?? this.bgOverrideHex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'layout': layout.name,
        'elements': elements.map((e) => e.toJson()).toList(),
        'speakerNotes': speakerNotes,
        'transition': transition.name,
        'transitionDurationMs': transitionDurationMs,
        'bgOverrideHex': bgOverrideHex,
      };

  factory SlidePage.fromJson(Map<String, dynamic> json) {
    return SlidePage(
      id: json['id'] as String? ?? 'slide_1',
      title: json['title'] as String? ?? 'Untitled Slide',
      layout: SlideLayoutType.values.firstWhere(
        (l) => l.name == json['layout'],
        orElse: () => SlideLayoutType.titleAndContent,
      ),
      elements: (json['elements'] as List<dynamic>?)
              ?.map((e) => SlideElement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      speakerNotes: json['speakerNotes'] as String? ?? '',
      transition: SlideTransitionType.values.firstWhere(
        (t) => t.name == json['transition'],
        orElse: () => SlideTransitionType.fade,
      ),
      transitionDurationMs: json['transitionDurationMs'] as int? ?? 380,
      bgOverrideHex: json['bgOverrideHex'] as String?,
    );
  }
}

class PresentationDeck {
  final String id;
  final String title;
  final String author;
  final String? filePath;
  final String format; // 'odp' | 'pptx' | 'html'
  final String aspectRatio; // '16:9' | '16:10' | '4:3'
  final DeckThemePreset theme;
  final List<SlidePage> slides;

  const PresentationDeck({
    required this.id,
    required this.title,
    this.author = 'FyrDE Studio',
    this.filePath,
    this.format = 'odp',
    this.aspectRatio = '16:9',
    this.theme = const DeckThemePreset(
      id: 'fyr_cyber_purple',
      name: 'Fyr Cyber Purple',
      bgStartHex: '#0B0714',
      bgEndHex: '#180E2C',
      accentHex: '#D040FF',
      secondaryAccentHex: '#00E5FF',
      textHex: '#F6F2FF',
      cardBgHex: '#1D1433',
    ),
    this.slides = const [],
  });

  double get aspectRatioValue {
    switch (aspectRatio) {
      case '16:10':
        return 16.0 / 10.0;
      case '4:3':
        return 4.0 / 3.0;
      default:
        return 16.0 / 9.0;
    }
  }

  PresentationDeck copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    String? format,
    String? aspectRatio,
    DeckThemePreset? theme,
    List<SlidePage>? slides,
  }) {
    return PresentationDeck(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      theme: theme ?? this.theme,
      slides: slides ?? this.slides.map((s) => s.copyWith()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'format': format,
        'aspectRatio': aspectRatio,
        'theme': theme.toJson(),
        'slides': slides.map((s) => s.toJson()).toList(),
      };

  factory PresentationDeck.fromJson(Map<String, dynamic> json) {
    return PresentationDeck(
      id: json['id'] as String? ?? 'deck_1',
      title: json['title'] as String? ?? 'fyrDE_2026_Keynote',
      author: json['author'] as String? ?? 'FyrDE Studio',
      filePath: json['filePath'] as String?,
      format: json['format'] as String? ?? 'odp',
      aspectRatio: json['aspectRatio'] as String? ?? '16:9',
      theme: json['theme'] != null
          ? DeckThemePreset.fromJson(json['theme'] as Map<String, dynamic>)
          : kDeckThemePresets.first,
      slides: (json['slides'] as List<dynamic>?)
              ?.map((s) => SlidePage.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
