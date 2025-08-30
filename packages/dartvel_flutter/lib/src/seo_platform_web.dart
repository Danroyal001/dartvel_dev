import 'package:web/web.dart' as web;
import '../dartvel_flutter.dart';

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
  if (p.imageUrl != null)
    _upsertMeta('og:image', p.imageUrl!, attr: 'property');
  if (p.siteName != null)
    _upsertMeta('og:site_name', p.siteName!, attr: 'property');

  // Twitter
  if (p.twitterHandle != null) _upsertMeta('twitter:site', p.twitterHandle!);
  _upsertMeta('twitter:title', p.title ?? '');
  _upsertMeta('twitter:description', p.description ?? '');
  if (p.imageUrl != null) _upsertMeta('twitter:image', p.imageUrl!);

  // Extra tags
  for (final e in p.extraMeta.entries) {
    _upsertMeta(e.key, e.value);
  }
}
