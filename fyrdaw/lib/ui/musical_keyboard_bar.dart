import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrdaw/main.dart';

/// Mapping from QWERTY home/top row physical keys to semitone offsets (C..C+1).
final Map<LogicalKeyboardKey, int> kQwertyNoteOffsets = {
  LogicalKeyboardKey.keyA: 0, // C
  LogicalKeyboardKey.keyW: 1, // C#
  LogicalKeyboardKey.keyS: 2, // D
  LogicalKeyboardKey.keyE: 3, // D#
  LogicalKeyboardKey.keyD: 4, // E
  LogicalKeyboardKey.keyF: 5, // F
  LogicalKeyboardKey.keyT: 6, // F#
  LogicalKeyboardKey.keyG: 7, // G
  LogicalKeyboardKey.keyY: 8, // G#
  LogicalKeyboardKey.keyH: 9, // A
  LogicalKeyboardKey.keyU: 10, // A#
  LogicalKeyboardKey.keyJ: 11, // B
  LogicalKeyboardKey.keyK: 12, // C+1
};

const List<(int offset, String keyChar, bool isBlack)> _kKeys = [
  (0, 'A', false),
  (1, 'W', true),
  (2, 'S', false),
  (3, 'E', true),
  (4, 'D', false),
  (5, 'F', false),
  (6, 'T', true),
  (7, 'G', false),
  (8, 'Y', true),
  (9, 'H', false),
  (10, 'U', true),
  (11, 'J', false),
  (12, 'K', false),
];

/// Dockable compact QWERTY Musical Typing Keyboard bar with clickable piano keys,
/// octave shift (`Z`/`X`), velocity (`C`/`V`), and active pitch highlights.
class MusicalKeyboardBar extends StatelessWidget {
  final int octave;
  final int velocity;
  final Set<int> activeNotes;
  final ValueChanged<int> onOctaveChanged;
  final ValueChanged<int> onVelocityChanged;
  final void Function(int midiNote) onNoteDown;
  final void Function(int midiNote) onNoteUp;
  final VoidCallback onClose;

  const MusicalKeyboardBar({
    super.key,
    required this.octave,
    required this.velocity,
    required this.activeNotes,
    required this.onOctaveChanged,
    required this.onVelocityChanged,
    required this.onNoteDown,
    required this.onNoteUp,
    required this.onClose,
  });

  int _midiForOffset(int offset) => ((octave + 1) * 12 + offset).clamp(0, 127);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(top: BorderSide(color: lavenderAccent, width: 1.5)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.keyboard, size: 14, color: lavenderAccent),
                  const SizedBox(width: 4),
                  Text(
                    'MUSICAL TYPING',
                    style: TextStyle(
                      color: textMain,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Oct [Z/X]: C$octave', style: TextStyle(color: textMuted, fontSize: 10)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => onOctaveChanged((octave - 1).clamp(1, 7)),
                    child: Icon(Icons.chevron_left, size: 14, color: textMuted),
                  ),
                  InkWell(
                    onTap: () => onOctaveChanged((octave + 1).clamp(1, 7)),
                    child: Icon(Icons.chevron_right, size: 14, color: textMuted),
                  ),
                  const SizedBox(width: 10),
                  Text('Vel [C/V]: $velocity', style: TextStyle(color: textMuted, fontSize: 10)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => onVelocityChanged((velocity - 15).clamp(20, 127)),
                    child: Icon(Icons.remove, size: 13, color: textMuted),
                  ),
                  InkWell(
                    onTap: () => onVelocityChanged((velocity + 15).clamp(20, 127)),
                    child: Icon(Icons.add, size: 13, color: textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kKeys.map((k) {
                  final midi = _midiForOffset(k.$1);
                  final isDown = activeNotes.contains(midi);
                  return Listener(
                    onPointerDown: (_) => onNoteDown(midi),
                    onPointerUp: (_) => onNoteUp(midi),
                    onPointerCancel: (_) => onNoteUp(midi),
                    child: Container(
                      width: k.$3 ? 28 : 34,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isDown
                            ? lavenderAccent
                            : (k.$3 ? bgDark : Colors.grey[200]),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDown ? Colors.white : borderMain,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            k.$2,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDown
                                  ? Colors.black
                                  : (k.$3 ? textMuted : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: textMuted),
            tooltip: 'Close Musical Typing',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

