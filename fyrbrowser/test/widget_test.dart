import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrbrowser/adblock_engine.dart';
import 'package:fyrbrowser/browser_models.dart';
import 'package:fyrbrowser/home_page.dart';

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
    test('resolveNavigationInput routes URLs vs search queries', () {
      expect(
        resolveNavigationInput('fyr://home', SearchEngine.duckDuckGo),
        kFyrHomeUrl,
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

  group('Home & Error Widgets', () {
    testWidgets('FyrHomePage renders search input and navigates on submit',
        (tester) async {
      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FyrHomePage(
              searchEngine: SearchEngine.duckDuckGo,
              adBlockEnabled: true,
              bookmarks: const [
                {'title': 'GitHub', 'url': 'https://github.com'},
              ],
              history: const [],
              onNavigate: (value) => navigatedTo = value,
              onOpenSettings: () {},
            ),
          ),
        ),
      );

      expect(find.text('FyrBrowser'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'flutter linux');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(navigatedTo, 'flutter linux');
    });

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
}
