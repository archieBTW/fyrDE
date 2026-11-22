import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/fyr_theme.dart';

class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -200,
            left: -120,
            right: -120,
            child: Center(
              child: Container(
                width: 980,
                height: 560,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      FyrColors.accentVibrant.withValues(alpha: 0.24),
                      FyrColors.accentCyan.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.48, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 420,
            right: -220,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    FyrColors.accentCyan.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -180,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    FyrColors.accentPink.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: CustomPaint(painter: _DotGridPainter()),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    const spacing = 34.0;
    for (double y = 16; y < size.height; y += spacing) {
      for (double x = 16; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FloatingNavBar extends StatelessWidget {
  final bool scrolled;
  final VoidCallback onLogoTap;
  final VoidCallback onOverviewTap;
  final VoidCallback onAppsTap;
  final VoidCallback onInstallTap;

  const FloatingNavBar({
    super.key,
    required this.scrolled,
    required this.onLogoTap,
    required this.onOverviewTap,
    required this.onAppsTap,
    required this.onInstallTap,
  });

  static const String _repoUrl = 'https://github.com/archieBTW/fyrDE';

  Future<void> _handleGitHubTap(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _repoUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: FyrColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: FyrColors.borderAccent),
          ),
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: FyrColors.accentEmerald,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copied GitHub URL: github.com/archieBTW/fyrDE',
                  style: FyrFonts.mono(fontSize: 12, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 680;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 28,
          vertical: isMobile ? 8 : 12,
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
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: scrolled
                        ? FyrColors.surface.withValues(alpha: 0.86)
                        : FyrColors.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scrolled
                          ? FyrColors.borderAccent.withValues(alpha: 0.55)
                          : FyrColors.borderSubtle,
                    ),
                    boxShadow: scrolled
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : const [],
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
                                      FyrColors.accentCyan,
                                      FyrColors.accentVibrant,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: FyrColors.accentVibrant
                                          .withValues(alpha: 0.7),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 9),
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  colors: [Colors.white, FyrColors.accent],
                                ).createShader(bounds),
                                child: Text(
                                  'fyrDE',
                                  style: FyrFonts.mono(
                                    fontWeight: FontWeight.w800,
                                    fontSize: isMobile ? 16 : 18,
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
                        _NavLink(label: 'Overview', onPressed: onOverviewTap),
                        _NavLink(label: 'Apps', onPressed: onAppsTap),
                        _NavLink(label: 'Install', onPressed: onInstallTap),
                        const SizedBox(width: 8),
                        GhostPillButton(
                          label: 'GitHub',
                          icon: Icons.open_in_new_rounded,
                          compact: true,
                          onPressed: () => _handleGitHubTap(context),
                        ),
                        const SizedBox(width: 8),
                        PrimaryPillButton(
                          label: 'Get fyrDE',
                          compact: true,
                          onPressed: onInstallTap,
                        ),
                      ] else ...[
                        _NavLink(
                          label: 'Apps',
                          compact: true,
                          onPressed: onAppsTap,
                        ),
                        _NavLink(
                          label: 'Install',
                          compact: true,
                          onPressed: onInstallTap,
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Copy GitHub link',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _handleGitHubTap(context),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: FyrColors.borderSubtle,
                                ),
                              ),
                              child: const Icon(
                                Icons.code_rounded,
                                size: 15,
                                color: FyrColors.accentCyan,
                              ),
                            ),
                          ),
                        ),
                      ],
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
  final bool compact;

  const _NavLink({
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

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
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: 6,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: FyrFonts.mono(
              fontSize: widget.compact ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: _hovered ? Colors.white : Colors.white70,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class FyrFooter extends StatelessWidget {
  final VoidCallback onBackToTop;

  const FyrFooter({super.key, required this.onBackToTop});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 28,
        isMobile ? 36 : 56,
        isMobile ? 16 : 28,
        isMobile ? 28 : 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Container(
            padding: const EdgeInsets.only(top: 22),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: FyrColors.borderSubtle)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'fyrDE — frick your RAM.',
                      style: FyrFonts.mono(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Built with SwayFX + native Flutter + Go + Kotlin. Zero Electron.',
                      style: FyrFonts.mono(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                GhostPillButton(
                  label: 'Back to top',
                  icon: Icons.arrow_upward_rounded,
                  compact: true,
                  onPressed: onBackToTop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
