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
                  child: _buildTrimWaveformArea(pad),
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

  String _formatTrimPosition(double fraction, double? totalSec) {
    if (totalSec != null && totalSec > 0.0) {
      final double sec = (fraction * totalSec).clamp(0.0, totalSec);
      if (sec < 1.0) return '${(sec * 1000).round()}ms';
      return '${sec.toStringAsFixed(2)}s';
    }
    return '${(fraction * 100).toStringAsFixed(1)}%';
  }

  Widget _buildTrimWaveformArea(SamplerPad pad) {
    final bool hasWaveform =
        pad.waveformData != null && pad.waveformData!.isNotEmpty;
    final bool canTrim = pad.source != null || hasWaveform;
    double? totalDurationSec;
    try {
      if (pad.source != null && SoLoud.instance.isInitialized) {
        totalDurationSec =
            SoLoud.instance.getLength(pad.source!).inMilliseconds / 1000.0;
      }
    } catch (_) {}

    final double safeStart = pad.trimStart.clamp(0.0, 0.99);
    final double safeEnd = pad.trimEnd.clamp(safeStart + 0.005, 1.0);
    final bool isTrimmed = safeStart > 0.002 || safeEnd < 0.998;

    return Container(
      key: const Key('sampler_waveform_trim_box'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgDark,
        border: Border.all(color: borderMain),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double startX = (safeStart * w).clamp(0.0, w);
          final double endX = (safeEnd * w).clamp(startX, w);
          const double hitW = 18.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (hasWaveform)
                Positioned.fill(
                  child: CustomPaint(
                    painter: SamplerWaveformPainter(pad),
                  ),
                ),
              if (!hasWaveform && pad.source == null)
                Center(
                  child: Text(
                    'No Audio Data',
                    style: TextStyle(color: textFaint),
                  ),
                ),
              if (canTrim && w > 20) ...[
                // Left trim handle (Start)
                Positioned(
                  key: const Key('sampler_trim_start_handle'),
                  left: (startX - hitW * 0.5).clamp(0.0, max(0.0, w - hitW)),
                  top: 0,
                  bottom: 0,
                  width: hitW,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          final double next =
                              (pad.trimStart + d.delta.dx / w).clamp(
                                0.0,
                                pad.trimEnd - 0.005,
                              );
                          pad.trimStart = next;
                        });
                        widget.onStateChanged();
                      },
                      child: Stack(
                        children: [
                          Center(
                            child: Container(
                              width: 2,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              color: Colors.cyanAccent,
                              child: const Text(
                                'IN',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Right trim handle (End)
                Positioned(
                  key: const Key('sampler_trim_end_handle'),
                  left: (endX - hitW * 0.5).clamp(0.0, max(0.0, w - hitW)),
                  top: 0,
                  bottom: 0,
                  width: hitW,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          final double next =
                              (pad.trimEnd + d.delta.dx / w).clamp(
                                pad.trimStart + 0.005,
                                1.0,
                              );
                          pad.trimEnd = next;
                        });
                        widget.onStateChanged();
                      },
                      child: Stack(
                        children: [
                          Center(
                            child: Container(
                              width: 2,
                              color: Colors.amberAccent,
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              color: Colors.amberAccent,
                              child: const Text(
                                'OUT',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Live Trim In/Out/Length readout badge
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: IgnorePointer(
                    ignoring: !isTrimmed,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'IN ${_formatTrimPosition(safeStart, totalDurationSec)}  |  OUT ${_formatTrimPosition(safeEnd, totalDurationSec)}  |  LEN ${_formatTrimPosition(safeEnd - safeStart, totalDurationSec)}',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (isTrimmed) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  pad.trimStart = 0.0;
                                  pad.trimEnd = 1.0;
                                });
                                widget.onStateChanged();
                              },
                              child: const Text(
                                'RESET',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
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

    final double midY = size.height * 0.5;
    final double halfH = max(1.0, size.height * 0.46);
    final double safeStart = pad.trimStart.clamp(0.0, 0.995);
    final double safeEnd = pad.trimEnd.clamp(safeStart + 0.005, 1.0);
    final double activeSpan = max(0.005, safeEnd - safeStart);
    final double activeLeftPx = safeStart * size.width;
    final double activeRightPx = safeEnd * size.width;

    // Guide lines (0 center & -6dB reference lines)
    final axisPaint = Paint()
      ..color = textFaint.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    final refPaint = Paint()
      ..color = textFaint.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), axisPaint);
    canvas.drawLine(
      Offset(0, size.height * 0.25),
      Offset(size.width, size.height * 0.25),
      refPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.75),
      Offset(size.width, size.height * 0.75),
      refPaint,
    );

    // Subtle highlight inside the active kept region
    canvas.drawRect(
      Rect.fromLTRB(activeLeftPx, 0, activeRightPx, size.height),
      Paint()..color = Colors.blueAccent.withValues(alpha: 0.09),
    );

    final peaks = pad.waveformData!;
    final int dataLen = peaks.length;

    double fadeGainAt(double playPos) {
      double g = 1.0;
      if (pad.fadeIn > 0.0) {
        final double fadeInLimit = pad.fadeIn / 2.0;
        if (fadeInLimit > 0 && playPos < fadeInLimit) {
          g *= (playPos / fadeInLimit).clamp(0.0, 1.0);
        }
      }
      if (pad.fadeOut > 0.0) {
        final double fadeOutLimit = pad.fadeOut / 2.0;
        if (fadeOutLimit > 0 && playPos > 1.0 - fadeOutLimit) {
          g *= ((1.0 - playPos) / fadeOutLimit).clamp(0.0, 1.0);
        }
      }
      return g;
    }

    // Continuous smooth mirrored waveform envelope (no gaps or rounded bars)
    final activeTop = Path();
    final activeBot = <Offset>[];
    final dimPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.30)
      ..strokeWidth = max(1.0, size.width / dataLen)
      ..strokeCap = StrokeCap.butt;

    bool inActivePath = false;
    for (int i = 0; i < dataLen; i++) {
      final double pos = dataLen == 1 ? 0.5 : i / (dataLen - 1);
      final double x = pos * size.width;
      final bool isKept = pos >= safeStart && pos <= safeEnd;
      double amp = peaks[i].clamp(0.0, 1.0) * halfH;

      if (isKept) {
        final double playPos = ((pos - safeStart) / activeSpan).clamp(0.0, 1.0);
        amp *= fadeGainAt(playPos);
        final double h = max(1.0, amp);
        if (!inActivePath) {
          activeTop.moveTo(x, midY - h);
          inActivePath = true;
        } else {
          activeTop.lineTo(x, midY - h);
        }
        activeBot.add(Offset(x, midY + h));
      } else {
        final double h = max(1.0, amp);
        canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), dimPaint);
      }
    }

    if (activeBot.isNotEmpty) {
      final fillPath = Path.from(activeTop);
      for (int i = activeBot.length - 1; i >= 0; i--) {
        fillPath.lineTo(activeBot[i].dx, activeBot[i].dy);
      }
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.48)
          ..style = PaintingStyle.fill,
      );
      final outline = Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.92)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(activeTop, outline);
      final botPath = Path();
      for (int i = 0; i < activeBot.length; i++) {
        if (i == 0) {
          botPath.moveTo(activeBot[i].dx, activeBot[i].dy);
        } else {
          botPath.lineTo(activeBot[i].dx, activeBot[i].dy);
        }
      }
      canvas.drawPath(botPath, outline);
    }

    // Crisp darkened trim masks outside [activeLeftPx, activeRightPx]
    final shadePaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    if (activeLeftPx > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, activeLeftPx, size.height), shadePaint);
    }
    if (activeRightPx < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(activeRightPx, 0, size.width - activeRightPx, size.height),
        shadePaint,
      );
    }

    try {
      if (pad.currentHandle != null &&
          pad.source != null &&
          SoLoud.instance.isInitialized &&
          SoLoud.instance.getIsValidVoiceHandle(pad.currentHandle!)) {
        final double pos =
            SoLoud.instance.getPosition(pad.currentHandle!).inMilliseconds /
            1000.0;
        final double totalLen =
            SoLoud.instance.getLength(pad.source!).inMilliseconds / 1000.0;
        if (totalLen > 0) {
          final double fraction = (pos / totalLen).clamp(0.0, 1.0);
          final double playheadX = size.width * fraction;
          canvas.drawLine(
            Offset(playheadX, 0),
            Offset(playheadX, size.height),
            Paint()
              ..color = Colors.white
              ..strokeWidth = 1.8,
          );
        }
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant SamplerWaveformPainter oldDelegate) {
    return true;
  }
}
