part of '../../main.dart';

extension _DawTrackHeadersView on _DawMainScreenState {
  Widget _buildTrackHeaders() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(right: BorderSide(color: textMuted, width: 2)),
      ),
      child: Column(
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: bgDark,
              border: Border(bottom: BorderSide(color: borderMain, width: 1)),
            ),
            child: Text(
              'OVERVIEW',
              style: TextStyle(
                color: textFaint,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('Tracks', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                PopupMenuButton<String>(
                  icon: Icon(Icons.add, size: 20),
                  onSelected: (v) {
                    if (v == 'audio') _addTrack(TrackType.audio);
                    if (v == 'midi') _addTrack(TrackType.midi);
                    if (v == 'sampler') _addTrack(TrackType.sampler);
                    if (v == 'group') _addTrack(TrackType.group);
                    if (v == 'import') _importAudioTrack();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'audio',
                      child: Text('Add Audio Track'),
                    ),
                    PopupMenuItem(value: 'midi', child: Text('Add MIDI Track')),
                    PopupMenuItem(
                      value: 'sampler',
                      child: Text('Add Sampler Track'),
                    ),
                    PopupMenuItem(
                      value: 'group',
                      child: Text('Add Group Bus'),
                    ),
                    PopupMenuItem(value: 'import', child: Text('Import WAV')),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: bgDark,
              border: Border(
                top: BorderSide(color: borderMain, width: 1),
                bottom: BorderSide(color: borderMain, width: 1),
              ),
            ),
            child: Text(
              'TEMPO / SIG',
              style: TextStyle(
                color: textFaint,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.zero,
              scrollController: _headerScrollController,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: panelLight.withValues(alpha: 0.92),
                elevation: 6,
                child: child,
              ),
              onReorder: _reorderTrack,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                if (!_isTrackVisibleInArrange(track)) {
                  return SizedBox.shrink(
                    key: ValueKey('track_hdr_${track.id}'),
                  );
                }
                final isSelected = _isTrackSelected(track, index);
                final isPrimarySelected = selectedTrackIndex == index;
                final parentGroup = _groupForTrack(track);
                final bool batchDeleteSelected =
                    multiSelectedTrackIds.length > 1 &&
                    multiSelectedTrackIds.contains(track.id);
                final visibleFlags =
                    tracks.map(_isTrackVisibleInArrange).toList();
                final int? prevVisibleIdx = adjacentVisibleTrackIndex(
                  visibleFlags,
                  index,
                  -1,
                );
                final int? nextVisibleIdx = adjacentVisibleTrackIndex(
                  visibleFlags,
                  index,
                  1,
                );
                return GestureDetector(
                  key: ValueKey('track_hdr_${track.id}'),
                  onSecondaryTapUp: (d) {
                    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                    showMenu<String>(
                      context: context,
                      position: RelativeRect.fromRect(
                        d.globalPosition & Size(40, 40),
                        Offset.zero & overlay.size,
                      ),
                      items: [
                        if (prevVisibleIdx != null)
                          PopupMenuItem(
                            value: 'move_up',
                            child: Row(
                              children: const [
                                Icon(Icons.arrow_upward, size: 14),
                                SizedBox(width: 8),
                                Text('Move Track Up'),
                              ],
                            ),
                          ),
                        if (nextVisibleIdx != null)
                          PopupMenuItem(
                            value: 'move_down',
                            child: Row(
                              children: const [
                                Icon(Icons.arrow_downward, size: 14),
                                SizedBox(width: 8),
                                Text('Move Track Down'),
                              ],
                            ),
                          ),
                        if (prevVisibleIdx != null || nextVisibleIdx != null)
                          PopupMenuDivider(),
                        PopupMenuItem(value: 'color', child: Text('Change Track Color')),
                        if (track.type != TrackType.group &&
                            tracks.any((t) => t.type == TrackType.group))
                          PopupMenuItem(
                            value: 'assign_group',
                            child: Text('Route to Group Bus...'),
                          ),
                        PopupMenuItem(value: 'bounce', child: Text('Bounce Track to Audio')),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            batchDeleteSelected
                                ? 'Delete ${multiSelectedTrackIds.length} Selected Tracks'
                                : 'Delete Track',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ).then((value) {
                      if (value == 'move_up' && prevVisibleIdx != null) {
                        _reorderTrack(index, prevVisibleIdx);
                      }
                      if (value == 'move_down' && nextVisibleIdx != null) {
                        _reorderTrack(index, nextVisibleIdx + 1);
                      }
                      if (value == 'color') _showTrackColorPicker(track);
                      if (value == 'assign_group') _assignTrackToGroupDialog(track);
                      if (value == 'bounce') _bounceTrackToAudio(track);
                      if (value == 'delete') {
                        if (batchDeleteSelected) {
                          _deleteTracks(_targetTracksForTrackAction(track));
                        } else {
                          _deleteTrack(track);
                        }
                      }
                    });
                  },
                  onTap: () {
                    _setState(() {
                      _handleTrackSelectionClick(index);
                    });
                  },
                  child: Container(
                    key: Key('track_header_${track.id}'),
                    height: track.showAutomation ? 140 : 100,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isPrimarySelected
                                ? panelLight
                                : panelLight.withValues(alpha: 0.72))
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: track.color,
                          width: isSelected ? 5 : 4,
                        ),
                        bottom: BorderSide(
                          color: isSelected && multiSelectedTrackIds.length > 1
                              ? Colors.cyanAccent.withValues(alpha: 0.65)
                              : textFaint,
                        ),
                      ),
                    ),
                    padding: EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ReorderableDragStartListener(
                              key: Key('track_drag_handle_${track.id}'),
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 14,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _showTrackColorPicker(track),
                              child: Container(
                                width: 10,
                                height: 10,
                                margin: EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: track.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            if (track.type == TrackType.group)
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _setState(
                                      () => track.isGroupCollapsed =
                                          !track.isGroupCollapsed,
                                    ),
                                    child: Icon(
                                      track.isGroupCollapsed
                                          ? Icons.chevron_right
                                          : Icons.expand_more,
                                      size: 16,
                                      color: Colors.amberAccent,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'BUS',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else if (track.type == TrackType.audio)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic, size: 16, color: track.color),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    tooltip: 'Select Audio Input Channel',
                                    initialValue: _channelOptionForTrack(track).id,
                                    onSelected: (chId) =>
                                        _selectTrackInputChannel(track, chId),
                                    itemBuilder: (_) => _inputChannelOptionsForSelectedDevice()
                                        .map(
                                          (opt) => PopupMenuItem<String>(
                                            value: opt.id,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  opt.id == _channelOptionForTrack(track).id
                                                      ? Icons.radio_button_checked
                                                      : Icons.radio_button_unchecked,
                                                  size: 13,
                                                  color: opt.id == _channelOptionForTrack(track).id
                                                      ? Colors.cyanAccent
                                                      : textMuted,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    opt.label,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    child: Container(
                                      key: Key('track_channel_pill_${track.id}'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bgDark,
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: track.inputChannelId != 'stereo:0'
                                              ? Colors.cyanAccent
                                              : borderMain,
                                        ),
                                      ),
                                      child: Text(
                                        _channelOptionForTrack(track).shortLabel,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: track.inputChannelId != 'stereo:0'
                                              ? Colors.cyanAccent
                                              : textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _showInstrumentDialog(track),
                                    child: Icon(
                                      Icons.piano,
                                      size: 16,
                                      color: track.color,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showMidiInputDialog(track),
                                    child: Icon(
                                      Icons.cable,
                                      size: 16,
                                      color: track.midiInputId == null
                                          ? track.color
                                          : Colors.cyanAccent,
                                    ),
                                  ),
                                ],
                              ),
                            if (parentGroup != null) ...[
                              SizedBox(width: 4),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: parentGroup.color.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'GRP',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: parentGroup.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onDoubleTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) {
                                      TextEditingController ctrl =
                                          TextEditingController(
                                            text: track.name,
                                          );
                                      return AlertDialog(
                                        title: Text('Rename Track'),
                                        content: TextField(
                                          controller: ctrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            filled: true,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              _setState(
                                                () => track.name = ctrl.text,
                                              );
                                              Navigator.pop(ctx);
                                            },
                                            child: Text('Save'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                                child: Text(
                                  track.name,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Spacer(),

                        Row(
                          children: [
                            _buildTrackButton(
                              'A',
                              track.showAutomation,
                              () => _setState(
                                () => track.showAutomation =
                                    !track.showAutomation,
                              ),
                              Colors.cyanAccent,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'M',
                              track.isMuted,
                              () {
                                final nextMute = !track.isMuted;
                                _setState(() {
                                  for (final t in _targetTracksForTrackAction(track)) {
                                    t.isMuted = nextMute;
                                  }
                                });
                                _syncTrackMonitoringHandles();
                              },
                              Colors.redAccent,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'S',
                              track.isSolo,
                              () {
                                final nextSolo = !track.isSolo;
                                _setState(() {
                                  for (final t in _targetTracksForTrackAction(track)) {
                                    t.isSolo = nextSolo;
                                  }
                                });
                                _syncTrackMonitoringHandles();
                              },
                              Colors.amber,
                            ),
                            if (track.type != TrackType.group) ...[
                              SizedBox(width: 4),
                              _buildTrackButton(
                                'R',
                                track.isArmed,
                                () async {
                                  final nextArm = !track.isArmed;
                                  _setState(() {
                                    for (final t in _targetTracksForTrackAction(track)) {
                                      if (t.type != TrackType.group) {
                                        t.isArmed = nextArm;
                                      }
                                    }
                                  });
                                  await _updateMicState();
                                },
                                activeRecord,
                              ),
                            ],
                            if (track.type == TrackType.audio) ...[
                              SizedBox(width: 4),
                              _buildTrackButton(
                                '',
                                track.isMonitoring,
                                () async {
                                  final nextMon = !track.isMonitoring;
                                  _setState(() {
                                    for (final t in _targetTracksForTrackAction(track)) {
                                      if (t.type == TrackType.audio) {
                                        t.isMonitoring = nextMon;
                                      }
                                    }
                                  });
                                  await _updateMicState();
                                },
                                Colors.green,
                                icon: Icons.headphones,
                              ),
                            ],
                            Spacer(),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.volume_up,
                                      size: 12,
                                      color: textMuted,
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: 6,
                                          ),
                                          overlayShape:
                                              SliderComponentShape.noOverlay,
                                        ),
                                        child: Tooltip(
                                          message:
                                              'Track Volume: ${(track.volume * 100).round()}%',
                                          child: Slider(
                                            key: Key(
                                              'track_volume_slider_${track.id}',
                                            ),
                                            onChangeStart: (_) => _saveState(),
                                            min: 0.0,
                                            max: kMaxTrackVolume,
                                            value: track.volume.clamp(
                                              0.0,
                                              kMaxTrackVolume,
                                            ),
                                            activeColor: lavenderAccent,
                                            onChanged: (v) =>
                                                _onTrackVolumeChanged(track, v),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'L ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: textMuted,
                                      ),
                                    ),
                                    PanDial(
                                      onChangeStart: _saveState,
                                      pan: track.pan,
                                      onChanged: (v) => _setState(() {
                                        track.pan = v;
                                        for (var c
                                            in trackClips[track.id] ?? []) {
                                          if (c is AudioClip &&
                                              c.currentHandle != null) {
                                            SoLoud.instance.setPan(
                                              c.currentHandle!,
                                              v,
                                            );
                                          }
                                        }
                                        _syncTrackMonitoringHandles();
                                      }),
                                    ),
                                    Text(
                                      ' R',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (track.showAutomation) ...[
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 14,
                                color: Colors.cyanAccent,
                              ),
                              SizedBox(width: 8),
                              Builder(
                                builder: (context) {
                                  final items = track.availableAutomationParams;
                                  if (!items.contains(
                                    track.currentAutomationParam,
                                  )) {
                                    track.currentAutomationParam = 'Volume';
                                  }
                                  return DropdownButton<String>(
                                    value: track.currentAutomationParam,
                                    dropdownColor: panelDark,
                                    underline: SizedBox(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: textMain,
                                    ),
                                    items: items
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        _setState(
                                          () =>
                                              track.currentAutomationParam = v,
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackButton(
    String label,
    bool isActive,
    VoidCallback onTap,
    Color activeColor, {
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.3) : bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? activeColor : textFaint),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 14, color: isActive ? activeColor : textMain)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive ? activeColor : textMain,
                  ),
                ),
        ),
      ),
    );
  }

}
