import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/emu_types.dart';
import '../state/emu_controller.dart';

class InputMapperDialog extends StatelessWidget {
  const InputMapperDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const InputMapperDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();
    final controllers = ctrl.connectedControllers;
    final liveMask = ctrl.computeJoypadMask();

    return Dialog(
      backgroundColor: FyrTheme.isDark ? const Color(0xFF141417) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: SizedBox(
        width: 640,
        height: 580,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sports_esports_rounded,
                      color: FyrTheme.accentColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Controls & Controller Mapping',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Controller Presets',
                    onSelected: ctrl.applyControllerPreset,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'xbox',
                          child: Text('Xbox / XInput Layout')),
                      PopupMenuItem(
                          value: 'nintendo',
                          child: Text('Nintendo / 8BitDo Layout')),
                      PopupMenuItem(
                          value: 'reset',
                          child: Text('Reset All to Defaults')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Presets',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down,
                              size: 16, color: FyrTheme.textColorMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Connected Gamepad Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Icon(
                    controllers.isNotEmpty
                        ? Icons.usb_rounded
                        : Icons.usb_off_rounded,
                    size: 16,
                    color: controllers.isNotEmpty
                        ? Colors.greenAccent
                        : FyrTheme.textColorMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controllers.isEmpty
                          ? 'No physical gamepad detected on /dev/input/js* — keyboard active'
                          : 'Connected: ${controllers[ctrl.inputProfile.controllerPortIndex.clamp(0, controllers.length - 1)].name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: controllers.isNotEmpty
                            ? FyrTheme.textColor
                            : FyrTheme.textColorMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (controllers.length > 1)
                    DropdownButton<int>(
                      value: ctrl.inputProfile.controllerPortIndex
                          .clamp(0, controllers.length - 1),
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: controllers
                          .map((c) => DropdownMenuItem(
                                value: c.index,
                                child: Text('Pad ${c.index + 1}',
                                    style: const TextStyle(fontSize: 12)),
                              ))
                          .toList(),
                      onChanged: (idx) {
                        if (idx != null) {
                          ctrl.inputProfile = InputProfile(
                            keyboardMap: ctrl.inputProfile.keyboardMap,
                            gamepadMap: ctrl.inputProfile.gamepadMap,
                            controllerPortIndex: idx,
                          );
                          ctrl.refresh();
                        }
                      },
                    ),
                ],
              ),
            ),
            if (ctrl.capturingButton != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                color: FyrTheme.accentColor.withValues(alpha: 0.18),
                child: Row(
                  children: [
                    Icon(Icons.sensors_rounded,
                        size: 16, color: FyrTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ctrl.capturingGamepad
                            ? 'Press any Gamepad button or move a stick/D-pad for "${ctrl.capturingButton!.label}"...'
                            : 'Press any Keyboard key for "${ctrl.capturingButton!.label}"...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.accentColor,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: ctrl.cancelCapture,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            // Mapping Table
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: RetroButton.values.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: FyrTheme.dividerColor),
                itemBuilder: (ctx, i) {
                  final btn = RetroButton.values[i];
                  final kbId = ctrl.inputProfile.keyboardMap[btn];
                  final gpSrc = ctrl.inputProfile.gamepadMap[btn];
                  final isPressed = (liveMask & (1 << btn.retroId)) != 0;
                  final capturingKb = ctrl.capturingButton == btn &&
                      !ctrl.capturingGamepad;
                  final capturingGp = ctrl.capturingButton == btn &&
                      ctrl.capturingGamepad;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isPressed
                                ? FyrTheme.accentColor
                                : FyrTheme.dividerColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          child: Text(
                            btn.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isPressed
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColor,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _BindButton(
                            icon: Icons.keyboard_rounded,
                            text: capturingKb
                                ? 'Press a key...'
                                : InputProfile.keyLabel(kbId),
                            active: capturingKb,
                            onTap: () =>
                                ctrl.beginCapture(btn, gamepad: false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _BindButton(
                            icon: Icons.gamepad_rounded,
                            text: capturingGp
                                ? 'Press button/axis...'
                                : (gpSrc?.displayLabel ?? 'Unbound'),
                            active: capturingGp,
                            onTap: () => ctrl.beginCapture(btn, gamepad: true),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Text(
                    'Left analog stick also maps to D-Pad automatically',
                    style: TextStyle(
                        fontSize: 11, color: FyrTheme.textColorMuted),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor:
                          FyrTheme.getContrastingColor(FyrTheme.accentColor),
                    ),
                    onPressed: () {
                      ctrl.cancelCapture();
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BindButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _BindButton({
    required this.icon,
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.22)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
