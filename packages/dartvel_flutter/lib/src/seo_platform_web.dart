
import 'dart:html' as html;
import '../dartvel_flutter.dart';

extension _AppendX on html.Element {
  void appendTo(html.Element parent) => parent.append(this);
}

void _upsertMeta(String name, String content, {String attr = 'name'}) {
  if (content.isEmpty) return;
  final head = html.document.head!;
  final selector = 'meta[$attr="$name"]';
  html.MetaElement? el = head.querySelector(selector) as html.MetaElement?;
  el ??= html.MetaElement()..setAttribute(attr, name)..appendTo(head);
  el.content = content;
}

void applySeo(SeoProps p) {
  final doc = html.document;
  if (p.title != null) doc.title = p.title!;

  _upsertMeta('description', p.description ?? '');

  if (p.canonicalUrl != null) {
    final head = doc.head!;
    final existing = head.querySelector('link[rel="canonical"]') as html.LinkElement?;
    final link = existing ?? (html.LinkElement()..rel = 'canonical')..href = p.canonicalUrl!;
    if (existing == null) head.append(link);
  }

  // OpenGraph
  _upsertMeta('og:title', p.title ?? '', attr: 'property');
  _upsertMeta('og:description', p.description ?? '', attr: 'property');
  if (p.imageUrl != null) _upsertMeta('og:image', p.imageUrl!, attr: 'property');
  if (p.siteName != null) _upsertMeta('og:site_name', p.siteName!, attr: 'property');

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
