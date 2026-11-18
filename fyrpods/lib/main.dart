import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'models/pod_models.dart';
import 'state/pods_controller.dart';
import 'widgets/containers_view.dart';
import 'widgets/dashboard_view.dart';
import 'widgets/images_view.dart';
import 'widgets/networks_view.dart';
import 'widgets/pods_view.dart';
import 'widgets/resizable_window.dart';
import 'widgets/sidebar_nav.dart';
import 'widgets/top_bar.dart';
import 'widgets/volumes_view.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 880),
    minimumSize: Size(1020, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrPods',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = PodsController(allowLiveCli: true, enableTicker: true);
  await controller.engine.detectAvailableRuntime();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrPodsApp(),
    ),
  );
}

class FyrPodsApp extends StatelessWidget {
  const FyrPodsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, _) {
        final accent = FyrTheme.accentColor;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrPods',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.light(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          home: const PodsShell(),
        );
      },
    );
  }
}

class PodsShell extends StatefulWidget {
  const PodsShell({super.key});

  @override
  State<PodsShell> createState() => _PodsShellState();
}

class _PodsShellState extends State<PodsShell> {
  final FocusNode _rootFocus = FocusNode();

  @override
  void dispose() {
    _rootFocus.dispose();
    super.dispose();
  }

  bool _isTypingInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus == _rootFocus) return false;
    final ctx = focus.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTypingInTextField()) return KeyEventResult.ignored;

    final ctrl = context.read<PodsController>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.digit1) {
      ctrl.setSection(PodsNavSection.dashboard);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2) {
      ctrl.setSection(PodsNavSection.containers);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3) {
      ctrl.setSection(PodsNavSection.pods);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4) {
      ctrl.setSection(PodsNavSection.images);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit5) {
      ctrl.setSection(PodsNavSection.volumes);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit6) {
      ctrl.setSection(PodsNavSection.networks);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();

    Widget mainView;
    switch (ctrl.activeSection) {
      case PodsNavSection.dashboard:
        mainView = const DashboardView();
        break;
      case PodsNavSection.containers:
        mainView = const ContainersView();
        break;
      case PodsNavSection.pods:
        mainView = const PodsView();
        break;
      case PodsNavSection.images:
        mainView = const ImagesView();
        break;
      case PodsNavSection.volumes:
        mainView = const VolumesView();
        break;
      case PodsNavSection.networks:
        mainView = const NetworksView();
        break;
    }

    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: ResizableWindow(
        child: Scaffold(
          backgroundColor: FyrTheme.bgColor,
          body: Column(
            children: [
              const TopBar(),
              Expanded(
                child: Row(
                  children: [
                    const SidebarNav(),
                    Expanded(child: mainView),
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
