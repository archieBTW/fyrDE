import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:json_view/json_view.dart';
import 'api_provider.dart';
import 'fyr_theme.dart';
import 'widgets/traffic_lights.dart';
import 'widgets/key_value_editor.dart';
import 'widgets/sidebar.dart';
import 'widgets/save_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1300, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  FyrTheme.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiProvider()),
      ],
      child: const FyrApiApp(),
    ),
  );
}

class FyrApiApp extends StatelessWidget {
  const FyrApiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: FyrTheme.themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Fyr Api',
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: FyrTheme.accentColor,
            textTheme: GoogleFonts.interTextTheme(),
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: FyrTheme.accentColor,
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late TabController _requestTabController;
  late TabController _responseTabController;
  bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _requestTabController = TabController(length: 3, vsync: this);
    _responseTabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
    final inputColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          if (_showSidebar) const Sidebar(),
          Expanded(
            child: Column(
              children: [
                // Custom Title Bar
                DragToMoveArea(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: bgColor,
                      border: Border(
                        bottom: BorderSide(color: borderColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!_showSidebar) ...[
                          const TrafficLights(),
                          const SizedBox(width: 24),
                        ] else ...[
                          IconButton(
                            icon: const Icon(Icons.menu_open, size: 20),
                            onPressed: () => setState(() => _showSidebar = false),
                          ),
                        ],
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_showSidebar) const SizedBox(width: 48),
                                Text(
                                  'Fyr Api',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: FyrTheme.accentColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: FyrTheme.accentColor.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    api.activeEnvironment.name,
                                    style: TextStyle(fontSize: 10, color: FyrTheme.accentColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showSidebar) const SizedBox(width: 48),
                        if (!_showSidebar) const SizedBox(width: 80),
                      ],
                    ),
                  ),
                ),

                // URL Bar & Buttons
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      if (!_showSidebar)
                        IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => setState(() => _showSidebar = true),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: inputColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: api.method,
                            onChanged: (val) => api.setMethod(val!),
                            items: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']
                                .map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m,
                                        style: TextStyle(
                                          color: _getMethodColor(m),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: api.url)..selection = TextSelection.collapsed(offset: api.url.length),
                          decoration: InputDecoration(
                            hintText: 'https://api.example.com/v1/resource',
                            filled: true,
                            fillColor: inputColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onChanged: (val) => api.setUrl(val),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => showDialog(context: context, builder: (context) => const SaveDialog()),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: api.isLoading ? null : () => api.sendRequest(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FyrTheme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: api.isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Send'),
                      ),
                    ],
                  ),
                ),

                // Main Content Area
                Expanded(
                  child: Row(
                    children: [
                      // Request Builder
                      Expanded(
                        child: Column(
                          children: [
                            TabBar(
                              controller: _requestTabController,
                              labelColor: FyrTheme.accentColor,
                              unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                              indicatorColor: FyrTheme.accentColor,
                              tabs: const [
                                Tab(text: 'Params'),
                                Tab(text: 'Headers'),
                                Tab(text: 'Body'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _requestTabController,
                                children: [
                                  KeyValueEditor(
                                    items: api.params,
                                    onAdd: api.addParam,
                                    onRemove: api.removeParam,
                                  ),
                                  KeyValueEditor(
                                    items: api.headers,
                                    onAdd: api.addHeader,
                                    onRemove: api.removeHeader,
                                  ),
                                  _buildBodyEditor(api, inputColor),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      VerticalDivider(width: 1, color: borderColor),

                      // Response Viewer
                      Expanded(
                        child: Column(
                          children: [
                            _buildMetadataRibbon(api, isDark, inputColor),
                            TabBar(
                              controller: _responseTabController,
                              labelColor: FyrTheme.accentColor,
                              unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                              indicatorColor: FyrTheme.accentColor,
                              tabs: const [
                                Tab(text: 'Body'),
                                Tab(text: 'Headers'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _responseTabController,
                                children: [
                                  _buildResponseBody(api, isDark),
                                  _buildResponseHeaders(api, isDark),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyEditor(ApiProvider api, Color inputColor) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: TextEditingController(text: api.body)..selection = TextSelection.collapsed(offset: api.body.length),
        maxLines: null,
        expands: true,
        style: GoogleFonts.firaCode(fontSize: 13),
        decoration: InputDecoration(
          hintText: '{ "key": "value" }',
          filled: true,
          fillColor: inputColor,
          border: const OutlineInputBorder(borderSide: BorderSide.none),
        ),
        onChanged: (val) => api.setBody(val),
      ),
    );
  }

  Widget _buildMetadataRibbon(ApiProvider api, bool isDark, Color inputColor) {
    if (api.response == null) {
      return Container(
        height: 40,
        width: double.infinity,
        alignment: Alignment.center,
        color: inputColor,
        child: const Text('No Response Yet'),
      );
    }

    final statusCode = api.response!.statusCode;
    final statusColor = statusCode >= 200 && statusCode < 300
        ? Colors.greenAccent
        : (statusCode >= 400 ? Colors.redAccent : Colors.orangeAccent);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: inputColor,
      child: Row(
        children: [
          Text(
            '$statusCode ${api.response!.reasonPhrase ?? ""}',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _buildInfoChip(
            '${api.responseTime?.inMilliseconds ?? 0} ms',
            Icons.timer_outlined,
            isDark,
          ),
          const SizedBox(width: 12),
          _buildInfoChip(
            '${api.payloadSizeKb.toStringAsFixed(2)} KB',
            Icons.data_usage_outlined,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 14, color: isDark ? Colors.white54 : Colors.black54),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildResponseBody(ApiProvider api, bool isDark) {
    if (api.response == null) return const Center(child: Text('Hit Send to see response'));

    final contentType = api.response!.headers['content-type'] ?? '';
    bool isJson = contentType.contains('application/json');

    if (isJson) {
      try {
        final decoded = json.decode(api.response!.body);
        return JsonView(
          json: decoded,
        );
      } catch (e) {
        // Fallback to text
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: HighlightView(
        api.response!.body,
        language: isJson ? 'json' : 'text',
        theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
        padding: const EdgeInsets.all(12),
        textStyle: GoogleFonts.firaCode(fontSize: 13),
      ),
    );
  }

  Widget _buildResponseHeaders(ApiProvider api, bool isDark) {
    if (api.response == null) return const SizedBox();
    final headers = api.response!.headers;
    return ListView.builder(
      itemCount: headers.length,
      itemBuilder: (context, index) {
        final key = headers.keys.elementAt(index);
        final value = headers[key];
        return ListTile(
          dense: true,
          title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          subtitle: Text(value ?? '', style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }

  Color _getMethodColor(String method) {
    switch (method) {
      case 'GET': return Colors.greenAccent;
      case 'POST': return Colors.blueAccent;
      case 'PUT': return Colors.orangeAccent;
      case 'PATCH': return Colors.purpleAccent;
      case 'DELETE': return Colors.redAccent;
      default: return Colors.grey;
    }
  }
}
