/// SSR-first: the server-rendered document is the page until Flutter's first
/// frame (`dartvel.web.ssrFirst: true`, off by default).
///
/// Every page already carries its document: the `.dv-fallback` block that
/// [dvApplyPageHtml] and [dvApplyPageText] write, from the one render path
/// the static build and the web server share. Normally it is kept off the
/// screen while the splash covers the page until the app has drawn. On a
/// slow phone network that is 30 seconds and more of splash.
///
/// With SSR-first the build writes [dvSsrFirstHead] into the shell. Every
/// page made from that shell then shows its document from the first paint:
/// in the app's colours, light and dark, as its own scroller above where
/// Flutter paints (so the engine fixing the body does not freeze it), with
/// working links, selection, find, Tab and screen readers. The loading bar
/// stays above it. The splash is hidden behind a page that has a document and
/// shown, as before, on one that has none.
///
/// At `dartvel-first-frame` the head's script fades the document out and
/// puts it back where it always is: the clipped one-pixel box that find,
/// crawlers and print use. If the reader is selecting text in it, the
/// handover waits until they finish (at most ten seconds). If they had
/// scrolled, the section at the top of their screen is revealed the way a
/// find match is, so the app scrolls to the same place.
library;

import 'dart:math' as math;

import 'page_text.dart' show dvApplyPageHtml, dvApplyPageText;

/// What marks a shell as SSR-first: the id of the style element
/// [dvSsrFirstHead] writes into its head.
const String dvSsrFirstMarker = 'id="dartvel-ssr-first"';

/// Whether [html] was built with SSR-first.
bool dvIsSsrFirst(String html) => html.contains(dvSsrFirstMarker);

/// The relative luminance of `#RRGGBB` (WCAG 2).
double _luminance(String hex) {
  final String digits = hex.replaceFirst('#', '');
  if (digits.length != 6) return 1;
  final int value = int.tryParse(digits, radix: 16) ?? 0xFFFFFF;
  double channel(int shift) {
    final double c = ((value >> shift) & 0xFF) / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

double _contrast(String a, String b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Body text on [background]: near-black on a light one, near-white on a
/// dark one.
String _ink(String background) =>
    _luminance(background) > 0.18 ? '#0B1020' : '#F2F5FA';

/// [accent] where it reads on [background] as text (4.5:1), else the ink.
String _link(String background, String accent) =>
    _contrast(accent, background) >= 4.5 ? accent : _ink(background);

String _colours(String background, String accent) {
  final String ink = _ink(background);
  final String link = _link(background, accent);
  return 'html:not([data-dv-app]) .dv-fallback{background:$background;color:$ink}'
      'html:not([data-dv-app]) .dv-fallback a{color:$link}'
      'html:not([data-dv-app]) .dv-fallback a:focus-visible'
      '{outline:2px solid $link;outline-offset:2px}';
}

/// The handover. Waits for a selection in the document to finish, reveals
/// the section at the top of the reader's screen for the app's find runtime
/// to scroll to, moves focus off the document, fades it, then marks the page
/// as the app's.
const String _handoverScript = '(function(){'
    'var d=document,h=d.documentElement;'
    'addEventListener("dartvel-first-frame",function(){'
    'var b=d.querySelector(".dv-fallback"),t=Date.now(),'
    'rm=matchMedia("(prefers-reduced-motion: reduce)").matches;'
    'function go(){'
    'var s=window.getSelection&&getSelection();'
    'if(b&&s&&!s.isCollapsed&&b.contains(s.anchorNode)&&Date.now()-t<1e4)'
    '{setTimeout(go,250);return}'
    'if(b){'
    'if(b.scrollTop>b.clientHeight/2){'
    'var all=b.querySelectorAll("[data-dv-anchor]");'
    'for(var i=0;i<all.length;i++){'
    'if(all[i].getBoundingClientRect().bottom>0){all[i].removeAttribute("hidden");break}}}'
    'if(b.contains(d.activeElement))d.activeElement.blur()}'
    'h.setAttribute("data-dv-handover","");'
    'setTimeout(function(){h.setAttribute("data-dv-app","");'
    'h.removeAttribute("data-dv-handover")},rm?0:200)}'
    'go()},{once:true})})()';

/// The style and script an SSR-first shell carries in its head.
///
/// [background] and [darkBackground] are the app's page colours (the
/// splash's, which come from `dartvel.splash` or `dartvel.pwa`); [accent] is
/// the link colour when it reads on them, the loading bar's by default.
String dvSsrFirstHead({
  required String background,
  required String darkBackground,
  required String accent,
}) {
  const String on = 'html:not([data-dv-app]) .dv-fallback';
  final String css = '@media screen{'
      // Its own scroller above where Flutter paints, below the loading bar.
      // The engine fixes the body and turns off selection and touch scrolling
      // on it; none of that reaches a fixed scroll container that sets its own.
      '$on{position:fixed;top:0;right:0;bottom:0;left:0;z-index:2147483645;'
      'width:auto;height:auto;max-width:none;margin:0;box-sizing:border-box;'
      'padding:2.5rem max(1.25rem,calc((100% - 44rem)/2)) 3rem;'
      'overflow:auto;overscroll-behavior:contain;clip-path:none;'
      'pointer-events:auto;touch-action:auto;'
      'user-select:text;-webkit-user-select:text}'
      // Every section on screen, though each keeps hidden="until-found" for
      // after the handover.
      '$on [data-dv-anchor]{display:block;content-visibility:visible}'
      // A run of plain links (a navigation bar, a pair of buttons) reads as
      // a row rather than a column of one-word lines.
      '$on [data-dv-anchor]:has(>a:only-child){display:inline-block;'
      'margin:0 1.25rem .75rem 0}'
      '$on a{text-underline-offset:.15em}'
      '${_colours(background, accent)}'
      // Behind a document the splash would only be covered; hidden, it is not
      // painted at all. A page with no document keeps it.
      '.dv-fallback~#dartvel-splash{display:none}'
      '}'
      '@media screen and (prefers-color-scheme:dark){'
      '${_colours(darkBackground, accent)}}'
      '@media screen and (prefers-reduced-motion:no-preference){'
      'html[data-dv-handover] .dv-fallback{transition:opacity .2s ease-out}}'
      'html[data-dv-handover] .dv-fallback{opacity:0;pointer-events:none}';
  return '<style $dvSsrFirstMarker>$css</style>\n'
      '<script>$_handoverScript</script>\n';
}
