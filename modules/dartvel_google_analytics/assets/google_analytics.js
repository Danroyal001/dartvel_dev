// The inline half of the Google tag, as published at
// https://developers.google.com/tag-platform/gtagjs: it defines dataLayer
// and gtag. The other half, the script from www.googletagmanager.com, is
// added by the Dartvel module once the visitor's consent allows it.
//
// A file rather than an inline script so a Content-Security-Policy can
// allow it as 'self' instead of 'unsafe-inline'.
window.dataLayer = window.dataLayer || [];
window.gtag = window.gtag || function(){window.dataLayer.push(arguments);};
window.gtag('js', new Date());
