import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const FyrWebsite());
}

class FyrWebsite extends StatelessWidget {
  const FyrWebsite({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fyr - frick your RAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF111111),
        ),
      ),
      home: const LandingPage(),
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // const FyrAppBar(),
          const SliverToBoxAdapter(child: HeroSection()),
          const SliverToBoxAdapter(child: InstallSection()),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'fyrShell',
              subtitle: 'A modern Flutter shell built on top of Sway.',
              id: 'core',
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            sliver: AppGrid(category: 'core'),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'fyrTools',
              subtitle: 'All the normal things you would expect from a DE.',
              id: 'system',
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            sliver: AppGrid(category: 'system'),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'fyrApps',
              subtitle: 'Purdy apps to go with you purdy shell.',
              id: 'productivity',
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            sliver: AppGrid(category: 'productivity'),
          ),
          const SliverToBoxAdapter(child: Footer()),
        ],
      ),
    );
  }
}

class FyrAppBar extends StatelessWidget {
  const FyrAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: const Color(0xFF050505).withOpacity(0.8),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ColorFilter.mode(
            Colors.black.withOpacity(0.1),
            BlendMode.dstIn,
          ),
          child: Container(),
        ),
      ),
      title: Text(
        'fyrDE',
        style: GoogleFonts.jetBrainsMono(
          fontWeight: FontWeight.w800,
          fontSize: 24,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [Colors.white, Colors.purpleAccent],
            ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
        ),
      ),
      actions: [
        // _NavButton(label: 'Core', onPressed: () {}),
        // _NavButton(label: 'System', onPressed: () {}),
        // _NavButton(label: 'Productivity', onPressed: () {}),
        // const SizedBox(width: 20),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _NavButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 20 : 60,
        horizontal: 20,
      ),
      child: Column(
        children: [
          Text(
            'frick your RAM.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: isMobile ? 48 : 80,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.3, end: 0),
          const SizedBox(height: 20),
          Text(
            'You\'ve got enough RAM. Use it.',
            style: const TextStyle(fontSize: 20, color: Colors.white70),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms, duration: 800.ms),
          const SizedBox(height: 20),
          Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purpleAccent.withOpacity(0.2),
                      blurRadius: 100,
                      spreadRadius: -20,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/screenshots/desktop.png',
                    fit: BoxFit.cover,
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 400.ms, duration: 1000.ms)
              .scale(begin: const Offset(0.9, 0.9)),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String id;
  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 40,
        isMobile ? 10 : 40,
        isMobile ? 20 : 40,
        isMobile ? 20 : 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.jetBrainsMono(
              fontSize: isMobile ? 32 : 48,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              color: Colors.white60,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 800.ms);
  }
}

class AppGrid extends StatelessWidget {
  final String category;
  const AppGrid({super.key, required this.category});

  List<Map<String, String>> getApps() {
    if (category == 'core') {
      return [
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar1.png',
        },
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar2.png',
        },
        {
          'name': 'fyrTaskbar',
          'desc': 'frickin sweet taskbar',
          'img': 'taskbar3.png',
        },
        {
          'name': 'fyrSearch',
          'desc': 'frickin sweet search',
          'img': 'search.png',
        },
        {
          'name': 'fyrOverview',
          'desc': 'frickin sweet overview',
          'img': 'overview.png',
        },
        {
          'name': 'Floating',
          'desc': 'frickin sweet floating manager',
          'img': 'floating.png',
        },
        {
          'name': 'Tiling',
          'desc': 'frickin sweet tiling manager',
          'img': 'tiling.png',
        },
        {
          'name': 'fyrDesktop',
          'desc': 'frickin sweet desktop',
          'img': 'desktop.png',
        },
      ];
    } else if (category == 'system') {
      return [
        {
          'name': 'Terminal',
          'desc': 'frickin sweet terminal',
          'img': 'terminal.png',
        },
        {
          'name': 'fyrFiles',
          'desc': 'frickin sweet file manager',
          'img': 'files.png',
        },
        {
          'name': 'fyrStore',
          'desc': 'frickin sweet app store',
          'img': 'store.png',
        },
        {
          'name': 'Settings',
          'desc': 'frickin sweet settings',
          'img': 'settings.png',
        },
        {
          'name': 'FyrAV',
          'desc': 'frickin sweet antivirus',
          'img': 'av.png',
        },
        {
          'name': 'FyrText',
          'desc': 'frickin sweet text editor',
          'img': 'text.png',
        },
        {
          'name': 'Calendar',
          'desc': 'frickin sweet calendar',
          'img': 'calendar.png',
        },
        {
          'name': 'Calculator',
          'desc': 'frickin sweet calculator',
          'img': 'calc.png',
        },
      ];
    } else {
      return [
        {
          'name': 'Goose',
          'desc': 'frickin sweet browser',
          'img': 'goose.png',
        },
        {
          'name': 'FyrCode',
          'desc': 'frickin sweet code editor',
          'img': 'code.png',
        },
        {
          'name': 'Music',
          'desc': 'frickin sweet music player',
          'img': 'music.png',
        },
        {
          'name': 'Sound Booth',
          'desc': 'frickin sweet DAW',
          'img': 'daw.png',
        },
        {
          'name': 'Journal',
          'desc': 'frickin sweet journal',
          'img': 'journal.png',
        },
        {
          'name': 'fyrConnect',
          'desc': 'frickin sweet mobile sync',
          'img': 'phone.png',
        },
        {
          'name': 'Photos',
          'desc': 'frickin sweet photo library',
          'img': 'fyrphotos.png',
        },
        {
          'name': 'Watchbox',
          'desc': 'frickin sweet video player',
          'img': 'seinfeld.png',
        },
        {
          'name': 'Camera',
          'desc': 'frickin sweet camera',
          'img': 'camera.png',
        },
        {
          'name': 'fyrVM',
          'desc': 'frickin sweet VM manager',
          'img': 'fyrvirt.png',
        },
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = getApps();
    return SliverToBoxAdapter(
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 30,
          runSpacing: 30,
          children: apps.map((app) {
            return Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: category == 'core'
                  ? AppCard(app: app, showText: false)
                  : AspectRatio(
                      aspectRatio: 1.2,
                      child: AppCard(app: app, showText: true),
                    ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class AppCard extends StatefulWidget {
  final Map<String, String> app;
  final bool showText;
  const AppCard({super.key, required this.app, this.showText = true});

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool isHovered = false;

  void _expandImage() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black.withOpacity(0.8),
              ),
            ),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/screenshots/${widget.app['img']}',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _expandImage,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child:
            AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isHovered
                          ? Colors.purpleAccent.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                    boxShadow: isHovered
                        ? [
                            BoxShadow(
                              color: Colors.purpleAccent.withOpacity(0.1),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showText)
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(23),
                            ),
                            child: Image.asset(
                              'assets/screenshots/${widget.app['img']}',
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(23),
                          child: Image.asset(
                            'assets/screenshots/${widget.app['img']}',
                            fit: BoxFit.fitWidth,
                          ),
                        ),
                      if (widget.showText)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.app['name']!,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.app['desc']!,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
                .animate(target: isHovered ? 1 : 0)
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.02, 1.02),
                ),
      ),
    );
  }
}

class InstallSection extends StatelessWidget {
  const InstallSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 40,
        vertical: isMobile ? 10 : 20,
      ),
      child: Column(
        children: [
          SectionHeader(
            title: 'Installation',
            subtitle: 'Get up and running with a few simple commands.',
            id: 'install',
          ),
          SizedBox(height: isMobile ? 20 : 40),
          Container(
            constraints: const BoxConstraints(maxWidth: 800),
            padding: EdgeInsets.all(isMobile ? 20 : 30),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStep(
                  '1',
                  'Clone the repository',
                  'git clone https://github.com/archieBTW/fyrDE.git',
                  context,
                ),
                SizedBox(height: isMobile ? 20 : 30),
                _buildStep(
                  '2',
                  'Navigate to the directory',
                  'cd fyrDE',
                  context,
                ),
                SizedBox(height: isMobile ? 20 : 30),
                _buildStep(
                  '3',
                  'Run the installation script',
                  './install.sh',
                  context,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    String number,
    String title,
    String command,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.purpleAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    command,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.purpleAccent,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.copy_all_rounded,
                  size: 20,
                  color: Colors.white54,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: command));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied to clipboard: $command'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.purpleAccent,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: const Center(
        child: Text(
          '© 2026 fyr - frick your RAM.',
          style: TextStyle(color: Colors.white30),
        ),
      ),
    );
  }
}
