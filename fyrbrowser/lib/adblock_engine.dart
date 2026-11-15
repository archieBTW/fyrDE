/// Safe network blocklist and CSS-only cosmetic filtering for FyrBrowser.
///
/// Network blocking is enforced natively in C++ via CEF's
/// `OnBeforeResourceLoad` with subdomain-boundary matching and first-party
/// exemption, avoiding fragile JS `fetch`/`XHR` monkey-patching.
class AdBlockEngine {
  static const List<String> blockedDomains = [
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'google-analytics.com',
    'googletagmanager.com',
    'adnxs.com',
    'criteo.com',
    'criteo.net',
    'taboola.com',
    'outbrain.com',
    'pubmatic.com',
    'rubiconproject.com',
    'openx.net',
    'casalemedia.com',
    'adsrvr.org',
    'moatads.com',
    'scorecardresearch.com',
    'quantserve.com',
    'zedo.com',
    'adroll.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'mgid.com',
    'revcontent.com',
    'amazon-adsystem.com',
    'mediavine.com',
    'adthrive.com',
    '2mdn.net',
    'chartbeat.com',
    'hotjar.com',
    'mouseflow.com',
    'smartadserver.com',
    'serving-sys.com',
    'yieldmo.com',
    'sharethrough.com',
  ];

  /// Specific ad-slot selectors only (no broad substring wildcards like `[id*="ad"]`).
  static const List<String> cosmeticSelectors = [
    'ins.adsbygoogle',
    '.adsbygoogle',
    'div[id^="google_ads_"]',
    'div[id^="div-gpt-ad"]',
    '[data-google-query-id]',
    'amp-ad',
    'amp-embed',
    'amp-sticky-ad',
  ];

  static const String _styleElementId = '__fyr_adblock_css__';

  /// Extracts a normalized lowercase hostname from [urlOrHost], stripping
  /// a leading `www.` so allowlisting works across `www.` and apex hosts.
  static String extractHost(String urlOrHost) {
    final trimmed = urlOrHost.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    String host = trimmed;
    if (trimmed.contains('://')) {
      host = Uri.tryParse(trimmed)?.host.toLowerCase() ?? '';
    } else if (trimmed.contains('/')) {
      host = Uri.tryParse('https://$trimmed')?.host.toLowerCase() ?? '';
    }
    if (host.startsWith('www.') && host.length > 4) {
      host = host.substring(4);
    }
    return host;
  }

  /// Idempotent CSS-only cosmetic hiding script (no JS globals or API hooks).
  static String get cosmeticCssScript {
    final cssRules =
        '${cosmeticSelectors.join(', ')} { display: none !important; }';
    final escapedCss = cssRules.replaceAll("'", "\\'");
    return '''
      (function() {
        var id = '$_styleElementId';
        if (document.getElementById(id)) return;
        var root = document.head || document.documentElement;
        if (!root) return;
        var style = document.createElement('style');
        style.id = id;
        style.textContent = '$escapedCss';
        root.appendChild(style);
      })();
    ''';
  }

  /// Removes injected cosmetic CSS when AdBlock is disabled or allowlisted.
  static String get removeCosmeticCssScript => '''
      (function() {
        var el = document.getElementById('$_styleElementId');
        if (el && el.parentNode) el.parentNode.removeChild(el);
      })();
    ''';
}
