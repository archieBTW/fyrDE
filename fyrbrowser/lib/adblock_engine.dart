class AdBlockEngine {
  static const List<String> adDomains = [
    'googleadservices.com',
    'doubleclick.net',
    'googlesyndication.com',
    'google-analytics.com',
    'adnxs.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'appnexus.com',
    'criteo.com',
    'amazon-adsystem.com',
    'facebook.net',
    'taboola.com',
    'outbrain.com',
    'scorecardresearch.com',
    'quantserve.com',
  ];

  static const List<String> adSelectors = [
    '.ad-container',
    '.ad-slot',
    '.ad-wrapper',
    '.banner-ad',
    'iframe[src*="ads"]',
    'iframe[src*="googleads"]',
    'div[id*="google_ads"]',
    '#ad-banner',
    '#ad-sidebar',
    '#ad-wrapper',
    '.adsbygoogle',
    'ins.adsbygoogle',
    '.text-ad',
    '.sponsored-post',
    '.promoted-post',
  ];

  static String get injectionScript {
    // Return a CSS-only injection to avoid JS "Illegal invocation" errors
    final selectors = adSelectors.join(',');
    return '''
      (function() {
        if (window._fyr_adblock_css_initialized) return;
        window._fyr_adblock_css_initialized = true;
        const style = document.createElement('style');
        style.id = 'fyr-adblock-styles';
        style.innerHTML = '$selectors { display: none !important; visibility: hidden !important; pointer-events: none !important; }';
        document.head.appendChild(style);
        console.log('FyrBrowser AdBlock Active (CSS-Only Mode)');
      })();
    ''';
  }

  static List<String> get selectors => adSelectors;
}
