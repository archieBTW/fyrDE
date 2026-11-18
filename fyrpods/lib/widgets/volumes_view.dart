import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/pods_controller.dart';

class VolumesView extends StatelessWidget {
  const VolumesView({super.key});

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
                'Persistent Volumes (${ctrl.volumes.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  foregroundColor:
                      FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () => _showCreateVolumeDialog(context, ctrl),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Create Volume',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ctrl.volumes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final vol = ctrl.volumes[index];
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
                    Icon(Icons.storage_rounded,
                        size: 18, color: FyrTheme.accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                vol.name,
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
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  vol.driver,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: FyrTheme.accentColor,
                                  ),
                                ),
                              ),
                              if (vol.attachedContainers.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Mounted by: ${vol.attachedContainers.join(", ")}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: const Color(0xFF10B981),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            vol.mountpoint,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: FyrTheme.textColorMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      vol.sizeMb >= 1024
                          ? '${(vol.sizeMb / 1024).toStringAsFixed(2)} GB'
                          : '${vol.sizeMb.toStringAsFixed(1)} MB',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove Volume',
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 16, color: FyrTheme.textColorMuted),
                      onPressed: () => ctrl.removeVolume(vol.name),
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

  void _showCreateVolumeDialog(BuildContext context, PodsController ctrl) {
    final nameCtrl = TextEditingController(text: 'fyr-cache-vol');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text('Create Persistent Volume',
            style: TextStyle(fontSize: 16, color: FyrTheme.textColor)),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: nameCtrl,
            style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
            decoration: InputDecoration(
              labelText: 'Volume Name',
              labelStyle: TextStyle(color: FyrTheme.textColorMuted),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor:
                  FyrTheme.getContrastingColor(FyrTheme.accentColor),
            ),
            onPressed: () {
              ctrl.createVolume(name: nameCtrl.text);
              Navigator.of(context).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
