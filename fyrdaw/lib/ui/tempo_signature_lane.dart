import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/tempo_marker.dart';

/// Compact interactive ruler strip for adding, editing, and visualizing
/// mid-song Tempo (BPM) & Time-Signature changes directly on the timeline.
class TempoSignatureLane extends StatelessWidget {
  final double baseBpm;
  final int baseNum;
  final int baseDen;
  final List<TempoMarker> markers;
  final double zoomX;
  final double snapResolution;
  final bool snapToGrid;
  final ValueChanged<TempoMarker> onAddOrUpdateMarker;
  final ValueChanged<String> onDeleteMarker;

  const TempoSignatureLane({
    super.key,
    required this.baseBpm,
    required this.baseNum,
    required this.baseDen,
    required this.markers,
    required this.zoomX,
    required this.snapResolution,
    required this.snapToGrid,
    required this.onAddOrUpdateMarker,
    required this.onDeleteMarker,
  });

  void _openMarkerDialog(
    BuildContext context, {
    required double position,
    TempoMarker? existing,
  }) {
    double editBpm = existing?.bpm ?? baseBpm;
    int editNum = existing?.numerator ?? baseNum;
    int editDen = existing?.denominator ?? baseDen;
    bool editRamp = existing?.isRamp ?? false;
    final bpmCtrl = TextEditingController(text: editBpm.round().toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: panelDark,
          title: Text(
            existing != null ? 'Edit Tempo / Meter Change' : 'Add Tempo / Meter Change',
            style: TextStyle(color: textMain, fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bpmCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: textMain, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'BPM (20 - 300)',
                        labelStyle: TextStyle(color: textMuted, fontSize: 11),
                        filled: true,
                        fillColor: bgDark,
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          editBpm = parsed.clamp(20.0, 300.0);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: '$editNum/$editDen',
                    dropdownColor: panelDark,
                    style: TextStyle(color: textMain, fontSize: 12),
                    items: const [
                      '3/4',
                      '4/4',
                      '5/4',
                      '6/4',
                      '7/4',
                      '6/8',
                      '7/8',
                    ]
                        .map(
                          (sig) => DropdownMenuItem(value: sig, child: Text(sig)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      final parts = val.split('/');
                      setModalState(() {
                        editNum = int.parse(parts[0]);
                        editDen = int.parse(parts[1]);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Gradual Tempo Ramp to Next Marker',
                  style: TextStyle(color: textMain, fontSize: 12),
                ),
                value: editRamp,
                activeThumbColor: lavenderAccent,
                onChanged: (v) => setModalState(() => editRamp = v),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  onDeleteMarker(existing.id);
                  Navigator.pop(ctx);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: lavenderAccent),
              onPressed: () {
                final marker = TempoMarker(
                  id: existing?.id ??
                      'tm_${DateTime.now().millisecondsSinceEpoch}',
                  position: existing?.position ?? position,
                  bpm: (double.tryParse(bpmCtrl.text) ?? editBpm)
                      .clamp(20.0, 300.0),
                  numerator: editNum,
                  denominator: editDen,
                  isRamp: editRamp,
                );
                onAddOrUpdateMarker(marker);
                Navigator.pop(ctx);
              },
              child: const Text('Save', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...markers]..sort((a, b) => a.position.compareTo(b.position));
    return GestureDetector(
      key: const Key('tempo_signature_lane'),
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (d) {
        double pos = max(0.0, d.localPosition.dx / zoomX);
        if (snapToGrid && snapResolution > 0) {
          pos = (pos / snapResolution).round() * snapResolution;
        }
        _openMarkerDialog(context, position: pos);
      },
      onSecondaryTapDown: (d) {
        double pos = max(0.0, d.localPosition.dx / zoomX);
        if (snapToGrid && snapResolution > 0) {
          pos = (pos / snapResolution).round() * snapResolution;
        }
        _openMarkerDialog(context, position: pos);
      },
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: bgDark.withValues(alpha: 0.92),
          border: Border(
            bottom: BorderSide(color: borderMain.withValues(alpha: 0.8)),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Base tempo badge at start of timeline
            Positioned(
              left: 4,
              top: 2,
              child: Text(
                '${baseBpm.round()} BPM · $baseNum/$baseDen (dbl-click to add change)',
                style: TextStyle(
                  color: textMuted.withValues(alpha: 0.65),
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ...sorted.map((m) {
              final leftPx = m.position * zoomX;
              return Positioned(
                left: leftPx,
                top: 1,
                child: InkWell(
                  onTap: () => _openMarkerDialog(
                    context,
                    position: m.position,
                    existing: m,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.tealAccent.withValues(alpha: 0.7),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m.isRamp ? Icons.trending_up : Icons.speed,
                          color: Colors.tealAccent,
                          size: 10,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${m.bpm.round()} · ${m.numerator}/${m.denominator}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
