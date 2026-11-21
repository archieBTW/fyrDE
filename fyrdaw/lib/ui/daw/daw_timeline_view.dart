part of '../../main.dart';

extension _DawTimelineView on _DawMainScreenState {
  Widget _buildClip(String trackId, DawClip clip) {
    final isSelected =
        selectedClip == clip || multiSelectedClips.contains(clip);
    final bool isMovingOffTrack = _activeDragClips.contains(clip) &&
        _dragTargetTrackId != null &&
        _dragTargetTrackId != trackId;
    return Positioned(
      key: ValueKey('clip_${clip.id}'),
      left: clip.start * _zoomX,
      top: 10,
      bottom: 10,
      width: clip.length * _zoomX,
      child: Opacity(
        opacity: isMovingOffTrack ? 0.35 : 1.0,
        child: GestureDetector(
        supportedDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        behavior: HitTestBehavior.opaque,
        onTap: () => _setState(() {
          selectedClip = clip;
          multiSelectedClips.clear();
          int tIdx = tracks.indexWhere((t) => t.id == trackId);
          if (tIdx != -1) {
            selectedTrackIndex = tIdx;
            _trackSelectionAnchorIndex = tIdx;
            multiSelectedTrackIds = {trackId};
          }
        }),
        onDoubleTapDown: (_) {},
        onDoubleTap: () => _setState(() {
          selectedClip = clip;
          multiSelectedClips.clear();
          int tIdx = tracks.indexWhere((t) => t.id == trackId);
          if (tIdx != -1) {
            selectedTrackIndex = tIdx;
          }
          isBottomPanelExpanded = true;
          if (_bottomPanelHeight < 360) {
            _bottomPanelHeight = 360;
          }
          if (clip is MidiClip) {
            selectedBottomTab = 0;
          } else if (clip is AudioClip) {
            selectedBottomTab = 4;
          }
        }),
        onSecondaryTapUp: (details) =>
            _showClipMenu(details.globalPosition, trackId, clip),
        onPanStart: (d) {
          _saveState();
          final sourceTargets = multiSelectedClips.contains(clip)
              ? [...multiSelectedClips]
              : [clip];
          _dragSourceTrackId = trackId;
          _dragTargetTrackId = trackId;
          if (HardwareKeyboard.instance.isAltPressed) {
            final clones = <DawClip>[];
            DawClip? clonedPrimary;
            for (final orig in sourceTargets) {
              final ownerId = _ownerTrackIdForClip(orig);
              final clone = _cloneClipForDragCopy(ownerId ?? trackId, orig);
              clones.add(clone);
              if (identical(orig, clip)) clonedPrimary = clone;
            }
            _setState(() {
              _activeDragClips = clones;
              if (multiSelectedClips.contains(clip)) {
                multiSelectedClips
                  ..clear()
                  ..addAll(clones);
                selectedClip = clonedPrimary ?? clones.first;
              } else {
                multiSelectedClips.clear();
                selectedClip = clonedPrimary ?? clones.first;
              }
            });
          } else {
            _activeDragClips = sourceTargets;
          }
        },
        onPanUpdate: (d) => _setState(() {
          final targets = _activeDragClips.isNotEmpty
              ? _activeDragClips
              : (multiSelectedClips.contains(clip)
                    ? multiSelectedClips
                    : [clip]);
          for (var c in targets) {
            c.start += (d.delta.dx / _zoomX);
            if (c.start < 0) c.start = 0;
          }
          final hovered = _trackAtGlobalY(d.globalPosition.dy);
          if (hovered != null && _canMoveClipToTrack(clip, hovered)) {
            _dragTargetTrackId = hovered.id;
          }
        }),
        onPanEnd: (d) => _setState(() {
          final targets = _activeDragClips.isNotEmpty
              ? _activeDragClips
              : (multiSelectedClips.contains(clip)
                    ? multiSelectedClips
                    : [clip]);
          if (snapToGrid) {
            for (var c in targets) {
              c.start = (c.start / snapResolution).round() * snapResolution;
            }
          }
          if (_dragTargetTrackId != null && _dragTargetTrackId != trackId) {
            final destTrack =
                tracks.where((t) => t.id == _dragTargetTrackId).firstOrNull;
            if (destTrack != null) {
              _moveClipsToTrack(targets, destTrack);
            }
          }
          _activeDragClips = [];
          _dragSourceTrackId = null;
          _dragTargetTrackId = null;
        }),
        onPanCancel: () => _setState(() {
          _activeDragClips = [];
          _dragSourceTrackId = null;
          _dragTargetTrackId = null;
        }),
        child: Container(
          decoration: BoxDecoration(
            color: clip.color.withValues(alpha: isSelected ? 0.8 : 0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? textMain : textMuted,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (clip is AudioClip)
                ClipRect(
                  child: Stack(
                    children: [
                      Positioned(
                        left: -clip.startOffset * _zoomX,
                        width: clip.originalLength * _zoomX,
                        top: 0,
                        bottom: 0,
                        child: CustomPaint(
                          painter: ClipWaveformPainter(
                            waveformData: (clip.waveformData != null &&
                                    clip.waveformData!.isNotEmpty)
                                ? clip.waveformData!
                                : List<double>.generate(
                                    64,
                                    (i) =>
                                        0.15 +
                                        0.55 *
                                            Random(clip.filePath.hashCode + i)
                                                .nextDouble(),
                                  ),
                            color: (clip.waveformData != null &&
                                    clip.waveformData!.isNotEmpty)
                                ? textMain
                                : textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (clip is MidiClip)
                Positioned.fill(
                  child: ClipRect(
                    child: CustomPaint(
                      painter: MidiClipThumbnailPainter(
                        notes: clip.notes,
                        clipLength: clip.length,
                        originalLength: clip.originalLength,
                        startOffset: clip.startOffset,
                        color: textMain,
                      ),
                    ),
                  ),
                ),
              if (clip is AudioClip)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LoopNotchesPainter(
                        clipLength: clip.length,
                        originalLength: clip.originalLength / clip.stretchFactor,
                      ),
                    ),
                  ),
                ),
              if (clip is AudioClip)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: ClipFadePainter(
                        fadeInRatio: clip.length > 0
                            ? (clip.fadeIn / clip.length).clamp(0.0, 0.9)
                            : 0.0,
                        fadeOutRatio: clip.length > 0
                            ? (clip.fadeOut / clip.length).clamp(0.0, 0.9)
                            : 0.0,
                        accentColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (clip.length * _zoomX > 36)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 2,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        if (clip is MidiClip && clip.patternGroupId != null)
                          Container(
                            margin: EdgeInsets.only(right: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '∞',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            clip.name.isNotEmpty
                                ? clip.name
                                : (clip is AudioClip
                                      ? p.basenameWithoutExtension(clip.filePath)
                                      : 'MIDI'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 2),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (clip is AudioClip && clip.takes.length > 1)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'T${clip.activeTakeIndex + 1}/${clip.takes.length}',
                              style: TextStyle(
                                color: Colors.lightGreenAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (clip is AudioClip && clip.isLooped)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'LOOP',
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (clip is AudioClip &&
                            (clip.stretchFactor - 1.0).abs() > 0.02)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${clip.stretchFactor.toStringAsFixed(2)}x',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        if (clip is AudioClip && clip.pitchSemitones != 0)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${clip.pitchSemitones > 0 ? "+" : ""}${clip.pitchSemitones.round()}st',
                              style: TextStyle(color: Colors.cyanAccent, fontSize: 8),
                            ),
                          ),
                        if (clip is AudioClip && (clip.gain - 1.0).abs() > 0.05)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${(clip.gain * 100).round()}%',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (clip is AudioClip && clip.length * _zoomX > 28) ...[
                Positioned(
                  left: ((clip.fadeIn * _zoomX) - 6).clamp(
                    6.0,
                    max(6.0, clip.length * _zoomX - 18),
                  ),
                  top: 0,
                  child: Tooltip(
                    message: 'Drag Fade-In',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => _saveState(),
                        onHorizontalDragUpdate: (d) => _setState(() {
                          clip.fadeIn = (clip.fadeIn + d.delta.dx / _zoomX)
                              .clamp(0.0, max(0.0, clip.length - clip.fadeOut));
                        }),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: ((clip.fadeOut * _zoomX) - 6).clamp(
                    6.0,
                    max(6.0, clip.length * _zoomX - 18),
                  ),
                  top: 0,
                  child: Tooltip(
                    message: 'Drag Fade-Out',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => _saveState(),
                        onHorizontalDragUpdate: (d) => _setState(() {
                          clip.fadeOut = (clip.fadeOut - d.delta.dx / _zoomX)
                              .clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                        }),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    supportedDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                    onHorizontalDragStart: (d) => _saveState(),
                    onHorizontalDragUpdate: (d) => _setState(() {
                      double dx = d.delta.dx / _zoomX;
                      double newLength = clip.length - dx;
                      if (newLength < 10) {
                        dx = clip.length - 10;
                        newLength = 10;
                      }
                      if (clip.startOffset + dx < 0) {
                        dx = -clip.startOffset;
                        newLength = clip.length - dx;
                      }
                      clip.start += dx;
                      clip.length = newLength;
                      clip.startOffset += dx;
                    }),
                    onHorizontalDragEnd: (d) => _setState(() {
                      if (snapToGrid) {
                        double oldStart = clip.start;
                        clip.start =
                            (clip.start / snapResolution).round() *
                            snapResolution;
                        double diff = clip.start - oldStart;
                        clip.length -= diff;
                        clip.startOffset += diff;
                        if (clip.startOffset < 0) {
                          clip.length += clip.startOffset;
                          clip.start -= clip.startOffset;
                          clip.startOffset = 0;
                        }
                      }
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: textFaint,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(4),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    supportedDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                    onHorizontalDragStart: (d) => _saveState(),
                    onHorizontalDragUpdate: (d) => _setState(() {
                      clip.length = max(10.0, clip.length + d.delta.dx / _zoomX);
                      if (clip is MidiClip) {
                        clip.originalLength = max(
                          clip.originalLength,
                          clip.startOffset + clip.length,
                        );
                      } else if (clip is AudioClip && !clip.isLooped) {
                        clip.length = min(
                          clip.length,
                          clip.originalLength - clip.startOffset,
                        );
                      }
                    }),
                    onHorizontalDragEnd: (d) => _setState(() {
                      if (snapToGrid) {
                        clip.length = max(
                          10.0,
                          (clip.length / snapResolution).round() *
                              snapResolution,
                        );
                        if (clip is MidiClip) {
                          clip.originalLength = max(
                            clip.originalLength,
                            clip.startOffset + clip.length,
                          );
                        } else if (clip is AudioClip && !clip.isLooped) {
                          clip.length = min(
                            clip.length,
                            clip.originalLength - clip.startOffset,
                          );
                        }
                      }
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: textFaint,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _showAddMarkerDialog(double pos) async {
    final ctrl = TextEditingController(text: 'Section');
    int pickedColor = 0xFF00E5FF;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: panelDark,
          title: Text('Add Arrangement Marker', style: TextStyle(color: textMain)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: textMain),
                decoration: InputDecoration(
                  hintText: 'Intro, Verse, Chorus, Drop...',
                  filled: true,
                  fillColor: bgDark,
                ),
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: ['Intro', 'Verse', 'Chorus', 'Bridge', 'Drop', 'Outro']
                    .map(
                      (preset) => ActionChip(
                        label: Text(preset, style: TextStyle(fontSize: 11)),
                        onPressed: () => ctrl.text = preset,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final label = ctrl.text.trim().isEmpty ? 'Marker' : ctrl.text.trim();
                _saveState();
                _setState(() {
                  songMarkers.add(
                    SongMarker(
                      id: UniqueKey().toString(),
                      label: label,
                      position: pos,
                      colorValue: pickedColor,
                    ),
                  );
                  songMarkers.sort((a, b) => a.position.compareTo(b.position));
                });
                Navigator.pop(ctx);
              },
              child: Text('Add', style: TextStyle(color: lavenderAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineMinimap() {
    final double totalTimelineUnits = _timelineTotalUnits;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(bottom: BorderSide(color: borderMain)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mapW = max(1.0, constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final targetPos =
                  (d.localPosition.dx / mapW) * totalTimelineUnits;
              _seekPlayhead(targetPos);
              if (_horizontalScrollController.hasClients) {
                final viewW = mapW;
                _horizontalScrollController.jumpTo(
                  (playheadPosition * _zoomX - viewW * 0.35).clamp(
                    0.0,
                    _horizontalScrollController.position.maxScrollExtent,
                  ),
                );
              }
            },
            onHorizontalDragUpdate: (d) {
              final targetPos =
                  (d.localPosition.dx / mapW) * totalTimelineUnits;
              _seekPlayhead(targetPos, retriggerAudio: false);
            },
            onHorizontalDragEnd: (_) => _seekPlayhead(playheadPosition),
            child: Stack(
              children: [
                for (int ti = 0; ti < tracks.length; ti++)
                  for (final c in trackClips[tracks[ti].id] ?? const <DawClip>[])
                    Positioned(
                      left: (c.start / totalTimelineUnits) * mapW,
                      width: max(2.0, (c.length / totalTimelineUnits) * mapW),
                      top: tracks.isEmpty
                          ? 2
                          : 2.0 + (ti / max(1, tracks.length)) * 18.0,
                      height: max(2.0, 16.0 / max(1, tracks.length)),
                      child: Container(
                        color: c.color.withValues(alpha: 0.75),
                      ),
                    ),
                Positioned(
                  left: (playheadPosition / totalTimelineUnits) * mapW,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Container(color: Colors.redAccent),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeline() {
    final double timelineUnits = _timelineTotalUnits;
    return Expanded(
      child: Column(
        children: [
          _buildTimelineMinimap(),
          Expanded(
            child: Container(
              color: bgDark,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: max(MediaQuery.of(context).size.width, timelineUnits * _zoomX),
                  child: Column(
                    children: [
                      Container(
                        height: 40,
                        color: panelDark,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTapDown: (d) => _seekPlayhead(
                                d.localPosition.dx / _zoomX,
                                snap: true,
                              ),
                              onDoubleTapDown: (d) {
                                double pos = (d.localPosition.dx / _zoomX)
                                    .clamp(0.0, timelineUnits);
                                if (snapToGrid) {
                                  pos = (pos / snapResolution).round() *
                                      snapResolution;
                                }
                                _showAddMarkerDialog(pos);
                              },
                              onSecondaryTapUp: (d) {
                                double pos = (d.localPosition.dx / _zoomX)
                                    .clamp(0.0, timelineUnits);
                                if (snapToGrid) {
                                  pos = (pos / snapResolution).round() *
                                      snapResolution;
                                }
                                final RenderBox overlay = Overlay.of(context)
                                    .context
                                    .findRenderObject() as RenderBox;
                                showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromRect(
                                    d.globalPosition & Size(40, 40),
                                    Offset.zero & overlay.size,
                                  ),
                                  items: [
                                    PopupMenuItem(
                                      value: 'add_marker',
                                      child: Text('Add Marker Here'),
                                    ),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuDivider(),
                                    ...songMarkers.map(
                                      (m) => PopupMenuItem(
                                        value: 'jump_${m.id}',
                                        child: Text('Jump to: ${m.label}'),
                                      ),
                                    ),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuDivider(),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuItem(
                                        value: 'clear_markers',
                                        child: Text(
                                          'Clear All Markers',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ).then((val) {
                                  if (val == 'add_marker') {
                                    _showAddMarkerDialog(pos);
                                  } else if (val == 'clear_markers') {
                                    _saveState();
                                    _setState(() => songMarkers.clear());
                                  } else if (val != null &&
                                      val.startsWith('jump_')) {
                                    final id = val.substring(5);
                                    final m = songMarkers
                                        .where((x) => x.id == id)
                                        .firstOrNull;
                                    if (m != null) {
                                      _seekPlayhead(m.position);
                                    }
                                  }
                                });
                              },
                              onPanUpdate: (d) => _seekPlayhead(
                                playheadPosition + (d.delta.dx / _zoomX),
                                retriggerAudio: false,
                              ),
                              onPanEnd: (d) => _seekPlayhead(
                                playheadPosition,
                                snap: true,
                              ),
                              child: CustomPaint(
                                painter: RulerPainter(
                                  zoomX: _zoomX,
                                  bpm: bpm,
                                  timeSigTop: timeSigTop,
                                  markers: songMarkers,
                                  tempoMarkers: tempoMarkers,
                                ),
                                size: Size(double.infinity, 40),
                              ),
                            ),
                      Positioned.fill(
                        child: TimelineLoopBar(
                          loopStart: loopStart,
                          loopEnd: loopEnd,
                          isLooping: isLooping,
                          zoomX: _zoomX,
                          beatWidth: beatWidth,
                          snapToGrid: snapToGrid,
                          snapResolution: snapResolution,
                          accentColor: lavenderAccent,
                          handleColor: textMain,
                          maxTimelineUnits: timelineUnits,
                          onDragStart: _saveState,
                          onToggleLoop: () =>
                              _setState(() => isLooping = !isLooping),
                          onLoopRangeChanged: (newStart, newEnd) =>
                              _setState(() {
                                loopStart = newStart;
                                loopEnd = newEnd;
                              }),
                        ),
                      ),
                    ],
                  ),
                ),
                TempoSignatureLane(
                  baseBpm: bpm.toDouble(),
                  baseNum: timeSigTop,
                  baseDen: timeSigBottom,
                  markers: tempoMarkers,
                  zoomX: _zoomX,
                  snapResolution: snapResolution,
                  snapToGrid: snapToGrid,
                  onAddOrUpdateMarker: (m) {
                    _saveState();
                    _setState(() {
                      tempoMarkers.removeWhere((e) => e.id == m.id);
                      tempoMarkers.add(m);
                      tempoMarkers.sort(
                        (a, b) => a.position.compareTo(b.position),
                      );
                    });
                  },
                  onDeleteMarker: (id) {
                    _saveState();
                    _setState(() {
                      tempoMarkers.removeWhere((e) => e.id == id);
                    });
                  },
                ),
                Expanded(
                  key: _timelineLaneListKey,
                  child: Stack(
                    children: [
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        controller: _timelineScrollController,
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          if (!_isTrackVisibleInArrange(track)) {
                            return const SizedBox.shrink();
                          }
                          return Builder(
                            builder: (laneCtx) => DragTarget<SampleBrowserItem>(
                              onAcceptWithDetails: (details) {
                                final box = laneCtx.findRenderObject() as RenderBox?;
                                final localX = box != null
                                    ? box.globalToLocal(details.offset).dx
                                    : playheadPosition * _zoomX;
                                _addBrowserItemToTrack(
                                  details.data,
                                  targetTrack: track,
                                  startPos: (localX / _zoomX).clamp(
                                    0.0,
                                    timelineUnits,
                                  ),
                                );
                              },
                              builder: (ctx, cand, rej) => Listener(
                            onPointerDown: (e) =>
                                _lastTimelinePointerDownGlobal = e.position,
                            child: GestureDetector(
                            supportedDevices: const {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.touch,
                              PointerDeviceKind.stylus,
                            },
                            onTapDown: (d) => _setState(() {
                              _handleTrackSelectionClick(
                                index,
                                clearClipsOnSingle: true,
                              );
                            }),
                            onSecondaryTapUp: (d) {
                              _seekPlayhead(d.localPosition.dx / _zoomX);
                              _showTimelineMenu(d.globalPosition);
                            },
                            onPanStart: (d) =>
                                _startTimelineMarquee(d.globalPosition),
                            onPanUpdate: (d) =>
                                _updateTimelineMarquee(d.globalPosition),
                            onPanEnd: (_) => _endTimelineMarquee(),
                            onPanCancel: _endTimelineMarquee,
                            onDoubleTapDown: (d) {
                              final double clickX = d.localPosition.dx / _zoomX;
                              final bool hitExisting =
                                  (trackClips[track.id] ?? []).any(
                                (c) =>
                                    clickX >= c.start &&
                                    clickX <= c.start + c.length,
                              );
                              if (hitExisting) return;
                              if (track.type == TrackType.midi ||
                                  track.type == TrackType.sampler) {
                                _saveState();
                                _setState(() {
                                  double start = snapToGrid
                                      ? ((d.localPosition.dx / _zoomX) /
                                                    snapResolution)
                                                .round() *
                                            snapResolution
                                      : (d.localPosition.dx / _zoomX);
                                  final newClip = MidiClip(
                                    id: UniqueKey().toString(),
                                    start: start,
                                    length: beatWidth * timeSigTop,
                                    color: track.color,
                                  );
                                  if (!trackClips.containsKey(track.id)) {
                                    trackClips[track.id] = [];
                                  }
                                  trackClips[track.id]!.add(newClip);
                                  selectedClip = newClip;
                                  selectedBottomTab = 0;
                                });
                              }
                            },
                            child: Container(
                              key: Key('timeline_lane_${track.id}'),
                              height: track.showAutomation ? 140 : 100,
                              decoration: BoxDecoration(
                                color: (_dragTargetTrackId == track.id &&
                                        _dragTargetTrackId != _dragSourceTrackId)
                                    ? Colors.cyanAccent.withValues(alpha: 0.14)
                                    : ((_isTrackSelected(track, index) &&
                                            multiSelectedTrackIds.length > 1)
                                          ? Colors.blueAccent.withValues(
                                              alpha: 0.08,
                                            )
                                          : (track.type == TrackType.group
                                                ? panelDark.withValues(
                                                    alpha: 0.45,
                                                  )
                                                : null)),
                                border: Border(
                                  bottom: BorderSide(
                                    color: (_dragTargetTrackId == track.id &&
                                            _dragTargetTrackId !=
                                                _dragSourceTrackId)
                                        ? Colors.cyanAccent
                                        : panelLight,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ...(trackClips[track.id] ?? []).map(
                                    (clip) => _buildClip(track.id, clip),
                                  ),
                                  if (_dragTargetTrackId == track.id &&
                                      _dragTargetTrackId != _dragSourceTrackId)
                                    for (final ghostClip in _activeDragClips)
                                      if (_canMoveClipToTrack(ghostClip, track))
                                        Positioned(
                                          left: ghostClip.start * _zoomX,
                                          top: 10,
                                          bottom: 10,
                                          width: ghostClip.length * _zoomX,
                                          child: IgnorePointer(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: track.color.withValues(
                                                  alpha: 0.45,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.cyanAccent,
                                                  width: 1.5,
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                ghostClip.name.isNotEmpty
                                                    ? ghostClip.name
                                                    : 'Clip',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                  if (track.type == TrackType.audio &&
                                      isRecording &&
                                      track.isArmed &&
                                      recordingStartPos != null)
                                    Positioned(
                                      left: recordingStartPos! * _zoomX,
                                      top: 20,
                                      bottom: 20,
                                      width: max(
                                        10.0,
                                        (playheadPosition -
                                                recordingStartPos!) *
                                            _zoomX,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.5,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text('Recording...'),
                                        ),
                                      ),
                                    ),
                                  if (track.showAutomation)
                                    Positioned.fill(
                                      child: AutomationLaneOverlay(
                                        track: track,
                                        laneHeight: 140.0,
                                        zoomX: _zoomX,
                                        snapResolution: snapResolution,
                                        snapToGrid: snapToGrid,
                                        onSaveState: _saveState,
                                        onChanged: () => _setState(() {}),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ),
                      );
                    },
                      ),
                      if (isSelecting &&
                          _marqueeStart != null &&
                          _marqueeEnd != null)
                        Builder(
                          builder: (ctx) {
                            final double scrollOffset =
                                _timelineScrollController.hasClients
                                    ? _timelineScrollController.offset
                                    : 0.0;
                            final double leftPx =
                                min(_marqueeStart!.dx, _marqueeEnd!.dx) *
                                _zoomX;
                            final double rightPx =
                                max(_marqueeStart!.dx, _marqueeEnd!.dx) *
                                _zoomX;
                            final double topPx =
                                min(_marqueeStart!.dy, _marqueeEnd!.dy) -
                                scrollOffset;
                            final double bottomPx =
                                max(_marqueeStart!.dy, _marqueeEnd!.dy) -
                                scrollOffset;
                            return Positioned(
                              key: const Key('timeline_marquee_box'),
                              left: leftPx,
                              top: topPx,
                              width: max(2.0, rightPx - leftPx),
                              height: max(2.0, bottomPx - topPx),
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(
                                      alpha: 0.24,
                                    ),
                                    border: Border.all(
                                      color: Colors.blueAccent,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      Positioned(
                        left: playheadPosition * _zoomX - 10,
                        top: 0,
                        bottom: 0,
                        width: 22,
                        child: GestureDetector(
                          onPanUpdate: (d) => _seekPlayhead(
                            playheadPosition + (d.delta.dx / _zoomX),
                            retriggerAudio: false,
                          ),
                          onPanEnd: (_) => _seekPlayhead(
                            playheadPosition,
                            snap: true,
                          ),
                          child: Container(
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Container(width: 2, color: Colors.red),
                          ),
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
      ],
    ),
    );
  }

}
