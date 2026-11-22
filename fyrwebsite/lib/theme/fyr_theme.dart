import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FyrColors {
  static const bg = Color(0xFF06060A);
  static const surface = Color(0xFF0E0E16);
  static const surfaceElevated = Color(0xFF151524);
  static const surfaceGlass = Color(0xCC11111B);
  static const accent = Color(0xFFC084FC);
  static const accentVibrant = Color(0xFFA855F7);
  static const accentDeep = Color(0xFF7E22CE);
  static const accentCyan = Color(0xFF67E8F9);
  static const accentPink = Color(0xFFF472B6);
  static const accentEmerald = Color(0xFF4ADE80);
  static const accentAmber = Color(0xFFFBBF24);
  static const accentSky = Color(0xFF38BDF8);
  static const borderSubtle = Color(0x1AFFFFFF);
  static const borderMedium = Color(0x2EFFFFFF);
  static const borderAccent = Color(0x66C084FC);
}

class FyrFonts {
  /// Disabled in widget tests to prevent network font downloads in hermetic runs.
  static bool enableGoogleFonts = true;

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    if (!enableGoogleFonts) {
      return TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    if (!enableGoogleFonts) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextTheme buildTextTheme(TextTheme base) {
    if (!enableGoogleFonts) {
      return base;
    }
    return GoogleFonts.spaceGroteskTextTheme(base);
  }
}

class PrimaryPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final IconData? icon;

  const PrimaryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.icon,
  });

  @override
  State<PrimaryPillButton> createState() => _PrimaryPillButtonState();
}

class _PrimaryPillButtonState extends State<PrimaryPillButton> {
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
            horizontal: widget.compact ? 14 : 22,
            vertical: widget.compact ? 8 : 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _hovered
                  ? const [Color(0xFFC084FC), FyrColors.accentVibrant]
                  : const [FyrColors.accentVibrant, FyrColors.accentDeep],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.35 : 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: FyrColors.accentVibrant
                    .withValues(alpha: _hovered ? 0.55 : 0.3),
                blurRadius: _hovered ? 26 : 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.compact ? 14 : 16, color: Colors.white),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: FyrFonts.mono(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.compact ? 12.5 : 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GhostPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool compact;

  const GhostPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  @override
  State<GhostPillButton> createState() => _GhostPillButtonState();
}

class _GhostPillButtonState extends State<GhostPillButton> {
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
            horizontal: widget.compact ? 13 : 20,
            vertical: widget.compact ? 8 : 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hovered
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: _hovered
                  ? FyrColors.accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.compact ? 14 : 16,
                  color: _hovered ? FyrColors.accentCyan : Colors.white70,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: FyrFonts.mono(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  fontSize: widget.compact ? 12.5 : 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
