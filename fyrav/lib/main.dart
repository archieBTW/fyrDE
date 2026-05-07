import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';

// Global state to keep track of security status
class SecurityState {
  static bool ufwActive = false;
  static int scanCount = 0;
  static bool isInitialised = false;
  static String lastScanLog = '';
  static String? _password;

  static Future<bool> authenticate() async {
    try {
      final result = await Process.run('zenity', [
        '--password',
        '--title=FyrAV Authentication',
        '--text=Please enter your administrative password.'
      ]);
      if (result.exitCode == 0) {
        _password = result.stdout.toString().trim();
        return true;
      }
    } catch (e) {}
    return false;
  }

  static Future<ProcessResult> runRootCommand(String command, [List<String>? args]) async {
    if (_password == null) {
      return Process.run('pkexec', [command, ...?args]);
    }
    
    final fullArgs = args != null ? args.join(' ') : '';
    final process = await Process.start('sudo', ['-S', 'sh', '-c', '$command $fullArgs']);
    process.stdin.writeln(_password);
    await process.stdin.flush();
    
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    
    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }

  static Future<void> updateStatus() async {
    try {
      final result = await runRootCommand('ufw', ['status']);
      if (result.exitCode == 0) {
        ufwActive = result.stdout.toString().contains('Status: active');
      }

      final logFile = File('${Platform.environment['HOME']}/.cache/fyrav/scan_history.json');
      if (logFile.existsSync()) {
        final data = jsonDecode(logFile.readAsStringSync());
        scanCount = data['count'] ?? 0;
      }
      isInitialised = true;
    } catch (e) {
      print('Error updating status: $e');
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
    } catch (e) {}
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
  
  // Consolidate authentication and initial status check
  await SecurityState.authenticate();
  await SecurityState.updateStatus();

  WindowOptions windowOptions = const WindowOptions(
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
  print('FyrAV Daemon started...');
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
  
  // Ignore common lock and temporary files
  if (fileName.endsWith('.lock') || 
      fileName.endsWith('.tmp') || 
      fileName.endsWith('.swp') || 
      fileName.endsWith('.swx') ||
      fileName.endsWith('~')) {
    return false;
  }
  
  // Ignore specific high-frequency hidden files/dirs
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
    // clamscan exit codes: 
    // 0: No virus found.
    // 1: Virus(es) found.
    // 2: Some error(s) occurred.
    if (result.exitCode == 1) {
      _notifyInfection(path);
    }
  } catch (e) {}
}

void _notifyInfection(String path) {
  Process.run('notify-send', [
    '-u', 'critical',
    'FyrAV: Threat Detected!',
    'A potential threat was found in $path'
  ]);
}

class FyrAVApp extends StatelessWidget {
  const FyrAVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
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
                          color: isSelected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                        ),
                        title: Text(
                          _pages[index]['title'],
                          style: TextStyle(
                            color: isSelected ? FyrTheme.textColor : FyrTheme.textColorMuted,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            _buildTrafficLight(const Color(0xFFFF5F57), () => windowManager.close()),
            const SizedBox(width: 8),
            _buildTrafficLight(const Color(0xFFFEBC2E), () => windowManager.minimize()),
            const SizedBox(width: 8),
            _buildTrafficLight(const Color(0xFF28C840), () => windowManager.maximize()),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: FyrTheme.textColorMuted),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 0: return const DashboardPage();
      case 1: return const FirewallPage();
      case 2: return const ScansPage();
      case 3: return const RealtimePage();
      case 4: return const SettingsPage();
      default: return const DashboardPage();
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
            Text('Security Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: FyrTheme.textColorMuted)),
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
            Expanded(child: _buildInfoCard('Files Scanned', SecurityState.scanCount == 0 ? 'Never' : SecurityState.scanCount.toString(), Icons.file_present)),
            const SizedBox(width: 24),
            Expanded(child: _buildInfoCard('Threats Blocked', '0', Icons.block, color: Colors.greenAccent)),
            const SizedBox(width: 24),
            Expanded(child: _buildInfoCard('UFW Status', SecurityState.ufwActive ? 'Active' : 'Disabled', Icons.shield, color: SecurityState.ufwActive ? FyrTheme.accentColor : Colors.redAccent)),
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
            isProtected ? FyrTheme.accentColor.withOpacity(0.2) : Colors.redAccent.withOpacity(0.1),
            Colors.transparent
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: (isProtected ? FyrTheme.accentColor : Colors.redAccent).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            isProtected ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: isProtected ? FyrTheme.accentColor : Colors.redAccent,
            size: 80
          ),
          const SizedBox(height: 24),
          Text(
            isProtected ? 'Your system is protected' : 'System Attention Required',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isProtected ? 'All security modules are running normally' : 'Firewall is currently disabled',
            style: TextStyle(color: FyrTheme.textColorMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, {Color? color}) {
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
          Text(label, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
  List<String> _rules = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final result = await SecurityState.runRootCommand('ufw', ['status']);
    if (mounted) {
      setState(() {
        _rules = result.stdout.toString().split('\n').where((l) => l.contains('/')).toList();
      });
    }
  }

  Future<void> _toggleFirewall() async {
    setState(() => _isLoading = true);
    final action = SecurityState.ufwActive ? 'disable' : 'enable';
    await SecurityState.runRootCommand('ufw', [action]);
    await SecurityState.updateStatus();
    await _loadRules();
    if (mounted) setState(() => _isLoading = false);
  }

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
              const Text('Firewall Protection', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Switch(
                    value: SecurityState.ufwActive,
                    onChanged: (_) => _toggleFirewall(),
                    activeColor: FyrTheme.accentColor,
                  ),
            ],
          ),
          const SizedBox(height: 32),
          Text('Active Rules', style: TextStyle(color: FyrTheme.textColorMuted)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_rules[index], style: const TextStyle(fontFamily: 'monospace')),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add Rule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
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
    
    final result = await Process.run('clamscan', ['-r', Platform.environment['HOME']!]);
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
    
    final result = await SecurityState.runRootCommand('rkhunter', ['--check', '--sk']);
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
                label: const Text('Full Antivirus Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startRKHunter,
                icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
                label: const Text('Rootkit Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12),
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
  List<String> _events = [];

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
              const Text('Real-time Monitoring', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
          Text('Recent Activity', style: TextStyle(color: FyrTheme.textColorMuted)),
          const SizedBox(height: 16),
          Expanded(
            child: _events.isEmpty
                ? Center(child: Text('No activity recorded', style: TextStyle(color: FyrTheme.textColorMuted.withOpacity(0.3))))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: Icon(Icons.history, color: FyrTheme.textColorMuted.withOpacity(0.3)),
                      title: Text(_events[index], style: TextStyle(fontSize: 14)),
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
        ListTile(
          title: const Text('Notification Level'),
          subtitle: const Text('Alert on every scan vs only on threats'),
          trailing: const Icon(Icons.chevron_right),
        ),
        const Divider(),
        ListTile(
          title: const Text('Update Virus Database'),
          subtitle: const Text('Last updated: 2 hours ago'),
          trailing: TextButton(onPressed: () {}, child: const Text('Update Now')),
        ),
      ],
    );
  }
}
