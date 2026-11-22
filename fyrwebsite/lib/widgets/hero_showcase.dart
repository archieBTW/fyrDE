import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/fyr_catalog.dart';
import '../theme/fyr_theme.dart';
import 'app_explorer.dart';

class HeroSection extends StatefulWidget {
  final VoidCallback onInstallTap;
  final VoidCallback onExploreTap;

  const HeroSection({
    super.key,
    required this.onInstallTap,
    required this.onExploreTap,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  int _activeShowcase = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 680;
    final activeItem = fyrDesktopShowcases[_activeShowcase];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 32,
        isMobile ? 10 : 28,
        isMobile ? 16 : 32,
        isMobile ? 20 : 36,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            children: [
              // Eyebrow pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FyrColors.accentVibrant.withValues(alpha: 0.16),
                      FyrColors.accentCyan.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: FyrColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: FyrColors.accentCyan,
                        boxShadow: [
                          BoxShadow(
                            color: FyrColors.accentCyan.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WAYLAND · SWAYFX · FLUTTER',
                      style: FyrFonts.mono(
                        fontSize: isMobile ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: FyrColors.accent,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 420.ms).slideY(begin: -0.15, end: 0),

              SizedBox(height: isMobile ? 14 : 20),

              // Punchy animated gradient headline
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Color(0xFFF3E8FF),
                    FyrColors.accent,
                    FyrColors.accentCyan,
                  ],
                  stops: [0.0, 0.42, 0.76, 1.0],
                ).createShader(bounds),
                child: Text(
                  'frick your RAM.',
                  style: FyrFonts.display(
                    fontSize: isMobile ? 42 : (width < 980 ? 64 : 80),
                    fontWeight: FontWeight.w800,
                    height: 1.02,
                    letterSpacing: isMobile ? -1.4 : -2.6,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
                  .animate()
                  .fadeIn(duration: 580.ms)
                  .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic),

              SizedBox(height: isMobile ? 10 : 14),

              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Text(
                  'A full Linux desktop environment & 40+ native apps built on SwayFX and Flutter. You bought all that RAM — make it glow.',
                  style: FyrFonts.display(
                    fontSize: isMobile ? 14.5 : 18,
                    color: Colors.white70,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 550.ms),

              SizedBox(height: isMobile ? 16 : 22),

              // Quick stats pills
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroStatPill(
                    value: '${fyrAppsCatalog.length}+',
                    label: 'Native Apps',
                    dotColor: FyrColors.accent,
                  ),
                  const _HeroStatPill(
                    value: 'SwayFX',
                    label: '+ Flutter',
                    dotColor: FyrColors.accentCyan,
                  ),
                  const _HeroStatPill(
                    value: 'Zero',
                    label: 'Electron',
                    dotColor: FyrColors.accentEmerald,
                  ),
                ],
              ).animate().fadeIn(delay: 180.ms, duration: 550.ms),

              SizedBox(height: isMobile ? 18 : 24),

              // Primary CTAs
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  PrimaryPillButton(
                    label: 'Install Now',
                    icon: Icons.terminal_rounded,
                    compact: isMobile,
                    onPressed: widget.onInstallTap,
                  ),
                  GhostPillButton(
                    label: 'Explore Suite',
                    icon: Icons.apps_rounded,
                    compact: isMobile,
                    onPressed: widget.onExploreTap,
                  ),
                ],
              ).animate().fadeIn(delay: 240.ms, duration: 550.ms),

              SizedBox(height: isMobile ? 22 : 34),

              // Interactive Desktop Showcase Switcher
              _DesktopShowcaseCard(
                activeIndex: _activeShowcase,
                activeItem: activeItem,
                isMobile: isMobile,
                onSelect: (index) => setState(() => _activeShowcase = index),
                onExpand: () => showImageLightbox(
                  context,
                  title: 'fyrDE · ${activeItem.label}',
                  subtitle: activeItem.caption,
                  assetPaths: [activeItem.assetPath],
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 680.ms)
                  .scale(
                    begin: const Offset(0.97, 0.97),
                    end: const Offset(1, 1),
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color dotColor;

  const _HeroStatPill({
    required this.value,
    required this.label,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FyrColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FyrColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: FyrFonts.mono(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: FyrFonts.mono(
              fontSize: 11.5,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopShowcaseCard extends StatelessWidget {
  final int activeIndex;
  final DesktopShowcaseItem activeItem;
  final bool isMobile;
  final ValueChanged<int> onSelect;
  final VoidCallback onExpand;

  const _DesktopShowcaseCard({
    required this.activeIndex,
    required this.activeItem,
    required this.isMobile,
    required this.onSelect,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1020),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FyrColors.accent.withValues(alpha: 0.48),
            Colors.white.withValues(alpha: 0.1),
            FyrColors.accentCyan.withValues(alpha: 0.35),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: FyrColors.accentVibrant.withValues(alpha: 0.25),
            blurRadius: 72,
            spreadRadius: -20,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isMobile ? 14.5 : 20.5),
        child: Container(
          color: FyrColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sleek window chrome + showcase pill switcher
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 16,
                  vertical: isMobile ? 8 : 10,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A12),
                  border: Border(
                    bottom: BorderSide(color: FyrColors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    if (!isMobile) ...[
                      _trafficDot(const Color(0xFFFF5F56)),
                      const SizedBox(width: 7),
                      _trafficDot(const Color(0xFFFFBD2E)),
                      const SizedBox(width: 7),
                      _trafficDot(const Color(0xFF27C93F)),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(
                            fyrDesktopShowcases.length,
                            (index) {
                              final item = fyrDesktopShowcases[index];
                              final selected = index == activeIndex;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => onSelect(index),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 10 : 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(999),
                                        color: selected
                                            ? FyrColors.accentVibrant
                                                .withValues(alpha: 0.25)
                                            : Colors.white
                                                .withValues(alpha: 0.04),
                                        border: Border.all(
                                          color: selected
                                              ? FyrColors.accent
                                                  .withValues(alpha: 0.7)
                                              : FyrColors.borderSubtle,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            item.icon,
                                            size: 13,
                                            color: selected
                                                ? FyrColors.accentCyan
                                                : Colors.white54,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            item.label,
                                            style: FyrFonts.mono(
                                              fontSize: 11.5,
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
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Expand preview',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onExpand,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Screenshot viewport
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onExpand,
                  child: AspectRatio(
                    aspectRatio: isMobile ? 16 / 10 : 16 / 9.2,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: Image.asset(
                            activeItem.assetPath,
                            key: ValueKey(activeItem.assetPath),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            cacheWidth: 1440,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: FyrColors.surfaceElevated,
                              alignment: Alignment.center,
                              child: Icon(
                                activeItem.icon,
                                size: 42,
                                color: FyrColors.accent,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 12 : 18,
                              vertical: isMobile ? 8 : 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.82),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    activeItem.caption,
                                    style: FyrFonts.mono(
                                      fontSize: isMobile ? 11 : 12,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!isMobile) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    activeItem.windowTitle,
                                    style: FyrFonts.mono(
                                      fontSize: 11,
                                      color: FyrColors.accentCyan,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _trafficDot(Color color) {
    return Container(
      width: 9.5,
      height: 9.5,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
