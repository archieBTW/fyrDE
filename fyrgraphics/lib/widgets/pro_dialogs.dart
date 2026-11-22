import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../engine/pro_pixel_ops.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';

class ProDialogs {
  // ---------------------------------------------------------------------------
  // Interactive Tone Curves Dialog (Master RGB, Red, Green, Blue)
  // ---------------------------------------------------------------------------

  static Future<void> showToneCurves(
    BuildContext context,
    EditorController ctrl,
  ) async {
    final layer = ctrl.activeDoc?.activeLayer;
    if (layer == null) return;

    ctrl.beginLayerPreview();
    final baseHist = ProPixelOps.computeHistogram(layer.pixels);

    int activeChannel = 0; // 0=RGB, 1=R, 2=G, 3=B
    final channelPoints = <int, List<Offset>>{
      0: [const Offset(0, 0), const Offset(0.5, 0.5), const Offset(1, 1)],
      1: [const Offset(0, 0), const Offset(1, 1)],
      2: [const Offset(0, 0), const Offset(1, 1)],
      3: [const Offset(0, 0), const Offset(1, 1)],
    };
    int? draggingIdx;

    void applyPreview() {
      final mLut = ProPixelOps.buildCurveLut(channelPoints[0]!);
      final rLut = ProPixelOps.buildCurveLut(channelPoints[1]!);
      final gLut = ProPixelOps.buildCurveLut(channelPoints[2]!);
      final bLut = ProPixelOps.buildCurveLut(channelPoints[3]!);
      ctrl.applyPreviewTransform(
        (src, w, h, mask) => ProPixelOps.applyCurvesLut(
          src,
          masterLut: mLut,
          rLut: rLut,
          gLut: gLut,
          bLut: bLut,
          selectionMask: mask,
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final pts = channelPoints[activeChannel]!;
          final channelColor = switch (activeChannel) {
            1 => Colors.redAccent,
            2 => Colors.greenAccent,
            3 => Colors.lightBlueAccent,
            _ => FyrTheme.accentColor,
          };

          void setPreset(String preset) {
            setState(() {
              if (preset == 'Reset') {
                channelPoints[0] = [
                  const Offset(0, 0),
                  const Offset(0.5, 0.5),
                  const Offset(1, 1),
                ];
                channelPoints[1] = [const Offset(0, 0), const Offset(1, 1)];
                channelPoints[2] = [const Offset(0, 0), const Offset(1, 1)];
                channelPoints[3] = [const Offset(0, 0), const Offset(1, 1)];
              } else if (preset == 'S-Curve') {
                channelPoints[activeChannel] = [
                  const Offset(0, 0),
                  const Offset(0.25, 0.18),
                  const Offset(0.5, 0.5),
                  const Offset(0.75, 0.84),
                  const Offset(1, 1),
                ];
              } else if (preset == 'Matte Lift') {
                channelPoints[activeChannel] = [
                  const Offset(0, 0.12),
                  const Offset(0.35, 0.36),
                  const Offset(0.75, 0.78),
                  const Offset(1, 0.94),
                ];
              } else if (preset == 'Brighten') {
                channelPoints[activeChannel] = [
                  const Offset(0, 0),
                  const Offset(0.45, 0.62),
                  const Offset(1, 1),
                ];
              }
            });
            applyPreview();
          }

          return AlertDialog(
            backgroundColor: FyrTheme.surfaceColor,
            title: Row(
              children: [
                Icon(Icons.show_chart_rounded,
                    color: FyrTheme.accentColor, size: 20),
                const SizedBox(width: 8),
                const Text('Tone Curves', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final entry in [
                        (0, 'RGB', FyrTheme.accentColor),
                        (1, 'Red', Colors.redAccent),
                        (2, 'Green', Colors.greenAccent),
                        (3, 'Blue', Colors.lightBlueAccent),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2,
                              style: const TextStyle(fontSize: 11)),
                          selected: activeChannel == entry.$1,
                          selectedColor: entry.$3.withValues(alpha: 0.25),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => activeChannel = entry.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 280,
                    height: 240,
                    child: LayoutBuilder(
                      builder: (_, box) {
                        Offset toLocal(Offset norm) => Offset(
                              norm.dx * box.maxWidth,
                              (1.0 - norm.dy) * box.maxHeight,
                            );
                        Offset toNorm(Offset local) => Offset(
                              (local.dx / box.maxWidth).clamp(0.0, 1.0),
                              (1.0 - local.dy / box.maxHeight).clamp(0.0, 1.0),
                            );

                        return GestureDetector(
                          onPanDown: (d) {
                            final pos = d.localPosition;
                            int? hit;
                            double best = 18.0;
                            for (int i = 0; i < pts.length; i++) {
                              final dist = (toLocal(pts[i]) - pos).distance;
                              if (dist < best) {
                                best = dist;
                                hit = i;
                              }
                            }
                            if (hit != null) {
                              draggingIdx = hit;
                            } else if (pts.length < 8) {
                              final n = toNorm(pos);
                              setState(() {
                                pts.add(n);
                                pts.sort((a, b) => a.dx.compareTo(b.dx));
                                draggingIdx = pts.indexOf(n);
                              });
                              applyPreview();
                            }
                          },
                          onPanUpdate: (d) {
                            if (draggingIdx == null) return;
                            final idx = draggingIdx!;
                            final n = toNorm(d.localPosition);
                            setState(() {
                              if (idx == 0) {
                                pts[0] = Offset(0.0, n.dy);
                              } else if (idx == pts.length - 1) {
                                pts[idx] = Offset(1.0, n.dy);
                              } else {
                                final minX = pts[idx - 1].dx + 0.03;
                                final maxX = pts[idx + 1].dx - 0.03;
                                pts[idx] = Offset(
                                  n.dx.clamp(minX, maxX),
                                  n.dy,
                                );
                              }
                            });
                            applyPreview();
                          },
                          onPanEnd: (_) => draggingIdx = null,
                          onSecondaryTapDown: (d) {
                            // Right-click interior point to remove it
                            for (int i = 1; i < pts.length - 1; i++) {
                              if ((toLocal(pts[i]) - d.localPosition).distance <
                                  16) {
                                setState(() => pts.removeAt(i));
                                applyPreview();
                                break;
                              }
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CustomPaint(
                              painter: _CurveEditorPainter(
                                points: pts,
                                lut: ProPixelOps.buildCurveLut(pts),
                                curveColor: channelColor,
                                histogram: baseHist,
                                channelIndex: activeChannel,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Click curve to add point • Drag to shape • Right-click point to remove',
                    style: TextStyle(
                      fontSize: 10,
                      color: FyrTheme.textColorMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in ['S-Curve', 'Matte Lift', 'Brighten', 'Reset'])
                        ActionChip(
                          label: Text(p, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setPreset(p),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Tone Curves');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  // ---------------------------------------------------------------------------
  // Quick Develop / Photo Adjust Dialog (Lightroom-style Develop Controls)
  // ---------------------------------------------------------------------------

  static Future<void> showDevelopAdjust(
    BuildContext context,
    EditorController ctrl, {
    bool simpleMode = false,
  }) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();

    double exposure = 0.0;
    double contrast = 0.0;
    double highlights = 0.0;
    double shadows = 0.0;
    double temperature = 0.0;
    double tint = 0.0;
    double vibrance = 0.0;
    double saturation = 0.0;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, mask) => ProPixelOps.adjustDevelop(
          src,
          exposure: exposure,
          contrast: contrast,
          highlights: highlights,
          shadows: shadows,
          temperature: temperature,
          tint: tint,
          vibrance: vibrance,
          saturation: saturation,
          selectionMask: mask,
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                simpleMode ? 'Quick Photo Adjust' : 'Develop & Tone',
                style: const TextStyle(fontSize: 16),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    exposure = 0;
                    contrast = 0;
                    highlights = 0;
                    shadows = 0;
                    temperature = 0;
                    tint = 0;
                    vibrance = 0;
                    saturation = 0;
                  });
                  preview();
                },
                child: const Text('Reset', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sliderRow('Exposure', '${exposure >= 0 ? '+' : ''}${exposure.toStringAsFixed(2)} EV',
                      exposure, -1.8, 1.8, (v) {
                    setState(() => exposure = v);
                    preview();
                  }),
                  _sliderRow('Contrast', '${(contrast * 100).round()}%',
                      contrast, -1.0, 1.0, (v) {
                    setState(() => contrast = v);
                    preview();
                  }),
                  if (!simpleMode) ...[
                    _sliderRow('Highlights', '${(highlights * 100).round()}%',
                        highlights, -1.0, 1.0, (v) {
                      setState(() => highlights = v);
                      preview();
                    }),
                    _sliderRow('Shadows', '${(shadows * 100).round()}%',
                        shadows, -1.0, 1.0, (v) {
                      setState(() => shadows = v);
                      preview();
                    }),
                  ],
                  _sliderRow('Warmth / Temp', '${(temperature * 100).round()}',
                      temperature, -1.0, 1.0, (v) {
                    setState(() => temperature = v);
                    preview();
                  }),
                  if (!simpleMode)
                    _sliderRow('Tint (G ↔ M)', '${(tint * 100).round()}',
                        tint, -1.0, 1.0, (v) {
                      setState(() => tint = v);
                      preview();
                    }),
                  _sliderRow('Vibrance', '${(vibrance * 100).round()}%',
                      vibrance, -1.0, 1.0, (v) {
                    setState(() => vibrance = v);
                    preview();
                  }),
                  _sliderRow('Saturation', '${(saturation * 100).round()}%',
                      saturation, -1.0, 1.0, (v) {
                    setState(() => saturation = v);
                    preview();
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview(simpleMode ? 'Quick Adjust' : 'Develop & Tone');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  // ---------------------------------------------------------------------------
  // Photo Looks / LUT Presets Dialog
  // ---------------------------------------------------------------------------

  static Future<void> showPhotoLooks(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();

    ColorLookPreset selected = ColorLookPreset.warmFilm;
    double intensity = 0.85;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, mask) => ProPixelOps.applyColorLookPreset(
          src,
          selected,
          intensity: intensity,
          selectionMask: mask,
        ),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Photo Looks & Color Grades',
              style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ColorLookPreset.values.map((look) {
                    final active = look == selected;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() => selected = look);
                        preview();
                      },
                      child: Container(
                        width: 185,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: active
                              ? FyrTheme.accentColor.withValues(alpha: 0.18)
                              : FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active
                                ? FyrTheme.accentColor
                                : FyrTheme.dividerColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              look.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              look.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: FyrTheme.textColorMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                _sliderRow(
                  'Intensity',
                  '${(intensity * 100).round()}%',
                  intensity,
                  0.0,
                  1.0,
                  (v) {
                    setState(() => intensity = v);
                    preview();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply Look'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Look: ${selected.label}');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  // ---------------------------------------------------------------------------
  // Pro Filters: Motion Blur, Radial Blur, Unsharp Mask, Chromatic Aberration, Halftone
  // ---------------------------------------------------------------------------

  static Future<void> showMotionBlur(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();
    double distance = 16;
    double angle = 0;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, _) => ProPixelOps.motionBlur(
          src,
          w,
          h,
          distance: distance,
          angleDeg: angle,
        ),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Motion Blur', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sliderRow('Distance', '${distance.round()} px', distance, 2, 50,
                    (v) {
                  setState(() => distance = v);
                  preview();
                }),
                _sliderRow('Angle', '${angle.round()}°', angle, 0, 360, (v) {
                  setState(() => angle = v);
                  preview();
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Motion Blur');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  static Future<void> showRadialBlur(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();
    double strength = 0.14;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, _) =>
            ProPixelOps.radialZoomBlur(src, w, h, strength: strength),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title:
              const Text('Radial Zoom Blur', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: _sliderRow(
              'Strength',
              '${(strength * 100).round()}%',
              strength,
              0.02,
              0.35,
              (v) {
                setState(() => strength = v);
                preview();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Radial Zoom Blur');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  static Future<void> showUnsharpMask(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();
    double amount = 1.1;
    double radius = 2.0;
    double threshold = 4.0;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, _) => ProPixelOps.unsharpMask(
          src,
          w,
          h,
          amount: amount,
          radius: radius,
          threshold: threshold.round(),
        ),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Unsharp Mask', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sliderRow(
                    'Amount', '${(amount * 100).round()}%', amount, 0.2, 3.0,
                    (v) {
                  setState(() => amount = v);
                  preview();
                }),
                _sliderRow(
                    'Radius', '${radius.toStringAsFixed(1)} px', radius, 0.8, 10,
                    (v) {
                  setState(() => radius = v);
                  preview();
                }),
                _sliderRow('Threshold', '${threshold.round()}', threshold, 0, 30,
                    (v) {
                  setState(() => threshold = v);
                  preview();
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Unsharp Mask');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  static Future<void> showChromaticAberration(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();
    double shift = 6;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, _) =>
            ProPixelOps.chromaticAberration(src, w, h, shiftPx: shift.round()),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Chromatic Aberration',
              style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: _sliderRow('RGB Shift', '${shift.round()} px', shift, -25, 25,
                (v) {
              setState(() => shift = v);
              preview();
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Chromatic Aberration');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  static Future<void> showHalftone(
    BuildContext context,
    EditorController ctrl,
  ) async {
    if (ctrl.activeDoc?.activeLayer == null) return;
    ctrl.beginLayerPreview();
    double cellSize = 10;
    bool colorMode = true;

    void preview() {
      ctrl.applyPreviewTransform(
        (src, w, h, _) => ProPixelOps.halftoneDots(
          src,
          w,
          h,
          cellSize: cellSize.round(),
          colorMode: colorMode,
        ),
      );
    }

    preview();

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Halftone Dot Screen',
              style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sliderRow('Dot Size', '${cellSize.round()} px', cellSize, 4, 28,
                    (v) {
                  setState(() => cellSize = v);
                  preview();
                }),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Color Dots', style: TextStyle(fontSize: 13)),
                  value: colorMode,
                  activeThumbColor: FyrTheme.accentColor,
                  onChanged: (v) {
                    setState(() => colorMode = v);
                    preview();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      ctrl.commitLayerPreview('Halftone');
    } else {
      await ctrl.cancelLayerPreview();
    }
  }

  // ---------------------------------------------------------------------------
  // Selection Operations: Feather, Expand/Contract, Stroke
  // ---------------------------------------------------------------------------

  static Future<void> showFeatherSelection(
    BuildContext context,
    EditorController ctrl,
  ) async {
    double radius = 8;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Feather Selection', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 300,
            child: _sliderRow('Feather Radius', '${radius.round()} px', radius, 1, 60,
                (v) => setState(() => radius = v)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Feather')),
          ],
        ),
      ),
    );
    if (ok == true) {
      ctrl.featherSelection(radius);
    }
  }

  static Future<void> showModifySelection(
    BuildContext context,
    EditorController ctrl,
  ) async {
    double delta = 4;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Expand / Contract Selection',
              style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 300,
            child: _sliderRow(
              delta >= 0 ? 'Expand' : 'Contract',
              '${delta >= 0 ? '+' : ''}${delta.round()} px',
              delta,
              -25,
              25,
              (v) => setState(() => delta = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok == true && delta.round() != 0) {
      ctrl.expandOrContractSelection(delta.round());
    }
  }

  static Future<void> showStrokeSelection(
    BuildContext context,
    EditorController ctrl,
  ) async {
    double width = 4;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Stroke Selection', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sliderRow('Stroke Width', '${width.round()} px', width, 1, 30,
                    (v) => setState(() => width = v)),
                const SizedBox(height: 6),
                Text(
                  'Uses current Foreground Color',
                  style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Stroke')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ctrl.strokeSelection(width.round());
    }
  }

  static Widget _sliderRow(
    String label,
    String valueText,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: FyrTheme.textColor)),
              Text(valueText,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.accentColor)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: FyrTheme.accentColor,
              thumbColor: FyrTheme.accentColor,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurveEditorPainter extends CustomPainter {
  final List<Offset> points;
  final Uint8List lut;
  final Color curveColor;
  final HistogramData histogram;
  final int channelIndex;

  _CurveEditorPainter({
    required this.points,
    required this.lut,
    required this.curveColor,
    required this.histogram,
    required this.channelIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF141418),
    );

    // 4x4 grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Background histogram
    final bins = switch (channelIndex) {
      1 => histogram.r,
      2 => histogram.g,
      3 => histogram.b,
      _ => histogram.luma,
    };
    final histPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < 256; i++) {
      final x = (i / 255.0) * size.width;
      final h = (bins[i] / max(1, histogram.maxCount)).clamp(0.0, 1.0) *
          size.height *
          0.75;
      histPath.lineTo(x, size.height - h);
    }
    histPath.lineTo(size.width, size.height);
    histPath.close();
    canvas.drawPath(
      histPath,
      Paint()..color = curveColor.withValues(alpha: 0.14),
    );

    // Baseline diagonal
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1,
    );

    // Spline curve from LUT
    final curvePath = Path();
    for (int i = 0; i < 256; i++) {
      final x = (i / 255.0) * size.width;
      final y = (1.0 - lut[i] / 255.0) * size.height;
      if (i == 0) {
        curvePath.moveTo(x, y);
      } else {
        curvePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Control handles
    for (final pt in points) {
      final pos = Offset(pt.dx * size.width, (1.0 - pt.dy) * size.height);
      canvas.drawCircle(pos, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        pos,
        5.5,
        Paint()
          ..color = curveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurveEditorPainter old) => true;
}
