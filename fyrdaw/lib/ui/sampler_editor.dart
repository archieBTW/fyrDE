import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fyrdaw/main.dart';

import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';

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

class _SamplerEditorWidgetState extends State<SamplerEditorWidget> {
  int _selectedPadIndex = 0;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _playbackTimer = Timer.periodic(Duration(milliseconds: 30), (_) {
      if (mounted) setState(() {});
    });
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
          padding: EdgeInsets.all(16),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 16,
            itemBuilder: (context, index) {
              bool isSelected = index == _selectedPadIndex;
              bool hasSample =
                  widget.track.samplerPads[index]?.filePath != null;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedPadIndex = index);
                  var p = widget.track.samplerPads[index];
                  if (p != null) {
                    p.play();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? lavenderAccent
                        : (hasSample ? panelLight : bgDark),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? textMain : textFaint,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Pad ${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        VerticalDivider(width: 1, color: textFaint),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
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
                        FilePickerResult? result = await FilePicker.pickFiles(
                          type: FileType.audio,
                        );
                        if (result != null &&
                            result.files.single.path != null) {
                          String p = result.files.single.path!;
                          pad.filePath = p;
                          if (SoLoud.instance.isInitialized) {
                            try {
                              if (pad.source != null) {
                                SoLoud.instance.disposeSource(pad.source!);
                              }
                              pad.source = await SoLoud.instance.loadFile(p);
                              pad.source!.filters.pitchShiftFilter.activate();
                              pad.extractWaveform();
                            } catch (_) {}
                          }
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
                          String? p = await widget.onRecordSample!();
                          if (p != null) {
                            pad.filePath = p;
                            if (SoLoud.instance.isInitialized) {
                              try {
                                if (pad.source != null) {
                                  SoLoud.instance.disposeSource(pad.source!);
                                }
                                pad.source = await SoLoud.instance.loadFile(p);
                                pad.source!.filters.pitchShiftFilter.activate();
                                pad.extractWaveform();
                              } catch (_) {}
                            }
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
                    SizedBox(width: 16),
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
                SizedBox(height: 16),
                Container(
                  height: 80,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bgDark,
                    border: Border.all(color: textFaint),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Stack(
                    children: [
                      if (pad.source != null && pad.waveformData != null)
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
                      if (pad.source == null)
                        Center(
                          child: Text(
                            'No Audio Data',
                            style: TextStyle(color: textFaint),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
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
