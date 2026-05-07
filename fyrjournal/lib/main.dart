import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fyr_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 850),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrJournalApp());
}

class FyrJournalApp extends StatelessWidget {
  const FyrJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: FyrTheme.accentColorNotifier,
      builder: (context, accent, _) {
        return MaterialApp(
          title: 'fyrjournal',
          theme: ThemeData(
            brightness: Brightness.light,
            useMaterial3: true,
            colorSchemeSeed: accent,
            fontFamily: 'Outfit',
          ),
          home: const JournalHomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class JournalHomePage extends StatefulWidget {
  const JournalHomePage({super.key});

  @override
  State<JournalHomePage> createState() => _JournalHomePageState();
}

class _JournalHomePageState extends State<JournalHomePage> {
  List<DateTime> _days = [];
  final Map<String, String> _entries = {};
  bool _isLoading = true;
  late final String _storagePath;

  @override
  void initState() {
    super.initState();
    _initStorage().then((_) => _loadDays());
  }

  Future<void> _initStorage() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/fyrjournal';
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _storagePath = path;
  }

  void _loadDays() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<DateTime> allDays = [];
    
    for (int i = 0; i < 366; i++) {
      allDays.add(today.subtract(Duration(days: i)));
    }

    for (final day in allDays) {
      final fileName = DateFormat('yyyy-MM-dd').format(day);
      final file = File('$_storagePath/$fileName.txt');
      if (file.existsSync()) {
        _entries[fileName] = file.readAsStringSync();
      }
    }

    _days = allDays.where((day) {
      final key = DateFormat('yyyy-MM-dd').format(day);
      return _entries.containsKey(key) || DateUtils.isSameDay(day, today);
    }).toList();

    _days.sort((a, b) => a.compareTo(b));

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveEntry(DateTime day, String text) async {
    final fileName = DateFormat('yyyy-MM-dd').format(day);
    final file = File('$_storagePath/$fileName.txt');
    await file.writeAsString(text);
    _entries[fileName] = text;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const softWhite = Color(0xFFFBFBF9);

    return Scaffold(
      backgroundColor: softWhite,
      body: Column(
        children: [
          GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              height: 40,
              color: softWhite,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _TrafficLight(color: Colors.red.shade400, onTap: () => windowManager.close()),
                  const SizedBox(width: 8),
                  _TrafficLight(color: Colors.amber.shade400, onTap: () => windowManager.minimize()),
                  const SizedBox(width: 8),
                  _TrafficLight(color: Colors.green.shade400, onTap: () => windowManager.maximize()),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _days.length + 1,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0), // Base offset for all lines
              itemBuilder: (context, index) {
                if (index == _days.length) {
                  return const NotebookFiller();
                }
                final day = _days[index];
                final dateKey = DateFormat('yyyy-MM-dd').format(day);
                final isToday = DateUtils.isSameDay(day, DateTime.now());
                return JournalDayItem(
                  date: day,
                  initialContent: _entries[dateKey] ?? '',
                  onChanged: (text) => _saveEntry(day, text),
                  autoFocus: isToday,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficLight extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _TrafficLight({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class NotebookFiller extends StatelessWidget {
  const NotebookFiller({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NotebookItemPainter(
        lineColor: Colors.blue.withOpacity(0.15),
        marginColor: Colors.red.withOpacity(0.2),
        drawSpirals: true,
      ),
      child: const SizedBox(height: 1000),
    );
  }
}

class JournalDayItem extends StatefulWidget {
  final DateTime date;
  final String initialContent;
  final Function(String) onChanged;
  final bool autoFocus;

  const JournalDayItem({
    super.key,
    required this.date,
    required this.initialContent,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<JournalDayItem> createState() => _JournalDayItemState();
}

class _JournalDayItemState extends State<JournalDayItem> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NotebookItemPainter(
        lineColor: Colors.blue.withOpacity(0.15),
        marginColor: Colors.red.withOpacity(0.2),
        drawSpirals: true,
      ),
      child: Container(
        padding: EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 35),
            // Sidebar (Handwritten Date)
            Container(
              width: 100,
              padding: const EdgeInsets.only(top: 0, left: 4), // Top 0 for 30px alignment
              height: 30, // Locked to first row height
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat('MMM d, EE').format(widget.date).toUpperCase(),
                style: GoogleFonts.caveat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20), // No top padding
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  onChanged: widget.onChanged,
                  strutStyle: StrutStyle(
                    fontFamily: GoogleFonts.caveat().fontFamily,
                    fontSize: 22,
                    height: 1.3636,
                    forceStrutHeight: true,
                  ),
                  style: GoogleFonts.caveat(
                    fontSize: 22,
                    height: 1.3636,
                    color: const Color(0xFF454545),
                  ),
                  selectionHeightStyle: BoxHeightStyle.tight,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: null,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}

class NotebookItemPainter extends CustomPainter {
  final Color lineColor;
  final Color marginColor;
  final bool drawSpirals;

  NotebookItemPainter({
    required this.lineColor,
    required this.marginColor,
    this.drawSpirals = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    // Strict 30px intervals
    for (double i = 30; i < size.height + 1; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final marginPaint = Paint()
      ..color = marginColor
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(138, 0), Offset(138, size.height), marginPaint);

    if (drawSpirals) {
      for (double i = 0; i < size.height - 8; i += 30) {
        final rect = Rect.fromLTWH(10, i + 7, 24, 16);
        final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
        final spiralPaint = Paint()
          ..shader = LinearGradient(
            colors: [Colors.grey[400]!, Colors.grey[200]!, Colors.grey[500]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect);
        canvas.drawRRect(rrect, spiralPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NotebookItemPainter oldDelegate) => true;
}







