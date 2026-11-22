import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/fyr_theme.dart';

class InstallSection extends StatefulWidget {
  const InstallSection({super.key});

  @override
  State<InstallSection> createState() => _InstallSectionState();
}

class _InstallSectionState extends State<InstallSection> {
  int _tabIndex = 0;
  int _suiteIndex = 0;

  static const List<String> _suiteTargets = [
    'creative',
    'office',
    'dev',
    'all',
  ];

  static const List<({String id, String label, String subtitle, IconData icon})>
      _tabs = [
    (
      id: 'full',
      label: 'Full fyrDE (Arch Linux)',
      subtitle:
          'Installs SwayFX, frosted shell, SDDM theme, fyrpak, and all 40+ native apps.',
      icon: Icons.terminal_rounded,
    ),
    (
      id: 'suites',
      label: 'Standalone Suites',
      subtitle:
          'Install Creative, Office, Dev, or All suites on Ubuntu, Arch, or Fedora (supports --deb).',
      icon: Icons.widgets_rounded,
    ),
    (
      id: 'fyrpak',
      label: 'fyrpak CLI',
      subtitle:
          'Native Go package manager, yay-compatible AUR helper, and built-in fyrDE updater.',
      icon: Icons.bolt_rounded,
    ),
  ];

  List<({String label, String command})> _activeCommands() {
    if (_tabIndex == 0) {
      return const [
        (
          label: 'Clone & enter repo',
          command: 'git clone https://github.com/archieBTW/fyrDE.git && cd fyrDE',
        ),
        (
          label: 'Run full Arch installer',
          command: 'chmod +x install.sh && ./install.sh',
        ),
        (
          label: 'Or rebuild a single app anytime',
          command: './install.sh -a fyrtaskbar',
        ),
      ];
    } else if (_tabIndex == 1) {
      final suite = _suiteTargets[_suiteIndex];
      return [
        (
          label: 'Clone & enter repo',
          command: 'git clone https://github.com/archieBTW/fyrDE.git && cd fyrDE',
        ),
        (
          label: 'Install standalone suite (Ubuntu / Arch / Fedora)',
          command: './install_suite.sh --suite $suite',
        ),
        (
          label: 'Optional: also build .deb packages',
          command: './install_suite.sh --suite $suite --deb',
        ),
      ];
    } else {
      return const [
        (
          label: 'Sync system & AUR packages',
          command: 'fyrpak -Syu',
        ),
        (
          label: 'Pull & update all fyrDE components',
          command: 'fyrpak fyr update',
        ),
        (
          label: 'Rebuild a specific Fyr app',
          command: 'fyrpak fyr rebuild <app>',
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    final activeTab = _tabs[_tabIndex];
    final commands = _activeCommands();
    final copyAllText = commands.map((e) => e.command).join('\n');

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 32,
        vertical: isMobile ? 18 : 34,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Compact Section Heading
              Column(
                crossAxisAlignment:
                    isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Text(
                    'QUICK START',
                    style: FyrFonts.mono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: FyrColors.accentCyan,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Install in minutes.',
                    style: FyrFonts.display(
                      fontSize: isMobile ? 26 : 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Go all-in on Arch Linux, pick standalone app suites on any distro, or drive updates with fyrpak.',
                    style: FyrFonts.display(
                      fontSize: isMobile ? 13 : 14.5,
                      color: Colors.white60,
                    ),
                    textAlign: isMobile ? TextAlign.left : TextAlign.center,
                  ),
                ],
              ),

              SizedBox(height: isMobile ? 14 : 22),

              // Glassmorphic Terminal Card
              Container(
                decoration: BoxDecoration(
                  color: FyrColors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: FyrColors.accent.withValues(alpha: 0.34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: FyrColors.accentVibrant.withValues(alpha: 0.14),
                      blurRadius: 48,
                      spreadRadius: -14,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top bar with install tabs
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 18,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0A0A12),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(19),
                        ),
                        border: Border(
                          bottom: BorderSide(color: FyrColors.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(_tabs.length, (i) {
                                  final tab = _tabs[i];
                                  final selected = i == _tabIndex;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        key: Key('install-tab-${tab.id}'),
                                        onTap: () =>
                                            setState(() => _tabIndex = i),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isMobile ? 10 : 13,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            color: selected
                                                ? FyrColors.accentVibrant
                                                    .withValues(alpha: 0.24)
                                                : Colors.white
                                                    .withValues(alpha: 0.04),
                                            border: Border.all(
                                              color: selected
                                                  ? FyrColors.accent
                                                      .withValues(alpha: 0.72)
                                                  : FyrColors.borderSubtle,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                tab.icon,
                                                size: 14,
                                                color: selected
                                                    ? FyrColors.accentCyan
                                                    : Colors.white54,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                tab.label,
                                                style: FyrFonts.mono(
                                                  fontSize:
                                                      isMobile ? 11.5 : 12,
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: selected
                                                      ? Colors.white
                                                      : Colors.white60,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                          if (!isMobile) ...[
                            const SizedBox(width: 10),
                            CopyCommandButton(
                              textToCopy: copyAllText,
                              label: 'Copy all',
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Body
                    Padding(
                      padding: EdgeInsets.all(isMobile ? 14 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeTab.subtitle,
                            style: FyrFonts.mono(
                              fontSize: 12,
                              color: Colors.white60,
                              height: 1.45,
                            ),
                          ),
                          if (_tabIndex == 1) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Target suite:',
                                  style: FyrFonts.mono(
                                    fontSize: 11.5,
                                    color: Colors.white54,
                                  ),
                                ),
                                ...List.generate(_suiteTargets.length, (i) {
                                  final selected = i == _suiteIndex;
                                  final target = _suiteTargets[i];
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _suiteIndex = i),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        color: selected
                                            ? FyrColors.accentCyan
                                                .withValues(alpha: 0.2)
                                            : Colors.white
                                                .withValues(alpha: 0.05),
                                        border: Border.all(
                                          color: selected
                                              ? FyrColors.accentCyan
                                              : FyrColors.borderSubtle,
                                        ),
                                      ),
                                      child: Text(
                                        '--suite $target',
                                        style: FyrFonts.mono(
                                          fontSize: 11,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? Colors.white
                                              : Colors.white60,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          ...List.generate(commands.length, (index) {
                            final item = commands[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == commands.length - 1 ? 0 : 12,
                              ),
                              child: _TerminalCommandRow(
                                step: '${index + 1}',
                                label: item.label,
                                command: item.command,
                                isMobile: isMobile,
                              ),
                            );
                          }),
                          if (isMobile) ...[
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: CopyCommandButton(
                                textToCopy: copyAllText,
                                label: 'Copy all',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalCommandRow extends StatelessWidget {
  final String step;
  final String label;
  final String command;
  final bool isMobile;

  const _TerminalCommandRow({
    required this.step,
    required this.label,
    required this.command,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [FyrColors.accentVibrant, FyrColors.accentDeep],
                ),
              ),
              child: Text(
                step,
                style: FyrFonts.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: FyrFonts.mono(
                  fontSize: isMobile ? 12 : 12.8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 11 : 14,
            vertical: isMobile ? 9 : 11,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF07070D),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: FyrColors.borderSubtle),
          ),
          child: Row(
            children: [
              Text(
                '\$ ',
                style: FyrFonts.mono(
                  color: FyrColors.accentCyan.withValues(alpha: 0.7),
                  fontSize: isMobile ? 12 : 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      command,
                      style: FyrFonts.mono(
                        color: FyrColors.accent,
                        fontSize: isMobile ? 12 : 13.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CopyCommandButton(textToCopy: command),
            ],
          ),
        ),
      ],
    );
  }
}

class CopyCommandButton extends StatefulWidget {
  final String textToCopy;
  final String? label;

  const CopyCommandButton({
    super.key,
    required this.textToCopy,
    this.label,
  });

  @override
  State<CopyCommandButton> createState() => _CopyCommandButtonState();
}

class _CopyCommandButtonState extends State<CopyCommandButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.textToCopy));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _copy,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.label != null || _copied ? 10 : 7,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _copied
                ? FyrColors.accentEmerald.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: _copied
                  ? FyrColors.accentEmerald.withValues(alpha: 0.55)
                  : FyrColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 14,
                color: _copied ? FyrColors.accentEmerald : Colors.white60,
              ),
              if (_copied || widget.label != null) ...[
                const SizedBox(width: 5),
                Text(
                  _copied ? 'Copied!' : widget.label!,
                  style: FyrFonts.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _copied ? FyrColors.accentEmerald : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
