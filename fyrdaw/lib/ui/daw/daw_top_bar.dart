part of '../../main.dart';

extension _DawTopBarView on _DawMainScreenState {
  Widget _buildTopBar() {
    return Container(
      height: 68,
      padding: EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(bottom: BorderSide(color: textMuted, width: 2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanStart: (d) => windowManager.startDragging(),
              onDoubleTap: () async {
                bool isMax = await windowManager.isMaximized();
                if (isMax) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => windowManager.close(),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.red.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => windowManager.minimize(),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => windowManager.isMaximized().then(
                        (m) => m
                            ? windowManager.unmaximize()
                            : windowManager.maximize(),
                      ),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 18),
                    Text(
                      'Sound Booth',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: lavenderAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: textMuted,
                            ),
                            onPressed: _togglePlay,
                          ),
                          IconButton(
                            icon: Icon(Icons.stop, color: textMuted),
                            onPressed: () {
                              if (isRecording) _toggleRecord();
                              _setState(() {
                                if (isPlaying) _togglePlay();
                                playheadPosition = isLooping ? loopStart : 0.0;
                                try {
                                  SoLoud.instance.filters.echoFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.robotizeFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.compressorFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.biquadResonantFilter.deactivate();
                                } catch (_) {}
                                _stopAllActivePlaybackVoices();
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              isRecording
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _countInBeatsLeft > 0
                                  ? Colors.amberAccent
                                  : activeRecord,
                            ),
                            tooltip: 'Record (R)',
                            onPressed: _toggleRecord,
                          ),
                          if (_countInBeatsLeft > 0)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$_countInBeatsLeft',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          SizedBox(width: 4),
                          Tooltip(
                            message: 'Count-In Bars before recording (Off / 1 Bar / 2 Bars)',
                            child: InkWell(
                              onTap: () => _setState(() => countInBars = (countInBars + 1) % 3),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: countInBars > 0
                                      ? Colors.amberAccent.withValues(alpha: 0.22)
                                      : textFaint,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: countInBars > 0 ? Colors.amberAccent : borderMain,
                                  ),
                                ),
                                child: Text(
                                  countInBars == 0 ? '1-2' : '${countInBars}B',
                                  style: TextStyle(
                                    color: countInBars > 0 ? Colors.amberAccent : textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          Tooltip(
                            message: 'Loop Punch-In/Out (Records inside loop brace)',
                            child: InkWell(
                              onTap: () => _setState(() => punchInLoop = !punchInLoop),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: punchInLoop
                                      ? activeRecord.withValues(alpha: 0.25)
                                      : textFaint,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: punchInLoop ? activeRecord : borderMain,
                                  ),
                                ),
                                child: Text(
                                  'PUNCH',
                                  style: TextStyle(
                                    color: punchInLoop ? activeRecord : textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: textFaint,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: textFaint),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.timer, size: 14, color: textMuted),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 28,
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: bpm.toString(),
                                    ),
                                    focusNode: _bpmFocus,
                                    style: TextStyle(
                                      color: textMain,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onSubmitted: (v) {
                                      int? nb = int.tryParse(v);
                                      if (nb != null && nb > 20 && nb < 300) {
                                        _changeTempo(nb);
                                      }
                                      _focusNode.requestFocus();
                                    },
                                    onTapOutside: (e) => _focusNode.requestFocus(),
                                  ),
                                ),
                                Text(
                                  'BPM',
                                  style: TextStyle(color: textMuted, fontSize: 10),
                                ),
                                TextButton(
                                  onPressed: _tapTempo,
                                  child: Text(
                                    'Tap',
                                    style: TextStyle(color: lavenderLight, fontSize: 10),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Tooltip(
                                  message: 'Toggle Metronome',
                                  child: InkWell(
                                    onTap: () {
                                      _setState(() {
                                        isMetronomeEnabled = !isMetronomeEnabled;
                                      });
                                    },
                                    child: Icon(
                                      Icons.notifications_active,
                                      size: 16,
                                      color: isMetronomeEnabled
                                          ? lavenderAccent
                                          : textMuted,
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message:
                                      'Metronome Volume (${(metronomeVolume * 100).round()}%)',
                                  child: SizedBox(
                                    width: 58,
                                    height: 22,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2.5,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 9,
                                            ),
                                      ),
                                      child: Slider(
                                        key: const Key('metronome_volume_slider'),
                                        value: metronomeVolume.clamp(0.0, 1.5),
                                        min: 0.0,
                                        max: 1.5,
                                        activeColor: lavenderAccent,
                                        inactiveColor: borderMain,
                                        onChanged: (v) {
                                          _setState(() => metronomeVolume = v);
                                        },
                                        onChangeEnd: _saveMetronomeVolumePref,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                DropdownButton<int>(
                                  value: timeSigTop,
                                  underline: SizedBox(),
                                  dropdownColor: panelDark,
                                  icon: SizedBox(),
                                  items: [3, 4, 5, 6, 7]
                                      .map(
                                        (i) => DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                            '$i / $timeSigBottom',
                                            style: TextStyle(
                                              color: textMain,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) _setState(() => timeSigTop = v);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.undo, color: textMuted),
                      onPressed: _undo,
                      tooltip: 'Undo (Ctrl+Z)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.redo, color: textMuted),
                      onPressed: _redo,
                      tooltip: 'Redo (Ctrl+Shift+Z)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_out, color: textMuted),
                      onPressed: _zoomOut,
                      tooltip: 'Zoom Out (Ctrl-)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_in, color: textMuted),
                      onPressed: _zoomIn,
                      tooltip: 'Zoom In (Ctrl+)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        snapToGrid ? Icons.grid_on : Icons.grid_off,
                        color: snapToGrid ? lavenderAccent : textMuted,
                      ),
                      tooltip: 'Snap to Grid',
                      onPressed: () => _setState(() => snapToGrid = !snapToGrid),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.center_focus_strong,
                        size: 18,
                        color: autoScrollPlayhead ? Colors.cyanAccent : textMuted,
                      ),
                      tooltip: 'Auto-Follow Playhead',
                      onPressed: () => _setState(
                        () => autoScrollPlayhead = !autoScrollPlayhead,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard,
                        size: 18,
                        color: isMusicalTypingEnabled
                            ? lavenderAccent
                            : textMuted,
                      ),
                      tooltip: 'QWERTY Musical Typing Keyboard',
                      onPressed: () => _setState(
                        () => isMusicalTypingEnabled = !isMusicalTypingEnabled,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        _isSessionView ? Icons.view_timeline : Icons.grid_view,
                        size: 18,
                        color: _isSessionView ? Colors.cyanAccent : textMuted,
                      ),
                      tooltip: _isSessionView
                          ? 'Switch to Timeline View'
                          : 'Switch to Session Clip Launcher',
                      onPressed: () =>
                          _setState(() => _isSessionView = !_isSessionView),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      key: const Key('toggle_sample_browser'),
                      icon: Icon(
                        Icons.library_music,
                        size: 18,
                        color: _showSampleBrowser
                            ? Colors.cyanAccent
                            : textMuted,
                      ),
                      tooltip: 'Toggle Sample & MIDI Browser',
                      onPressed: () => _setState(
                        () => _showSampleBrowser = !_showSampleBrowser,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.sensors,
                        size: 18,
                        color: _midiLearnActive ? Colors.amberAccent : textMuted,
                      ),
                      tooltip: _midiLearnActive
                          ? 'MIDI Learn Active (Click mixer control then move HW knob/fader)'
                          : 'MIDI Learn Mode (${midiMappings.length} mapped)',
                      onPressed: () => _setState(() {
                        _midiLearnActive = !_midiLearnActive;
                        if (!_midiLearnActive) _midiLearnTarget = null;
                      }),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    SizedBox(width: 4),
                    MasterSpectrumWidget(
                      samples: _masterVizSamples,
                      width: 96,
                      height: 28,
                      accentColor: lavenderAccent,
                    ),
                    SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.settings, color: textMuted),
                      onSelected: (val) {
                        if (val == 'new') _newProject();
                        if (val == 'templates') _openTemplates();
                        if (val == 'open') _openProject();
                        if (val == 'save') _saveProject();
                        if (val == 'save_as') _saveProjectAs();
                        if (val == 'import_midi') _importMidiFile();
                        if (val == 'export_midi') _exportSelectedMidiClip();
                        if (val == 'export') _exportAudio();
                        if (val == 'export_stems') _exportStems();
                        if (val == 'preferences') _openPreferences();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'new',
                          child: Text('New Project'),
                        ),
                        PopupMenuItem(
                          value: 'templates',
                          child: Text('New from Template...'),
                        ),
                        PopupMenuItem(
                          value: 'open',
                          child: Text('Open Project'),
                        ),
                        PopupMenuItem(
                          value: 'save',
                          enabled: currentProjectPath != null,
                          child: Text('Save Project'),
                        ),
                        PopupMenuItem(
                          value: 'save_as',
                          child: Text('Save As...'),
                        ),
                        PopupMenuItem(
                          value: 'import_midi',
                          child: Text('Import MIDI (.mid)...'),
                        ),
                        PopupMenuItem(
                          value: 'export_midi',
                          enabled: selectedClip is MidiClip,
                          child: Text('Export Selected Clip as .mid'),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text('Export Mixdown (WAV/FLAC/MP3)'),
                        ),
                        PopupMenuItem(
                          value: 'export_stems',
                          child: Text('Export Stems'),
                        ),
                        PopupMenuItem(
                          value: 'preferences',
                          child: Text('Preferences'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
