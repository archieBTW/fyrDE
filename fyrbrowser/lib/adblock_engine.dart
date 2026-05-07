class AdBlockEngine {
  static const List<String> adDomains = [
    'doubleclick.net',
    'googleadservices.com',
    'googlesyndication.com',
    'adnxs.com',
    'carbonads.net',
    'adservice.google.com',
    'adform.net',
    'amazon-adsystem.com',
    'app-measurement.com',
    'bidswitch.net',
    'criteo.com',
    'facebook.net',
    'openx.net',
    'pubmatic.com',
    'rubiconproject.com',
    'scorecardresearch.com',
    'taboola.com',
    'outbrain.com',
    'quantserve.com',
    'zedo.com',
  ];

  static const List<String> adSelectors = [
    '.ad',
    '.ads',
    '.ad-container',
    '.ad-slot',
    '.advertisement',
    '[id^="ad-"]',
    '[class^="ad-"]',
    '.gpt-ad',
    '.top-ad',
    '.bottom-ad',
    '.side-ad',
    '#ad-wrapper',
    '.adsbygoogle',
    'ins.adsbygoogle',
    '.text-ad',
    '.sponsored-post',
    '.promoted-post',
  ];

  static String get injectionScript {
    final domainsJson = adDomains.map((d) => "'$d'").join(',');
    return '''
      (function() {
        const adDomains = [$domainsJson];
        
        // Block Fetch
        const originalFetch = window.fetch;
        window.fetch = function() {
          const url = arguments[0];
          if (typeof url === 'string') {
            if (adDomains.some(domain => url.includes(domain))) {
              console.log('FyrBrowser blocked fetch to: ' + url);
              return Promise.reject(new Error('Blocked by FyrBrowser AdBlock'));
            }
          }
          return originalFetch.apply(this, arguments);
        };

        // Block XHR
        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function() {
          const url = arguments[1];
          if (typeof url === 'string') {
            if (adDomains.some(domain => url.includes(domain))) {
              console.log('FyrBrowser blocked XHR to: ' + url);
              return;
            }
          }
          return originalOpen.apply(this, arguments);
        };

        // CSS Hiding
        const style = document.createElement('style');
        style.innerHTML = '${adSelectors.join(',')} { display: none !important; visibility: hidden !important; height: 0 !important; width: 0 !important; }';
        document.head.appendChild(style);

        console.log('FyrBrowser AdBlock Injected');
      })();
    ''';
  }
}
