import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/director_types.dart';

class MediaEngine {
  static String get _cacheDir =>
      p.join(Platform.environment['HOME'] ?? '/tmp', '.cache', 'fyrdirector');

  static const Set<String> imageExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.gif',
  };
  static const Set<String> audioExts = {
    '.mp3',
    '.wav',
    '.flac',
    '.ogg',
    '.aac',
    '.m4a',
    '.opus',
  };

  static Future<MediaAsset> probeMedia(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
    final name = p.basename(filePath);

    if (imageExts.contains(ext)) {
      int w = 1920, h = 1080;
      try {
        final bytes = await File(filePath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        w = frame.image.width;
        h = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
      return MediaAsset(
        id: id,
        name: name,
        path: filePath,
        type: MediaType.image,
        durationSec: 5.0,
        width: w,
        height: h,
        fps: 30.0,
        hasAudio: false,
        thumbnailPaths: [filePath],
      );
    }

    double duration = 10.0;
    int width = 1920;
    int height = 1080;
    double fps = 30.0;
    bool hasVideo = false;
    bool hasAudio = false;

    try {
      final res = await Process.run('ffprobe', [
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        filePath,
      ]);
      if (res.exitCode == 0) {
        final data = jsonDecode(res.stdout as String) as Map<String, dynamic>;
        final fmt = data['format'] as Map<String, dynamic>? ?? {};
        duration = double.tryParse('${fmt['duration'] ?? ''}') ?? 10.0;
        final streams = (data['streams'] as List<dynamic>? ?? []);
        for (final raw in streams) {
          final s = raw as Map<String, dynamic>;
          final kind = s['codec_type'] as String?;
          if (kind == 'video' && !hasVideo) {
            hasVideo = true;
            width = s['width'] as int? ?? 1920;
            height = s['height'] as int? ?? 1080;
            final rfr = s['r_frame_rate'] as String? ?? '30/1';
            final parts = rfr.split('/');
            if (parts.length == 2) {
              final num = double.tryParse(parts[0]) ?? 30;
              final den = double.tryParse(parts[1]) ?? 1;
              if (den > 0) fps = (num / den).clamp(1.0, 120.0);
            }
          } else if (kind == 'audio') {
            hasAudio = true;
          }
        }
      }
    } catch (_) {}

    final type = (!hasVideo || audioExts.contains(ext))
        ? MediaType.audio
        : MediaType.video;

    return MediaAsset(
      id: id,
      name: name,
      path: filePath,
      type: type,
      durationSec: max(0.5, duration),
      width: width,
      height: height,
      fps: fps,
      hasAudio: hasAudio,
    );
  }

  static Future<List<String>> generateThumbnails(MediaAsset asset) async {
    if (asset.type != MediaType.video) return asset.thumbnailPaths;
    final dir = Directory(p.join(_cacheDir, 'thumbs', asset.id));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    const count = 6;
    final paths = <String>[];
    for (int i = 0; i < count; i++) {
      final t = (asset.durationSec * (i + 0.5) / count)
          .clamp(0.0, max(0.1, asset.durationSec - 0.1));
      final outPath = p.join(dir.path, 'thumb_$i.jpg');
      try {
        final res = await Process.run('ffmpeg', [
          '-y',
          '-ss',
          t.toStringAsFixed(2),
          '-i',
          asset.path,
          '-vf',
          'scale=140:-1',
          '-frames:v',
          '1',
          '-q:v',
          '5',
          outPath,
        ]);
        if (res.exitCode == 0 && File(outPath).existsSync()) {
          paths.add(outPath);
        }
      } catch (_) {}
    }
    return paths;
  }

  static Future<Float32List?> extractWaveform(MediaAsset asset) async {
    if (!asset.hasAudio && asset.type != MediaType.audio) return null;
    try {
      final proc = await Process.run(
        'ffmpeg',
        [
          '-v',
          'quiet',
          '-i',
          asset.path,
          '-ac',
          '1',
          '-ar',
          '1000',
          '-f',
          's16le',
          'pipe:1',
        ],
        stdoutEncoding: null,
      );
      if (proc.exitCode != 0) return null;
      final raw = proc.stdout as List<int>;
      if (raw.length < 4) return null;
      final bytes = Uint8List.fromList(raw);
      final bd = ByteData.sublistView(bytes);
      final sampleCount = bytes.length ~/ 2;
      const bins = 120;
      final peaks = Float32List(bins);
      final step = max(1, sampleCount ~/ bins);
      for (int b = 0; b < bins; b++) {
        final start = b * step;
        final end = min(sampleCount, start + step);
        int maxAmp = 0;
        for (int s = start; s < end; s++) {
          final v = bd.getInt16(s * 2, Endian.little).abs();
          if (v > maxAmp) maxAmp = v;
        }
        peaks[b] = (maxAmp / 32768.0).clamp(0.05, 1.0);
      }
      return peaks;
    } catch (_) {
      return null;
    }
  }

  /// Renders a [TitleClipStyle] into a transparent PNG at [width]x[height]
  /// so FFmpeg export matches the live Program Monitor identically.
  static Future<String> renderTitlePng(
    TitleClipStyle style,
    int width,
    int height,
    String outPath,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    final painter = TextPainter(
      text: TextSpan(
        text: style.text,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
          color: style.textColor,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(2, 2)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: width * 0.88);

    final dx = (width - painter.width) / 2.0;
    final dy = (height * style.posYRatio - painter.height / 2.0)
        .clamp(16.0, max(16.0, height - painter.height - 16.0))
        .toDouble();

    if (style.bgOpacity > 0.01) {
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            dx - 22, dy - 12, painter.width + 44, painter.height + 24),
        const Radius.circular(14),
      );
      canvas.drawRRect(
        bgRect,
        Paint()..color = style.bgColor.withValues(alpha: style.bgOpacity),
      );
    }

    painter.paint(canvas, Offset(dx, dy));

    final pic = recorder.endRecording();
    final img = await pic.toImage(width, height);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bd != null) {
      await File(outPath).writeAsBytes(bd.buffer.asUint8List());
    }
    return outPath;
  }

  /// Renders the full multi-track timeline to [outputPath] using FFmpeg.
  static Future<Process> startExport({
    required List<TimelineTrack> tracks,
    required List<TimelineClip> clips,
    required Map<String, MediaAsset> assetsById,
    required String outputPath,
    required ExportFormat format,
    required int width,
    required int height,
    required double fps,
    required int crf,
    required ValueChanged<double> onProgress,
    required VoidCallback onSuccess,
    required ValueChanged<String> onError,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('fyrdirector_exp_');

    // Compute total timeline duration
    double totalDur = 0.0;
    for (final c in clips) {
      if (c.timelineEndSec > totalDur) totalDur = c.timelineEndSec;
    }
    totalDur = max(0.5, totalDur);

    final anySoloVideo =
        tracks.any((t) => !t.isAudio && t.solo && t.visible);
    final anySoloAudio = tracks.any((t) => t.isAudio && t.solo);

    bool isVideoTrackActive(int idx) {
      if (idx < 0 || idx >= tracks.length) return false;
      final t = tracks[idx];
      if (!t.visible) return false;
      if (anySoloVideo && !t.solo) return false;
      return true;
    }

    bool isAudioTrackActive(int idx) {
      if (idx < 0 || idx >= tracks.length) return false;
      final t = tracks[idx];
      if (t.muted) return false;
      if (anySoloAudio && !t.solo) return false;
      return true;
    }

    // Sort visual clips bottom-to-top so higher tracks (lower index V2 above V1, wait:
    // let's check track ordering convention: track 0 = top-most or bottom-most?
    // In our timeline, track index 0 is top video track V2, index 1 is V1, etc., OR V1 is bottom and V2 is top.
    // Let's sort descending by trackIndex so lower-numbered visual tracks overlay higher-numbered ones!)
    final visualClips = clips
        .where((c) =>
            (c.type == MediaType.video ||
                c.type == MediaType.image ||
                c.type == MediaType.title) &&
            isVideoTrackActive(c.trackIndex))
        .toList()
      ..sort((a, b) => b.trackIndex.compareTo(a.trackIndex));

    final audioClips = clips.where((c) {
      if (c.type == MediaType.audio) return isAudioTrackActive(c.trackIndex);
      if (c.type == MediaType.video) {
        final asset = assetsById[c.assetId];
        if (asset != null &&
            asset.hasAudio &&
            isVideoTrackActive(c.trackIndex) &&
            !tracks[c.trackIndex].muted &&
            c.effects.volume > 0.01) {
          return true;
        }
      }
      return false;
    }).toList();

    final args = <String>['-y', '-progress', 'pipe:1'];
    final filters = <String>[];

    // Base black canvas
    filters.add(
        'color=c=black:s=${width}x$height:r=${fps.round()}:d=${totalDur.toStringAsFixed(3)}[base]');
    String currentVideo = '[base]';

    int inputIdx = 0;
    final clipInputIndex = <String, int>{};

    // Add inputs
    for (final c in visualClips) {
      if (c.type == MediaType.title) {
        final pngPath = p.join(tempDir.path, 'title_${c.id}.png');
        await renderTitlePng(
            c.titleStyle ?? TitleClipStyle(), width, height, pngPath);
        args.addAll([
          '-loop',
          '1',
          '-t',
          c.durationSec.toStringAsFixed(3),
          '-i',
          pngPath,
        ]);
        clipInputIndex[c.id] = inputIdx++;
      } else {
        final asset = assetsById[c.assetId];
        if (asset == null) continue;
        if (c.type == MediaType.image) {
          args.addAll([
            '-loop',
            '1',
            '-t',
            c.durationSec.toStringAsFixed(3),
            '-i',
            asset.path,
          ]);
        } else {
          args.addAll(['-i', asset.path]);
        }
        clipInputIndex[c.id] = inputIdx++;
      }
    }

    for (final c in audioClips) {
      if (!clipInputIndex.containsKey(c.id)) {
        final asset = assetsById[c.assetId];
        if (asset == null) continue;
        args.addAll(['-i', asset.path]);
        clipInputIndex[c.id] = inputIdx++;
      }
    }

    // Build visual filter chains
    int vCounter = 0;
    for (final c in visualClips) {
      final inId = clipInputIndex[c.id];
      if (inId == null) continue;
      final lbl = 'v$vCounter';
      final e = c.effects;
      final chain = <String>[];

      if (c.type == MediaType.video) {
        final srcEnd = c.sourceInSec + c.durationSec * e.speed;
        chain.add(
            'trim=start=${c.sourceInSec.toStringAsFixed(3)}:end=${srcEnd.toStringAsFixed(3)}');
        chain.add('setpts=(PTS-STARTPTS)/${e.speed.toStringAsFixed(3)}');
      } else {
        chain.add('setpts=PTS-STARTPTS');
      }

      final scaledW = max(2, ((width * e.scale).round() ~/ 2) * 2);
      final scaledH = max(2, ((height * e.scale).round() ~/ 2) * 2);
      chain.add(
          'scale=$scaledW:$scaledH:force_original_aspect_ratio=decrease');
      chain.add('format=rgba');

      if (e.brightness.abs() > 0.01 ||
          (e.contrast - 1.0).abs() > 0.01 ||
          (e.saturation - 1.0).abs() > 0.01) {
        chain.add(
            'eq=brightness=${e.brightness.toStringAsFixed(2)}:contrast=${e.contrast.toStringAsFixed(2)}:saturation=${e.saturation.toStringAsFixed(2)}');
      }
      if (e.blur > 0.3) {
        final b = e.blur.clamp(1, 20).toStringAsFixed(1);
        chain.add('boxblur=$b:1');
      }
      if (e.rotationDeg.abs() > 0.5) {
        final rad = (e.rotationDeg * pi / 180.0).toStringAsFixed(4);
        chain.add('rotate=$rad:c=none');
      }
      if (e.opacity < 0.99) {
        chain.add('colorchannelmixer=aa=${e.opacity.toStringAsFixed(2)}');
      }
      if (e.fadeInSec > 0.02 || e.transitionIn == TransitionKind.fade || e.transitionIn == TransitionKind.dissolve) {
        final fd = e.fadeInSec > 0.02 ? e.fadeInSec : e.transitionDurationSec;
        chain.add('fade=t=in:st=0:d=${fd.toStringAsFixed(2)}:alpha=1');
      }
      if (e.fadeOutSec > 0.02) {
        final st = max(0.0, c.durationSec - e.fadeOutSec);
        chain.add(
            'fade=t=out:st=${st.toStringAsFixed(2)}:d=${e.fadeOutSec.toStringAsFixed(2)}:alpha=1');
      }

      // Shift PTS to timeline position
      chain.add('setpts=PTS+${c.timelineStartSec.toStringAsFixed(3)}/TB');
      filters.add('[$inId:v]${chain.join(',')}[$lbl]');

      final ox = '(W-w)/2+${(e.offsetX * width).round()}';
      final oy = '(H-h)/2+${(e.offsetY * height).round()}';
      final nextOut = 'comp$vCounter';
      filters.add(
          '$currentVideo[$lbl]overlay=x=$ox:y=$oy:enable=\'between(t,${c.timelineStartSec.toStringAsFixed(3)},${c.timelineEndSec.toStringAsFixed(3)})\':eof_action=pass[$nextOut]');
      currentVideo = '[$nextOut]';
      vCounter++;
    }

    // Build audio mix filter chains
    final audioLabels = <String>[];
    int aCounter = 0;
    if (format != ExportFormat.gif && audioClips.isNotEmpty) {
      for (final c in audioClips) {
        final inId = clipInputIndex[c.id];
        if (inId == null) continue;
        final lbl = 'a$aCounter';
        final e = c.effects;
        final srcEnd = c.sourceInSec + c.durationSec * e.speed;
        final chain = <String>[
          'atrim=start=${c.sourceInSec.toStringAsFixed(3)}:end=${srcEnd.toStringAsFixed(3)}',
          'asetpts=PTS-STARTPTS',
        ];
        if ((e.speed - 1.0).abs() > 0.02) {
          chain.add('atempo=${e.speed.clamp(0.5, 2.0).toStringAsFixed(2)}');
        }
        if ((e.volume - 1.0).abs() > 0.02) {
          chain.add('volume=${e.volume.toStringAsFixed(2)}');
        }
        if (e.fadeInSec > 0.02) {
          chain.add('afade=t=in:st=0:d=${e.fadeInSec.toStringAsFixed(2)}');
        }
        if (e.fadeOutSec > 0.02) {
          final st = max(0.0, c.durationSec - e.fadeOutSec);
          chain.add(
              'afade=t=out:st=${st.toStringAsFixed(2)}:d=${e.fadeOutSec.toStringAsFixed(2)}');
        }
        final delayMs = max(0, (c.timelineStartSec * 1000).round());
        if (delayMs > 0) {
          chain.add('adelay=$delayMs|$delayMs');
        }
        filters.add('[$inId:a]${chain.join(',')}[$lbl]');
        audioLabels.add('[$lbl]');
        aCounter++;
      }
      if (audioLabels.length == 1) {
        filters.add('${audioLabels.first}anull[aout]');
      } else if (audioLabels.length > 1) {
        filters.add(
            '${audioLabels.join('')}amix=inputs=${audioLabels.length}:duration=longest:normalize=0[aout]');
      }
    }

    args.addAll(['-filter_complex', filters.join(';')]);
    args.addAll(['-map', currentVideo]);
    if (audioLabels.isNotEmpty && format != ExportFormat.gif) {
      args.addAll(['-map', '[aout]', '-c:a', format.acodec]);
    }

    if (format == ExportFormat.gif) {
      args.addAll(['-loop', '0', outputPath]);
    } else {
      args.addAll([
        '-c:v',
        format.vcodec,
        '-pix_fmt',
        'yuv420p',
        '-crf',
        '$crf',
        '-t',
        totalDur.toStringAsFixed(3),
        outputPath,
      ]);
    }

    final proc = await Process.start('ffmpeg', args);
    final stderrBuf = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBuf.write(chunk);
    });
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('out_time_us=')) {
        final us = int.tryParse(line.substring(12)) ?? 0;
        final sec = us / 1000000.0;
        onProgress((sec / totalDur).clamp(0.0, 1.0));
      }
    });

    proc.exitCode.then((code) async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      if (code == 0) {
        onProgress(1.0);
        onSuccess();
      } else {
        onError('FFmpeg exited with code $code:\n${stderrBuf.toString()}');
      }
    });

    return proc;
  }
}
