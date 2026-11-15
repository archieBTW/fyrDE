import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fyrdaw/main.dart';

import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';

enum SamplerSixteenMode { off, velocity, pitch }

class SamplerEditorWidget extends StatefulWidget {
  final Track track;
  final VoidCallback onStateChanged;
  final Future<String?> Function()? onRecordSample;

  const SamplerEditorWidget({
    super.key,
    required this.track,
    required this.onStateChanged,
    this.onRecordSample,
  });

  @override
  State<SamplerEditorWidget> createState() => _SamplerEditorWidgetState();
}

class _KitMenuSelection {
  final DrumKitPreset? builtIn;
  final SavedSamplerKit? saved;

  const _KitMenuSelection.builtIn(this.builtIn) : saved = null;
  const _KitMenuSelection.saved(this.saved) : builtIn = null;
}

class _SamplerEditorWidgetState extends State<SamplerEditorWidget> {
  int _selectedPadIndex = 0;
  SamplerSixteenMode _sixteenMode = SamplerSixteenMode.off;
  Timer? _playbackTimer;
  List<SavedSamplerKit> _savedKits = [];
  String? _activeKitName;

  @override
  void initState() {
    super.initState();
    _refreshSavedKits();
    _playbackTimer = Timer.periodic(Duration(milliseconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshSavedKits() async {
    final kits = await SavedSamplerKitStore.loadAll();
    if (!mounted) return;
    setState(() => _savedKits = kits);
  }

  Future<void> _deleteSavedKit(
    SavedSamplerKit kit,
    BuildContext menuContext,
  ) async {
    Navigator.of(menuContext).pop();
    await SavedSamplerKitStore.delete(kit.id);
    if (_activeKitName == kit.name) {
      _activeKitName = null;
    }
    await _refreshSavedKits();
  }

  Future<void> _showSaveSamplerDialog() async {
    final controller = TextEditingController(
      text: _activeKitName ?? widget.track.name,
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panelDark,
        title: Text(
          'Save Sampler Kit',
          style: TextStyle(color: textMain, fontSize: 15),
        ),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final trimmed = value.text.trim();
              final willOverwrite = trimmed.isNotEmpty &&
                  _savedKits.any(
                    (k) => k.name.toLowerCase() == trimmed.toLowerCase(),
                  );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('save_sampler_name_field'),
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: textMain, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Sampler Name',
                      labelStyle: TextStyle(color: textMuted, fontSize: 12),
                      hintText: 'e.g. Custom Lo-Fi Kit',
                      hintStyle: TextStyle(color: textFaint, fontSize: 12),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: textFaint),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: lavenderAccent),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        Navigator.of(dialogContext).pop(text.trim());
                      }
                    },
                  ),
                  if (willOverwrite) ...[
                    const SizedBox(height: 8),
                    Text(
                      'A saved sampler with this name already exists and will be updated.',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSave = value.text.trim().isNotEmpty;
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: lavenderAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: canSave
                    ? () => Navigator.of(dialogContext).pop(value.text.trim())
                    : null,
                child: const Text('Save'),
              );
            },
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    final saved = await SavedSamplerKitStore.save(
      name: result.trim(),
      samplerPads: widget.track.samplerPads,
    );
    await _refreshSavedKits();
    if (!mounted) return;
    setState(() => _activeKitName = saved.name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved sampler "${saved.name}"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Widget _buildSamplerKnob(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: textMuted, fontSize: 10)),
        SizedBox(height: 8),
        Transform.scale(
          scale: 1.5,
          child: ValueDial(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(height: 12),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(color: textFaint, fontSize: 10),
        ),
      ],
    );
  }

  Future<String?> _pickAudioFile({String? title, String? initialDirectory}) async {
    final home = Platform.environment['HOME'] ?? '';
    final fyrfilesCandidates = [
      if (home.isNotEmpty) p.join(home, '.local/bin/fyrfiles'),
      if (home.isNotEmpty) p.join(home, '.local/share/fyrDE/fyrfiles/fyrfiles'),
      '/usr/local/bin/fyrfiles',
      '/usr/bin/fyrfiles',
    ];

    String? fyrfilesPath;
    for (final c in fyrfilesCandidates) {
      if (File(c).existsSync()) {
        fyrfilesPath = c;
        break;
      }
    }

    if (fyrfilesPath != null) {
      try {
        final startDir = (initialDirectory != null && Directory(initialDirectory).existsSync())
            ? initialDirectory
            : (home.isNotEmpty && Directory(p.join(home, 'Music')).existsSync()
                ? p.join(home, 'Music')
                : (home.isNotEmpty ? home : '.'));

        final args = <String>['--picker'];
        if (title != null && title.isNotEmpty) {
          args.add('--title=$title');
        }
        args.add(startDir);

        final res = await Process.run(fyrfilesPath, args);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            final picked = out.split('\n').first.trim();
            if (File(picked).existsSync()) {
              return picked;
            }
          }
        }
        return null;
      } catch (_) {}
    }

    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: title,
        initialDirectory: initialDirectory,
        type: FileType.audio,
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        return result.files.single.path;
      }
    } catch (_) {}

    return null;
  }

  @override
  Widget build(BuildContext context) {
    var pad = widget.track.samplerPads[_selectedPadIndex] ?? SamplerPad();
    if (!widget.track.samplerPads.containsKey(_selectedPadIndex)) {
      widget.track.samplerPads[_selectedPadIndex] = pad;
    }

    return Row(
      children: [
        Container(
          width: 320,
          padding: EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Kit:',
                    style: TextStyle(color: textMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: PopupMenuButton<_KitMenuSelection>(
                      tooltip: 'Load Drum Kit or Saved Sampler',
                      color: panelDark,
                      onSelected: (selection) async {
                        if (selection.builtIn != null) {
                          final kit = selection.builtIn!;
                          await applyDrumKitToPads(widget.track.samplerPads, kit);
                          if (mounted) {
                            setState(() => _activeKitName = kit.name);
                            widget.onStateChanged();
                          }
                        } else if (selection.saved != null) {
                          final kit = selection.saved!;
                          await applySavedSamplerKitToPads(
                            widget.track.samplerPads,
                            kit,
                          );
                          if (mounted) {
                            setState(() => _activeKitName = kit.name);
                            widget.onStateChanged();
                          }
                        }
                      },
                      itemBuilder: (menuContext) => [
                        PopupMenuItem<_KitMenuSelection>(
                          enabled: false,
                          height: 24,
                          child: Text(
                            'PRESET KITS',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        ...kDrumKits.map(
                          (kit) => PopupMenuItem<_KitMenuSelection>(
                            value: _KitMenuSelection.builtIn(kit),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  kit.name,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  kit.description,
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<_KitMenuSelection>(
                          enabled: false,
                          height: 24,
                          child: Text(
                            'SAVED SAMPLERS',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        if (_savedKits.isEmpty)
                          PopupMenuItem<_KitMenuSelection>(
                            enabled: false,
                            height: 30,
                            child: Text(
                              'No saved samplers yet',
                              style: TextStyle(
                                color: textFaint,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          ..._savedKits.map(
                            (kit) => PopupMenuItem<_KitMenuSelection>(
                              value: _KitMenuSelection.saved(kit),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          kit.name,
                                          style: TextStyle(
                                            color: lavenderLight,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${kit.sampleCount} / 16 pads loaded',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: 'Delete Saved Sampler',
                                    child: InkWell(
                                      key: Key('delete_saved_kit_${kit.name}'),
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () =>
                                          _deleteSavedKit(kit, menuContext),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: bgDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: textFaint),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                _activeKitName ?? 'Load Drum Kit...',
                                style: TextStyle(color: lavenderLight, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, size: 16, color: lavenderLight),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Save Current Sampler',
                    child: InkWell(
                      key: const Key('save_sampler_button'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: _showSaveSamplerDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: bgDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: textFaint),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.save_outlined,
                              size: 13,
                              color: lavenderLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Save',
                              style: TextStyle(
                                color: lavenderLight,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '16-Level:',
                    style: TextStyle(color: textMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: DropdownButton<SamplerSixteenMode>(
                      value: _sixteenMode,
                      isDense: true,
                      isExpanded: true,
                      underline: SizedBox(),
                      dropdownColor: panelDark,
                      style: TextStyle(color: lavenderLight, fontSize: 11),
                      items: const [
                        DropdownMenuItem(
                          value: SamplerSixteenMode.off,
                          child: Text('Off (Pads 1-16)', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: SamplerSixteenMode.velocity,
                          child: Text('16-Level Velocity', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: SamplerSixteenMode.pitch,
                          child: Text('16-Level Pitch', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (m) {
                        if (m != null) setState(() => _sixteenMode = m);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 16,
                  itemBuilder: (context, index) {
                    bool isSelected = index == _selectedPadIndex;
                    final padItem = widget.track.samplerPads[index];
                    bool hasSample = padItem?.filePath != null;
                    final choke = padItem?.chokeGroup ?? 0;
                    final label = _sixteenMode == SamplerSixteenMode.velocity
                        ? 'V${((index + 1) / 16.0 * 127).round()}'
                        : (_sixteenMode == SamplerSixteenMode.pitch
                              ? '${(index - 7) >= 0 ? '+' : ''}${index - 7}st'
                              : (padItem?.name ?? 'Pad ${index + 1}'));
                    return GestureDetector(
                      onTap: () {
                        if (_sixteenMode == SamplerSixteenMode.off) {
                          setState(() => _selectedPadIndex = index);
                          var p = widget.track.samplerPads[index];
                          p?.play(
                            127.0,
                            widget.track.bus,
                            widget.track.volume,
                            widget.track.pan,
                            widget.track.samplerPads.values,
                          );
                        } else {
                          var p = widget.track.samplerPads[_selectedPadIndex];
                          if (p != null) {
                            final vel = _sixteenMode == SamplerSixteenMode.velocity
                                ? ((index + 1) / 16.0 * 127.0)
                                : 120.0;
                            final pitchMult = _sixteenMode == SamplerSixteenMode.pitch
                                ? pow(2.0, (index - 7) / 12.0).toDouble()
                                : 1.0;
                            p.play(
                              vel,
                              widget.track.bus,
                              widget.track.volume,
                              widget.track.pan,
                              widget.track.samplerPads.values,
                              pitchMult,
                            );
                          }
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _sixteenMode != SamplerSixteenMode.off
                              ? panelLight
                              : (isSelected
                                    ? lavenderAccent
                                    : (hasSample ? panelLight : bgDark)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? textMain : textFaint,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: (_sixteenMode == SamplerSixteenMode.off && isSelected)
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (_sixteenMode == SamplerSixteenMode.off && choke > 0)
                              Positioned(
                                top: 2,
                                right: 4,
                                child: Text(
                                  String.fromCharCode(64 + choke),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: textFaint),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: panelLight,
                      ),
                      onPressed: () async {
                        final path = await _pickAudioFile(title: 'Load Audio Sample');
                        if (path != null) {
                          await pad.loadSample(
                            path,
                            label: p.basenameWithoutExtension(path),
                          );
                          setState(() {});
                          widget.onStateChanged();
                        }
                      },
                      child: Text(
                        'Load Sample',
                        style: TextStyle(color: textMain),
                      ),
                    ),
                    SizedBox(width: 8),
                    if (widget.onRecordSample != null)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: panelLight,
                        ),
                        onPressed: () async {
                          String? path = await widget.onRecordSample!();
                          if (path != null) {
                            await pad.loadSample(
                              path,
                              label: p.basenameWithoutExtension(path),
                            );
                            setState(() {});
                            widget.onStateChanged();
                          }
                        },
                        child: Icon(Icons.mic, color: Colors.red, size: 20),
                      ),

                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        pad.filePath ?? 'No sample loaded',
                        style: TextStyle(color: textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Choke Grp',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        ),
                        SizedBox(height: 4),
                        DropdownButton<int>(
                          value: pad.chokeGroup.clamp(0, 4),
                          isDense: true,
                          dropdownColor: panelDark,
                          style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Off')),
                            DropdownMenuItem(value: 1, child: Text('Grp A')),
                            DropdownMenuItem(value: 2, child: Text('Grp B')),
                            DropdownMenuItem(value: 3, child: Text('Grp C')),
                            DropdownMenuItem(value: 4, child: Text('Grp D')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => pad.chokeGroup = v);
                              widget.onStateChanged();
                            }
                          },
                        ),
                      ],
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'MIDI Note',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        ),
                        SizedBox(height: 4),
                        SizedBox(
                          width: 50,
                          height: 30,
                          child: TextField(
                            controller: TextEditingController(
                              text: pad.midiNote.toString(),
                            ),
                            style: TextStyle(color: textMain, fontSize: 12),
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: bgDark,
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (v) {
                              int? note = int.tryParse(v);
                              if (note != null) {
                                setState(() => pad.midiNote = note);
                                widget.onStateChanged();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: bgDark,
                      border: Border.all(color: textFaint),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Stack(
                      children: [
                        if (pad.waveformData != null && pad.waveformData!.isNotEmpty)
                          CustomPaint(
                            size: Size.infinite,
                            painter: SamplerWaveformPainter(pad),
                          ),
                        if (pad.source != null)
                          Positioned.fill(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: lavenderAccent.withValues(
                                  alpha: 0.3,
                                ),
                                inactiveTrackColor: textMuted,
                                thumbColor: lavenderAccent,
                                overlayColor: lavenderAccent.withValues(
                                  alpha: 0.2,
                                ),
                                trackHeight: 80,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                              ),
                              child: RangeSlider(
                                values: RangeValues(pad.trimStart, pad.trimEnd),
                                min: 0.0,
                                max: 1.0,
                                onChanged: (RangeValues values) {
                                  setState(() {
                                    pad.trimStart = values.start;
                                    pad.trimEnd = values.end;
                                  });
                                  widget.onStateChanged();
                                },
                              ),
                            ),
                          ),
                        if (pad.source == null &&
                            (pad.waveformData == null ||
                                pad.waveformData!.isEmpty))
                          Center(
                            child: Text(
                              'No Audio Data',
                              style: TextStyle(color: textFaint),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSamplerKnob('Volume', pad.volume, 0.0, 2.0, (v) {
                      setState(() => pad.volume = v);
                      widget.onStateChanged();
                    }),
                    _buildSamplerKnob('Pitch', pad.pitch, 0.1, 2.0, (v) {
                      setState(() => pad.pitch = v);
                      widget.onStateChanged();
                    }),
                    _buildSamplerKnob('Fade In', pad.fadeIn, 0.0, 2.0, (v) {
                      setState(() => pad.fadeIn = v);
                      widget.onStateChanged();
                    }),
                    _buildSamplerKnob('Fade Out', pad.fadeOut, 0.0, 2.0, (v) {
                      setState(() => pad.fadeOut = v);
                      widget.onStateChanged();
                    }),
                    if (pad.filePath != null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Reverse',
                            style: TextStyle(color: textMuted, fontSize: 10),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: pad.reversed
                                  ? lavenderAccent
                                  : panelLight,
                              shape: CircleBorder(),
                              padding: EdgeInsets.all(16),
                            ),
                            onPressed: () async {
                              await pad.toggleReverse(() => setState(() {}));
                              widget.onStateChanged();
                            },
                            child: Icon(
                              Icons.sync,
                              color: pad.reversed ? Colors.black : Colors.white,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            pad.reversed ? 'On' : 'Off',
                            style: TextStyle(color: textFaint, fontSize: 10),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SamplerWaveformPainter extends CustomPainter {
  final SamplerPad pad;

  SamplerWaveformPainter(this.pad);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (pad.waveformData == null || pad.waveformData!.isEmpty) return;

    Paint paint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    double midY = size.height / 2;
    int dataLen = pad.waveformData!.length;
    double step = size.width / dataLen;

    for (int i = 0; i < dataLen; i++) {
      double x = i * step;
      double amplitude = pad.waveformData![i] * (size.height / 2);

      double pos = i / dataLen;
      double playPos = (pos - pad.trimStart) / (pad.trimEnd - pad.trimStart);

      if (pos >= pad.trimStart && pos <= pad.trimEnd) {
        if (pad.fadeIn > 0.0) {
          double fadeInLimit = pad.fadeIn / 2.0;
          if (playPos < fadeInLimit) {
            amplitude *= (playPos / fadeInLimit);
          }
        }
        if (pad.fadeOut > 0.0) {
          double fadeOutLimit = pad.fadeOut / 2.0;
          if (playPos > 1.0 - fadeOutLimit) {
            amplitude *= ((1.0 - playPos) / fadeOutLimit).clamp(0.0, 1.0);
          }
        }
      } else {
        amplitude *= 0.2;
        paint.color = Colors.blueAccent.withValues(alpha: 0.3);
      }

      if (pos >= pad.trimStart && pos <= pad.trimEnd) {
        paint.color = Colors.blueAccent.withValues(alpha: 0.8);
      }

      canvas.drawLine(
        Offset(x, midY - amplitude),
        Offset(x, midY + amplitude),
        paint,
      );
    }

    if (pad.currentHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(pad.currentHandle!)) {
      try {
        double pos =
            SoLoud.instance.getPosition(pad.currentHandle!).inMilliseconds /
            1000.0;
        double totalLen =
            SoLoud.instance.getLength(pad.source!).inMilliseconds / 1000.0;
        if (totalLen > 0) {
          double fraction = pos / totalLen;
          double playheadX = size.width * fraction;
          Paint playheadPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = 2;
          canvas.drawLine(
            Offset(playheadX, 0),
            Offset(playheadX, size.height),
            playheadPaint,
          );
        }
      } catch (_) {}
    }
  }

  @override
  bool shouldRepaint(covariant SamplerWaveformPainter oldDelegate) {
    return true;
  }
}
