import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:math_expressions/math_expressions.dart';
import 'fyr_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(350, 550),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrCalculatorApp());
}

class FyrCalculatorApp extends StatelessWidget {
  const FyrCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: FyrTheme.themeMode,
          theme: ThemeData.light().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: FyrTheme.bgColor,
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.light(
              primary: FyrTheme.accentColor,
              surface: FyrTheme.bgColor,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: FyrTheme.bgColor,
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.dark(
              primary: FyrTheme.accentColor,
              surface: FyrTheme.bgColor,
            ),
          ),
          home: const CalculatorHome(),
        );
      },
    );
  }
}

class CalculatorHome extends StatefulWidget {
  const CalculatorHome({super.key});

  @override
  State<CalculatorHome> createState() => _CalculatorHomeState();
}

class _CalculatorHomeState extends State<CalculatorHome> {
  String _input = '';
  String _result = '0';
  bool _isScientific = false;

  void _onPressed(String text) {
    setState(() {
      if (text == 'AC') {
        _input = '';
        _result = '0';
      } else if (text == 'C') {
        if (_input.isNotEmpty) {
          _input = _input.substring(0, _input.length - 1);
        }
      } else if (text == '=') {
        _calculate();
      } else {
        _input += text;
      }
    });
  }

  void _calculate() {
    try {
      String finalInput = _input.replaceAll('×', '*').replaceAll('÷', '/');
      Parser p = Parser();
      Expression exp = p.parse(finalInput);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);
      
      setState(() {
        _result = eval.toString();
        if (_result.endsWith('.0')) {
          _result = _result.substring(0, _result.length - 2);
        }
      });
    } catch (e) {
      setState(() {
        _result = 'Error';
      });
    }
  }


  Widget _buildTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildTrafficLight(const Color(0xFFFF5F57), () => windowManager.close()),
            const SizedBox(width: 8),
            _buildTrafficLight(const Color(0xFFFEBC2E), () => windowManager.minimize()),
            const SizedBox(width: 8),
            _buildTrafficLight(const Color(0xFF28C840), () => windowManager.maximize()),
            const Spacer(),
            IconButton(
              onPressed: () {
                setState(() {
                  _isScientific = !_isScientific;
                  windowManager.setSize(
                    _isScientific ? const Size(600, 550) : const Size(350, 550),
                    animate: true,
                  );
                });
              },
              icon: Icon(
                _isScientific ? Icons.grid_view_rounded : Icons.science_rounded,
                color: FyrTheme.textColorMuted,
                size: 20,
              ),
              tooltip: _isScientific ? 'Basic Mode' : 'Scientific Mode',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }


  // Replacing GridView with manual layout for better control (especially wide '0')
  Widget _buildKeypadManual() {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 20),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isScientific)
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _buildRow(['sin(', 'cos(', 'tan('], isScientific: true),
                  const SizedBox(height: 8),
                  _buildRow(['ln(', 'log(', 'sqrt('], isScientific: true),
                  const SizedBox(height: 8),
                  _buildRow(['e', 'pi', '^'], isScientific: true),
                  const SizedBox(height: 8),
                  _buildRow(['(', ')', '!'], isScientific: true),
                ],
              ),
            ),
          if (_isScientific) const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildRow(['AC', 'C', '%', '÷']),
                const SizedBox(height: 8),
                _buildRow(['7', '8', '9', '×']),
                const SizedBox(height: 8),
                _buildRow(['4', '5', '6', '-']),
                const SizedBox(height: 8),
                _buildRow(['1', '2', '3', '+']),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildButton('0')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildButton('.')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildButton('=', isAccent: true)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys, {bool isScientific = false}) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildButton(key, isScientific: isScientific),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildButton(String text, {bool isScientific = false, bool isAccent = false, bool isWide = false}) {
    bool isOperator = ['÷', '×', '-', '+', '=', '%'].contains(text);
    bool isAction = ['AC', 'C'].contains(text);
    
    Color btnColor = FyrTheme.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    Color txtColor = FyrTheme.textColor;

    if (isAccent) {
      btnColor = FyrTheme.accentColor;
      txtColor = Colors.white;
    } else if (isOperator) {
      txtColor = FyrTheme.accentColor;
    } else if (isAction) {
      txtColor = Colors.redAccent;
    } else if (isScientific) {
      txtColor = FyrTheme.accentColor.withOpacity(0.8);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onPressed(text),
        child: Container(
          height: isScientific ? 40 : 52,
          decoration: BoxDecoration(
            color: btnColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (isAccent)
                BoxShadow(
                  color: FyrTheme.accentColor.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: isScientific ? 16 : 22,
                fontWeight: isAccent || isOperator ? FontWeight.bold : FontWeight.w500,
                color: txtColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTitleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        _input,
                        style: TextStyle(
                          fontSize: 28,
                          color: FyrTheme.textColorMuted,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        _result,
                        style: TextStyle(
                          fontSize: _result.length > 8 ? 48 : 64,
                          color: FyrTheme.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildKeypadManual(),
        ],
      ),
    );
  }
}
