import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../engine/media_engine.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExportDialog(),
    );
  }

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportFormat _format = ExportFormat.mp4;
  late SequencePreset _resPreset;
  int _crf = 22;
  bool _exporting = false;
  double _progress = 0.0;
  String? _errorMsg;
  Process? _activeProcess;

  @override
  void initState() {
    super.initState();
    _resPreset = context.read<DirectorController>().sequence;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<DirectorController>();

    return Dialog(
      backgroundColor: FyrTheme.isDark ? const Color(0xFF141417) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.movie_creation_rounded,
                      color: FyrTheme.accentColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Export Video',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<ExportFormat>(
                    initialValue: _format,
                    decoration: const InputDecoration(
                      labelText: 'Container / Codec',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: ExportFormat.values
                        .map((f) =>
                            DropdownMenuItem(value: f, child: Text(f.label)))
                        .toList(),
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _format = v);
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SequencePreset>(
                    initialValue: kSequencePresets.contains(_resPreset)
                        ? _resPreset
                        : kSequencePresets.first,
                    decoration: const InputDecoration(
                      labelText: 'Resolution & Frame Rate',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: kSequencePresets
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                  '${p.name} (${p.width}×${p.height} @ ${p.fps.round()}fps)'),
                            ))
                        .toList(),
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _resPreset = v);
                          },
                  ),
                  const SizedBox(height: 14),
                  if (_format != ExportFormat.gif) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Quality (CRF)',
                            style: TextStyle(fontSize: 12)),
                        Text(
                          _crf <= 18
                              ? 'High ($_crf)'
                              : (_crf <= 24
                                  ? 'Balanced ($_crf)'
                                  : 'Compact ($_crf)'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.accentColor,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _crf.toDouble(),
                      min: 14,
                      max: 32,
                      divisions: 18,
                      activeColor: FyrTheme.accentColor,
                      onChanged: _exporting
                          ? null
                          : (v) => setState(() => _crf = v.round()),
                    ),
                  ],
                  if (_exporting) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _progress,
                      color: FyrTheme.accentColor,
                      backgroundColor: FyrTheme.cardColor,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rendering via FFmpeg... ${(_progress * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted),
                    ),
                  ],
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _errorMsg!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _activeProcess?.kill();
                      Navigator.pop(context);
                    },
                    child: Text(_exporting ? 'Abort' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor:
                          FyrTheme.getContrastingColor(FyrTheme.accentColor),
                    ),
                    onPressed: _exporting || ctrl.clips.isEmpty
                        ? null
                        : () => _beginExport(ctrl),
                    icon: const Icon(Icons.ios_share_rounded, size: 15),
                    label: const Text('Render & Save...'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _beginExport(DirectorController ctrl) async {
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export Video',
      fileName: '${ctrl.projectTitle}.${_format.ext}',
      type: FileType.custom,
      allowedExtensions: [_format.ext],
    );
    if (savePath == null) return;
    final outPath = savePath.toLowerCase().endsWith('.${_format.ext}')
        ? savePath
        : '$savePath.${_format.ext}';

    setState(() {
      _exporting = true;
      _progress = 0.0;
      _errorMsg = null;
    });

    final assetsById = {for (final a in ctrl.mediaBin) a.id: a};
    _activeProcess = await MediaEngine.startExport(
      tracks: ctrl.tracks,
      clips: ctrl.clips,
      assetsById: assetsById,
      outputPath: outPath,
      format: _format,
      width: _resPreset.width,
      height: _resPreset.height,
      fps: _resPreset.fps,
      crf: _crf,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onSuccess: () {
        if (!mounted) return;
        ctrl.setStatus('Exported $outPath');
        Navigator.pop(context);
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _exporting = false;
          _errorMsg = err;
        });
      },
    );
  }
}
