import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../engine/core_manager.dart';
import '../fyr_theme.dart';
import '../models/emu_types.dart';
import '../state/emu_controller.dart';

class CoreManagerDialog extends StatelessWidget {
  const CoreManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CoreManagerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();

    return Dialog(
      backgroundColor: FyrTheme.isDark ? const Color(0xFF141417) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 580,
        height: 520,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.memory_rounded,
                      color: FyrTheme.accentColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Libretro Emulation Cores',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final res = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['so'],
                      );
                      if (res != null && res.files.single.path != null) {
                        await ctrl.importCoreFile(res.files.single.path!);
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Import .so',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: kRecommendedCores.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final spec = kRecommendedCores[i];
                  final installedPath = CoreManager.findCoreFile(spec.filename);
                  final isDownloading = ctrl.downloadingCores.contains(spec.id);

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: installedPath != null
                            ? Colors.greenAccent.withValues(alpha: 0.35)
                            : FyrTheme.dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    spec.name,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ...spec.platforms.map((p) => Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color:
                                              p.accent.withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          p.shortLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: p.accent,
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                spec.description,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: FyrTheme.textColorMuted,
                                ),
                              ),
                              if (installedPath != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    installedPath,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.greenAccent
                                          .withValues(alpha: 0.85),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (isDownloading)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (installedPath != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 14, color: Colors.greenAccent),
                                SizedBox(width: 5),
                                Text('Installed',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        else
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: FyrTheme.accentColor,
                              foregroundColor: FyrTheme.getContrastingColor(
                                  FyrTheme.accentColor),
                            ),
                            onPressed: () => ctrl.downloadRecommendedCore(spec),
                            icon: const Icon(Icons.download_rounded, size: 15),
                            label: const Text('Install',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cores stored in ~/.config/fyr/cores & /usr/lib/libretro',
                      style: TextStyle(
                          fontSize: 11, color: FyrTheme.textColorMuted),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor:
                          FyrTheme.getContrastingColor(FyrTheme.accentColor),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
