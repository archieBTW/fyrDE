import 'package:webview_cef/webview_cef.dart';
import 'adblock_engine.dart';

const String kDefaultHomePage = 'https://start.duckduckgo.com';

bool isInternalUrl(String url) =>
    url == 'about:blank' || url.startsWith('fyr://');

enum SearchEngine {
  duckDuckGo('DuckDuckGo', 'https://start.duckduckgo.com/?q='),
  google('Google', 'https://www.google.com/search?q='),
  brave('Brave Search', 'https://search.brave.com/search?q='),
  startpage('Startpage', 'https://www.startpage.com/do/search?query='),
  bing('Bing', 'https://www.bing.com/search?q=');

  final String label;
  final String searchBaseUrl;

  const SearchEngine(this.label, this.searchBaseUrl);

  String buildSearchUrl(String query) =>
      '$searchBaseUrl${Uri.encodeComponent(query)}';

  static SearchEngine fromName(String? rawName) {
    for (final engine in SearchEngine.values) {
      if (engine.name == rawName) return engine;
    }
    return SearchEngine.duckDuckGo;
  }
}

class LoadErrorInfo {
  final int errorCode;
  final String errorText;
  final String failedUrl;

  const LoadErrorInfo({
    required this.errorCode,
    required this.errorText,
    required this.failedUrl,
  });

  String get friendlyTitle {
    switch (errorCode) {
      case -105:
        return 'Server not found';
      case -106:
        return 'No internet connection';
      case -102:
        return 'Connection refused';
      case -118:
        return 'Connection timed out';
      case -200:
      case -201:
      case -202:
        return 'Certificate security error';
      default:
        return 'Unable to load page';
    }
  }
}

class BrowserSettings {
  SearchEngine searchEngine;
  String homePage;
  bool adBlockEnabled;
  List<String> adBlockWhitelist;

  BrowserSettings({
    this.searchEngine = SearchEngine.duckDuckGo,
    this.homePage = kDefaultHomePage,
    this.adBlockEnabled = true,
    List<String>? adBlockWhitelist,
  }) : adBlockWhitelist = adBlockWhitelist ?? [];

  bool isHostWhitelisted(String host) {
    final normalized = AdBlockEngine.extractHost(host);
    if (normalized.isEmpty) return false;
    for (final entry in adBlockWhitelist) {
      final allowed = AdBlockEngine.extractHost(entry);
      if (allowed.isEmpty) continue;
      if (normalized == allowed || normalized.endsWith('.$allowed')) {
        return true;
      }
    }
    return false;
  }

  void toggleWhitelistHost(String host) {
    final normalized = AdBlockEngine.extractHost(host);
    if (normalized.isEmpty) return;
    if (adBlockWhitelist.contains(normalized)) {
      adBlockWhitelist.remove(normalized);
    } else {
      adBlockWhitelist.add(normalized);
    }
  }

  Map<String, dynamic> toJson() => {
        'searchEngine': searchEngine.name,
        'homePage': homePage,
        'adBlockEnabled': adBlockEnabled,
        'adBlockWhitelist': adBlockWhitelist,
      };

  factory BrowserSettings.fromJson(Map<String, dynamic> json) {
    final rawWhitelist = json['adBlockWhitelist'];
    final whitelist = rawWhitelist is List
        ? rawWhitelist
            .map((e) => AdBlockEngine.extractHost(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : <String>[];
    final rawHome = (json['homePage'] as String?)?.trim();
    final resolvedHome =
        (rawHome != null && rawHome.isNotEmpty && rawHome != 'fyr://home')
            ? rawHome
            : kDefaultHomePage;
    return BrowserSettings(
      searchEngine: SearchEngine.fromName(json['searchEngine'] as String?),
      homePage: resolvedHome,
      adBlockEnabled: json['adBlockEnabled'] is bool
          ? json['adBlockEnabled'] as bool
          : true,
      adBlockWhitelist: whitelist,
    );
  }
}

class BrowserTab {
  final String id;
  final WebViewController controller;
  String title;
  String url;
  bool isReady;
  bool isLoading;
  bool canGoBack;
  bool canGoForward;
  bool isPwa;
  String? faviconUrl;
  double zoomLevel;
  int blockedCount;
  LoadErrorInfo? loadError;

  BrowserTab({
    required this.id,
    required this.controller,
    this.title = 'New Tab',
    this.url = kDefaultHomePage,
    this.isReady = false,
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.isPwa = false,
    this.faviconUrl,
    this.zoomLevel = 0.0,
    this.blockedCount = 0,
    this.loadError,
  });
}

/// Resolves user input from the address bar into a target URL.
String resolveNavigationInput(String rawInput, SearchEngine engine) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) return kDefaultHomePage;

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('file://') ||
      lower.startsWith('about:')) {
    return trimmed;
  }

  final hasSpaces = trimmed.contains(RegExp(r'\s'));
  if (!hasSpaces &&
      (lower.startsWith('localhost') || lower.startsWith('127.0.0.1'))) {
    return 'http://$trimmed';
  }
  if (!hasSpaces &&
      trimmed.contains('.') &&
      !trimmed.startsWith('.') &&
      !trimmed.endsWith('.')) {
    return 'https://$trimmed';
  }

  return engine.buildSearchUrl(trimmed);
}
