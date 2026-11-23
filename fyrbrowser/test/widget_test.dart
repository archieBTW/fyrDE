import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrbrowser/adblock_engine.dart';
import 'package:fyrbrowser/browser_models.dart';
import 'package:fyrbrowser/home_page.dart';
import 'package:fyrbrowser/url_bar.dart';
import 'package:webview_cef/webview_cef.dart';

void main() {
  group('AdBlockEngine', () {
    test('extracts normalized hostnames without www prefix', () {
      expect(
        AdBlockEngine.extractHost('https://WWW.Example.com/path?a=1'),
        'example.com',
      );
      expect(AdBlockEngine.extractHost('sub.domain.org'), 'sub.domain.org');
      expect(AdBlockEngine.extractHost('   '), '');
    });

    test('cosmetic script uses safe CSS selectors without fetch/XHR hooks', () {
      final script = AdBlockEngine.cosmeticCssScript;
      expect(script.contains('XMLHttpRequest'), isFalse);
      expect(script.contains('window.fetch'), isFalse);
      expect(script.contains('[id*="ad"]'), isFalse);
      expect(script.contains('.adsbygoogle'), isTrue);
    });
  });

  group('BrowserModels & Navigation', () {
    test('defaults homepage to start.duckduckgo.com and migrates fyr://home', () {
      final defaults = BrowserSettings();
      expect(defaults.homePage, kDefaultHomePage);
      expect(defaults.homePage, 'https://start.duckduckgo.com');

      final migrated = BrowserSettings.fromJson({'homePage': 'fyr://home'});
      expect(migrated.homePage, 'https://start.duckduckgo.com');
    });

    test('BrowserTab defaults isReady to false before CEF init', () {
      final controller = WebviewManager().createWebView();
      final tab = BrowserTab(id: 'tab_1', controller: controller);
      expect(tab.isReady, isFalse);
      expect(tab.url, 'https://start.duckduckgo.com');
    });

    test('resolveNavigationInput routes URLs vs search queries', () {
      expect(
        resolveNavigationInput('  ', SearchEngine.duckDuckGo),
        'https://start.duckduckgo.com',
      );
      expect(
        resolveNavigationInput('https://google.com', SearchEngine.duckDuckGo),
        'https://google.com',
      );
      expect(
        resolveNavigationInput('example.com/test', SearchEngine.duckDuckGo),
        'https://example.com/test',
      );
      expect(
        resolveNavigationInput('localhost:8080', SearchEngine.duckDuckGo),
        'http://localhost:8080',
      );
      expect(
        resolveNavigationInput('how to cook rice', SearchEngine.google),
        'https://www.google.com/search?q=how%20to%20cook%20rice',
      );
    });

    test('BrowserSettings whitelist matching supports subdomains', () {
      final settings = BrowserSettings(adBlockWhitelist: ['example.com']);
      expect(settings.isHostWhitelisted('example.com'), isTrue);
      expect(settings.isHostWhitelisted('www.example.com'), isTrue);
      expect(settings.isHostWhitelisted('docs.example.com'), isTrue);
      expect(settings.isHostWhitelisted('badexample.com'), isFalse);

      final roundTrip = BrowserSettings.fromJson(settings.toJson());
      expect(roundTrip.adBlockEnabled, isTrue);
      expect(roundTrip.adBlockWhitelist, ['example.com']);
    });
  });

  group('Error Widget', () {
    testWidgets('FyrErrorPage triggers retry and home callbacks',
        (tester) async {
      bool retried = false;
      bool wentHome = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FyrErrorPage(
              error: const LoadErrorInfo(
                errorCode: -105,
                errorText: 'ERR_NAME_NOT_RESOLVED',
                failedUrl: 'https://missing.invalid',
              ),
              onRetry: () => retried = true,
              onGoHome: () => wentHome = true,
            ),
          ),
        ),
      );

      expect(find.text('Server not found'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      await tester.tap(find.text('Go Home'));
      expect(retried, isTrue);
      expect(wentHome, isTrue);
    });
  });

  group('FyrUrlBar History Suggestions', () {
    final sampleBookmarks = [
      {'title': 'GitHub', 'url': 'https://github.com'},
    ];
    final sampleHistory = [
      {'title': 'GitLab Projects', 'url': 'https://gitlab.com/projects'},
      {'title': 'Arch Linux Wiki', 'url': 'https://wiki.archlinux.org'},
    ];

    testWidgets('clicking a history suggestion submits its URL',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      String? submittedUrl;
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: FyrUrlBar(
                controller: controller,
                focusNode: focusNode,
                currentUrl: 'https://start.duckduckgo.com',
                searchEngineLabel: 'DuckDuckGo',
                isError: false,
                isBookmarked: false,
                showInstallPwa: false,
                bookmarks: sampleBookmarks,
                history: sampleHistory,
                onSubmit: (url) => submittedUrl = url,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('browser-url-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('browser-url-field')), 'git');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('url-suggestion-0')), findsOneWidget);
      expect(find.byKey(const Key('url-suggestion-1')), findsOneWidget);

      // Tap the second suggestion (GitLab Projects) and ensure it submits
      // without being dismissed by focus loss on pointer down.
      await tester.tap(find.byKey(const Key('url-suggestion-1')));
      await tester.pumpAndSettle();

      expect(submittedUrl, 'https://gitlab.com/projects');
    });

    testWidgets('arrow keys + enter navigate and select history suggestions',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      String? submittedUrl;
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: FyrUrlBar(
                controller: controller,
                focusNode: focusNode,
                currentUrl: 'https://start.duckduckgo.com',
                searchEngineLabel: 'DuckDuckGo',
                isError: false,
                isBookmarked: false,
                showInstallPwa: false,
                bookmarks: sampleBookmarks,
                history: sampleHistory,
                onSubmit: (url) => submittedUrl = url,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('browser-url-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('browser-url-field')), 'git');
      await tester.pumpAndSettle();

      // Down twice -> selects index 1 (GitLab), then Up once -> back to index 0 (GitHub), then Down -> index 1
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(submittedUrl, 'https://gitlab.com/projects');
    });

    testWidgets('escape closes suggestions dropdown', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: FyrUrlBar(
                controller: controller,
                focusNode: focusNode,
                currentUrl: 'https://start.duckduckgo.com',
                searchEngineLabel: 'DuckDuckGo',
                isError: false,
                isBookmarked: false,
                showInstallPwa: false,
                bookmarks: sampleBookmarks,
                history: sampleHistory,
                onSubmit: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('browser-url-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('browser-url-field')), 'arch');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('url-suggestion-0')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('url-suggestion-0')), findsNothing);
    });
  });
}
