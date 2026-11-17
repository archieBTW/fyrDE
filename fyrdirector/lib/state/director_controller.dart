import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../engine/media_engine.dart';
import '../models/director_types.dart';

class _DirectorSnapshot {
  final List<TimelineTrack> tracks;
  final List<TimelineClip> clips;
  final String? selectedClipId;

  _DirectorSnapshot(this.tracks, this.clips, this.selectedClipId);
}

class DirectorController extends ChangeNotifier {
  final bool enableMediaKit;

  Player? videoPlayer;
  VideoController? videoController;
  Player? audioPlayer;

  String projectTitle = 'Untitled Project';
  String? projectFilePath;
  SequencePreset sequence = kSequencePresets.first;

  final List<MediaAsset> mediaBin = [];
  List<TimelineTrack> tracks = [
    TimelineTrack(id: 'v2', name: 'V2 Overlay', isAudio: false),
    TimelineTrack(id: 'v1', name: 'V1 Video', isAudio: false),
    TimelineTrack(id: 'a1', name: 'A1 Audio', isAudio: true),
    TimelineTrack(id: 'a2', name: 'A2 Music', isAudio: true),
  ];
  List<TimelineClip> clips = [];

  String? selectedClipId;
  DirectorTool activeTool = DirectorTool.select;
  bool snapEnabled = true;
  bool showSafeGuides = false;

  double playheadSec = 0.0;
  bool isPlaying = false;
  double timelineZoom = 60.0; // pixels per second
  double masterVolume = 0.9;
  bool masterMuted = false;

  String? _loadedVideoPath;
  String? _loadedAudioPath;
  Timer? _playTimer;
  DateTime? _lastTickTime;

  final List<_DirectorSnapshot> _history = [];
  int _historyIndex = -1;

  String? statusMessage;
  Timer? _statusTimer;

  DirectorController({this.enableMediaKit = true}) {
    if (enableMediaKit) {
      videoPlayer = Player();
      videoController = VideoController(videoPlayer!);
      audioPlayer = Player();
    }
    _pushHistory();
  }

  void refresh() => notifyListeners();

  void setStatus(String msg) {
    statusMessage = msg;
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 3), () {
      statusMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  TimelineClip? get selectedClip {
    if (selectedClipId == null) return null;
    return clips.where((c) => c.id == selectedClipId).firstOrNull;
  }

  MediaAsset? assetById(String? id) {
    if (id == null) return null;
    return mediaBin.where((a) => a.id == id).firstOrNull;
  }

  double get totalDurationSec {
    double maxEnd = 15.0;
    for (final c in clips) {
      if (c.timelineEndSec + 5.0 > maxEnd) maxEnd = c.timelineEndSec + 5.0;
    }
    return maxEnd;
  }

  double get contentEndSec {
    double maxEnd = 0.0;
    for (final c in clips) {
      if (c.timelineEndSec > maxEnd) maxEnd = c.timelineEndSec;
    }
    return maxEnd;
  }

  // ---------------------------------------------------------------------------
  // Active Clips at Playhead (for Program Monitor WYSIWYG Compositing)
  // ---------------------------------------------------------------------------

  bool _isTrackVisible(int idx) {
    if (idx < 0 || idx >= tracks.length) return false;
    final t = tracks[idx];
    if (!t.visible) return false;
    final anySolo = tracks.any((tr) => !tr.isAudio && tr.solo && tr.visible);
    if (anySolo && !t.solo) return false;
    return true;
  }

  bool _isAudioTrackActive(int idx) {
    if (idx < 0 || idx >= tracks.length) return false;
    final t = tracks[idx];
    if (t.muted) return false;
    final anySolo = tracks.any((tr) => tr.isAudio && tr.solo);
    if (anySolo && !t.solo) return false;
    return true;
  }

  List<TimelineClip> activeVisualClipsAt(double t) {
    final active = clips
        .where((c) =>
            (c.type == MediaType.video ||
                c.type == MediaType.image ||
                c.type == MediaType.title) &&
            _isTrackVisible(c.trackIndex) &&
            t >= c.timelineStartSec &&
            t < c.timelineEndSec)
        .toList()
      ..sort((a, b) => b.trackIndex.compareTo(a.trackIndex));
    return active;
  }

  TimelineClip? primaryVideoClipAt(double t) {
    final visuals = activeVisualClipsAt(t);
    return visuals.where((c) => c.type == MediaType.video).lastOrNull;
  }

  TimelineClip? activeAudioClipAt(double t) {
    return clips
        .where((c) =>
            c.type == MediaType.audio &&
            _isAudioTrackActive(c.trackIndex) &&
            t >= c.timelineStartSec &&
            t < c.timelineEndSec)
        .firstOrNull;
  }

  // ---------------------------------------------------------------------------
  // Playback & Sync
  // ---------------------------------------------------------------------------

  void togglePlay() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (isPlaying) return;
    isPlaying = true;
    _lastTickTime = DateTime.now();
    _syncPlayersToPlayhead(forceSeek: true, shouldPlay: true);
    _playTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _onPlayTick(),
    );
    notifyListeners();
  }

  void pause() {
    if (!isPlaying) return;
    isPlaying = false;
    _playTimer?.cancel();
    _playTimer = null;
    videoPlayer?.pause();
    audioPlayer?.pause();
    notifyListeners();
  }

  void seekTo(double sec) {
    playheadSec = sec.clamp(0.0, totalDurationSec);
    _syncPlayersToPlayhead(forceSeek: true, shouldPlay: isPlaying);
    notifyListeners();
  }

  void stepFrame(int deltaFrames) {
    pause();
    seekTo(playheadSec + deltaFrames / sequence.fps);
  }

  void _onPlayTick() {
    final now = DateTime.now();
    final dt = (_lastTickTime == null)
        ? 0.016
        : now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
    _lastTickTime = now;

    playheadSec += dt;
    if (contentEndSec > 0.1 && playheadSec >= contentEndSec) {
      playheadSec = contentEndSec;
      pause();
      return;
    }
    _syncPlayersToPlayhead(forceSeek: false, shouldPlay: true);
    notifyListeners();
  }

  Future<void> _syncPlayersToPlayhead({
    required bool forceSeek,
    required bool shouldPlay,
  }) async {
    if (!enableMediaKit) return;

    // Video player sync
    final vClip = primaryVideoClipAt(playheadSec);
    final vAsset = assetById(vClip?.assetId);
    if (vClip != null && vAsset != null && videoPlayer != null) {
      final targetSrcSec = vClip.sourceInSec +
          (playheadSec - vClip.timelineStartSec) * vClip.effects.speed;
      final trackMuted = tracks[vClip.trackIndex].muted;
      final vol =
          (masterMuted || trackMuted) ? 0.0 : (vClip.effects.volume * masterVolume * 100.0);
      await videoPlayer!.setVolume(vol.clamp(0.0, 100.0));
      await videoPlayer!.setRate(vClip.effects.speed.clamp(0.25, 4.0));

      if (_loadedVideoPath != vAsset.path) {
        _loadedVideoPath = vAsset.path;
        await videoPlayer!.open(Media(vAsset.path), play: shouldPlay);
        await videoPlayer!.seek(
          Duration(milliseconds: (targetSrcSec * 1000).round()),
        );
      } else {
        if (forceSeek) {
          await videoPlayer!.seek(
            Duration(milliseconds: (targetSrcSec * 1000).round()),
          );
        }
        if (shouldPlay && !videoPlayer!.state.playing) {
          await videoPlayer!.play();
        } else if (!shouldPlay && videoPlayer!.state.playing) {
          await videoPlayer!.pause();
        }
      }
    } else if (videoPlayer != null && videoPlayer!.state.playing) {
      await videoPlayer!.pause();
    }

    // Audio player sync
    final aClip = activeAudioClipAt(playheadSec);
    final aAsset = assetById(aClip?.assetId);
    if (aClip != null && aAsset != null && audioPlayer != null) {
      final targetSrcSec = aClip.sourceInSec +
          (playheadSec - aClip.timelineStartSec) * aClip.effects.speed;
      final vol = masterMuted ? 0.0 : (aClip.effects.volume * masterVolume * 100.0);
      await audioPlayer!.setVolume(vol.clamp(0.0, 100.0));
      await audioPlayer!.setRate(aClip.effects.speed.clamp(0.25, 4.0));

      if (_loadedAudioPath != aAsset.path) {
        _loadedAudioPath = aAsset.path;
        await audioPlayer!.open(Media(aAsset.path), play: shouldPlay);
        await audioPlayer!.seek(
          Duration(milliseconds: (targetSrcSec * 1000).round()),
        );
      } else {
        if (forceSeek) {
          await audioPlayer!.seek(
            Duration(milliseconds: (targetSrcSec * 1000).round()),
          );
        }
        if (shouldPlay && !audioPlayer!.state.playing) {
          await audioPlayer!.play();
        } else if (!shouldPlay && audioPlayer!.state.playing) {
          await audioPlayer!.pause();
        }
      }
    } else if (audioPlayer != null && audioPlayer!.state.playing) {
      await audioPlayer!.pause();
    }
  }

  // ---------------------------------------------------------------------------
  // Media Import & Clip Placement
  // ---------------------------------------------------------------------------

  Future<void> importMediaFiles(List<String> paths) async {
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      if (mediaBin.any((a) => a.path == path)) continue;
      final asset = await MediaEngine.probeMedia(path);
      mediaBin.add(asset);
      notifyListeners();

      // Generate thumbnails & waveform in background
      if (asset.type == MediaType.video) {
        MediaEngine.generateThumbnails(asset).then((thumbs) {
          asset.thumbnailPaths = thumbs;
          notifyListeners();
        });
      }
      if (asset.hasAudio || asset.type == MediaType.audio) {
        MediaEngine.extractWaveform(asset).then((peaks) {
          asset.waveformPeaks = peaks;
          notifyListeners();
        });
      }
    }
    setStatus('Imported ${paths.length} media file(s)');
  }

  void addAssetToTimeline(
    MediaAsset asset, {
    int? trackIndex,
    double? atSec,
  }) {
    final targetTrack = trackIndex ?? _defaultTrackForType(asset.type);
    final start = atSec ?? _nextFreeSlotOnTrack(targetTrack, at: playheadSec);
    final clip = TimelineClip(
      id: _newId(),
      assetId: asset.id,
      name: asset.name,
      type: asset.type,
      trackIndex: targetTrack,
      timelineStartSec: start,
      sourceInSec: 0.0,
      durationSec: asset.durationSec,
      maxSourceDurationSec:
          asset.type == MediaType.image ? 3600.0 : asset.durationSec,
      clipColor: _colorForType(asset.type),
    );
    clips.add(clip);
    selectedClipId = clip.id;
    _pushHistory();
    _syncPlayersToPlayhead(forceSeek: true, shouldPlay: isPlaying);
    notifyListeners();
  }

  void addTitleClip({
    required String name,
    required TitleClipStyle style,
    double durationSec = 4.0,
    double? atSec,
  }) {
    // Place on top video track (index 0 = V2 Overlay)
    final clip = TimelineClip(
      id: _newId(),
      name: name,
      type: MediaType.title,
      trackIndex: 0,
      timelineStartSec: atSec ?? playheadSec,
      durationSec: durationSec,
      clipColor: const Color(0xFFE040FB),
      titleStyle: style,
    );
    clips.add(clip);
    selectedClipId = clip.id;
    _pushHistory();
    notifyListeners();
  }

  int _defaultTrackForType(MediaType t) {
    if (t == MediaType.audio) {
      return tracks.indexWhere((tr) => tr.isAudio).clamp(0, tracks.length - 1);
    }
    if (t == MediaType.title) return 0;
    final v1 = tracks.indexWhere((tr) => !tr.isAudio && tr.id == 'v1');
    if (v1 != -1) return v1;
    return tracks.indexWhere((tr) => !tr.isAudio).clamp(0, tracks.length - 1);
  }

  double _nextFreeSlotOnTrack(int trackIdx, {double at = 0.0}) {
    final onTrack = clips.where((c) => c.trackIndex == trackIdx).toList()
      ..sort((a, b) => a.timelineStartSec.compareTo(b.timelineStartSec));
    double candidate = at;
    for (final c in onTrack) {
      if (candidate < c.timelineEndSec && candidate + 0.05 > c.timelineStartSec) {
        candidate = c.timelineEndSec;
      }
    }
    return candidate;
  }

  Color _colorForType(MediaType t) {
    switch (t) {
      case MediaType.video:
        return const Color(0xFF5C6BC0);
      case MediaType.audio:
        return const Color(0xFF26A69A);
      case MediaType.image:
        return const Color(0xFFFFA726);
      case MediaType.title:
        return const Color(0xFFE040FB);
      case MediaType.color:
        return const Color(0xFFEC407A);
    }
  }

  // ---------------------------------------------------------------------------
  // Timeline Editing (Move, Trim, Split / Razor, Delete, Duplicate)
  // ---------------------------------------------------------------------------

  double snapTime(double rawSec, {String? ignoreClipId}) {
    if (!snapEnabled) return max(0.0, rawSec);
    final threshold = 10.0 / timelineZoom;
    double best = max(0.0, rawSec);
    double bestDist = threshold;

    void check(double target) {
      final d = (rawSec - target).abs();
      if (d < bestDist) {
        bestDist = d;
        best = target;
      }
    }

    check(0.0);
    check(playheadSec);
    for (final c in clips) {
      if (c.id == ignoreClipId) continue;
      check(c.timelineStartSec);
      check(c.timelineEndSec);
    }
    return max(0.0, best);
  }

  void selectClip(String? id) {
    selectedClipId = id;
    notifyListeners();
  }

  void moveClip(String id, double newStartSec, int newTrackIdx,
      {bool commit = false}) {
    final clip = clips.where((c) => c.id == id).firstOrNull;
    if (clip == null) return;
    final targetTrack = newTrackIdx.clamp(0, tracks.length - 1);
    if (tracks[targetTrack].locked) return;
    // Keep audio clips on audio tracks and visual clips on video tracks
    if ((clip.type == MediaType.audio) != tracks[targetTrack].isAudio) {
      // keep existing track if incompatible
    } else {
      clip.trackIndex = targetTrack;
    }
    clip.timelineStartSec = snapTime(newStartSec, ignoreClipId: id);
    if (commit) {
      _pushHistory();
      _syncPlayersToPlayhead(forceSeek: true, shouldPlay: isPlaying);
    }
    notifyListeners();
  }

  void trimClipLeft(String id, double deltaSec, {bool commit = false}) {
    final clip = clips.where((c) => c.id == id).firstOrNull;
    if (clip == null || tracks[clip.trackIndex].locked) return;
    final clampedDelta = deltaSec.clamp(
      -clip.sourceInSec / clip.effects.speed,
      clip.durationSec - 0.2,
    );
    clip.timelineStartSec = max(0.0, clip.timelineStartSec + clampedDelta);
    clip.sourceInSec =
        max(0.0, clip.sourceInSec + clampedDelta * clip.effects.speed);
    clip.durationSec = max(0.2, clip.durationSec - clampedDelta);
    if (commit) _pushHistory();
    notifyListeners();
  }

  void trimClipRight(String id, double deltaSec, {bool commit = false}) {
    final clip = clips.where((c) => c.id == id).firstOrNull;
    if (clip == null || tracks[clip.trackIndex].locked) return;
    final maxDur =
        (clip.maxSourceDurationSec - clip.sourceInSec) / clip.effects.speed;
    clip.durationSec = (clip.durationSec + deltaSec).clamp(0.2, max(0.2, maxDur));
    if (commit) _pushHistory();
    notifyListeners();
  }

  void splitClipAt(String id, double atSec) {
    final idx = clips.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final clip = clips[idx];
    if (tracks[clip.trackIndex].locked) return;
    if (atSec <= clip.timelineStartSec + 0.1 ||
        atSec >= clip.timelineEndSec - 0.1) {
      return;
    }

    final leftDur = atSec - clip.timelineStartSec;
    final rightDur = clip.durationSec - leftDur;

    final rightClip = clip.clone();
    clips[idx].durationSec = leftDur;

    final newRight = TimelineClip(
      id: _newId(),
      assetId: rightClip.assetId,
      name: rightClip.name,
      type: rightClip.type,
      trackIndex: rightClip.trackIndex,
      timelineStartSec: atSec,
      sourceInSec: rightClip.sourceInSec + leftDur * rightClip.effects.speed,
      durationSec: rightDur,
      maxSourceDurationSec: rightClip.maxSourceDurationSec,
      clipColor: rightClip.clipColor,
      effects: rightClip.effects.clone(),
      titleStyle: rightClip.titleStyle?.clone(),
    );

    clips.insert(idx + 1, newRight);
    selectedClipId = newRight.id;
    _pushHistory();
    setStatus('Split ${clip.name}');
    notifyListeners();
  }

  void splitAtPlayhead() {
    if (selectedClip != null) {
      splitClipAt(selectedClip!.id, playheadSec);
      return;
    }
    // Otherwise split all unlocked clips under playhead
    final under = clips
        .where((c) =>
            playheadSec > c.timelineStartSec + 0.1 &&
            playheadSec < c.timelineEndSec - 0.1)
        .map((c) => c.id)
        .toList();
    for (final id in under) {
      splitClipAt(id, playheadSec);
    }
  }

  void deleteSelectedClip() {
    if (selectedClipId == null) return;
    final clip = selectedClip;
    if (clip != null && tracks[clip.trackIndex].locked) return;
    clips.removeWhere((c) => c.id == selectedClipId);
    selectedClipId = null;
    _pushHistory();
    notifyListeners();
  }

  void duplicateSelectedClip() {
    final c = selectedClip;
    if (c == null) return;
    final dup = TimelineClip(
      id: _newId(),
      assetId: c.assetId,
      name: '${c.name} Copy',
      type: c.type,
      trackIndex: c.trackIndex,
      timelineStartSec: c.timelineEndSec,
      sourceInSec: c.sourceInSec,
      durationSec: c.durationSec,
      maxSourceDurationSec: c.maxSourceDurationSec,
      clipColor: c.clipColor,
      effects: c.effects.clone(),
      titleStyle: c.titleStyle?.clone(),
    );
    clips.add(dup);
    selectedClipId = dup.id;
    _pushHistory();
    notifyListeners();
  }

  void addTrack({required bool isAudio}) {
    final count = tracks.where((t) => t.isAudio == isAudio).length + 1;
    final track = TimelineTrack(
      id: _newId(),
      name: isAudio ? 'A$count Audio' : 'V$count Video',
      isAudio: isAudio,
    );
    if (isAudio) {
      tracks.add(track);
    } else {
      tracks.insert(0, track);
      for (final c in clips) {
        c.trackIndex++;
      }
    }
    _pushHistory();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo
  // ---------------------------------------------------------------------------

  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;

  void commitEffectChange() {
    _pushHistory();
    notifyListeners();
  }

  void _pushHistory() {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(
      _DirectorSnapshot(
        tracks.map((t) => t.clone()).toList(),
        clips.map((c) => c.clone()).toList(),
        selectedClipId,
      ),
    );
    if (_history.length > 40) {
      _history.removeAt(0);
    }
    _historyIndex = _history.length - 1;
  }

  void undo() {
    if (!canUndo) return;
    _historyIndex--;
    _restoreSnapshot(_history[_historyIndex]);
  }

  void redo() {
    if (!canRedo) return;
    _historyIndex++;
    _restoreSnapshot(_history[_historyIndex]);
  }

  void _restoreSnapshot(_DirectorSnapshot snap) {
    tracks = snap.tracks.map((t) => t.clone()).toList();
    clips = snap.clips.map((c) => c.clone()).toList();
    selectedClipId = snap.selectedClipId;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Project Save / Load (.fyrd)
  // ---------------------------------------------------------------------------

  Future<void> saveProject(String path) async {
    final outPath = path.toLowerCase().endsWith('.fyrd') ? path : '$path.fyrd';
    final payload = jsonEncode({
      'version': 1,
      'title': p.basenameWithoutExtension(outPath),
      'sequence': {
        'name': sequence.name,
        'width': sequence.width,
        'height': sequence.height,
        'fps': sequence.fps,
      },
      'mediaBin': mediaBin.map((a) => a.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'clips': clips.map((c) => c.toJson()).toList(),
    });
    await File(outPath).writeAsString(payload);
    projectFilePath = outPath;
    projectTitle = p.basenameWithoutExtension(outPath);
    setStatus('Saved ${p.basename(outPath)}');
    notifyListeners();
  }

  Future<void> openProject(String path) async {
    pause();
    final data =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    projectFilePath = path;
    projectTitle = data['title'] as String? ?? p.basenameWithoutExtension(path);

    final seq = data['sequence'] as Map<String, dynamic>?;
    if (seq != null) {
      sequence = SequencePreset(
        seq['name'] as String? ?? 'Custom',
        seq['width'] as int? ?? 1920,
        seq['height'] as int? ?? 1080,
        (seq['fps'] as num?)?.toDouble() ?? 30.0,
      );
    }

    mediaBin.clear();
    for (final raw in (data['mediaBin'] as List<dynamic>? ?? [])) {
      mediaBin.add(MediaAsset.fromJson(raw as Map<String, dynamic>));
    }
    tracks = (data['tracks'] as List<dynamic>? ?? [])
        .map((e) => TimelineTrack.fromJson(e as Map<String, dynamic>))
        .toList();
    clips = (data['clips'] as List<dynamic>? ?? [])
        .map((e) => TimelineClip.fromJson(e as Map<String, dynamic>))
        .toList();

    playheadSec = 0.0;
    selectedClipId = null;
    _history.clear();
    _historyIndex = -1;
    _pushHistory();
    setStatus('Opened ${p.basename(path)}');
    notifyListeners();
  }

  void newProject() {
    pause();
    projectTitle = 'Untitled Project';
    projectFilePath = null;
    mediaBin.clear();
    clips.clear();
    tracks = [
      TimelineTrack(id: 'v2', name: 'V2 Overlay', isAudio: false),
      TimelineTrack(id: 'v1', name: 'V1 Video', isAudio: false),
      TimelineTrack(id: 'a1', name: 'A1 Audio', isAudio: true),
      TimelineTrack(id: 'a2', name: 'A2 Music', isAudio: true),
    ];
    selectedClipId = null;
    playheadSec = 0.0;
    _history.clear();
    _historyIndex = -1;
    _pushHistory();
    notifyListeners();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  @override
  void dispose() {
    _playTimer?.cancel();
    _statusTimer?.cancel();
    videoPlayer?.dispose();
    audioPlayer?.dispose();
    super.dispose();
  }
}
