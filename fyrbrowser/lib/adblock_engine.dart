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
    'ads-twitter.com',
    'adform.net',
    'advertising.com',
    'ads-tw.com',
    'adnxs-simple.com',
    'adzerk.net',
    'bidsync.com',
    'carbonads.net',
    'clickbank.net',
    'creative-serving.com',
    'directrev.com',
    'exponential.com',
    'gumgum.com',
    'lijit.com',
    'mathtag.com',
    'media.net',
    'moatads.com',
    'mopub.com',
    'nativo.com',
    'revcontent.com',
    'sharethrough.com',
    'smartadserver.com',
    'yieldmo.com',
    'zedo.com',
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
    '.advertisement',
    '.ad-unit',
    '.ad-box',
    '.ad-label',
    '.ad-content',
    'aside[id*="ad"]',
    'div[id*="ad-box"]',
    'div[class*="ad-box"]',
    '.ads-container',
    '#sidebar-ads',
    '.ad-visible',
    '.ad-placement',
  ];

  static String get injectionScript {
    final selectors = adSelectors.join(',');
    final domainsJson = '["${adDomains.join('","')}"]';
    
    return '''
      (function() {
        if (window._fyr_adblock_initialized) return;
        window._fyr_adblock_initialized = true;

        // 1. CSS Hiding
        const style = document.createElement('style');
        style.id = 'fyr-adblock-styles';
        style.innerHTML = '$selectors { display: none !important; visibility: hidden !important; pointer-events: none !important; height: 0 !important; width: 0 !important; margin: 0 !important; padding: 0 !important; opacity: 0 !important; }';
        document.head.appendChild(style);

        // 2. Request Interception (Monkey-patch fetch and XHR)
        const adDomains = $domainsJson;
        
        const isAdUrl = (url) => {
          if (!url) return false;
          return adDomains.some(domain => url.includes(domain));
        };

        // Intercept fetch
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
          const url = typeof input === 'string' ? input : (input instanceof Request ? input.url : '');
          if (isAdUrl(url)) {
            console.log('FyrBrowser [AdBlock] Blocked fetch to:', url);
            return Promise.reject(new Error('Blocked by FyrBrowser AdBlock'));
          }
          return originalFetch.apply(this, arguments);
        };

        // Intercept XHR
        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          if (typeof url === 'string' && isAdUrl(url)) {
            console.log('FyrBrowser [AdBlock] Blocked XHR to:', url);
            this.abort();
            return;
          }
          return originalOpen.apply(this, arguments);
        };

        console.log('FyrBrowser AdBlock Active');
      })();
    ''';
  }

  static List<String> get selectors => adSelectors;
}
