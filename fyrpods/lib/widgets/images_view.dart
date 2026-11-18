import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/pods_controller.dart';
import 'dialogs.dart';

class ImagesView extends StatelessWidget {
  const ImagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor.withValues(alpha: 0.45),
            border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Text(
                'OCI Container Images (${ctrl.images.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => BuildImageDialog.show(context),
                icon: const Icon(Icons.construction_rounded, size: 15),
                label: const Text('Build from Containerfile',
                    style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  foregroundColor:
                      FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () => PullImageDialog.show(context),
                icon: const Icon(Icons.cloud_download_rounded, size: 15),
                label: const Text('Pull Image',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ctrl.images.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final img = ctrl.images[index];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.album_outlined,
                        size: 18, color: FyrTheme.accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                img.repository,
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: FyrTheme.textColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: FyrTheme.accentColor
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  img.tag,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: FyrTheme.accentColor,
                                  ),
                                ),
                              ),
                              if (img.inUse) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'IN USE',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'sha256:${img.shortId} • ${img.layersCount} OCI layers',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      img.sizeMb >= 1024
                          ? '${(img.sizeMb / 1024).toStringAsFixed(2)} GB'
                          : '${img.sizeMb.toStringAsFixed(1)} MB',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    TextButton.icon(
                      onPressed: () => RunContainerDialog.show(
                        context,
                        initialImage: img.fullTag,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label:
                          const Text('Run', style: TextStyle(fontSize: 11.5)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove Image',
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 16, color: FyrTheme.textColorMuted),
                      onPressed: () => ctrl.removeImage(img.id),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
