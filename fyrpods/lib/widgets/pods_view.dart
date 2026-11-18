import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../services/container_engine.dart';
import '../state/pods_controller.dart';
import 'dialogs.dart';

class PodsView extends StatelessWidget {
  const PodsView({super.key});

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
                'Pods & Compose Stacks (${ctrl.pods.length})',
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
                onPressed: () => PlayKubeDialog.show(context),
                icon: const Icon(Icons.hub_rounded, size: 15),
                label: const Text('Deploy Kube YAML',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ctrl.pods.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final pod = ctrl.pods[index];
              final members = ctrl.containers
                  .where((c) => pod.containerIds.contains(c.id))
                  .toList();
              return _PodCard(pod: pod, members: members);
            },
          ),
        ),
      ],
    );
  }
}

class _PodCard extends StatelessWidget {
  final PodGroupInfo pod;
  final List<ContainerInfo> members;

  const _PodCard({required this.pod, required this.members});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PodsController>();
    final isRunning = pod.status == 'Running';
    final statusColor = isRunning
        ? const Color(0xFF10B981)
        : pod.status == 'Degraded'
            ? const Color(0xFFF59E0B)
            : const Color(0xFF6B7280);

    return Container(
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
              Icon(Icons.hub_rounded, size: 18, color: FyrTheme.accentColor),
              const SizedBox(width: 8),
              Text(
                pod.name,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  pod.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Infra: ${pod.infraId} • ${members.length} containers',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ctrl.startPod(pod.id),
                icon: const Icon(Icons.play_arrow_rounded,
                    size: 15, color: Color(0xFF10B981)),
                label: const Text('Start Pod', style: TextStyle(fontSize: 11.5)),
              ),
              TextButton.icon(
                onPressed: () => ctrl.stopPod(pod.id),
                icon: const Icon(Icons.stop_rounded,
                    size: 15, color: Color(0xFFEF4444)),
                label: const Text('Stop Pod', style: TextStyle(fontSize: 11.5)),
              ),
              TextButton.icon(
                onPressed: () => ctrl.restartPod(pod.id),
                icon: Icon(Icons.restart_alt_rounded,
                    size: 15, color: FyrTheme.textColorMuted),
                label:
                    const Text('Restart', style: TextStyle(fontSize: 11.5)),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final yaml =
                      ContainerEngine.generatePodKubeYaml(pod, members);
                  Clipboard.setData(ClipboardData(text: yaml));
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: FyrTheme.surfaceColor,
                      title: Text('Exported Kube YAML — ${pod.name}',
                          style: TextStyle(
                              fontSize: 15, color: FyrTheme.textColor)),
                      content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            yaml,
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5, color: FyrTheme.textColor),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.code_rounded, size: 14),
                label: const Text('Export Kube YAML',
                    style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: members
                .map(
                  (c) => InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      ctrl.selectContainer(c.id);
                      ctrl.setSection(PodsNavSection.containers);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: FyrTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: c.state.isRunning
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: FyrTheme.textColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${c.image})',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
