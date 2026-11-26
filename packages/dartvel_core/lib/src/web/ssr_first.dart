/// SSR-first: the server-rendered document is the page until Flutter's first
/// frame (`dartvel.web.ssrFirst`, on by default since 3.47.11; `false` opts out).
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

import '../config/accessibility_controls.dart' show dvAccessibilityStorageKey;
import 'page_text.dart' show dvApplyPageHtml, dvApplyPageText;
import 'ssr_first_layout.dart' show dvFirstScreenId;

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
///
/// A field the visitor is typing in keeps its focus, also when the app's
/// first frame focuses the app's view behind the document: the app has already
/// carried what was typed into its own field and moves focus there itself
/// (dvHandOverSsrFields in dartvel_flutter), following every keystroke that
/// lands in the document's field until it does, so nothing typed mid-word is
/// lost and typing never waits. If no field of the app takes it within three
/// seconds, the document's field lets go. Its selection is a field's, not a
/// reading selection, so the handover does not wait for it.
///
/// A button pressed before the app is there (`role="button"` in the
/// document) is not dead: it shows it is busy, and once the app has taken
/// over, the press is made on the app's button of the same name.
///
/// Nothing pressed during the handover's fade is dropped either: the
/// document keeps taking presses while it fades (it lies exactly over the
/// app), so a link navigates and a button is queued as before, and any other
/// press -- a field, a card -- is made again, once the app has the page, on
/// what the app has at that point (its semantics node: a field is focused,
/// anything else clicked).
const String _handoverScript = '(function(){'
    'var d=document,h=d.documentElement,q=[],'
    'F="[data-dv-field]",B=".dv-fallback [role=button]";'
    'function press(e){'
    'if(h.hasAttribute("data-dv-app"))return;'
    'var t=e.target&&e.target.closest&&e.target.closest(B);if(!t)return;'
    'if(e.type=="keydown"&&e.key!="Enter"&&e.key!=" ")return;'
    'e.preventDefault();'
    'if(t.getAttribute("aria-busy")=="true")return;'
    't.setAttribute("aria-busy","true");'
    'q.push(t.getAttribute("aria-label")||t.textContent.trim())}'
    'd.addEventListener("click",press,true);'
    'd.addEventListener("keydown",press,true);'
    // The app's first frame focuses its view or a node of its semantics tree
    // (the engine moves the keyboard there when the first route takes focus)
    // while the document still covers it, where no key types anything: the
    // field the visitor is typing in gets the keyboard back. Nothing of the
    // app can be reached by the visitor before the handover, so no such
    // move is theirs. Once the app has carried the fields (data-dv-carried)
    // it moves the keyboard itself (dvHandOverSsrFields asks for its view
    // again when its field takes the visitor's typing).
    'd.addEventListener("focusin",function(e){'
    'if(h.hasAttribute("data-dv-app")||h.hasAttribute("data-dv-carried"))return;'
    'var t=e.target,r=e.relatedTarget;'
    'if(t&&t.closest&&t.closest("flutter-view,flt-glass-pane,flt-semantics-host")'
    '&&r&&r.matches&&r.matches(F)&&r.closest(".dv-fallback"))'
    'r.focus({preventScroll:true})},true);'
    // A press during the fade that is not a link's or a button's: kept for
    // the app (and a field is not focused in the document meanwhile).
    'var pq=[];'
    'function fade(e){'
    'if(!h.hasAttribute("data-dv-handover")||h.hasAttribute("data-dv-app"))return;'
    'var t=e.target;if(!t||!t.closest||!t.closest(".dv-fallback"))return;'
    'if(t.closest("a[href]")||t.closest(B))return;'
    'e.preventDefault();'
    'if(e.type=="click")pq.push([e.clientX,e.clientY])}'
    'd.addEventListener("pointerdown",fade,true);'
    'd.addEventListener("mousedown",fade,true);'
    'd.addEventListener("click",fade,true);'
    'function replay(){'
    'var n=Date.now();'
    'pq.splice(0).forEach(function(p){'
    'var e=d.elementFromPoint(p[0],p[1]);if(!e)return;'
    'if(e.matches("input,textarea,[contenteditable]"))e.focus();else e.click()});'
    '(function next(){'
    'if(!q.length)return;'
    'var all=d.querySelectorAll("flt-semantics-host [role=button]"),hit=null;'
    'for(var i=0;i<all.length;i++){'
    'var l=all[i].getAttribute("aria-label")||all[i].textContent.trim();'
    'if(l==q[0]){hit=all[i];break}}'
    'if(hit){q.shift();hit.click();next();return}'
    'if(Date.now()-n<5e3){setTimeout(next,100);return}'
    'q.shift();n=Date.now();next()})()}'
    'addEventListener("dartvel-first-frame",function(){'
    'var b=d.querySelector(".dv-fallback"),t=Date.now(),'
    'rm=matchMedia("(prefers-reduced-motion: reduce)").matches||h.hasAttribute("data-dv-reduce-motion");'
    'function go(){'
    'var s=window.getSelection&&getSelection(),a=d.activeElement,'
    'typing=!!(b&&a&&b.contains(a)&&a.matches&&a.matches(F));'
    'if(b&&s&&!typing&&!s.isCollapsed&&b.contains(s.anchorNode)&&Date.now()-t<1e4)'
    '{setTimeout(go,250);return}'
    'if(b){'
    'if(b.scrollTop>b.clientHeight/2){'
    'var all=b.querySelectorAll("[data-dv-anchor]");'
    'for(var i=0;i<all.length;i++){'
    'if(all[i].getBoundingClientRect().bottom>0){all[i].removeAttribute("hidden");break}}}'
    'if(typing)setTimeout(function(){if(d.activeElement===a)a.blur()},3e3);'
    'else if(b.contains(a))a.blur();'
    'var busy=b.querySelectorAll("[aria-busy=true]");'
    'for(var j=0;j<busy.length;j++)busy[j].removeAttribute("aria-busy")}'
    'h.setAttribute("data-dv-handover","");'
    'setTimeout(function(){h.setAttribute("data-dv-app","");'
    'h.removeAttribute("data-dv-handover");replay()},rm?0:200)}'
    'go()},{once:true})})()';

/// Holds the first paint until the end of the first screen is parsed: a
/// render-blocking `<link rel="expect">` naming the element the layout ends
/// the first screen with ([dvFirstScreenId]). Without it a browser paints as
/// soon as it can -- the bare canvas while the head is read, then whatever of
/// the body has arrived -- so a slow line showed the page's colour, then
/// half a page, then the page. With it the first frame is the first screen in
/// place. A page with no layout is held until it is parsed, which the
/// browser does anyway when nothing names the element. Written by a script
/// because the link must name this page: under `<base href="/">` a bare
/// `#id` names the site's root and is ignored on every other route. A
/// browser without `blocking` ignores it and paints as before, on the app's
/// colour (the splash style paints the canvas).
const String _firstScreenScript = '(function(){'
    'var d=document,l=d.createElement("link");'
    'l.rel="expect";'
    'l.href=location.href.split("#")[0]+"#$dvFirstScreenId";'
    'l.setAttribute("blocking","render");'
    'd.head.appendChild(l)})()';

/// The visitor's accessibility settings (`dartvel.accessibility.defaultControls`),
/// read before the first paint and written on `<html>`:
///
/// * `data-dv-reduce-motion`: the handover does not fade;
/// * `data-dv-contrast`: the document in pure black and white (also when the
///   operating system asks for more contrast);
/// * `data-dv-text` and `--dv-text-scale`: the document's text at the
///   visitor's size;
/// * `data-dv-plain`: large text or high contrast. The captured layout is the
///   app drawn at the default settings, so the document is shown as the
///   reading column in the visitor's settings instead (the layout and theme
///   stylesheets are gated on `:not([data-dv-plain])`).
const String _accessibilityScript = '(function(){try{'
    'var h=document.documentElement,s={};'
    'try{s=JSON.parse(localStorage.getItem("$dvAccessibilityStorageKey")||"{}")||{}}catch(e){}'
    'var t=+s.textScale;if(!(t>1&&t<4))t=1;'
    'if(t>1){h.setAttribute("data-dv-text","");h.style.setProperty("--dv-text-scale",String(t))}'
    'if(s.highContrast===true||matchMedia("(prefers-contrast: more)").matches)h.setAttribute("data-dv-contrast","");'
    'if(s.reducedMotion===true)h.setAttribute("data-dv-reduce-motion","");'
    'if(t>1||h.hasAttribute("data-dv-contrast"))h.setAttribute("data-dv-plain","")'
    '}catch(e){}})()';

/// The document in the visitor's settings: text size and pure black and
/// white, as the app draws them once it has taken over.
const String _accessibilityStyle = '@media screen{'
    'html[data-dv-text]:not([data-dv-app]) .dv-fallback{font-size:calc(1rem * var(--dv-text-scale,1))}'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback{background:#FFFFFF;color:#000000}'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback a{color:#000000;text-decoration:underline}'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback a:focus-visible,'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback [role=button]:focus-visible'
    '{outline:3px solid #000000;outline-offset:2px}}'
    '@media screen and (prefers-color-scheme:dark){'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback{background:#000000;color:#FFFFFF}'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback a{color:#FFFFFF}'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback a:focus-visible,'
    'html[data-dv-contrast]:not([data-dv-app]) .dv-fallback [role=button]:focus-visible'
    '{outline-color:#FFFFFF}}'
    'html[data-dv-reduce-motion][data-dv-handover] .dv-fallback{transition:none}';

/// The style and script an SSR-first shell carries in its head.
///
/// With [accessibilityControls] (`dartvel.accessibility.defaultControls`) it also
/// reads the visitor's accessibility settings before the first paint.
///
/// [background] and [darkBackground] are the app's page colours (the
/// splash's, which come from `dartvel.splash` or `dartvel.pwa`); [accent] is
/// the link colour when it reads on them, the loading bar's by default.
String dvSsrFirstHead({
  required String background,
  required String darkBackground,
  required String accent,
  bool accessibilityControls = false,
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
      // A button pressed before the app is there says it is on its way.
      '$on [aria-busy=true]{cursor:progress;opacity:.6}'
      '${_colours(background, accent)}'
      // Behind a document the splash would only be covered; hidden, it is not
      // painted at all. A page with no document keeps it.
      '.dv-fallback~#dartvel-splash{display:none}'
      '}'
      '@media screen and (prefers-color-scheme:dark){'
      '${_colours(darkBackground, accent)}}'
      '@media screen and (prefers-reduced-motion:no-preference){'
      'html[data-dv-handover] .dv-fallback{transition:opacity .2s ease-out}}'
      // Still taking presses while it fades: it lies exactly over the app,
      // and a press there is a link's, a queued button's or one made again
      // on the app (see the handover script).
      'html[data-dv-handover] .dv-fallback{opacity:0}';
  return '<script>$_firstScreenScript</script>\n'
      '${accessibilityControls ? '<script>$_accessibilityScript</script>\n' : ''}'
      '<style $dvSsrFirstMarker>$css${accessibilityControls ? _accessibilityStyle : ''}</style>\n'
      '<script>$_handoverScript</script>\n';
}
