import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/pods_controller.dart';

class NetworksView extends StatelessWidget {
  const NetworksView({super.key});

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
                'Container Networks (${ctrl.networks.length})',
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
                onPressed: () => _showCreateNetworkDialog(context, ctrl),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Create Network',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ctrl.networks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final net = ctrl.networks[index];
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
                    Icon(Icons.lan_outlined,
                        size: 18, color: FyrTheme.accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                net.name,
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
                                  net.driver.toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: FyrTheme.accentColor,
                                  ),
                                ),
                              ),
                              if (net.dnsEnabled) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'aardvark-dns',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Subnet: ${net.subnet} • Gateway: ${net.gateway} • Attached: ${net.connectedContainers.length} containers',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (net.name != 'podman' && net.name != 'host')
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove Network',
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 16, color: FyrTheme.textColorMuted),
                        onPressed: () => ctrl.removeNetwork(net.id),
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

  void _showCreateNetworkDialog(BuildContext context, PodsController ctrl) {
    final nameCtrl = TextEditingController(text: 'fyr-backend-net');
    final subnetCtrl = TextEditingController(text: '10.92.0.0/24');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text('Create Container Network (Netavark)',
            style: TextStyle(fontSize: 16, color: FyrTheme.textColor)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Network Name',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subnetCtrl,
                style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'IPv4 CIDR Subnet',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                ),
              ),
            ],
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
              ctrl.createNetwork(
                name: nameCtrl.text,
                subnet: subnetCtrl.text,
              );
              Navigator.of(context).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
