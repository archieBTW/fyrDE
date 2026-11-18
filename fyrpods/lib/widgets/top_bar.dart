import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../state/pods_controller.dart';
import 'dialogs.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();

    return DragToMoveArea(
      child: Container(
        height: 48,
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
                Icons.layers_rounded,
                size: 14,
                color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'fyrPods',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(width: 14),
            // Runtime Selector Pill
            PopupMenuButton<ContainerRuntime>(
              tooltip: 'Switch Container Runtime',
              onSelected: ctrl.setRuntime,
              itemBuilder: (_) => ContainerRuntime.values
                  .map(
                    (rt) => PopupMenuItem(
                      value: rt,
                      child: Row(
                        children: [
                          Icon(
                            rt.isRootless
                                ? Icons.shield_outlined
                                : Icons.dns_outlined,
                            size: 15,
                            color: FyrTheme.accentColor,
                          ),
                          const SizedBox(width: 8),
                          Text(rt.label, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ctrl.activeRuntime.shortLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down_rounded,
                        size: 15, color: FyrTheme.accentColor),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Engine Health Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Text(
                '${ctrl.runningContainersCount} Running • ${ctrl.formattedTotalRam} RAM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ),
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
            _pillBtn(
              icon: Icons.cloud_download_outlined,
              label: 'Pull Image',
              onTap: () => PullImageDialog.show(context),
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.hub_outlined,
              label: 'Play Kube YAML',
              onTap: () => PlayKubeDialog.show(context),
            ),
            const SizedBox(width: 6),
            _pillBtn(
              icon: Icons.cleaning_services_outlined,
              label: 'Prune',
              onTap: ctrl.pruneUnused,
            ),
            const SizedBox(width: 8),
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
              onPressed: () => RunContainerDialog.show(context),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('+ Run Container',
                  style:
                      TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: FyrTheme.textColorMuted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor)),
          ],
        ),
      ),
    );
  }
}
