// Meta's Pixel base code, as published at
// https://developers.facebook.com/docs/meta-pixel/get-started, without its
// last two calls: fbq('init', ...) and fbq('track', 'PageView') are made by
// the Dartvel module once the visitor's consent allows them.
//
// A file rather than an inline script so a Content-Security-Policy can
// allow it as 'self' instead of 'unsafe-inline'.
!function(f,b,e,v,n,t,s)
{if(f.fbq)return;n=f.fbq=function(){n.callMethod?
n.callMethod.apply(n,arguments):n.queue.push(arguments)};
if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
n.queue=[];t=b.createElement(e);t.async=!0;
t.src=v;s=b.getElementsByTagName(e)[0];
s.parentNode.insertBefore(t,s)}(window, document,'script',
'https://connect.facebook.net/en_US/fbevents.js');
