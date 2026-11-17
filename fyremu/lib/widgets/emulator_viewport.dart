import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/emu_types.dart';
import '../state/emu_controller.dart';

class EmulatorViewport extends StatelessWidget {
  const EmulatorViewport({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();

    return Expanded(
      child: Column(
        children: [
          // Video Frame Canvas
          Expanded(
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final aspect = ctrl.coreAspectRatio > 0.1
                            ? ctrl.coreAspectRatio
                            : 4 / 3;
                        double w = constraints.maxWidth;
                        double h = w / aspect;
                        if (h > constraints.maxHeight) {
                          h = constraints.maxHeight;
                          w = h * aspect;
                        }
                        if (ctrl.integerScale &&
                            ctrl.frameWidth > 0 &&
                            ctrl.frameHeight > 0) {
                          final factor = max(
                            1,
                            min(
                              (constraints.maxWidth / ctrl.frameWidth).floor(),
                              (constraints.maxHeight / ctrl.frameHeight)
                                  .floor(),
                            ),
                          );
                          w = (ctrl.frameWidth * factor).toDouble();
                          h = (ctrl.frameHeight * factor).toDouble();
                        }

                        return SizedBox(
                          width: w,
                          height: h,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (ctrl.currentFrameImage != null)
                                RawImage(
                                  image: ctrl.currentFrameImage,
                                  fit: BoxFit.fill,
                                  filterQuality: ctrl.smoothFilter
                                      ? FilterQuality.medium
                                      : FilterQuality.none,
                                )
                              else
                                Center(
                                  child: Text(
                                    'Starting emulation...',
                                    style: TextStyle(
                                        color: FyrTheme.textColorMuted),
                                  ),
                                ),
                              if (ctrl.crtScanlines)
                                const IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CrtScanlinePainter(),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (ctrl.isPaused)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: FyrTheme.accentColor.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'PAUSED',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: FyrTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                  if (ctrl.showOnScreenPad)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: _OnScreenGamepad(ctrl: ctrl),
                    ),
                ],
              ),
            ),
          ),
          // Bottom Emulation HUD Strip
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Text(
                  ctrl.frameWidth > 0
                      ? '${ctrl.frameWidth}×${ctrl.frameHeight} • ${ctrl.coreFps.toStringAsFixed(1)} FPS'
                      : 'Loading...',
                  style:
                      TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
                ),
                const SizedBox(width: 14),
                Text('Slot:',
                    style:
                        TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
                const SizedBox(width: 6),
                ...List.generate(6, (slot) {
                  final active = ctrl.saveStateSlot == slot;
                  final occupied = ctrl.hasStateInSlot(slot);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () {
                        ctrl.saveStateSlot = slot;
                        ctrl.refresh();
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active
                              ? FyrTheme.accentColor.withValues(alpha: 0.25)
                              : FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: active
                                ? FyrTheme.accentColor
                                : (occupied
                                    ? Colors.greenAccent.withValues(alpha: 0.5)
                                    : FyrTheme.dividerColor),
                          ),
                        ),
                        child: Text(
                          '$slot',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? FyrTheme.accentColor
                                : FyrTheme.textColorMuted,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                if (ctrl.statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      ctrl.statusMessage!,
                      style: TextStyle(
                          fontSize: 11,
                          color: FyrTheme.accentColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                _toggleChip('CRT', ctrl.crtScanlines, () {
                  ctrl.crtScanlines = !ctrl.crtScanlines;
                  ctrl.refresh();
                }),
                const SizedBox(width: 6),
                _toggleChip('Int Scale', ctrl.integerScale, () {
                  ctrl.integerScale = !ctrl.integerScale;
                  ctrl.refresh();
                }),
                const SizedBox(width: 6),
                _toggleChip('Smooth', ctrl.smoothFilter, () {
                  ctrl.smoothFilter = !ctrl.smoothFilter;
                  ctrl.refresh();
                }),
                const SizedBox(width: 6),
                _toggleChip('Touch Pad', ctrl.showOnScreenPad, () {
                  ctrl.showOnScreenPad = !ctrl.showOnScreenPad;
                  ctrl.refresh();
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.2)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _CrtScanlinePainter extends CustomPainter {
  const _CrtScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = 1.0;
    for (double y = 0; y < size.height; y += 3.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final vig = Paint()
      ..shader = RadialGradient(
        radius: 0.85,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vig);
  }

  @override
  bool shouldRepaint(covariant _CrtScanlinePainter oldDelegate) => false;
}

class _OnScreenGamepad extends StatelessWidget {
  final EmuController ctrl;
  const _OnScreenGamepad({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // D-Pad
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            children: [
              Positioned(
                  left: 40,
                  top: 0,
                  child: _padBtn('▲', RetroButton.up)),
              Positioned(
                  left: 40,
                  bottom: 0,
                  child: _padBtn('▼', RetroButton.down)),
              Positioned(
                  left: 0,
                  top: 40,
                  child: _padBtn('◀', RetroButton.left)),
              Positioned(
                  right: 0,
                  top: 40,
                  child: _padBtn('▶', RetroButton.right)),
            ],
          ),
        ),
        // Select / Start
        Row(
          children: [
            _pillPad('SELECT', RetroButton.select),
            const SizedBox(width: 10),
            _pillPad('START', RetroButton.start),
          ],
        ),
        // L / R + ABXY
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                _pillPad('L', RetroButton.l),
                const SizedBox(width: 8),
                _pillPad('R', RetroButton.r),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  Positioned(
                      left: 40, top: 0, child: _padBtn('X', RetroButton.x)),
                  Positioned(
                      left: 40, bottom: 0, child: _padBtn('B', RetroButton.b)),
                  Positioned(
                      left: 0, top: 40, child: _padBtn('Y', RetroButton.y)),
                  Positioned(
                      right: 0, top: 40, child: _padBtn('A', RetroButton.a)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _padBtn(String label, RetroButton btn) {
    return Listener(
      onPointerDown: (_) => ctrl.setVirtualButton(btn, true),
      onPointerUp: (_) => ctrl.setVirtualButton(btn, false),
      onPointerCancel: (_) => ctrl.setVirtualButton(btn, false),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _pillPad(String label, RetroButton btn) {
    return Listener(
      onPointerDown: (_) => ctrl.setVirtualButton(btn, true),
      onPointerUp: (_) => ctrl.setVirtualButton(btn, false),
      onPointerCancel: (_) => ctrl.setVirtualButton(btn, false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white30),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}
