import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../state/pods_controller.dart';

class SidebarNav extends StatelessWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();

    return Container(
      width: 215,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text(
              'RESOURCES',
              style: GoogleFonts.outfit(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: FyrTheme.textColorMuted.withValues(alpha: 0.65),
              ),
            ),
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.dashboard,
            icon: Icons.space_dashboard_outlined,
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.containers,
            icon: Icons.view_in_ar_rounded,
            badge: '${ctrl.containers.length}',
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.pods,
            icon: Icons.hub_outlined,
            badge: '${ctrl.pods.length}',
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.images,
            icon: Icons.album_outlined,
            badge: '${ctrl.images.length}',
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.volumes,
            icon: Icons.storage_rounded,
            badge: '${ctrl.volumes.length}',
          ),
          _navItem(
            ctrl: ctrl,
            section: PodsNavSection.networks,
            icon: Icons.lan_outlined,
            badge: '${ctrl.networks.length}',
          ),
          const Spacer(),
          // Aggregate Resource Telemetry Card
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 14, color: FyrTheme.accentColor),
                    const SizedBox(width: 5),
                    Text(
                      'ENGINE TELEMETRY',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: FyrTheme.textColorMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _metricBar(
                  label: 'Total CPU',
                  valueText: '${ctrl.totalCpuPercent.toStringAsFixed(1)}%',
                  fraction: (ctrl.totalCpuPercent / 100.0).clamp(0.0, 1.0),
                  color: FyrTheme.accentColor,
                ),
                const SizedBox(height: 8),
                _metricBar(
                  label: 'Memory',
                  valueText: ctrl.formattedTotalRam,
                  fraction:
                      (ctrl.totalMemUsageMb / 24576.0).clamp(0.0, 1.0),
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 8),
                Text(
                  ctrl.activeRuntime.socketPath,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    color: FyrTheme.textColorMuted.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required PodsController ctrl,
    required PodsNavSection section,
    required IconData icon,
    String? badge,
  }) {
    final isSelected = ctrl.activeSection == section;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => ctrl.setSection(section),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? FyrTheme.accentColor.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? FyrTheme.accentColor
                    : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? FyrTheme.textColor
                        : FyrTheme.textColorMuted,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? FyrTheme.accentColor.withValues(alpha: 0.25)
                        : FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricBar({
    required String label,
    required String valueText,
    required double fraction,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
            Text(
              valueText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: FyrTheme.dividerColor,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
