import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';

class MediaBinPanel extends StatefulWidget {
  const MediaBinPanel({super.key});

  @override
  State<MediaBinPanel> createState() => _MediaBinPanelState();
}

class _MediaBinPanelState extends State<MediaBinPanel> {
  int _tabIndex = 0; // 0=Media, 1=Titles, 2=FX & Transitions

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FyrTheme.contentColor,
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _tabBtn('Media', Icons.video_library_rounded, 0),
                _tabBtn('Titles', Icons.title_rounded, 1),
                _tabBtn('Effects', Icons.auto_awesome_rounded, 2),
              ],
            ),
          ),
          Expanded(
            child: switch (_tabIndex) {
              0 => _buildMediaTab(ctrl),
              1 => _buildTitlesTab(ctrl),
              _ => _buildEffectsTab(ctrl),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, IconData icon, int idx) {
    final active = _tabIndex == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = idx),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? FyrTheme.accentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 13,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaTab(DirectorController ctrl) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor.withValues(alpha: 0.18),
                foregroundColor: FyrTheme.accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: FyrTheme.accentColor.withValues(alpha: 0.45)),
                ),
              ),
              onPressed: () async {
                final res = await FilePicker.pickFiles(
                  allowMultiple: true,
                  type: FileType.custom,
                  allowedExtensions: [
                    'mp4',
                    'mkv',
                    'mov',
                    'webm',
                    'avi',
                    'mp3',
                    'wav',
                    'flac',
                    'ogg',
                    'm4a',
                    'png',
                    'jpg',
                    'jpeg',
                    'webp',
                  ],
                );
                if (res != null) {
                  final paths = res.paths.whereType<String>().toList();
                  if (paths.isNotEmpty) await ctrl.importMediaFiles(paths);
                }
              },
              icon: const Icon(Icons.add_to_photos_rounded, size: 15),
              label: const Text('Import Media...',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Expanded(
          child: ctrl.mediaBin.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Import or drag & drop video, audio, or image files here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: FyrTheme.textColorMuted),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: ctrl.mediaBin.length,
                  itemBuilder: (_, i) {
                    final asset = ctrl.mediaBin[i];
                    return Draggable<MediaAsset>(
                      data: asset,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: FyrTheme.accentColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            asset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: FyrTheme.getContrastingColor(
                                  FyrTheme.accentColor),
                            ),
                          ),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onDoubleTap: () => ctrl.addAssetToTimeline(asset),
                        child: Container(
                          decoration: BoxDecoration(
                            color: FyrTheme.cardColor,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: FyrTheme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (asset.thumbnailPaths.isNotEmpty &&
                                          File(asset.thumbnailPaths.first)
                                              .existsSync())
                                        Image.file(
                                          File(asset.thumbnailPaths.first),
                                          fit: BoxFit.cover,
                                        )
                                      else
                                        Container(
                                          color: Colors.black26,
                                          child: Icon(
                                            asset.type == MediaType.audio
                                                ? Icons.audiotrack_rounded
                                                : Icons.movie_rounded,
                                            color: FyrTheme.accentColor,
                                          ),
                                        ),
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: InkWell(
                                          onTap: () =>
                                              ctrl.addAssetToTimeline(asset),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: FyrTheme.accentColor,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.add,
                                              size: 13,
                                              color:
                                                  FyrTheme.getContrastingColor(
                                                      FyrTheme.accentColor),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.7),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${asset.durationSec.toStringAsFixed(1)}s',
                                            style: const TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  asset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: FyrTheme.textColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTitlesTab(DirectorController ctrl) {
    final presets = [
      (
        'Center Bold Title',
        'Opening title centered on screen',
        TitleClipStyle(
          text: 'YOUR TITLE',
          fontSize: 72,
          bold: true,
          posYRatio: 0.5,
        ),
      ),
      (
        'Lower Third Banner',
        'Clean speaker / scene caption',
        TitleClipStyle(
          text: 'Scene Name • Subtitle',
          fontSize: 42,
          bold: true,
          bgColor: Colors.black,
          bgOpacity: 0.65,
          posYRatio: 0.82,
        ),
      ),
      (
        'Accent Pill Caption',
        'CapCut-style highlighted caption',
        TitleClipStyle(
          text: 'Highlight Caption!',
          fontSize: 46,
          bold: true,
          textColor: Colors.white,
          bgColor: FyrTheme.accentColor,
          bgOpacity: 0.88,
          posYRatio: 0.78,
        ),
      ),
      (
        'Top Header Tag',
        'Compact top-of-frame header',
        TitleClipStyle(
          text: 'CHAPTER 01',
          fontSize: 38,
          bold: true,
          posYRatio: 0.14,
        ),
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: presets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = presets[i];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => ctrl.addTitleClip(name: item.$1, style: item.$3),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.title_rounded,
                    color: FyrTheme.accentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(item.$2,
                          style: TextStyle(
                              fontSize: 10.5, color: FyrTheme.textColorMuted)),
                    ],
                  ),
                ),
                Icon(Icons.add_circle_outline,
                    size: 18, color: FyrTheme.accentColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEffectsTab(DirectorController ctrl) {
    final clip = ctrl.selectedClip;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          clip == null
              ? 'Select a clip on the timeline to apply quick looks & transitions.'
              : 'Apply to "${clip.name}"',
          style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
        ),
        const SizedBox(height: 12),
        const Text('Transitions (In)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: TransitionKind.values.map((t) {
            final active = clip?.effects.transitionIn == t;
            return ChoiceChip(
              label: Text(t.label, style: const TextStyle(fontSize: 11)),
              selected: active,
              selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
              onSelected: clip == null
                  ? null
                  : (_) {
                      clip.effects.transitionIn = t;
                      ctrl.commitEffectChange();
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Color Presets',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _fxPresetTile(ctrl, 'Normal / Reset', 0.0, 1.0, 1.0, 0.0),
        _fxPresetTile(ctrl, 'Cinema High Contrast', -0.04, 1.28, 1.15, 0.0),
        _fxPresetTile(ctrl, 'B&W Noir', -0.02, 1.35, 0.0, 0.0),
        _fxPresetTile(ctrl, 'Vibrant Pop', 0.04, 1.12, 1.48, 0.0),
        _fxPresetTile(ctrl, 'Soft Dream Blur', 0.05, 0.95, 0.9, 4.0),
      ],
    );
  }

  Widget _fxPresetTile(
    DirectorController ctrl,
    String title,
    double b,
    double c,
    double s,
    double blur,
  ) {
    final clip = ctrl.selectedClip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: clip == null
            ? null
            : () {
                clip.effects.brightness = b;
                clip.effects.contrast = c;
                clip.effects.saturation = s;
                clip.effects.blur = blur;
                ctrl.commitEffectChange();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_fix_high_rounded,
                  size: 15, color: FyrTheme.accentColor),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
