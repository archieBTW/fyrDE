import 'package:flutter/material.dart';

import '../theme/fyr_theme.dart';

enum FyrCategory {
  shell(
    label: 'Shell & Core',
    shortLabel: 'Shell',
    eyebrow: 'fyrShell',
    subtitle: 'Native Flutter desktop shell layered on top of SwayFX.',
    icon: Icons.layers_rounded,
    accent: FyrColors.accent,
  ),
  system(
    label: 'System & Daily',
    shortLabel: 'System',
    eyebrow: 'fyrTools',
    subtitle: 'Everyday utilities, system controls, files, and connectivity.',
    icon: Icons.tune_rounded,
    accent: FyrColors.accentCyan,
  ),
  creative(
    label: 'Creative & Media',
    shortLabel: 'Creative',
    eyebrow: 'fyrCreative',
    subtitle: 'Design, video, audio DAW, photos, media players, and retro gaming.',
    icon: Icons.palette_rounded,
    accent: FyrColors.accentPink,
  ),
  office(
    label: 'Office Suite',
    shortLabel: 'Office',
    eyebrow: 'fyrOffice',
    subtitle: 'Documents, spreadsheets, slide decks, PDFs, and rich text.',
    icon: Icons.description_rounded,
    accent: FyrColors.accentSky,
  ),
  dev(
    label: 'Dev & Virt',
    shortLabel: 'Dev',
    eyebrow: 'fyrDev',
    subtitle: 'Agentic IDE, API testing, SQL, containers, and KVM/QEMU VMs.',
    icon: Icons.code_rounded,
    accent: FyrColors.accentEmerald,
  ),
  cliMobile(
    label: 'CLI & Mobile',
    shortLabel: 'CLI & Mobile',
    eyebrow: 'Ecosystem',
    subtitle: 'Native Go package tooling, system fetch, and Android companion.',
    icon: Icons.smartphone_rounded,
    accent: FyrColors.accentAmber,
  );

  final String label;
  final String shortLabel;
  final String eyebrow;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const FyrCategory({
    required this.label,
    required this.shortLabel,
    required this.eyebrow,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class DesktopShowcaseItem {
  final String id;
  final String label;
  final String windowTitle;
  final String caption;
  final String assetPath;
  final IconData icon;

  const DesktopShowcaseItem({
    required this.id,
    required this.label,
    required this.windowTitle,
    required this.caption,
    required this.assetPath,
    required this.icon,
  });
}

const List<DesktopShowcaseItem> fyrDesktopShowcases = [
  DesktopShowcaseItem(
    id: 'desktop',
    label: 'Desktop',
    windowTitle: 'fyrDE · swayfx · wayland',
    caption: 'SwayFX compositor paired with a frosted native Flutter shell.',
    assetPath: 'assets/screenshots/desktop.png',
    icon: Icons.desktop_windows_rounded,
  ),
  DesktopShowcaseItem(
    id: 'tiling',
    label: 'Tiling',
    windowTitle: 'fyrDE · tiling layout',
    caption: 'Snap-fast keyboard tiling with rounded corners, gaps, and blur.',
    assetPath: 'assets/screenshots/tiling.png',
    icon: Icons.grid_view_rounded,
  ),
  DesktopShowcaseItem(
    id: 'floating',
    label: 'Floating',
    windowTitle: 'fyrDE · floating mode',
    caption: 'Toggle floating mode anytime (Super + M) with fluid shadows.',
    assetPath: 'assets/screenshots/floating.png',
    icon: Icons.web_asset_rounded,
  ),
  DesktopShowcaseItem(
    id: 'overview',
    label: 'Overview',
    windowTitle: 'fyrOverview · Super + Tab',
    caption: 'Exposé-style live window and workspace overview at a glance.',
    assetPath: 'assets/screenshots/overview.png',
    icon: Icons.view_carousel_rounded,
  ),
  DesktopShowcaseItem(
    id: 'taskbar',
    label: 'Taskbar',
    windowTitle: 'fyrTaskbar · quick settings',
    caption: 'Top bar with media controls, notifications, tray, and Quick Settings.',
    assetPath: 'assets/screenshots/taskbar1.png',
    icon: Icons.view_headline_rounded,
  ),
];

class FyrAppItem {
  final String id;
  final String name;
  final String? alias;
  final String badge;
  final String description;
  final String? screenshot;
  final List<String> extraScreenshots;
  final String? shortcut;
  final IconData icon;
  final FyrCategory category;
  final bool isNew;
  final List<String> highlights;

  const FyrAppItem({
    required this.id,
    required this.name,
    this.alias,
    required this.badge,
    required this.description,
    this.screenshot,
    this.extraScreenshots = const [],
    this.shortcut,
    required this.icon,
    required this.category,
    this.isNew = false,
    this.highlights = const [],
  });

  String? get screenshotAsset =>
      screenshot != null ? 'assets/screenshots/$screenshot' : null;

  List<String> get allScreenshotAssets => [
        if (screenshot != null) 'assets/screenshots/$screenshot',
        ...extraScreenshots.map((file) => 'assets/screenshots/$file'),
      ];

  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        (alias?.toLowerCase().contains(q) ?? false) ||
        badge.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        category.label.toLowerCase().contains(q) ||
        category.eyebrow.toLowerCase().contains(q);
  }
}

const List<FyrAppItem> fyrAppsCatalog = [
  // ===========================================================================
  // SHELL & CORE (fyrShell) — 8 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrtaskbar',
    name: 'fyrTaskbar',
    badge: 'Top Panel',
    description:
        'Desktop bar with notifications, screenshot toasts, tray, clock, media controls, and frosted Quick Settings.',
    screenshot: 'taskbar1.png',
    extraScreenshots: ['taskbar2.png', 'taskbar3.png'],
    icon: Icons.view_headline_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Frosted Quick Settings popover for Wi-Fi, Bluetooth, audio & brightness',
      'Live media player controls, system tray, and screenshot toast actions',
      'Layer-shell Wayland integration built natively in Flutter',
    ],
  ),
  FyrAppItem(
    id: 'fyrdock',
    name: 'fyrDock',
    badge: 'App Dock',
    description:
        'Translucent animated dock for pinned launchers, running indicators, and rapid window switching.',
    screenshot: 'fyrdock.png',
    icon: Icons.dock_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Pinned app launchers with live Sway window state tracking',
      'Glassmorphic blur styling matched to the active Fyr theme',
      'Smooth hover magnification and drag-friendly layout',
    ],
  ),
  FyrAppItem(
    id: 'fyrsearch',
    name: 'fyrSearch',
    badge: 'Launcher',
    description:
        'Spotlight-style application launcher with instant fuzzy search and an inline calculator.',
    screenshot: 'search.png',
    shortcut: 'Super + Space',
    icon: Icons.search_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Sub-frame fuzzy app discovery across desktop entries',
      'Built-in inline math evaluation right in the search bar',
      'Keyboard-first navigation with instant launch',
    ],
  ),
  FyrAppItem(
    id: 'fyroverview',
    name: 'fyrOverview',
    badge: 'Exposé',
    description:
        'Fluid Exposé-style overview to inspect, focus, and organize every open window across monitors.',
    screenshot: 'overview.png',
    shortcut: 'Super + Tab',
    icon: Icons.view_carousel_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Instant live overview triggered via Super + Tab or 3-finger swipe',
      'One-click window focus and quick close actions',
      'Multi-monitor aware layout with smooth scale transitions',
    ],
  ),
  FyrAppItem(
    id: 'fyrwindowoverview',
    name: 'fyrWindowOverview',
    badge: 'Workspaces',
    description:
        'Workspace-centric mission control for jumping between workspaces and moving tiled or floating windows.',
    screenshot: 'tiling.png',
    shortcut: 'Super + W',
    icon: Icons.grid_view_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Bird\'s-eye view of all active SwayFX workspaces',
      'Fast workspace switching and window organization',
      'Designed for both keyboard and touchpad gesture workflows',
    ],
  ),
  FyrAppItem(
    id: 'fyrclipboard',
    name: 'fyrClipboard',
    badge: 'Clipboard',
    description:
        'Frosted-glass clipboard history manager with text & image capture, pinning, filtering, and instant search.',
    screenshot: 'fyrclipboard.png',
    shortcut: 'Alt + V',
    icon: Icons.content_paste_rounded,
    category: FyrCategory.shell,
    isNew: true,
    highlights: [
      'Captures both rich text snippets and copied images',
      'Pin frequently used items and filter by content type',
      'Instant keyboard search and paste from anywhere with Alt + V',
    ],
  ),
  FyrAppItem(
    id: 'fyremoji',
    name: 'fyrEmoji',
    badge: 'Emoji Picker',
    description:
        'Integrated Wayland emoji picker with instant search, categories, and one-tap clipboard insert.',
    screenshot: 'fyremoji.png',
    shortcut: 'Super + .',
    icon: Icons.emoji_emotions_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Zero-latency search across full Unicode emoji groups',
      'Remembers recently used picks for fast repeat access',
      'Summon anywhere with Super + .',
    ],
  ),
  FyrAppItem(
    id: 'fyrhelp',
    name: 'fyrHelp',
    badge: 'Cheatsheet',
    description:
        'Interactive keyboard shortcut cheatsheet covering SwayFX, gestures, screenshots, and shell bindings.',
    screenshot: 'fyrhelp.png',
    shortcut: 'Super + Ctrl',
    icon: Icons.keyboard_rounded,
    category: FyrCategory.shell,
    highlights: [
      'Categorized reference for window, workspace, and media keys',
      'Touchpad gesture guide built right into the overlay',
      'Opens instantly with Super + Ctrl whenever you need a hint',
    ],
  ),

  // ===========================================================================
  // SYSTEM & DAILY (fyrTools) — 14 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrfiles',
    name: 'fyrFiles',
    badge: 'File Manager',
    description:
        'Fast native file manager with sidebar bookmarks, previews, tabs, and clean grid/list views.',
    screenshot: 'files.png',
    shortcut: 'Super + F',
    icon: Icons.folder_rounded,
    category: FyrCategory.system,
    highlights: [
      'Breadcrumb path bar, quick search, and multi-view browsing',
      'Drag-and-drop operations with archive and preview support',
      'Matches the obsidian glass theme of fyrDE',
    ],
  ),
  FyrAppItem(
    id: 'fyrterm',
    name: 'fyrTerm',
    alias: 'Terminal',
    description:
        'Custom GPU-accelerated Flutter terminal emulator built for ZSH, tmux, and daily CLI workflows.',
    badge: 'Terminal',
    screenshot: 'terminal.png',
    shortcut: 'Super + T',
    icon: Icons.terminal_rounded,
    category: FyrCategory.system,
    highlights: [
      'Crisp JetBrains Mono rendering with translucent Wayland blur',
      'Full PTY support with tabs, splits, and shell integration',
      'Launches immediately with Super + T',
    ],
  ),
  FyrAppItem(
    id: 'fyrsettings',
    name: 'fyrSettings',
    alias: 'Settings',
    badge: 'Control Center',
    description:
        'Unified control center for displays, SwayFX blur/corners, themes, audio, Bluetooth, and accounts.',
    screenshot: 'settings.png',
    icon: Icons.settings_rounded,
    category: FyrCategory.system,
    highlights: [
      'Live appearance & SwayFX compositor tweaking without editing files',
      'Display scaling, refresh rates, network, and input device panels',
      'Clean sidebar navigation modeled for rapid configuration',
    ],
  ),
  FyrAppItem(
    id: 'fyrmonitor',
    name: 'fyrMonitor',
    alias: 'Task Manager',
    badge: 'Processes',
    description:
        'Live apps, processes, and telemetry monitor with CPU, RAM/swap, disk, and network charts.',
    screenshot: 'fyrmonitor.png',
    shortcut: 'Ctrl + Shift + Esc',
    icon: Icons.monitor_heart_rounded,
    category: FyrCategory.system,
    highlights: [
      'Real-time CPU, memory, swap, disk I/O, and network graphs',
      'Inspect open apps and background processes with quick end-task',
      'Keyboard shortcut Ctrl + Shift + Esc just like you expect',
    ],
  ),
  FyrAppItem(
    id: 'fyrdisks',
    name: 'fyrDisks',
    badge: 'Storage & ISO',
    description:
        'Disk, partition, LUKS encryption, SMART health, and bootable USB ISO flasher utility.',
    screenshot: 'fyrdisks.png',
    icon: Icons.storage_rounded,
    category: FyrCategory.system,
    highlights: [
      'Visual partition map, mount management, and filesystem tools',
      'Built-in LUKS volume unlock and creation workflows',
      'Direct USB ISO image flashing without extra third-party tools',
    ],
  ),
  FyrAppItem(
    id: 'fyrav',
    name: 'fyrAV',
    badge: 'Security',
    description:
        'On-demand malware scanner, quarantine manager, and system security posture dashboard.',
    screenshot: 'av.png',
    icon: Icons.shield_rounded,
    category: FyrCategory.system,
    highlights: [
      'Quick, full, and custom-folder ClamAV-backed scans',
      'Signature update checks and quarantine management UI',
      'Firewall and security health overview in one view',
    ],
  ),
  FyrAppItem(
    id: 'fyrstore',
    name: 'fyrStore',
    badge: 'App Center',
    description:
        'Visual software center for discovering, installing, and updating desktop apps and packages.',
    screenshot: 'store.png',
    icon: Icons.storefront_rounded,
    category: FyrCategory.system,
    highlights: [
      'Browse curated software categories with screenshots and details',
      'One-click install, remove, and update progress tracking',
      'Seamless integration with your Linux package backend',
    ],
  ),
  FyrAppItem(
    id: 'fyrconnect',
    name: 'fyrConnect',
    alias: 'formerly fyrPhone',
    badge: 'Phone Sync',
    description:
        'Mobile device companion for wireless file transfer, notifications, clipboard sync, and phone controls.',
    screenshot: 'phone.png',
    icon: Icons.phonelink_rounded,
    category: FyrCategory.system,
    isNew: true,
    highlights: [
      'Pairs with Android devices for notifications and media remote',
      'Fast LAN file sharing and shared clipboard sync',
      'Battery telemetry and find-my-phone ping right from your desktop',
    ],
  ),
  FyrAppItem(
    id: 'fyrbrowser',
    name: 'fyrBrowser',
    alias: 'Goose',
    badge: 'CEF Browser',
    description:
        'Chromium Embedded Framework web browser tailored to fyrDE with crisp dark chrome and tabs.',
    screenshot: 'goose.png',
    icon: Icons.public_rounded,
    category: FyrCategory.system,
    highlights: [
      'Full modern web rendering powered by CEF',
      'Minimal frosted toolbar that stays out of your way',
      'Bookmarks, history, downloads, and keyboard shortcuts built in',
    ],
  ),
  FyrAppItem(
    id: 'fyrjournal',
    name: 'fyrJournal',
    alias: 'Journal',
    badge: 'Notes',
    description:
        'Distraction-free personal journal and daily note-taking workspace with Markdown and search.',
    screenshot: 'journal.png',
    icon: Icons.menu_book_rounded,
    category: FyrCategory.system,
    highlights: [
      'Date-indexed entries with tags and instant full-text search',
      'Clean Markdown editing with calm obsidian typography',
      'Local-first storage so your thoughts stay yours',
    ],
  ),
  FyrAppItem(
    id: 'fyrcalculator',
    name: 'fyrCalculator',
    alias: 'Calculator',
    badge: 'Math',
    description:
        'High-contrast scientific and standard calculator with expression history and keyboard entry.',
    screenshot: 'calc.png',
    icon: Icons.calculate_rounded,
    category: FyrCategory.system,
    highlights: [
      'Standard, scientific, and programmer-friendly operations',
      'Scrollable tape history with click-to-reuse answers',
      'Full numpad and keyboard shortcut responsiveness',
    ],
  ),
  FyrAppItem(
    id: 'fyrcalendar',
    name: 'fyrCalendar',
    alias: 'Calendar',
    badge: 'Schedule',
    description:
        'Modern desktop calendar with month/week views, color-coded events, and quick agenda creation.',
    screenshot: 'calendar.png',
    icon: Icons.calendar_month_rounded,
    category: FyrCategory.system,
    highlights: [
      'Month, week, and daily agenda perspectives',
      'Fast event creation with recurring schedules and reminders',
      'Clean dark aesthetic matched to fyrTaskbar clock popover',
    ],
  ),
  FyrAppItem(
    id: 'fyrclock',
    name: 'fyrClock',
    alias: 'Clock',
    badge: 'Time',
    description:
        'World Clock, Alarms, Stopwatch, and multi-preset Timers in a sleek high-contrast interface.',
    screenshot: 'clock.png',
    icon: Icons.schedule_rounded,
    category: FyrCategory.system,
    highlights: [
      'Track global timezones with live offset badges',
      'Precision stopwatch with lap splits and countdown timers',
      'Custom alarms integrated with desktop notifications',
    ],
  ),
  FyrAppItem(
    id: 'fyrtorrent',
    name: 'fyrTorrent',
    badge: 'BitTorrent',
    description:
        'Lightweight BitTorrent and magnet-link client with transfer graphs, peer stats, and queue rules.',
    screenshot: 'fyrtorrent.png',
    icon: Icons.downloading_rounded,
    category: FyrCategory.system,
    highlights: [
      'Instant magnet link and .torrent file handling',
      'Live download/upload speed telemetry and peer inspection',
      'Selective file downloads and bandwidth limit controls',
    ],
  ),

  // ===========================================================================
  // CREATIVE STUDIO — 8 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrgraphics',
    name: 'fyrGraphics',
    badge: 'Raster & Vector',
    description:
        'Layered image editor with Simple & Pro modes: Curves, Develop, Photo Looks, Symmetry, Alpha Lock, and Clipping Masks.',
    screenshot: 'fyrgraphics.png',
    icon: Icons.brush_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Switch smoothly between Simple and Advanced Pro workspaces',
      'Curves, Develop adjustments, Color Harmonies & Stamp Visible',
      'Symmetry drawing, Alpha Lock, and non-destructive Clipping Masks',
    ],
  ),
  FyrAppItem(
    id: 'devign',
    name: 'devign',
    badge: 'UI/UX Design',
    description:
        'Vector UI/UX design & prototyping studio with Auto-Layout, Master Components, Bezier pen, tokens, and Flutter/CSS/SVG export.',
    screenshot: 'devign.png',
    icon: Icons.design_services_rounded,
    category: FyrCategory.creative,
    isNew: true,
    highlights: [
      'Multi-page frames, Auto-Layout flexbox containers & color tokens',
      'Reusable Master Components, Instances & live Prototype Player',
      'Direct Flutter, CSS, SVG, and PNG code & asset export',
    ],
  ),
  FyrAppItem(
    id: 'fyrdirector',
    name: 'fyrDirector',
    badge: 'Video NLE',
    description:
        'Multi-track non-linear video editor with timeline scrubbing, transitions, color tools, and FFmpeg export.',
    screenshot: 'fyrdirector.png',
    icon: Icons.movie_creation_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Multi-track video & audio timeline with razor and ripple editing',
      'Real-time preview monitor with keyframe and transition controls',
      'Hardware-friendly encoding presets for web and desktop',
    ],
  ),
  FyrAppItem(
    id: 'fyrdaw',
    name: 'fyrDAW',
    alias: 'Sound Booth',
    badge: 'Audio DAW',
    description:
        'Digital Audio Workstation with multi-track arrangement, piano roll MIDI, mixer console, and effects rack.',
    screenshot: 'daw.png',
    icon: Icons.graphic_eq_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Multi-track audio & MIDI sequencing with snap-to-grid editing',
      'Integrated mixer faders, panning, meters, and FX chain',
      'Also installable standalone via the Fyr Creative Suite',
    ],
  ),
  FyrAppItem(
    id: 'fyrphotos',
    name: 'fyrPhotos',
    alias: 'Photos',
    badge: 'Photo Library',
    description:
        'Fast photo library and viewer with albums, EXIF metadata inspector, zoomable canvas, and quick edits.',
    screenshot: 'fyrphotos.png',
    icon: Icons.photo_library_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Smooth timeline grid with instant album filtering',
      'Lossless zoom, slideshow mode, and EXIF camera details',
      'Quick crop, rotate, and share right from the viewer',
    ],
  ),
  FyrAppItem(
    id: 'fyrcamera',
    name: 'fyrCamera',
    alias: 'Camera',
    badge: 'Capture',
    description:
        'Low-latency webcam photo & video capture app with timers, framing grid, and device switching.',
    screenshot: 'camera.png',
    icon: Icons.photo_camera_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Instant V4L2/PipeWire camera detection and resolution picker',
      'Photo burst, countdown timer, and video recording modes',
      'Direct gallery strip to review your latest captures',
    ],
  ),
  FyrAppItem(
    id: 'fyrmusic',
    name: 'fyrMusic',
    alias: 'Music',
    badge: 'Audio Player',
    description:
        'Local music library and player with album art, playlists, queue management, and MPRIS taskbar controls.',
    screenshot: 'music.png',
    icon: Icons.music_note_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Rich library browser sorted by artist, album, and playlists',
      'Lossless FLAC, MP3, OGG, and WAV playback',
      'Native MPRIS integration with fyrTaskbar media controls',
    ],
  ),
  FyrAppItem(
    id: 'fyrvideo',
    name: 'fyrVideo',
    alias: 'Watchbox',
    badge: 'Video Player',
    description:
        'Hardware-accelerated video player with clean OSD controls, subtitle tracks, and chapter seeking.',
    screenshot: 'seinfeld.png',
    icon: Icons.play_circle_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Smooth playback for MKV, MP4, WebM, and high-bitrate video',
      'Subtitle styling, audio track switching, and speed controls',
      'Borderless theater mode that shines on SwayFX',
    ],
  ),
  FyrAppItem(
    id: 'fyremu',
    name: 'fyrEmu',
    badge: 'Retro Gaming',
    description:
        'Multi-platform retro game emulator frontend with library box art, save states, and controller mapping.',
    screenshot: 'fyremu.png',
    icon: Icons.sports_esports_rounded,
    category: FyrCategory.creative,
    highlights: [
      'Unified library for classic console ROMs with cover art',
      'Instant save states, shaders, and rewind support',
      'Plug-and-play gamepad configuration',
    ],
  ),

  // ===========================================================================
  // OFFICE SUITE — 5 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrdocs',
    name: 'fyrDocs',
    badge: 'Word & ODT',
    description:
        'Rich word processor supporting OpenDocument (.odt) and Word (.docx) with clean page layout tools.',
    screenshot: 'fyrdocs.png',
    icon: Icons.article_rounded,
    category: FyrCategory.office,
    highlights: [
      'Native .odt and .docx read/write compatibility',
      'Styles, headers, tables, images, and PDF export',
      'Clean, clutter-free writing ribbon with dark mode support',
    ],
  ),
  FyrAppItem(
    id: 'fyrsheets',
    name: 'fyrSheets',
    badge: 'Spreadsheets',
    description:
        'Spreadsheet studio for OpenDocument (.ods), Excel (.xlsx), and CSV files with live formulas and charts.',
    screenshot: 'fyrsheets.png',
    icon: Icons.table_chart_rounded,
    category: FyrCategory.office,
    highlights: [
      'Formula engine, cell formatting, sorting, and multi-sheet tabs',
      'Seamless .ods, .xlsx, and .csv import/export',
      'Snappy virtualized grid built in native Flutter',
    ],
  ),
  FyrAppItem(
    id: 'fyrslides',
    name: 'fyrSlides',
    badge: 'Presentations',
    description:
        'Presentation studio for OpenDocument (.odp) and PowerPoint (.pptx) decks with live presenter mode.',
    screenshot: 'fyrslides.png',
    icon: Icons.slideshow_rounded,
    category: FyrCategory.office,
    highlights: [
      'Slide canvas with shapes, typography, media, and alignment guides',
      'Open and export .odp and .pptx slide decks effortlessly',
      'Fullscreen presentation playback with smooth transitions',
    ],
  ),
  FyrAppItem(
    id: 'fyrpdf',
    name: 'fyrPDF',
    badge: 'PDF Reader',
    description:
        'Fast native PDF reader with thumbnails, table of contents outline, bookmarks, in-document search, and dark reading mode.',
    screenshot: 'fyrpdf.png',
    icon: Icons.picture_as_pdf_rounded,
    category: FyrCategory.office,
    isNew: true,
    highlights: [
      'Crisp page rendering with sidebar thumbnails and table of contents',
      'Highlight, annotate, fill forms, and search across large PDFs',
      'Split, merge, rotate, and export pages without heavy bloat',
    ],
  ),
  FyrAppItem(
    id: 'fyrtext',
    name: 'fyrText',
    badge: 'Text Editor',
    description:
        'Lightweight tabbed text and code-aware notepad with syntax highlighting, find/replace, and instant launch.',
    screenshot: 'text.png',
    icon: Icons.edit_note_rounded,
    category: FyrCategory.office,
    highlights: [
      'Multi-tab editing with regex find & replace',
      'Syntax highlighting for config files, JSON, Markdown, and scripts',
      'Zero-lag startup for quick notes and config tweaks',
    ],
  ),

  // ===========================================================================
  // DEV & VIRTUALIZATION — 6 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrcode',
    name: 'fyrCode',
    badge: 'Agentic IDE',
    description:
        'Agentic code editor & IDE with built-in AI coding assistant, inline diffs, integrated terminal, and LSP support.',
    screenshot: 'code.png',
    icon: Icons.code_rounded,
    category: FyrCategory.dev,
    highlights: [
      'Integrated AI agent with inline diff review and multi-file edits',
      'Language Server Protocol diagnostics, completions & go-to-definition',
      'Built-in Git panel, project search, and native terminal pane',
    ],
  ),
  FyrAppItem(
    id: 'fyrapi',
    name: 'fyrAPI',
    badge: 'HTTP Client',
    description:
        'REST & HTTP API workbench for crafting requests, managing environments, and inspecting JSON responses.',
    screenshot: 'fyrapi.png',
    icon: Icons.api_rounded,
    category: FyrCategory.dev,
    highlights: [
      'Saved collections, auth presets, and environment variables',
      'Formatted JSON/header/timing response viewer',
      'Zero Electron overhead — starts instantaneously',
    ],
  ),
  FyrAppItem(
    id: 'fyrdb',
    name: 'fyrDB',
    badge: 'SQL & ER',
    description:
        'Universal database manager, SQL IDE, and visual ER diagram studio for Postgres, MySQL, SQLite, and more.',
    screenshot: 'fyrdb.png',
    icon: Icons.dns_rounded,
    category: FyrCategory.dev,
    highlights: [
      'Schema explorer, inline cell editing, and query execution plans',
      'Auto-generated visual ER diagrams for complex databases',
      'Syntax-highlighted SQL editor with saved query history',
    ],
  ),
  FyrAppItem(
    id: 'fyrpods',
    name: 'fyrPods',
    badge: 'Containers',
    description:
        'Container, pod, image, volume, and Compose stack manager supporting both Podman and Docker.',
    screenshot: 'fyrpods.png',
    icon: Icons.inventory_2_rounded,
    category: FyrCategory.dev,
    highlights: [
      'Live container logs, exec shell, and CPU/RAM stats',
      'Manage images, networks, volumes, and Compose stacks visually',
      'First-class support for rootless Podman and Docker engines',
    ],
  ),
  FyrAppItem(
    id: 'fyrvirt',
    name: 'fyrVirt',
    alias: 'fyrVM',
    badge: 'KVM / QEMU',
    description:
        'Virtual Machine Manager for creating, snapshotting, and running KVM/QEMU/libvirt guests effortlessly.',
    screenshot: 'fyrvirt.png',
    icon: Icons.computer_rounded,
    category: FyrCategory.dev,
    highlights: [
      'Guided VM creation wizard with ISO boot and hardware tuning',
      'Live graphical console, snapshots, and resource telemetry',
      'Clean desktop alternative to legacy libvirt frontends',
    ],
  ),

  // ===========================================================================
  // CLI & MOBILE — 3 apps
  // ===========================================================================
  FyrAppItem(
    id: 'fyrpak',
    name: 'fyrpak',
    badge: 'Go CLI / AUR',
    description:
        'Native Go package manager, yay-compatible AUR helper, and built-in fyrDE updater & diagnostics CLI.',
    screenshot: 'fyrpak.png',
    icon: Icons.bolt_rounded,
    category: FyrCategory.cliMobile,
    isNew: true,
    highlights: [
      'Full pacman/AUR workflow: -Syu, -S, -Ss, -Si, -R, -Q, -Yc, -Ps, -G',
      'Built-in fyrDE lifecycle: fyrpak fyr update, status, doctor & clean',
      'Single compiled Go binary with snappy colored terminal output',
    ],
  ),
  FyrAppItem(
    id: 'fyrandroid',
    name: 'fyrAndroid',
    badge: 'Kotlin Launcher',
    description:
        'Native Kotlin Android launcher bringing the FyrDE squircle grid, frosted dock, fyrSearch drawer, and Quick Settings to mobile.',
    screenshot: 'fyrandroid.png',
    icon: Icons.smartphone_rounded,
    category: FyrCategory.cliMobile,
    isNew: true,
    highlights: [
      'Paged 4x5 squircle home grid with frosted dock and Fyr accents',
      'Swipe-up fyrSearch app drawer with autofocus & inline calculator',
      'Swipe-down Fyr Quick Settings sheet with live Light/Dark theming',
    ],
  ),
  FyrAppItem(
    id: 'fyrfetch',
    name: 'fyrfetch',
    badge: 'System Fetch',
    description:
        'Custom lightweight terminal system-information fetch utility styled with fyrDE ASCII branding and palette.',
    screenshot: 'fyrfetch.png',
    icon: Icons.auto_awesome_rounded,
    category: FyrCategory.cliMobile,
    highlights: [
      'Displays kernel, SwayFX session, packages, CPU, GPU, and RAM',
      'Zero-dependency shell integration installed directly to PATH',
      'Matching obsidian/purple/cyan color swatches out of the box',
    ],
  ),
];

List<FyrAppItem> appsForCategory(FyrCategory category) {
  return fyrAppsCatalog.where((app) => app.category == category).toList();
}
