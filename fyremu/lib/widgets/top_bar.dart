import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../state/emu_controller.dart';
import 'core_manager_dialog.dart';
import 'input_mapper_dialog.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();

    return DragToMoveArea(
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 14),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FyrTheme.accentColor,
                    FyrTheme.accentColor.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.sports_esports_rounded,
                size: 15,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrEmu',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            if (ctrl.isRunning && ctrl.activeRom != null) ...[
              const SizedBox(width: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ctrl.activeRom!.platform.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: ctrl.activeRom!.platform.accent
                          .withValues(alpha: 0.4)),
                ),
                child: Text(
                  ctrl.activeRom!.platform.shortLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: ctrl.activeRom!.platform.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  ctrl.activeRom!.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: FyrTheme.textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              const SizedBox(width: 12),
              if (ctrl.statusMessage != null)
                Expanded(
                  child: Text(
                    ctrl.statusMessage!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: FyrTheme.accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
            ],
            if (ctrl.isRunning) const Spacer(),
            if (ctrl.isRunning) ...[
              _pillBtn(
                icon: Icons.arrow_back_rounded,
                label: 'Library',
                onTap: ctrl.stopEmulation,
              ),
              const SizedBox(width: 6),
              _iconBtn(
                icon: ctrl.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                tip: ctrl.isPaused ? 'Resume (P)' : 'Pause (P)',
                active: ctrl.isPaused,
                onTap: ctrl.togglePause,
              ),
              _iconBtn(
                icon: Icons.restart_alt_rounded,
                tip: 'Reset Console',
                onTap: ctrl.resetGame,
              ),
              _pillBtn(
                icon: Icons.fast_forward_rounded,
                label: '${ctrl.speedMultiplier}x',
                active: ctrl.speedMultiplier > 1,
                onTap: ctrl.cycleSpeed,
              ),
              const SizedBox(width: 4),
              _iconBtn(
                icon: Icons.save_rounded,
                tip: 'Quick Save State (F5)',
                onTap: () => ctrl.saveQuickState(),
              ),
              _iconBtn(
                icon: Icons.restore_page_rounded,
                tip: 'Quick Load State (F8)',
                onTap: () => ctrl.loadQuickState(),
              ),
              const SizedBox(width: 4),
              _iconBtn(
                icon: ctrl.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                tip: ctrl.muted ? 'Unmute' : 'Mute',
                onTap: ctrl.toggleMute,
              ),
              SizedBox(
                width: 72,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 9),
                    activeTrackColor: FyrTheme.accentColor,
                    thumbColor: FyrTheme.accentColor,
                  ),
                  child: Slider(
                    value: ctrl.volume,
                    onChanged: ctrl.setVolume,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.gamepad_rounded,
              label: ctrl.connectedControllers.isNotEmpty
                  ? '${ctrl.connectedControllers.length} Pad'
                  : 'Controls',
              active: ctrl.connectedControllers.isNotEmpty,
              onTap: () => InputMapperDialog.show(context),
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.memory_rounded,
              label: 'Cores',
              onTap: () => CoreManagerDialog.show(context),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: const Size(0, 30),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final res = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'gb',
                    'gbc',
                    'gba',
                    'nes',
                    'sfc',
                    'smc',
                    'md',
                    'gen',
                    'zip',
                  ],
                );
                if (res != null && res.files.single.path != null) {
                  final ok = await ctrl.launchRomFile(res.files.single.path!);
                  if (!ok && context.mounted) {
                    await CoreManagerDialog.show(context);
                  }
                }
              },
              icon: const Icon(Icons.folder_open_rounded, size: 15),
              label: const Text('Open ROM',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
        ),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        onPressed: onTap,
      ),
    );
  }

  Widget _pillBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.16)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.5)
                : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
