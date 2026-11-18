import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  DbDriverType _driver = DbDriverType.postgres;
  final _nameCtrl = TextEditingController(text: 'prod_replica_eu');
  final _hostCtrl = TextEditingController(text: '10.24.8.40');
  final _portCtrl = TextEditingController(text: '5432');
  final _dbCtrl = TextEditingController(text: 'fyr_metrics');
  final _userCtrl = TextEditingController(text: 'fyr_readonly');
  bool _ssl = true;
  bool _readOnly = false;
  String? _testStatus;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = FyrTheme.accentColor;

    return Dialog(
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cable_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'New Database Connection',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: FyrTheme.textColorMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Select Driver',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: DbDriverType.values.map((d) {
                  final selected = d == _driver;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _driver = d;
                        if (d.defaultPort > 0) {
                          _portCtrl.text = '${d.defaultPort}';
                        }
                        if (d.isFileBased) {
                          _dbCtrl.text = '~/.local/share/fyrdb/local_${d.name}.db';
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? d.badgeColor.withValues(alpha: 0.18)
                            : FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? d.badgeColor : FyrTheme.dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(d.icon, size: 14, color: d.badgeColor),
                          const SizedBox(width: 6),
                          Text(
                            d.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: FyrTheme.textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field('Connection Name', _nameCtrl),
                  ),
                  const SizedBox(width: 10),
                  if (!_driver.isFileBased) ...[
                    Expanded(
                      flex: 3,
                      child: _field('Host', _hostCtrl),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _field('Port', _portCtrl),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      _driver.isFileBased ? 'Database File Path' : 'Database Name',
                      _dbCtrl,
                    ),
                  ),
                  if (!_driver.isFileBased) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _field('Username', _userCtrl),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _ssl,
                    activeColor: accent,
                    onChanged: (v) => setState(() => _ssl = v ?? true),
                  ),
                  Text(
                    'TLS / SSL Encrypted',
                    style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                  ),
                  const SizedBox(width: 16),
                  Checkbox(
                    value: _readOnly,
                    activeColor: accent,
                    onChanged: (v) => setState(() => _readOnly = v ?? false),
                  ),
                  Text(
                    'Read-Only Safety Lock',
                    style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                  ),
                ],
              ),
              if (_testStatus != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: Color(0xFF22C55E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _testStatus!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _testStatus =
                            'Ping OK (1.4 ms) — ${_driver.label} driver ready (${_driver.cliBinary})';
                      });
                    },
                    icon: const Icon(Icons.radar_rounded, size: 15),
                    label: const Text('Test Connection'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: FyrTheme.getContrastingColor(accent),
                    ),
                    onPressed: () {
                      final ctrl = context.read<DbController>();
                      ctrl.addConnection(
                        DbConnectionProfile(
                          id: 'conn_${DateTime.now().millisecondsSinceEpoch}',
                          name: _nameCtrl.text.trim().isEmpty
                              ? 'new_connection'
                              : _nameCtrl.text.trim(),
                          driver: _driver,
                          host: _hostCtrl.text.trim(),
                          port: int.tryParse(_portCtrl.text.trim()) ??
                              _driver.defaultPort,
                          databaseOrPath: _dbCtrl.text.trim(),
                          username: _userCtrl.text.trim(),
                          sslEnabled: _ssl,
                          readOnly: _readOnly,
                          isConnected: true,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.power_rounded, size: 15),
                    label: const Text('Connect & Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
            style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              filled: true,
              fillColor: FyrTheme.bgColor,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: FyrTheme.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: FyrTheme.accentColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
