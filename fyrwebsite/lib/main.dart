import 'package:flutter/material.dart';

import 'data/fyr_catalog.dart';
import 'theme/fyr_theme.dart';
import 'widgets/app_explorer.dart';
import 'widgets/hero_showcase.dart';
import 'widgets/install_section.dart';
import 'widgets/nav_and_backdrop.dart';

export 'data/fyr_catalog.dart';
export 'theme/fyr_theme.dart';

void main() {
  runApp(const FyrWebsite());
}

class FyrWebsite extends StatelessWidget {
  const FyrWebsite({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fyrDE — frick your RAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: FyrColors.bg,
        textTheme: FyrFonts.buildTextTheme(ThemeData.dark().textTheme),
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
  final _heroKey = GlobalKey();
  final _appsKey = GlobalKey();
  final _installKey = GlobalKey();

  FyrCategory _selectedCategory = FyrCategory.shell;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final isScrolled = _scrollController.offset > 20;
    if (isScrolled != _scrolled) {
      setState(() => _scrolled = isScrolled);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollTo(GlobalKey key, {FyrCategory? selectCategory}) {
    if (selectCategory != null && selectCategory != _selectedCategory) {
      setState(() => _selectedCategory = selectCategory);
    }
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 680;

    return Scaffold(
      backgroundColor: FyrColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: isMobile ? 64 : 80),
                KeyedSubtree(
                  key: _heroKey,
                  child: HeroSection(
                    onInstallTap: () => _scrollTo(_installKey),
                    onExploreTap: () => _scrollTo(_appsKey),
                  ),
                ),
                KeyedSubtree(
                  key: _appsKey,
                  child: TabbedAppExplorer(
                    selectedCategory: _selectedCategory,
                    onCategoryChanged: (category) =>
                        setState(() => _selectedCategory = category),
                  ),
                ),
                KeyedSubtree(
                  key: _installKey,
                  child: const InstallSection(),
                ),
                FyrFooter(onBackToTop: _scrollToTop),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FloatingNavBar(
              scrolled: _scrolled,
              onLogoTap: _scrollToTop,
              onOverviewTap: () => _scrollTo(_heroKey),
              onAppsTap: () => _scrollTo(_appsKey),
              onInstallTap: () => _scrollTo(_installKey),
            ),
          ),
        ],
      ),
    );
  }
}
