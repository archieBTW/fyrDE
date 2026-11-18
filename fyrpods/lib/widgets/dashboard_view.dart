import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../state/pods_controller.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Container Engine Overview — ${ctrl.activeRuntime.label}',
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: FyrTheme.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Socket: ${ctrl.activeRuntime.socketPath} • OCI Runtime: crun 1.19 • Network Stack: netavark + aardvark-dns',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11.5,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _statTile(
                title: 'Running Containers',
                value: '${ctrl.runningContainersCount} / ${ctrl.containers.length}',
                sub: '${ctrl.pausedContainersCount} Paused • ${ctrl.stoppedContainersCount} Exited',
                icon: Icons.view_in_ar_rounded,
                color: const Color(0xFF10B981),
                onTap: () => ctrl.setSection(PodsNavSection.containers),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statTile(
                title: 'Active Pods & Stacks',
                value: '${ctrl.pods.length}',
                sub: 'Shared network & port namespaces',
                icon: Icons.hub_outlined,
                color: FyrTheme.accentColor,
                onTap: () => ctrl.setSection(PodsNavSection.pods),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statTile(
                title: 'Local OCI Images',
                value: '${ctrl.images.length}',
                sub: 'Cached in overlayfs storage',
                icon: Icons.album_outlined,
                color: const Color(0xFF3B82F6),
                onTap: () => ctrl.setSection(PodsNavSection.images),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statTile(
                title: 'Volumes & Networks',
                value: '${ctrl.volumes.length} Vols • ${ctrl.networks.length} Nets',
                sub: 'Rootless storage & bridge mesh',
                icon: Icons.storage_rounded,
                color: const Color(0xFFF59E0B),
                onTap: () => ctrl.setSection(PodsNavSection.volumes),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'TOP RESOURCE CONSUMERS',
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 10),
        ...ctrl.containers.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                ctrl.selectContainer(c.id);
                ctrl.setSection(PodsNavSection.containers);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        c.name,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        c.image,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        'CPU ${c.cpuPercent.toStringAsFixed(1)}%',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          color: FyrTheme.accentColor,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        'RAM ${c.memUsageMb.round()} MB',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statTile({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: FyrTheme.textColorMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10.5,
                color: FyrTheme.textColorMuted.withValues(alpha: 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
