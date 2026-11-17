import 'dart:typed_data';
import 'package:flutter/material.dart';

enum MediaType { video, audio, image, title, color }

enum DirectorTool { select, razor }

enum TransitionKind {
  none('None'),
  fade('Fade'),
  dissolve('Cross Dissolve'),
  slideLeft('Slide Left'),
  zoomIn('Zoom In');

  final String label;
  const TransitionKind(this.label);
}

enum ExportFormat {
  mp4('MP4 (H.264 + AAC)', 'mp4', 'libx264', 'aac'),
  mkv('MKV (H.264 + AAC)', 'mkv', 'libx264', 'aac'),
  webm('WebM (VP9 + Opus)', 'webm', 'libvpx-vp9', 'libopus'),
  gif('Animated GIF', 'gif', 'gif', '');

  final String label;
  final String ext;
  final String vcodec;
  final String acodec;
  const ExportFormat(this.label, this.ext, this.vcodec, this.acodec);
}

class SequencePreset {
  final String name;
  final int width;
  final int height;
  final double fps;

  const SequencePreset(this.name, this.width, this.height, this.fps);
}

const List<SequencePreset> kSequencePresets = [
  SequencePreset('1080p Landscape', 1920, 1080, 30),
  SequencePreset('1080p 60fps', 1920, 1080, 60),
  SequencePreset('Vertical Shorts / Reels', 1080, 1920, 30),
  SequencePreset('720p HD', 1280, 720, 30),
  SequencePreset('4K UHD', 3840, 2160, 30),
  SequencePreset('Square 1:1', 1080, 1080, 30),
];

class MediaAsset {
  final String id;
  final String name;
  final String path;
  final MediaType type;
  final double durationSec;
  final int width;
  final int height;
  final double fps;
  final bool hasAudio;
  List<String> thumbnailPaths;
  Float32List? waveformPeaks;

  MediaAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.durationSec,
    this.width = 1920,
    this.height = 1080,
    this.fps = 30.0,
    this.hasAudio = false,
    List<String>? thumbnailPaths,
    this.waveformPeaks,
  }) : thumbnailPaths = thumbnailPaths ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'type': type.name,
        'durationSec': durationSec,
        'width': width,
        'height': height,
        'fps': fps,
        'hasAudio': hasAudio,
      };

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        type: MediaType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MediaType.video,
        ),
        durationSec: (json['durationSec'] as num?)?.toDouble() ?? 5.0,
        width: json['width'] as int? ?? 1920,
        height: json['height'] as int? ?? 1080,
        fps: (json['fps'] as num?)?.toDouble() ?? 30.0,
        hasAudio: json['hasAudio'] as bool? ?? false,
      );
}

class ClipEffects {
  double opacity; // 0..1
  double brightness; // -0.5..0.5
  double contrast; // 0.2..2.0
  double saturation; // 0.0..2.0
  double blur; // 0..20
  double scale; // 0.1..3.0
  double offsetX; // -1..1 normalized to canvas width
  double offsetY; // -1..1 normalized to canvas height
  double rotationDeg; // -180..180
  double volume; // 0..2.0
  double speed; // 0.25..4.0
  double fadeInSec;
  double fadeOutSec;
  TransitionKind transitionIn;
  double transitionDurationSec;

  ClipEffects({
    this.opacity = 1.0,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.blur = 0.0,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.rotationDeg = 0.0,
    this.volume = 1.0,
    this.speed = 1.0,
    this.fadeInSec = 0.0,
    this.fadeOutSec = 0.0,
    this.transitionIn = TransitionKind.none,
    this.transitionDurationSec = 0.5,
  });

  ClipEffects clone() => ClipEffects(
        opacity: opacity,
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
        blur: blur,
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY,
        rotationDeg: rotationDeg,
        volume: volume,
        speed: speed,
        fadeInSec: fadeInSec,
        fadeOutSec: fadeOutSec,
        transitionIn: transitionIn,
        transitionDurationSec: transitionDurationSec,
      );

  Map<String, dynamic> toJson() => {
        'opacity': opacity,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'blur': blur,
        'scale': scale,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'rotationDeg': rotationDeg,
        'volume': volume,
        'speed': speed,
        'fadeInSec': fadeInSec,
        'fadeOutSec': fadeOutSec,
        'transitionIn': transitionIn.name,
        'transitionDurationSec': transitionDurationSec,
      };

  factory ClipEffects.fromJson(Map<String, dynamic> json) => ClipEffects(
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
        contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
        saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
        blur: (json['blur'] as num?)?.toDouble() ?? 0.0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
        offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.0,
        offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.0,
        rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        fadeInSec: (json['fadeInSec'] as num?)?.toDouble() ?? 0.0,
        fadeOutSec: (json['fadeOutSec'] as num?)?.toDouble() ?? 0.0,
        transitionIn: TransitionKind.values.firstWhere(
          (e) => e.name == json['transitionIn'],
          orElse: () => TransitionKind.none,
        ),
        transitionDurationSec:
            (json['transitionDurationSec'] as num?)?.toDouble() ?? 0.5,
      );
}

class TitleClipStyle {
  String text;
  String fontFamily;
  double fontSize;
  bool bold;
  Color textColor;
  Color bgColor;
  double bgOpacity;
  double posYRatio; // 0.15=top, 0.5=center, 0.82=lower-third

  TitleClipStyle({
    this.text = 'Title Text',
    this.fontFamily = 'Outfit',
    this.fontSize = 64.0,
    this.bold = true,
    this.textColor = Colors.white,
    this.bgColor = const Color(0xFF000000),
    this.bgOpacity = 0.0,
    this.posYRatio = 0.5,
  });

  TitleClipStyle clone() => TitleClipStyle(
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        bold: bold,
        textColor: textColor,
        bgColor: bgColor,
        bgOpacity: bgOpacity,
        posYRatio: posYRatio,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'textColor': textColor.toARGB32(),
        'bgColor': bgColor.toARGB32(),
        'bgOpacity': bgOpacity,
        'posYRatio': posYRatio,
      };

  factory TitleClipStyle.fromJson(Map<String, dynamic> json) => TitleClipStyle(
        text: json['text'] as String? ?? 'Title',
        fontFamily: json['fontFamily'] as String? ?? 'Outfit',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 64.0,
        bold: json['bold'] as bool? ?? true,
        textColor: Color(json['textColor'] as int? ?? 0xFFFFFFFF),
        bgColor: Color(json['bgColor'] as int? ?? 0xFF000000),
        bgOpacity: (json['bgOpacity'] as num?)?.toDouble() ?? 0.0,
        posYRatio: (json['posYRatio'] as num?)?.toDouble() ?? 0.5,
      );
}

class TimelineClip {
  final String id;
  final String? assetId;
  String name;
  final MediaType type;
  int trackIndex;
  double timelineStartSec;
  double sourceInSec;
  double durationSec; // Timeline duration (after speed)
  double maxSourceDurationSec;
  Color clipColor;
  ClipEffects effects;
  TitleClipStyle? titleStyle;

  TimelineClip({
    required this.id,
    this.assetId,
    required this.name,
    required this.type,
    required this.trackIndex,
    required this.timelineStartSec,
    this.sourceInSec = 0.0,
    required this.durationSec,
    this.maxSourceDurationSec = 3600.0,
    required this.clipColor,
    ClipEffects? effects,
    this.titleStyle,
  }) : effects = effects ?? ClipEffects();

  double get timelineEndSec => timelineStartSec + durationSec;

  TimelineClip clone() => TimelineClip(
        id: id,
        assetId: assetId,
        name: name,
        type: type,
        trackIndex: trackIndex,
        timelineStartSec: timelineStartSec,
        sourceInSec: sourceInSec,
        durationSec: durationSec,
        maxSourceDurationSec: maxSourceDurationSec,
        clipColor: clipColor,
        effects: effects.clone(),
        titleStyle: titleStyle?.clone(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'assetId': assetId,
        'name': name,
        'type': type.name,
        'trackIndex': trackIndex,
        'timelineStartSec': timelineStartSec,
        'sourceInSec': sourceInSec,
        'durationSec': durationSec,
        'maxSourceDurationSec': maxSourceDurationSec,
        'clipColor': clipColor.toARGB32(),
        'effects': effects.toJson(),
        if (titleStyle != null) 'titleStyle': titleStyle!.toJson(),
      };

  factory TimelineClip.fromJson(Map<String, dynamic> json) => TimelineClip(
        id: json['id'] as String,
        assetId: json['assetId'] as String?,
        name: json['name'] as String? ?? 'Clip',
        type: MediaType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MediaType.video,
        ),
        trackIndex: json['trackIndex'] as int? ?? 0,
        timelineStartSec:
            (json['timelineStartSec'] as num?)?.toDouble() ?? 0.0,
        sourceInSec: (json['sourceInSec'] as num?)?.toDouble() ?? 0.0,
        durationSec: (json['durationSec'] as num?)?.toDouble() ?? 5.0,
        maxSourceDurationSec:
            (json['maxSourceDurationSec'] as num?)?.toDouble() ?? 3600.0,
        clipColor: Color(json['clipColor'] as int? ?? 0xFF7E57C2),
        effects: json['effects'] != null
            ? ClipEffects.fromJson(json['effects'] as Map<String, dynamic>)
            : ClipEffects(),
        titleStyle: json['titleStyle'] != null
            ? TitleClipStyle.fromJson(
                json['titleStyle'] as Map<String, dynamic>)
            : null,
      );
}

class TimelineTrack {
  final String id;
  String name;
  final bool isAudio;
  bool muted;
  bool solo;
  bool locked;
  bool visible;

  TimelineTrack({
    required this.id,
    required this.name,
    required this.isAudio,
    this.muted = false,
    this.solo = false,
    this.locked = false,
    this.visible = true,
  });

  TimelineTrack clone() => TimelineTrack(
        id: id,
        name: name,
        isAudio: isAudio,
        muted: muted,
        solo: solo,
        locked: locked,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isAudio': isAudio,
        'muted': muted,
        'solo': solo,
        'locked': locked,
        'visible': visible,
      };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Track',
        isAudio: json['isAudio'] as bool? ?? false,
        muted: json['muted'] as bool? ?? false,
        solo: json['solo'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
        visible: json['visible'] as bool? ?? true,
      );
}
