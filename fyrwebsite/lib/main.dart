import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const FyrWebsite());
}

class FyrColors {
  static const bg = Color(0xFF06060A);
  static const surface = Color(0xFF0E0E15);
  static const surfaceElevated = Color(0xFF141420);
  static const accent = Color(0xFFC084FC);
  static const accentVibrant = Color(0xFFA855F7);
  static const accentCyan = Color(0xFF67E8F9);
  static const borderSubtle = Color(0x18FFFFFF);
  static const borderAccent = Color(0x55C084FC);
}

class FyrWebsite extends StatelessWidget {
  const FyrWebsite({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fyr - frick your RAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: FyrColors.bg,
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: FyrColors.accentVibrant,
          brightness: Brightness.dark,
          surface: FyrColors.surface,
        ),
      ),
      home: const LandingPage(),
    );
  }
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scrollController = ScrollController();
  final _installKey = GlobalKey();
  final _coreKey = GlobalKey();
  final _systemKey = GlobalKey();
  final _appsKey = GlobalKey();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 24;
      if (isScrolled != _scrolled) {
        setState(() => _scrolled = isScrolled);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 680;
    final horizontalPad = isMobile ? 20.0 : (width < 1100 ? 32.0 : 48.0);

    return Scaffold(
      backgroundColor: FyrColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackdrop()),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: isMobile ? 76 : 88)),
              SliverToBoxAdapter(
                child: HeroSection(
                  onInstallTap: () => _scrollTo(_installKey),
                  onExploreTap: () => _scrollTo(_coreKey),
                ),
              ),
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _installKey,
                  child: const InstallSection(),
                ),
              ),
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _coreKey,
                  child: const SectionHeader(
                    eyebrow: 'COMPOSITOR & SHELL',
                    title: 'fyrShell',
                    subtitle: 'A modern Flutter shell built on top of Sway.',
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                sliver: const AppGrid(category: 'core'),
              ),
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _systemKey,
                  child: const SectionHeader(
                    eyebrow: 'DAILY UTILITIES',
                    title: 'fyrTools',
                    subtitle: 'All the normal things you would expect from a DE.',
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                sliver: const AppGrid(category: 'system'),
              ),
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _appsKey,
                  child: const SectionHeader(
                    eyebrow: 'CREATIVE, OFFICE & DEV',
                    title: 'fyrApps',
                    subtitle: 'Purdy apps to go with your purdy shell.',
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                sliver: const AppGrid(category: 'productivity'),
              ),
              const SliverToBoxAdapter(child: Footer()),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FloatingNavBar(
              scrolled: _scrolled,
              onLogoTap: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                );
              },
              onInstallTap: () => _scrollTo(_installKey),
              onCoreTap: () => _scrollTo(_coreKey),
              onSystemTap: () => _scrollTo(_systemKey),
              onAppsTap: () => _scrollTo(_appsKey),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 960,
                height: 540,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      FyrColors.accentVibrant.withValues(alpha: 0.22),
                      FyrColors.accentCyan.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _DotGridPainter()),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    const spacing = 32.0;
    for (double y = 16; y < size.height; y += spacing) {
      for (double x = 16; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FloatingNavBar extends StatelessWidget {
  final bool scrolled;
  final VoidCallback onLogoTap;
  final VoidCallback onInstallTap;
  final VoidCallback onCoreTap;
  final VoidCallback onSystemTap;
  final VoidCallback onAppsTap;

  const _FloatingNavBar({
    required this.scrolled,
    required this.onLogoTap,
    required this.onInstallTap,
    required this.onCoreTap,
    required this.onSystemTap,
    required this.onAppsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 28,
          vertical: 12,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 22,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scrolled
                        ? FyrColors.surface.withValues(alpha: 0.82)
                        : FyrColors.surface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scrolled
                          ? FyrColors.borderAccent.withValues(alpha: 0.45)
                          : FyrColors.borderSubtle,
                    ),
                  ),
                  child: Row(
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onLogoTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      FyrColors.accent,
                                      FyrColors.accentVibrant,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: FyrColors.accentVibrant
                                          .withValues(alpha: 0.65),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  colors: [Colors.white, FyrColors.accent],
                                ).createShader(bounds),
                                child: Text(
                                  'fyrDE',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!isMobile) ...[
                        _NavLink(label: 'fyrShell', onPressed: onCoreTap),
                        _NavLink(label: 'fyrTools', onPressed: onSystemTap),
                        _NavLink(label: 'fyrApps', onPressed: onAppsTap),
                        const SizedBox(width: 12),
                      ],
                      _PrimaryPillButton(
                        label: 'Install',
                        compact: true,
                        onPressed: onInstallTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _NavLink({required this.label, required this.onPressed});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _hovered ? Colors.white : Colors.white60,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final IconData? icon;

  const _PrimaryPillButton({
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.icon,
  });

  @override
  State<_PrimaryPillButton> createState() => _PrimaryPillButtonState();
}

class _PrimaryPillButtonState extends State<_PrimaryPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 16 : 24,
            vertical: widget.compact ? 8 : 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [FyrColors.accentVibrant, Color(0xFF7E22CE)],
            ),
            boxShadow: [
              BoxShadow(
                color: FyrColors.accentVibrant
                    .withValues(alpha: _hovered ? 0.5 : 0.28),
                blurRadius: _hovered ? 24 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.compact ? 13 : 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _GhostPillButton({required this.label, required this.onPressed});

  @override
  State<_GhostPillButton> createState() => _GhostPillButtonState();
}

class _GhostPillButtonState extends State<_GhostPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class HeroSection extends StatelessWidget {
  final VoidCallback onInstallTap;
  final VoidCallback onExploreTap;

  const HeroSection({
    super.key,
    required this.onInstallTap,
    required this.onExploreTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 680;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 20 : 48,
        horizontal: isMobile ? 18 : 32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: FyrColors.accentVibrant.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: FyrColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: FyrColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WAYLAND · SWAYFX · FLUTTER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: isMobile ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: FyrColors.accent,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2, end: 0),
              const SizedBox(height: 22),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Color(0xFFF3E8FF),
                    FyrColors.accent,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ).createShader(bounds),
                child: Text(
                  'frick your RAM.',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: isMobile ? 42 : (width < 980 ? 64 : 84),
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: isMobile ? -1.5 : -3.0,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ).animate().fadeIn(duration: 700.ms).slideY(begin: 0.25, end: 0),
              const SizedBox(height: 18),
              Text(
                'You\'ve got enough RAM. Use it.',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: isMobile ? 16 : 20,
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 160.ms, duration: 700.ms),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _PrimaryPillButton(
                    label: 'Get Started',
                    icon: Icons.terminal_rounded,
                    onPressed: onInstallTap,
                  ),
                  _GhostPillButton(
                    label: 'Explore Apps',
                    onPressed: onExploreTap,
                  ),
                ],
              ).animate().fadeIn(delay: 260.ms, duration: 700.ms),
              SizedBox(height: isMobile ? 32 : 48),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showImageLightbox(
                    context,
                    'fyrDE Desktop',
                    'SwayFX Wayland compositor with native Flutter shell',
                    'assets/screenshots/desktop.png',
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          FyrColors.accent.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.08),
                          FyrColors.accentCyan.withValues(alpha: 0.25),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              FyrColors.accentVibrant.withValues(alpha: 0.28),
                          blurRadius: 90,
                          spreadRadius: -24,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(isMobile ? 14.5 : 22.5),
                      child: Container(
                        color: FyrColors.surface,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0B0B12),
                                border: Border(
                                  bottom: BorderSide(
                                    color: FyrColors.borderSubtle,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _trafficDot(const Color(0xFFFF5252)),
                                  const SizedBox(width: 7),
                                  _trafficDot(const Color(0xFFFFAB40)),
                                  const SizedBox(width: 7),
                                  _trafficDot(const Color(0xFF69F0AE)),
                                  const Spacer(),
                                  Text(
                                    'fyrDE · swayfx',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.open_in_full_rounded,
                                    size: 13,
                                    color: Colors.white30,
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/screenshots/desktop.png',
                              fit: BoxFit.cover,
                              cacheWidth: 1440,
                              filterQuality: FilterQuality.medium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 340.ms, duration: 900.ms)
                  .scale(
                    begin: const Offset(0.96, 0.96),
                    end: const Offset(1, 1),
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 28),
              const Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  _StatChip(value: '38+', label: 'Native Flutter Apps'),
                  _StatChip(value: 'SwayFX', label: 'Blur, Corners & Slide'),
                  _StatChip(value: 'Suites', label: 'Creative · Office · Dev'),
                ],
              ).animate().fadeIn(delay: 480.ms, duration: 700.ms),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _trafficDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FyrColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FyrColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: FyrColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 40,
        isMobile ? 48 : 72,
        isMobile ? 20 : 40,
        isMobile ? 22 : 34,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            eyebrow,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: FyrColors.accent,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.jetBrainsMono(
              fontSize: isMobile ? 30 : 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              subtitle,
              style: GoogleFonts.jetBrainsMono(
                fontSize: isMobile ? 14 : 16,
                color: Colors.white60,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms);
  }
}

class AppGrid extends StatelessWidget {
  final String category;
  const AppGrid({super.key, required this.category});

  List<Map<String, String>> getApps() {
    if (category == 'core') {
      return const [
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar1.png',
        },
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar2.png',
        },
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar3.png',
        },
        {
          'name': 'fyrSearch',
          'desc': 'frickin sweet search',
          'img': 'search.png',
        },
        {
          'name': 'fyrOverview',
          'desc': 'frickin sweet overview',
          'img': 'overview.png',
        },
        {
          'name': 'Floating',
          'desc': 'frickin sweet floating manager',
          'img': 'floating.png',
        },
        {
          'name': 'Tiling',
          'desc': 'frickin sweet tiling manager',
          'img': 'tiling.png',
        },
        {
          'name': 'fyrDesktop',
          'desc': 'frickin sweet desktop',
          'img': 'desktop.png',
        },
      ];
    } else if (category == 'system') {
      return const [
        {
          'name': 'Terminal',
          'desc': 'frickin sweet terminal',
          'img': 'terminal.png',
        },
        {
          'name': 'fyrFiles',
          'desc': 'frickin sweet file manager',
          'img': 'files.png',
        },
        {
          'name': 'fyrStore',
          'desc': 'frickin sweet app store',
          'img': 'store.png',
        },
        {
          'name': 'Settings',
          'desc': 'frickin sweet settings',
          'img': 'settings.png',
        },
        {
          'name': 'fyrMonitor',
          'desc': 'frickin sweet task manager',
          'img': 'fyrmonitor.png',
        },
        {
          'name': 'fyrDisks',
          'desc': 'frickin sweet disk manager',
          'img': 'fyrdisks.png',
        },
        {'name': 'FyrAV', 'desc': 'frickin sweet antivirus', 'img': 'av.png'},
        {
          'name': 'FyrText',
          'desc': 'frickin sweet text editor',
          'img': 'text.png',
        },
        {
          'name': 'Calendar',
          'desc': 'frickin sweet calendar',
          'img': 'calendar.png',
        },
        {
          'name': 'Clock',
          'desc': 'frickin sweet clock',
          'img': 'clock.png',
        },
        {
          'name': 'Calculator',
          'desc': 'frickin sweet calculator',
          'img': 'calc.png',
        },
        {
          'name': 'fyrHelp',
          'desc': 'frickin sweet shortcut cheatsheet',
          'img': 'fyrhelp.png',
        },
        {
          'name': 'fyrEmoji',
          'desc': 'frickin sweet emoji picker',
          'img': 'fyremoji.png',
        },
      ];
    } else {
      return const [
        {'name': 'Goose', 'desc': 'frickin sweet browser', 'img': 'goose.png'},
        {
          'name': 'FyrCode',
          'desc': 'frickin sweet code editor',
          'img': 'code.png',
        },
        {
          'name': 'fyrAPI',
          'desc': 'frickin sweet API client',
          'img': 'fyrapi.png',
        },
        {
          'name': 'Music',
          'desc': 'frickin sweet music player',
          'img': 'music.png',
        },
        {'name': 'Sound Booth', 'desc': 'frickin sweet DAW', 'img': 'daw.png'},
        {
          'name': 'Journal',
          'desc': 'frickin sweet journal',
          'img': 'journal.png',
        },
        {
          'name': 'fyrConnect',
          'desc': 'frickin sweet mobile sync',
          'img': 'phone.png',
        },
        {
          'name': 'Photos',
          'desc': 'frickin sweet photo library',
          'img': 'fyrphotos.png',
        },
        {
          'name': 'Watchbox',
          'desc': 'frickin sweet video player',
          'img': 'seinfeld.png',
        },
        {'name': 'Camera', 'desc': 'frickin sweet camera', 'img': 'camera.png'},
        {
          'name': 'fyrVM',
          'desc': 'frickin sweet VM manager',
          'img': 'fyrvirt.png',
        },
        {
          'name': 'fyrTorrent',
          'desc': 'frickin sweet torrent client',
          'img': 'fyrtorrent.png',
        },
        {
          'name': 'fyrGraphics',
          'desc': 'frickin sweet image editor',
          'img': 'fyrgraphics.png',
        },
        {
          'name': 'fyrEmu',
          'desc': 'frickin sweet emulator',
          'img': 'fyremu.png',
        },
        {
          'name': 'fyrDirector',
          'desc': 'frickin sweet video editor',
          'img': 'fyrdirector.png',
        },
        {
          'name': 'fyrDocs',
          'desc': 'frickin sweet word processor',
          'img': 'fyrdocs.png',
        },
        {
          'name': 'fyrSheets',
          'desc': 'frickin sweet spreadsheets',
          'img': 'fyrsheets.png',
        },
        {
          'name': 'fyrSlides',
          'desc': 'frickin sweet presentations',
          'img': 'fyrslides.png',
        },
        {
          'name': 'fyrDB',
          'desc': 'frickin sweet database manager',
          'img': 'fyrdb.png',
        },
        {
          'name': 'fyrPods',
          'desc': 'frickin sweet container manager',
          'img': 'fyrpods.png',
        },
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = getApps();
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final cols = maxW >= 1040 ? 3 : (maxW >= 640 ? 2 : 1);
              const spacing = 22.0;
              final cardWidth = (maxW - spacing * (cols - 1)) / cols;

              return Wrap(
                alignment: WrapAlignment.center,
                spacing: spacing,
                runSpacing: spacing,
                children: apps.map((app) {
                  return SizedBox(
                    width: cardWidth,
                    child: category == 'core'
                        ? AppCard(app: app, showText: false)
                        : AspectRatio(
                            aspectRatio: 1.18,
                            child: AppCard(app: app, showText: true),
                          ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatefulWidget {
  final Map<String, String> app;
  final bool showText;
  const AppCard({super.key, required this.app, this.showText = true});

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool isHovered = false;

  void _expandImage() {
    _showImageLightbox(
      context,
      widget.app['name']!,
      widget.app['desc']!,
      'assets/screenshots/${widget.app['img']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: _expandImage,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, isHovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: isHovered ? FyrColors.surfaceElevated : FyrColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHovered
                  ? FyrColors.accent.withValues(alpha: 0.55)
                  : FyrColors.borderSubtle,
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: FyrColors.accentVibrant.withValues(alpha: 0.18),
                      blurRadius: 32,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showText)
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          scale: isHovered ? 1.03 : 1.0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: Image.asset(
                            'assets/screenshots/${widget.app['img']}',
                            fit: BoxFit.cover,
                            cacheWidth: 720,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 36,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  (isHovered
                                          ? FyrColors.surfaceElevated
                                          : FyrColors.surface)
                                      .withValues(alpha: 0.9),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  AnimatedScale(
                    scale: isHovered ? 1.02 : 1.0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: Image.asset(
                      'assets/screenshots/${widget.app['img']}',
                      fit: BoxFit.fitWidth,
                      cacheWidth: 720,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                if (widget.showText)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.app['name']!,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.app['desc']!,
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white54,
                                  fontSize: 12.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: isHovered ? 1.0 : 0.25,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(
                            Icons.north_east_rounded,
                            size: 16,
                            color: FyrColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showImageLightbox(
  BuildContext context,
  String title,
  String subtitle,
  String assetPath,
) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(dialogContext),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: FyrColors.accent.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Image.asset(assetPath, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: FyrColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: FyrColors.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.jetBrainsMono(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '· $subtitle',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: FyrColors.surface.withValues(alpha: 0.85),
              ),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
        ],
      ),
    ),
  );
}

class InstallSection extends StatefulWidget {
  const InstallSection({super.key});

  @override
  State<InstallSection> createState() => _InstallSectionState();
}

class _InstallSectionState extends State<InstallSection> {
  int _modeIndex = 0;

  static const _modes = [
    (
      label: 'Full DE',
      runCmd: './install.sh',
      note: 'Arch, Ubuntu/Debian & Fedora — installs SwayFX + all 38 apps',
    ),
    (
      label: 'Creative Suite (Ubuntu)',
      runCmd: './install_cs_ubuntu.sh',
      note: 'Sound Booth (DAW), fyrGraphics & fyrDirector standalone',
    ),
    (
      label: 'App Suites',
      runCmd: './install_suite.sh --suite creative',
      note: 'Pick creative, office, or dev suites (supports --deb)',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    final activeMode = _modes[_modeIndex];
    final fullSnippet =
        'git clone https://github.com/archieBTW/fyrDE.git\ncd fyrDE\n${activeMode.runCmd}';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 18 : 32,
        vertical: isMobile ? 10 : 20,
      ),
      child: Column(
        children: [
          const SectionHeader(
            eyebrow: 'QUICK START',
            title: 'Installation',
            subtitle: 'Get up and running with a few simple commands.',
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 18 : 28),
              decoration: BoxDecoration(
                color: FyrColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: FyrColors.accent.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: FyrColors.accentVibrant.withValues(alpha: 0.1),
                    blurRadius: 48,
                    spreadRadius: -14,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_modes.length, (i) {
                            final selected = i == _modeIndex;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => setState(() => _modeIndex = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: selected
                                        ? FyrColors.accentVibrant
                                            .withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.04),
                                    border: Border.all(
                                      color: selected
                                          ? FyrColors.accent
                                              .withValues(alpha: 0.6)
                                          : FyrColors.borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    _modes[i].label,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected
                                          ? Colors.white
                                          : Colors.white60,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      if (!isMobile) ...[
                        const SizedBox(width: 12),
                        _CopyButton(
                          textToCopy: fullSnippet,
                          label: 'Copy all',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    activeMode.note,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  SizedBox(height: isMobile ? 18 : 24),
                  const _InstallStep(
                    number: '1',
                    title: 'Clone the repository',
                    command:
                        'git clone https://github.com/archieBTW/fyrDE.git',
                  ),
                  SizedBox(height: isMobile ? 16 : 20),
                  const _InstallStep(
                    number: '2',
                    title: 'Navigate to the directory',
                    command: 'cd fyrDE',
                  ),
                  SizedBox(height: isMobile ? 16 : 20),
                  _InstallStep(
                    number: '3',
                    title: 'Run the installation script',
                    command: activeMode.runCmd,
                  ),
                  if (isMobile) ...[
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _CopyButton(
                        textToCopy: fullSnippet,
                        label: 'Copy all',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  final String number;
  final String title;
  final String command;

  const _InstallStep({
    required this.number,
    required this.title,
    required this.command,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [FyrColors.accentVibrant, Color(0xFF7E22CE)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                number,
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 11 : 13,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF07070B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FyrColors.borderSubtle),
          ),
          child: Row(
            children: [
              Text(
                '\$ ',
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white30,
                  fontSize: isMobile ? 12.5 : 14.5,
                ),
              ),
              Expanded(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      command,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrColors.accent,
                        fontSize: isMobile ? 12.5 : 14.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CopyButton(textToCopy: command),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String textToCopy;
  final String? label;

  const _CopyButton({required this.textToCopy, this.label});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
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
            horizontal: widget.label != null ? 10 : 7,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _copied
                ? const Color(0xFF22C55E).withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: _copied
                  ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                  : FyrColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 15,
                color: _copied ? const Color(0xFF4ADE80) : Colors.white60,
              ),
              if (widget.label != null) ...[
                const SizedBox(width: 6),
                Text(
                  _copied ? 'Copied' : widget.label!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _copied ? const Color(0xFF4ADE80) : Colors.white70,
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

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Container(
            padding: const EdgeInsets.only(top: 28),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: FyrColors.borderSubtle)),
            ),
            child: Column(
              children: [
                Text(
                  '© 2026 fyr - frick your RAM.',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Built with SwayFX + Flutter.',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white24,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
