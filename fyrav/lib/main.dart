import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';

class FirewallRule {
  final int? number;
  final String target;
  final String action;
  final String from;
  final bool isIpv6;

  const FirewallRule({
    this.number,
    required this.target,
    required this.action,
    required this.from,
    this.isIpv6 = false,
  });

  String get displayLine => '$target  $action  $from';
}

// Global state to keep track of security status
class SecurityState {
  static bool ufwActive = false;
  static int scanCount = 0;
  static bool isInitialised = false;
  static String lastScanLog = '';

  /// Runs a privileged command via `pkexec`.
  /// Must ONLY be called in response to an explicit user administrative action.
  static Future<ProcessResult> runRootCommand(
    String command, [
    List<String>? args,
  ]) async {
    return Process.run('pkexec', [command, ...?args]);
  }

  /// Parses `/etc/ufw/ufw.conf` for `ENABLED=yes`.
  static bool parseUfwConfEnabled(String content) {
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('=');
      if (parts.length == 2 && parts[0].trim().toUpperCase() == 'ENABLED') {
        return parts[1].trim().toLowerCase() == 'yes';
      }
    }
    return false;
  }

  /// Parses `### tuple ###` lines from `/etc/ufw/user.rules` or `user6.rules`.
  static List<FirewallRule> parseUserRulesFile(
    String content, {
    bool isIpv6 = false,
  }) {
    final rules = <FirewallRule>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('### tuple ###')) continue;
      final body = line.substring('### tuple ###'.length).trim();
      final parts = body.split(RegExp(r'\s+'));
      if (parts.length < 7) continue;

      final rawAction = parts[0].split('_').first.toUpperCase();
      final proto = parts[1].toLowerCase();
      final dport = parts[2];
      final src = parts[5];
      final rawDir = parts[6];

      String dirLabel;
      String? iface;
      if (rawDir.startsWith('out')) {
        dirLabel = 'OUT';
        if (rawDir.contains('_')) iface = rawDir.substring(rawDir.indexOf('_') + 1);
      } else if (rawDir.startsWith('fwd')) {
        dirLabel = 'FWD';
        if (rawDir.contains('_')) iface = rawDir.substring(rawDir.indexOf('_') + 1);
      } else {
        dirLabel = 'IN';
        if (rawDir.contains('_')) iface = rawDir.substring(rawDir.indexOf('_') + 1);
      }

      String target;
      if (dport == 'any') {
        target = 'Anywhere';
      } else if (proto == 'any') {
        target = dport;
      } else {
        target = '$dport/$proto';
      }
      if (iface != null && iface.isNotEmpty) {
        target = '$target on $iface';
      }
      if (isIpv6) {
        target = '$target (v6)';
      }

      String from;
      if (src == '0.0.0.0/0') {
        from = 'Anywhere';
      } else if (src == '::/0') {
        from = 'Anywhere (v6)';
      } else {
        from = src;
      }

      rules.add(
        FirewallRule(
          target: target,
          action: '$rawAction $dirLabel',
          from: from,
          isIpv6: isIpv6,
        ),
      );
    }
    return rules;
  }

  /// Parses output of `ufw status numbered`.
  static List<FirewallRule> parseNumberedStatus(String stdout) {
    final rules = <FirewallRule>[];
    final detailedPattern = RegExp(
      r'^\[\s*(\d+)\]\s+(.+?)\s{2,}((?:ALLOW|DENY|REJECT|LIMIT)(?:\s+(?:IN|OUT|FWD))?)\s+(.+)$',
    );
    final fallbackPattern = RegExp(r'^\[\s*(\d+)\]\s+(.+)$');

    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('[')) continue;

      final match = detailedPattern.firstMatch(line);
      if (match != null) {
        final num = int.tryParse(match.group(1)!);
        final target = match.group(2)!.trim();
        final action = match.group(3)!.trim();
        final from = match.group(4)!.trim();
        rules.add(
          FirewallRule(
            number: num,
            target: target,
            action: action,
            from: from,
            isIpv6: target.contains('(v6)'),
          ),
        );
        continue;
      }

      final fallback = fallbackPattern.firstMatch(line);
      if (fallback != null) {
        final num = int.tryParse(fallback.group(1)!);
        final rest = fallback.group(2)!.trim();
        rules.add(
          FirewallRule(
            number: num,
            target: rest,
            action: 'RULE',
            from: '',
            isIpv6: rest.contains('(v6)'),
          ),
        );
      }
    }
    return rules;
  }

  /// Validates a port or port range string (e.g. `22`, `443`, `1714:1764`).
  static String? validatePortSpec(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Enter a port or range (e.g. 22 or 1714:1764).';
    final single = RegExp(r'^\d+$');
    final range = RegExp(r'^(\d+):(\d+)$');
    if (single.hasMatch(value)) {
      final port = int.tryParse(value);
      if (port == null || port < 1 || port > 65535) {
        return 'Port must be between 1 and 65535.';
      }
      return null;
    }
    final rangeMatch = range.firstMatch(value);
    if (rangeMatch != null) {
      final start = int.tryParse(rangeMatch.group(1)!);
      final end = int.tryParse(rangeMatch.group(2)!);
      if (start == null ||
          end == null ||
          start < 1 ||
          end > 65535 ||
          start >= end) {
        return 'Port range must be valid (start < end, 1–65535).';
      }
      return null;
    }
    return 'Use a port number (22) or range (1714:1764).';
  }

  /// Updates UFW active state and scan history WITHOUT requiring root/pkexec.
  static Future<void> updateStatus() async {
    try {
      bool confEnabled = false;
      try {
        final confFile = File('/etc/ufw/ufw.conf');
        if (confFile.existsSync()) {
          confEnabled = parseUfwConfEnabled(await confFile.readAsString());
        }
      } catch (_) {}

      bool serviceActive = confEnabled;
      try {
        final result = await Process.run('systemctl', ['is-active', 'ufw']);
        serviceActive = result.stdout.toString().trim() == 'active';
      } catch (_) {}

      ufwActive = confEnabled && serviceActive;

      final home = Platform.environment['HOME'];
      if (home != null) {
        final logFile = File('$home/.cache/fyrav/scan_history.json');
        if (logFile.existsSync()) {
          final data = jsonDecode(logFile.readAsStringSync());
          scanCount = data['count'] ?? 0;
        }
      }
      isInitialised = true;
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  static Future<void> updateScanHistory() async {
    try {
      final cacheDir = Directory('${Platform.environment['HOME']}/.cache/fyrav');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final logFile = File('${cacheDir.path}/scan_history.json');
      int count = 0;
      if (logFile.existsSync()) {
        final data = jsonDecode(logFile.readAsStringSync());
        count = data['count'] ?? 0;
      }
      count++;
      scanCount = count;
      await logFile.writeAsString(jsonEncode({'count': count}));
    } catch (_) {}
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();

  if (args.contains('--daemon')) {
    _runDaemon();
    return;
  }

  await windowManager.ensureInitialized();

  // Unprivileged initial status check — never prompt for a password on launch.
  await SecurityState.updateStatus();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1100, 750),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrAVApp());
}

void _runDaemon() {
  debugPrint('FyrAV Daemon started...');
  final homeDir = Platform.environment['HOME'];
  if (homeDir != null) {
    Directory(homeDir).watch(recursive: true).listen((event) {
      if (event.type == FileSystemEvent.create) {
        if (_shouldScan(event.path)) {
          _scanFile(event.path);
        }
      }
    });
  }
}

bool _shouldScan(String path) {
  final fileName = path.split('/').last.toLowerCase();

  if (fileName.endsWith('.lock') ||
      fileName.endsWith('.tmp') ||
      fileName.endsWith('.swp') ||
      fileName.endsWith('.swx') ||
      fileName.endsWith('~')) {
    return false;
  }

  if (path.contains('/.git/') ||
      path.contains('/.cache/') ||
      path.contains('/.config/google-chrome/') ||
      path.contains('/.vscode/')) {
    return false;
  }

  return true;
}

Future<void> _scanFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) return;

  try {
    final result = await Process.run('clamscan', ['--no-summary', path]);
    if (result.exitCode == 1) {
      _notifyInfection(path);
    }
  } catch (_) {}
}

void _notifyInfection(String path) {
  Process.run('notify-send', [
    '-u',
    'critical',
    'FyrAV: Threat Detected!',
    'A potential threat was found in $path',
  ]);
}

class FyrAVApp extends StatelessWidget {
  const FyrAVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.themeModeNotifier,
        FyrTheme.accentColorNotifier,
      ]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FyrAV',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData.light().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: FyrTheme.bgColor,
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.light(
              primary: FyrTheme.accentColor,
              surface: FyrTheme.surfaceColor,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: FyrTheme.bgColor,
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.dark(
              primary: FyrTheme.accentColor,
              surface: FyrTheme.surfaceColor,
            ),
          ),
          home: const FyrAVMain(),
        );
      },
    );
  }
}

class FyrAVMain extends StatefulWidget {
  const FyrAVMain({super.key});

  @override
  State<FyrAVMain> createState() => _FyrAVMainState();
}

class _FyrAVMainState extends State<FyrAVMain> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _pages = [
    {'title': 'Dashboard', 'icon': Icons.dashboard_outlined},
    {'title': 'Firewall', 'icon': Icons.security_outlined},
    {'title': 'Scans', 'icon': Icons.radar_outlined},
    {'title': 'Real-time', 'icon': Icons.update_outlined},
    {'title': 'Settings', 'icon': Icons.settings_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: FyrTheme.sidebarColor,
              border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Column(
              children: [
                _buildTitleBar(),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedIndex == index;
                      return ListTile(
                        leading: Icon(
                          _pages[index]['icon'],
                          color: isSelected
                              ? FyrTheme.accentColor
                              : FyrTheme.textColorMuted,
                        ),
                        title: Text(
                          _pages[index]['title'],
                          style: TextStyle(
                            color: isSelected
                                ? FyrTheme.textColor
                                : FyrTheme.textColorMuted,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        onTap: () => setState(() => _selectedIndex = index),
                        selected: isSelected,
                        selectedTileColor: FyrTheme.accentColor.withOpacity(0.1),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: FyrTheme.contentColor,
              child: Column(
                children: [
                  _buildContentHeader(),
                  Expanded(
                    child: _buildPageContent(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildTrafficLight(
              const Color(0xFFFF5F57),
              () => windowManager.close(),
            ),
            const SizedBox(width: 8),
            _buildTrafficLight(
              const Color(0xFFFEBC2E),
              () => windowManager.minimize(),
            ),
            const SizedBox(width: 8),
            _buildTrafficLight(const Color(0xFF28C840), () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }),
            const SizedBox(width: 20),
            Icon(Icons.security, color: FyrTheme.accentColor, size: 24),
            const SizedBox(width: 12),
            const Text(
              'FyrAV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentHeader() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(
              _pages[_selectedIndex]['title'],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: FyrTheme.textColorMuted,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardPage();
      case 1:
        return const FirewallPage();
      case 2:
        return const ScansPage();
      case 3:
        return const RealtimePage();
      case 4:
        return const SettingsPage();
      default:
        return const DashboardPage();
    }
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Security Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FyrTheme.textColorMuted,
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh, color: FyrTheme.textColorMuted),
              onPressed: () async {
                setState(() => _isLoading = true);
                await SecurityState.updateStatus();
                if (mounted) setState(() => _isLoading = false);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildStatusCard(),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                'Files Scanned',
                SecurityState.scanCount == 0
                    ? 'Never'
                    : SecurityState.scanCount.toString(),
                Icons.file_present,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildInfoCard(
                'Threats Blocked',
                '0',
                Icons.block,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildInfoCard(
                'UFW Status',
                SecurityState.ufwActive ? 'Active' : 'Disabled',
                Icons.shield,
                color: SecurityState.ufwActive
                    ? FyrTheme.accentColor
                    : Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final isProtected = SecurityState.ufwActive;
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isProtected
                ? FyrTheme.accentColor.withOpacity(0.2)
                : Colors.redAccent.withOpacity(0.1),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (isProtected ? FyrTheme.accentColor : Colors.redAccent)
              .withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            isProtected
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            color: isProtected ? FyrTheme.accentColor : Colors.redAccent,
            size: 80,
          ),
          const SizedBox(height: 24),
          Text(
            isProtected
                ? 'Your system is protected'
                : 'System Attention Required',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isProtected
                ? 'All security modules are running normally'
                : 'Firewall is currently disabled',
            style: TextStyle(color: FyrTheme.textColorMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? FyrTheme.textColorMuted, size: 32),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class FirewallPage extends StatefulWidget {
  const FirewallPage({super.key});

  @override
  State<FirewallPage> createState() => _FirewallPageState();
}

class _FirewallPageState extends State<FirewallPage> {
  List<FirewallRule> _rules = [];
  bool _isLoading = false;
  bool _requiresAdminForRules = false;
  bool _loadedNumberedRules = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  /// Unprivileged rule inspection: reads `/etc/ufw/user.rules` and `user6.rules`
  /// directly without ever invoking `pkexec` or `sudo`.
  Future<void> _loadRules() async {
    await SecurityState.updateStatus();

    final parsed = <FirewallRule>[];
    bool accessDenied = false;

    for (final entry in const [
      ('/etc/ufw/user.rules', false),
      ('/etc/ufw/user6.rules', true),
    ]) {
      final file = File(entry.$1);
      try {
        if (file.existsSync()) {
          final content = await file.readAsString();
          parsed.addAll(
            SecurityState.parseUserRulesFile(content, isIpv6: entry.$2),
          );
        }
      } on FileSystemException {
        accessDenied = true;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _rules = parsed;
        _requiresAdminForRules = accessDenied && parsed.isEmpty;
        _loadedNumberedRules = false;
      });
    }
  }

  /// Privileged rule inspection: runs `ufw status numbered` via `pkexec`.
  /// ONLY called when the user explicitly clicks "Load Rules" or after an admin
  /// firewall modification.
  Future<void> _loadNumberedRules() async {
    setState(() => _isLoading = true);
    try {
      final result = await SecurityState.runRootCommand('ufw', [
        'status',
        'numbered',
      ]);
      await SecurityState.updateStatus();
      if (!mounted) return;
      if (result.exitCode == 0) {
        final stdout = result.stdout.toString();
        SecurityState.ufwActive = stdout.contains('Status: active');
        setState(() {
          _rules = SecurityState.parseNumberedStatus(stdout);
          _requiresAdminForRules = false;
          _loadedNumberedRules = true;
        });
      } else {
        final err = result.stderr.toString().trim();
        if (err.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load rules: $err')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFirewall() async {
    setState(() => _isLoading = true);
    try {
      final args = SecurityState.ufwActive ? ['disable'] : ['--force', 'enable'];
      final result = await SecurityState.runRootCommand('ufw', args);
      await SecurityState.updateStatus();
      if (!mounted) return;
      if (result.exitCode != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.stderr.toString().trim().isNotEmpty
                  ? result.stderr.toString().trim()
                  : 'Firewall update cancelled.',
            ),
          ),
        );
      } else if (_loadedNumberedRules) {
        await _loadNumberedRules();
      } else {
        await _loadRules();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRule(FirewallRule rule) async {
    if (rule.number == null) return;
    setState(() => _isLoading = true);
    try {
      final result = await SecurityState.runRootCommand('ufw', [
        '--force',
        'delete',
        '${rule.number}',
      ]);
      if (!mounted) return;
      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted rule #${rule.number}')),
        );
        await _loadNumberedRules();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.stderr.toString().trim().isNotEmpty
                  ? result.stderr.toString().trim()
                  : 'Could not delete rule.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddRuleDialog() async {
    final portController = TextEditingController();
    String selectedProto = 'tcp';
    String selectedAction = 'allow';
    String? errorText;
    final accentContrast = FyrTheme.getContrastingColor(FyrTheme.accentColor);

    final ruleArgs = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: const Text('Add Firewall Rule'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Port or Range',
                  style: TextStyle(
                    color: FyrTheme.textColorMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: portController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'e.g. 22 or 1714:1764',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Protocol',
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: selectedProto,
                            dropdownColor: FyrTheme.surfaceColor,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                              DropdownMenuItem(value: 'udp', child: Text('UDP')),
                              DropdownMenuItem(
                                value: 'any',
                                child: Text('Any (TCP+UDP)'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedProto = v);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Action',
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: selectedAction,
                            dropdownColor: FyrTheme.surfaceColor,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'allow',
                                child: Text('Allow'),
                              ),
                              DropdownMenuItem(
                                value: 'deny',
                                child: Text('Deny'),
                              ),
                              DropdownMenuItem(
                                value: 'limit',
                                child: Text('Limit'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedAction = v);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final port = portController.text.trim();
                final validationError = SecurityState.validatePortSpec(port);
                if (validationError != null) {
                  setDialogState(() => errorText = validationError);
                  return;
                }
                if (port.contains(':') && selectedProto == 'any') {
                  setDialogState(
                    () => errorText =
                        'Port ranges require TCP or UDP protocol.',
                  );
                  return;
                }
                final spec = selectedProto == 'any'
                    ? port
                    : '$port/$selectedProto';
                Navigator.pop(dialogContext, [selectedAction, spec]);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: accentContrast,
              ),
              child: const Text('Add Rule'),
            ),
          ],
        ),
      ),
    );

    portController.dispose();

    if (ruleArgs == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final result = await SecurityState.runRootCommand('ufw', ruleArgs);
      if (!mounted) return;
      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added rule: ufw ${ruleArgs.join(' ')}')),
        );
        await _loadNumberedRules();
      } else {
        final msg = result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : result.stdout.toString().trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg.isNotEmpty ? msg : 'Failed to add firewall rule.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentContrast = FyrTheme.getContrastingColor(FyrTheme.accentColor);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Firewall Protection',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SecurityState.ufwActive
                        ? 'UFW is active and filtering incoming connections'
                        : 'UFW is currently disabled',
                    style: TextStyle(
                      color: SecurityState.ufwActive
                          ? FyrTheme.textColorMuted
                          : Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: SecurityState.ufwActive,
                      onChanged: (_) => _toggleFirewall(),
                      activeColor: FyrTheme.accentColor,
                    ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                'Active Rules',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!_requiresAdminForRules)
                TextButton.icon(
                  onPressed: _isLoading ? null : _loadNumberedRules,
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                  label: Text(
                    _loadedNumberedRules ? 'Refresh Rules' : 'Manage / Delete Rules',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildRulesArea(accentContrast),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _showAddRuleDialog,
                icon: Icon(Icons.add, color: accentContrast),
                label: Text(
                  'Add Rule',
                  style: TextStyle(
                    color: accentContrast,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_requiresAdminForRules) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loadNumberedRules,
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Load Rules'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FyrTheme.textColor,
                    side: BorderSide(color: FyrTheme.dividerColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRulesArea(Color accentContrast) {
    if (_requiresAdminForRules) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 36,
                color: FyrTheme.accentColor,
              ),
              const SizedBox(height: 12),
              Text(
                'Administrator Access Required to Inspect Rules',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Firewall rules require administrator access to inspect. Toggle the firewall or click \'Load Rules\' / \'Add Rule\' to authenticate.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadNumberedRules,
                icon: Icon(Icons.lock_open, size: 16, color: accentContrast),
                label: Text(
                  'Load Rules',
                  style: TextStyle(
                    color: accentContrast,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_rules.isEmpty) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 36,
                color: FyrTheme.textColorMuted,
              ),
              const SizedBox(height: 12),
              Text(
                'No custom firewall rules configured',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Default UFW policies apply. Click "Add Rule" to allow or block specific ports.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _rules.length,
      itemBuilder: (context, index) {
        final rule = _rules[index];
        final isAllow = rule.action.startsWith('ALLOW');
        final isLimit = rule.action.startsWith('LIMIT');
        final badgeColor = isAllow
            ? Colors.greenAccent
            : (isLimit ? Colors.amber : Colors.redAccent);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Row(
            children: [
              if (rule.number != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${rule.number}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 3,
                child: Text(
                  rule.target,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rule.action,
                  style: TextStyle(
                    color: badgeColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Text(
                  rule.from,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: FyrTheme.textColorMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              if (rule.number != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.redAccent,
                  tooltip: 'Delete rule #${rule.number}',
                  onPressed: _isLoading ? null : () => _deleteRule(rule),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ScansPage extends StatefulWidget {
  const ScansPage({super.key});

  @override
  State<ScansPage> createState() => _ScansPageState();
}

class _ScansPageState extends State<ScansPage> {
  bool _isScanning = false;

  Future<void> _startClamScan() async {
    setState(() {
      _isScanning = true;
      SecurityState.lastScanLog = 'Starting ClamAV scan...\n';
    });

    final result = await Process.run('clamscan', [
      '-r',
      Platform.environment['HOME']!,
    ]);
    await SecurityState.updateScanHistory();
    if (mounted) {
      setState(() {
        _isScanning = false;
        SecurityState.lastScanLog += result.stdout.toString();
      });
    }
  }

  Future<void> _startRKHunter() async {
    setState(() {
      _isScanning = true;
      SecurityState.lastScanLog = 'Starting RKHunter scan...\n';
    });

    final result = await SecurityState.runRootCommand('rkhunter', [
      '--check',
      '--sk',
    ]);
    await SecurityState.updateScanHistory();
    if (mounted) {
      setState(() {
        _isScanning = false;
        SecurityState.lastScanLog += result.stdout.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startClamScan,
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text(
                  'Full Antivirus Scan',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startRKHunter,
                icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
                label: const Text(
                  'Rootkit Scan',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (_isScanning) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text('Scan Log', style: TextStyle(color: FyrTheme.textColorMuted)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FyrTheme.isDark ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: SingleChildScrollView(
                child: Text(
                  SecurityState.lastScanLog,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.greenAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RealtimePage extends StatefulWidget {
  const RealtimePage({super.key});

  @override
  State<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends State<RealtimePage> {
  bool _isMonitoring = false;
  final List<String> _events = [];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Real-time Monitoring',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Switch(
                value: _isMonitoring,
                onChanged: (val) => setState(() => _isMonitoring = val),
                activeColor: FyrTheme.accentColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Automatically scan files as they are created in your home folder.',
            style: TextStyle(color: FyrTheme.textColorMuted),
          ),
          const SizedBox(height: 32),
          Text(
            'Recent Activity',
            style: TextStyle(color: FyrTheme.textColorMuted),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _events.isEmpty
                ? Center(
                    child: Text(
                      'No activity recorded',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted.withOpacity(0.3),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: Icon(
                        Icons.history,
                        color: FyrTheme.textColorMuted.withOpacity(0.3),
                      ),
                      title: Text(
                        _events[index],
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        ListTile(
          title: const Text('Run as Daemon'),
          subtitle: const Text('Start monitoring service on login'),
          trailing: Switch(value: true, onChanged: (val) {}),
        ),
        const Divider(),
        const ListTile(
          title: Text('Notification Level'),
          subtitle: Text('Alert on every scan vs only on threats'),
          trailing: Icon(Icons.chevron_right),
        ),
        const Divider(),
        ListTile(
          title: const Text('Update Virus Database'),
          subtitle: const Text('Last updated: 2 hours ago'),
          trailing: TextButton(
            onPressed: () {},
            child: const Text('Update Now'),
          ),
        ),
      ],
    );
  }
}
