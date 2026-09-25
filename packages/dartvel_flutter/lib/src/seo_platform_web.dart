import 'package:dartvel_core/dartvel.dart' show dvFallbackIsStale;
import 'package:web/web.dart' as web;
import '../dartvel_flutter.dart';
import 'find/find_platform_web.dart' show dvFindOwnsFallback;

/// Where the reader is, as the served page's block would have written it.
///
/// The hash first, for an application using the hash URL strategy: there the
/// path is `#/invoice/12` and `pathname` is whatever served the shell.
String _currentPath() {
  final String hash = web.window.location.hash;
  if (hash.startsWith('#/')) return hash.substring(1);
  return web.window.location.pathname;
}

/// Drop the crawler-visible block once the reader has routed off the page it
/// was written for.
///
/// The build writes the page's own HTML into the document, hidden from the
/// screen, and the print stylesheet shows it instead of the canvas Flutter
/// paints into. The application routes on the client, so one navigation later
/// that block is the page the reader arrived on. Printing it would put the
/// right title in the header and somebody else's page on the paper.
///
/// Removing it takes the print rules with it -- they are in the style element
/// beside it -- so printing goes back to what the browser would do without
/// Dartvel. That is the safe direction, and it is also where this lands if
/// the comparison is ever wrong: the worst a mistake here can do is print the
/// page the way Flutter does.
///
/// Only until a page shell is up. From then the find runtime keeps the block
/// current instead -- rewriting it for the page on screen after each
/// navigation, so find and print both follow the reader -- and drops it itself
/// where no findable page is there to rewrite it for.
void _dropStaleFallback() {
  if (dvFindOwnsFallback) return;
  final web.Element? block = web.document.querySelector('.dv-fallback');
  if (block == null) return;
  if (!dvFallbackIsStale(block.getAttribute('data-dv-path'), _currentPath())) {
    return;
  }
  final web.NodeList parts =
      web.document.querySelectorAll('.dv-fallback,.dv-fallback-style');
  for (int i = parts.length - 1; i >= 0; i--) {
    (parts.item(i) as web.Element?)?.remove();
  }
}

web.HTMLMetaElement _ensureMeta(String attr, String name) {
  final head = web.document.head!;
  final selector = 'meta[$attr="$name"]';
  final found = head.querySelector(selector) as web.HTMLMetaElement?;
  if (found != null) return found;
  final el = web.document.createElement('meta') as web.HTMLMetaElement;
  el.setAttribute(attr, name);
  head.append(el);
  return el;
}

void _upsertMeta(String name, String content, {String attr = 'name'}) {
  if (content.isEmpty) return;
  final el = _ensureMeta(attr, name);
  el.content = content;
}

void applySeo(SeoProps p) {
  final doc = web.document;
  // First, and before any early return below: a page the reader has left
  // must not be the page their printer is given.
  _dropStaleFallback();
  if (p.title != null) doc.title = p.title!;

  _upsertMeta('description', p.description ?? '');

  if (p.canonicalUrl != null) {
    final head = doc.head!;

    final existing =
        head.querySelector('link[rel="canonical"]') as web.HTMLLinkElement?;
    final link =
        existing ?? (web.document.createElement('link') as web.HTMLLinkElement)
          ..rel = 'canonical';
    link.href = p.canonicalUrl!;
    if (existing == null) head.append(link);
  }

  // OpenGraph
  _upsertMeta('og:title', p.title ?? '', attr: 'property');
  _upsertMeta('og:description', p.description ?? '', attr: 'property');
  if (p.imageUrl != null) {
    _upsertMeta('og:image', p.imageUrl!, attr: 'property');
  }
  if (p.siteName != null) {
    _upsertMeta('og:site_name', p.siteName!, attr: 'property');
  }

  // Twitter
  if (p.twitterHandle != null) _upsertMeta('twitter:site', p.twitterHandle!);
  _upsertMeta('twitter:title', p.title ?? '');
  _upsertMeta('twitter:description', p.description ?? '');
  if (p.imageUrl != null) _upsertMeta('twitter:image', p.imageUrl!);

  // Extra tags
  for (final e in p.extraMeta.entries) {
    _upsertMeta(e.key, e.value);
  }

  // Structured data: one JSON-LD script, replaced per page rather than
  // accumulated.
  final jsonLd = p.structuredDataJson();
  final head = doc.head!;
  final existingScript =
      head.querySelector('script#dartvel-jsonld') as web.HTMLScriptElement?;
  if (jsonLd == null) {
    existingScript?.remove();
    return;
  }
  final script = existingScript ??
      (doc.createElement('script') as web.HTMLScriptElement
        ..id = 'dartvel-jsonld'
        ..type = 'application/ld+json');
  script.text = jsonLd;
  if (existingScript == null) head.append(script);
}
