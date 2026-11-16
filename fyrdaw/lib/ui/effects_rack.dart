import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/meters.dart';
import 'package:fyrdaw/ui/parametric_eq_widget.dart';
import 'package:fyrdaw/ui/tuner_gate_panel.dart';
import 'package:fyrdaw/utils/pitch_detector.dart';

/// Modular Stompbox Effects Rack view with Audio Input Source / Tuner & Noise Gate,
/// Reorderable Pedalboard, Interactive EQ curves, Sidechain Ducking selector on
/// Compressor pedals, Pop-out Pedal Inspector dialog, and Chain Presets.
class EffectsRackView extends StatelessWidget {
  final Track track;
  final List<Track> allTracks;
  final List<InputDevice> inputDevices;
  final InputDevice? selectedInputDevice;
  final double trackLevel;
  final double sidechainGr;
  final List<double> fftSpectrum;
  final PitchDetectionResult? detectedPitch;
  final bool tunerEnabled;
  final bool isMasterRack;
  final VoidCallback? onToggleMasterRack;
  final VoidCallback onSaveState;
  final ValueChanged<InputDevice?> onInputDeviceChanged;
  final VoidCallback onToggleTuner;
  final ValueChanged<double> onNoiseGateChanged;
  final void Function(int oldIndex, int newIndex) onReorderEffect;
  final void Function(int index) onRemoveEffect;
  final void Function(DawEffect fx) onToggleBypass;
  final void Function(DawEffect fx, String paramKey, double val) onParamChanged;
  final void Function(DawEffect fx, String? sourceTrackId) onSidechainChanged;
  final void Function(String presetName) onApplyPreset;
  final VoidCallback onAddEffectPressed;
  final VoidCallback? onAddExternalPluginPressed;

  const EffectsRackView({
    super.key,
    required this.track,
    required this.allTracks,
    required this.inputDevices,
    required this.selectedInputDevice,
    required this.trackLevel,
    required this.sidechainGr,
    this.fftSpectrum = const [],
    required this.detectedPitch,
    required this.tunerEnabled,
    this.isMasterRack = false,
    this.onToggleMasterRack,
    required this.onSaveState,
    required this.onInputDeviceChanged,
    required this.onToggleTuner,
    required this.onNoiseGateChanged,
    required this.onReorderEffect,
    required this.onRemoveEffect,
    required this.onToggleBypass,
    required this.onParamChanged,
    required this.onSidechainChanged,
    required this.onApplyPreset,
    required this.onAddEffectPressed,
    this.onAddExternalPluginPressed,
  });

  Color _pedalColor(String name) {
    switch (name) {
      case 'EQ':
        return Colors.blue[800]!;
      case 'Compressor':
        return Colors.green[800]!;
      case 'Overdrive':
      case 'TubeScreamer':
        return Colors.red[800]!;
      case 'GuitarAmp':
        return Colors.grey[900]!;
      default:
        return Colors.deepPurple[800]!;
    }
  }

  void _showExpandedPedalDialog(BuildContext context, DawEffect fx) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: panelDark,
          title: Row(
            children: [
              Icon(Icons.tune, color: lavenderAccent, size: 18),
              const SizedBox(width: 8),
              Text('${fx.name} Inspector', style: TextStyle(color: textMain)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  onToggleBypass(fx);
                  setModalState(() {});
                },
                child: Text(
                  fx.isBypassed ? 'BYPASSED' : 'ACTIVE',
                  style: TextStyle(
                    color: fx.isBypassed ? textMuted : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: fx.name == 'EQ' ? 500 : 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fx.name == 'EQ') ...[
                    ParametricEqWidget(
                      effect: fx,
                      fftSpectrum: fftSpectrum,
                      height: 195,
                      onParamChanged: (k, v) {
                        onParamChanged(fx, k, v);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Drag colored nodes for Frequency/Gain, adjust Q below, double-click node to reset',
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                  ] else ...[
                    PedalVisualizerWidget(
                      effect: fx,
                      activityLevel: trackLevel,
                      gainReduction: fx.name == 'Compressor' ? sidechainGr : 0.0,
                      height: 92,
                      onParamChanged: null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (fx.name == 'Compressor') ...[
                    Row(
                      children: [
                        Text(
                          'Sidechain Duck Source:',
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String?>(
                            value: allTracks.any((t) => t.id == fx.sidechainTrackId)
                                ? fx.sidechainTrackId
                                : null,
                            isExpanded: true,
                            dropdownColor: bgDark,
                            style: TextStyle(color: textMain, fontSize: 12),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None (Internal)'),
                              ),
                              ...allTracks
                                  .where((t) => t.id != track.id)
                                  .map(
                                    (t) => DropdownMenuItem<String?>(
                                      value: t.id,
                                      child: Text(t.name),
                                    ),
                                  ),
                            ],
                            onChanged: (v) {
                              onSidechainChanged(fx, v);
                              setModalState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (fx.name != 'EQ')
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: fx.parameters.keys.map((k) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PanDial(
                              onChangeStart: onSaveState,
                              size: 32,
                              pan: (fx.parameters[k] ?? 0.5) * 2 - 1.0,
                              onChanged: (v) {
                                onParamChanged(
                                  fx,
                                  k,
                                  ((v + 1.0) / 2.0).clamp(0.0, 1.0),
                                );
                                setModalState(() {});
                              },
                            ),
                            const SizedBox(height: 4),
                            Text(k, style: TextStyle(color: textMain, fontSize: 11)),
                            Text(
                              '${((fx.parameters[k] ?? 0.5) * 100).round()}%',
                              style: TextStyle(color: textMuted, fontSize: 10),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: lavenderLight)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!isMasterRack && track.type == TrackType.audio)
          Container(
            width: 215,
            color: panelDark,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Input Source',
                    style: TextStyle(
                      color: textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (inputDevices.isEmpty)
                    Text(
                      'No inputs found',
                      style: TextStyle(color: textFaint, fontSize: 10),
                    )
                  else
                    DropdownButton<InputDevice>(
                      value: selectedInputDevice,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: bgDark,
                      icon: Icon(Icons.mic, color: textMuted, size: 15),
                      underline: Container(height: 1, color: lavenderAccent),
                      style: TextStyle(color: textMain, fontSize: 11),
                      onChanged: onInputDeviceChanged,
                      items: inputDevices.map((InputDevice value) {
                        return DropdownMenuItem<InputDevice>(
                          value: value,
                          child: Text(
                            value.label.isNotEmpty
                                ? value.label
                                : 'Microphone ${value.id}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 10),
                  TunerGatePanel(
                    detectedPitch: detectedPitch,
                    noiseGateThreshold: track.noiseGateThreshold,
                    onGateChanged: onNoiseGateChanged,
                    tunerEnabled: tunerEnabled,
                    onToggleTuner: onToggleTuner,
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  onReorder: onReorderEffect,
                  children: track.effectsChain.asMap().entries.map((e) {
                    final idx = e.key;
                    final fx = e.value;
                    final isAmp = fx.name == 'GuitarAmp';
                    final isComp = fx.name == 'Compressor';
                    return Center(
                      key: ValueKey('${fx.name}_$idx'),
                      child: Opacity(
                        opacity: fx.isBypassed ? 0.55 : 1.0,
                        child: Container(
                          width: isAmp ? 250 : 146,
                          height: 204,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _pedalColor(fx.name),
                            borderRadius: BorderRadius.circular(isAmp ? 4 : 8),
                            boxShadow: [
                              BoxShadow(
                                color: fx.isBypassed ? Colors.black38 : textMuted,
                                blurRadius: fx.isBypassed ? 2 : 5,
                                offset: const Offset(2, 2),
                              ),
                            ],
                            border: Border.all(
                              color: fx.isBypassed ? Colors.white24 : textFaint,
                              width: isAmp ? 4 : 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                color: Colors.black26,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: fx.isBypassed
                                            ? Colors.grey[800]
                                            : Colors.redAccent,
                                        boxShadow: fx.isBypassed
                                            ? null
                                            : [
                                                BoxShadow(
                                                  color: Colors.redAccent
                                                      .withValues(alpha: 0.85),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          if (fx.pluginFormat != null)
                                            Container(
                                              margin: const EdgeInsets.only(right: 4),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 3,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.tealAccent.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: Colors.tealAccent,
                                                  width: 0.6,
                                                ),
                                              ),
                                              child: Text(
                                                fx.pluginFormat!,
                                                style: const TextStyle(
                                                  color: Colors.tealAccent,
                                                  fontSize: 7,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              fx.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showExpandedPedalDialog(context, fx),
                                      child: Icon(
                                        Icons.open_in_full,
                                        size: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => onRemoveEffect(idx),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                              PedalVisualizerWidget(
                                effect: fx,
                                activityLevel: trackLevel,
                                gainReduction: isComp ? sidechainGr : 0.0,
                                onParamChanged: fx.name == 'EQ'
                                    ? (k, v) => onParamChanged(fx, k, v)
                                    : null,
                              ),
                              if (isComp)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Row(
                                    children: [
                                      const Text(
                                        'SC:',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: DropdownButton<String?>(
                                          value: allTracks.any(
                                            (t) => t.id == fx.sidechainTrackId,
                                          )
                                              ? fx.sidechainTrackId
                                              : null,
                                          isExpanded: true,
                                          isDense: true,
                                          underline: const SizedBox(),
                                          dropdownColor: bgDark,
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.amberAccent,
                                          ),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('None'),
                                            ),
                                            ...allTracks
                                                .where((t) => t.id != track.id)
                                                .map(
                                                  (t) => DropdownMenuItem<String?>(
                                                    value: t.id,
                                                    child: Text(
                                                      t.name,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                          onChanged: (v) => onSidechainChanged(fx, v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  runAlignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: (fx.name == 'EQ'
                                          ? const ['Low', 'Mid', 'High']
                                          : fx.parameters.keys.take(4).toList())
                                      .where((k) => fx.parameters.containsKey(k))
                                      .map((k) {
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PanDial(
                                          onChangeStart: onSaveState,
                                          pan: fx.parameters[k]!.clamp(0.0, 1.0) * 2 - 1.0,
                                          onChanged: (v) => onParamChanged(
                                            fx,
                                            k,
                                            ((v + 1.0) / 2.0).clamp(0.0, 1.0),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          k,
                                          style: const TextStyle(
                                            fontSize: 8,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              Tooltip(
                                message: fx.isBypassed
                                    ? 'Enable effect'
                                    : 'Bypass effect',
                                child: GestureDetector(
                                  onTap: () => onToggleBypass(fx),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    width: isAmp ? 86 : 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: isAmp
                                          ? Colors.black87
                                          : Colors.grey[300],
                                      shape: isAmp
                                          ? BoxShape.rectangle
                                          : BoxShape.circle,
                                      border: Border.all(
                                        color: fx.isBypassed
                                            ? Colors.grey
                                            : Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 3,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: fx.isBypassed
                                              ? Colors.grey[700]
                                              : Colors.greenAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: fx.isBypassed
                                              ? null
                                              : [
                                                  BoxShadow(
                                                    color: Colors.greenAccent
                                                        .withValues(alpha: 0.9),
                                                    blurRadius: 6,
                                                  ),
                                                ],
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
                    );
                  }).toList(),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onToggleMasterRack != null)
                    InkWell(
                      onTap: onToggleMasterRack,
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 16, bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isMasterRack
                              ? Colors.amberAccent.withValues(alpha: 0.2)
                              : panelLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isMasterRack
                                ? Colors.amberAccent
                                : borderMain,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.speaker,
                              size: 13,
                              color: isMasterRack
                                  ? Colors.amberAccent
                                  : textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isMasterRack ? 'MASTER FX' : 'TRACK FX',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isMasterRack
                                    ? Colors.amberAccent
                                    : textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Load Effect Chain Preset',
                    color: panelDark,
                    onSelected: onApplyPreset,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'Crunch Guitar',
                        child: Text('Crunch Guitar Rig'),
                      ),
                      PopupMenuItem(
                        value: 'Vocal Polish',
                        child: Text('Vocal Polish Chain'),
                      ),
                      PopupMenuItem(
                        value: 'Lo-Fi Tape',
                        child: Text('Lo-Fi Tape Machine'),
                      ),
                      PopupMenuItem(
                        value: 'Wide Ambient',
                        child: Text('Wide Ambient Space'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'Clear Chain',
                        child: Text('Clear All Effects'),
                      ),
                    ],
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 16, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: panelLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderMain),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_fix_high,
                            size: 14,
                            color: lavenderAccent,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Presets',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onAddEffectPressed,
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: DottedBorder(
                        options: RoundedRectDottedBorderOptions(
                          color: textMuted,
                          strokeWidth: 2,
                          dashPattern: const [6, 4],
                          radius: const Radius.circular(8),
                        ),
                        child: Container(
                          width: 120,
                          height: onAddExternalPluginPressed != null ? 86 : 118,
                          decoration: BoxDecoration(
                            color: textFaint.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, color: textMuted, size: 24),
                              const SizedBox(height: 4),
                              Text(
                                'Add Effect',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onAddExternalPluginPressed != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 16),
                      child: InkWell(
                        key: const Key('add_external_plugin_btn'),
                        onTap: onAddExternalPluginPressed,
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.tealAccent.withValues(alpha: 0.65),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.extension,
                                  size: 12,
                                  color: Colors.tealAccent,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'LV2 / VST3',
                                  style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
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
            ],
          ),
        ),
      ],
    );
  }
}

