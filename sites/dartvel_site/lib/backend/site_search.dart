/// The site search: every page this server serves, searched by meaning and
/// by word, through the SitePage data model.
///
/// Nothing here is a search engine. The pages come from the server itself
/// (`DVSitePages.load()`), each section is a SitePage record, and the search
/// is `SitePage.semanticSearch(...)` in hybrid mode: the model's keyword
/// provider and its semantic index, fused by rank. The embedder is fitted to
/// the site's own text, so the search needs no key, no network and no paid
/// provider, and costs nothing per query.
library;

import 'package:dartvel_core/dartvel.dart';

import '../components/section_anchor.dart';
import '../dartvel_client/dartvel_server.dart';

/// The longest query answered. A search box needs a sentence at most, and a
/// megabyte of query is a megabyte of tokenizing for nothing.
const int kSiteSearchMaxQuery = 200;

/// The most pages one search returns.
const int kSiteSearchMaxResults = 8;
/// The least cosine a match by meaning needs. Below it, a page shares a
/// word or two with the question and is not about it. Chosen with
/// tool/search_quality.dart on the site's own pages.
const double kSiteSearchMinScore = 0.3;

Future<void>? _ready;

/// Indexes the site, once per process, on the first search.
Future<void> _prepare() async {
  final List<DVSitePage> pages = await DVSitePages.load();
  final List<SitePage> sections = <SitePage>[
    for (final DVSitePage page in pages)
      for (int i = 0; i < page.sections.length; i++)
        SitePage(
          id: '${page.path}#$i',
          path: page.path,
          title: page.title,
          heading: page.sections[i].heading,
          body: page.sections[i].text,
        ),
  ];

  // The records follow the pages: a section that is gone is deleted, one
  // that changed is saved, one that did not is left alone.
  final Set<String> current = <String>{
    for (final SitePage s in sections) s.id,
  };
  final Map<String, SitePage> stored = <String, SitePage>{
    for (final SitePage s in await SitePage.all()) s.id: s,
  };
  for (final SitePage old in stored.values) {
    if (!current.contains(old.id)) await old.destroy();
  }
  for (final SitePage section in sections) {
    final SitePage? old = stored[section.id];
    if (old != null &&
        old.title == section.title &&
        old.heading == section.heading &&
        old.body == section.body) {
      continue;
    }
    await section.save(onConflict: DVConflict.lastWriteWins);
  }

  SitePage.useSearchProvider(DVInMemorySearchProvider<SitePage, SitePageFacets>(
    records: sections,
    document: siteSearchDocument,
    tuning: SitePage.searchTuning,
  ));
  SitePage.useSemanticSearch(
    embedder: DVLatentSemanticEmbedder.fit(
      sections.map(siteSearchDocument),
      dimensions: 96,
    ),
  );
  await SitePage.semanticBackfill();
}

/// What a section is searched as: its page's title, its heading and its
/// text.
String siteSearchDocument(SitePage s) => '${s.title}\n${s.heading}\n${s.body}';

/// One page a search found.
class const SiteSearchResult({
  required final String path,
  required final String title,
  required final String heading,
  required final String snippet,
}) {
  /// Where to send the reader: the page, and the section when it has one of
  /// its own below the page's heading.
  String get href => heading.isEmpty ? path : '$path#${sectionAnchor(heading)}';

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'href': href,
        'title': title,
        'heading': heading,
        'snippet': snippet,
      };
}

/// Searches the site for [query]: at most [kSiteSearchMaxResults] pages,
/// best first, each with the section that matched best.
Future<List<SiteSearchResult>> siteSearch(
  String query, {
  double minScore = kSiteSearchMinScore,
  DVSearchMode mode = DVSearchMode.hybrid,
}) async {
  final String text = query.trim();
  if (text.isEmpty) return const <SiteSearchResult>[];
  final String asked = text.length > kSiteSearchMaxQuery
      ? text.substring(0, kSiteSearchMaxQuery)
      : text;

  final Future<void> ready = _ready ??= _prepare();
  try {
    await ready;
  } on Object {
    // A failed index is tried again by the next search rather than kept.
    _ready = null;
    rethrow;
  }

  final DVSemanticPage<SitePage> page = await SitePage.semanticSearch(
    asked,
    mode: mode,
    limit: kSiteSearchMaxResults * 3,
    minScore: minScore,
  );
  final Map<String, SiteSearchResult> byPage = <String, SiteSearchResult>{};
  for (final DVSemanticHit<SitePage> hit in page.hits) {
    final SitePage s = hit.record;
    if (byPage.containsKey(s.path)) continue;
    byPage[s.path] = SiteSearchResult(
      path: s.path,
      title: s.title,
      // The first section is the page's own heading, not a place to jump to.
      heading: s.id.endsWith('#0') ? '' : s.heading,
      snippet: siteSearchSnippet(s.body, asked),
    );
    if (byPage.length == kSiteSearchMaxResults) break;
  }
  return byPage.values.toList(growable: false);
}

/// About two lines of [body], around the first word of [query] it contains.
String siteSearchSnippet(String body, String query, {int length = 180}) {
  if (body.length <= length) return body;
  final String lower = body.toLowerCase();
  int at = -1;
  for (final String word in query.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (word.length < 3) continue;
    at = lower.indexOf(word);
    if (at >= 0) break;
  }
  int start = at < 0 ? 0 : (at - length ~/ 3).clamp(0, body.length - length);
  if (start > 0) {
    final int space = body.indexOf(' ', start);
    if (space >= 0 && space < start + 20) start = space + 1;
  }
  int end = (start + length).clamp(0, body.length);
  if (end < body.length) {
    final int space = body.lastIndexOf(' ', end);
    if (space > start) end = space;
  }
  return '${start > 0 ? '...' : ''}${body.substring(start, end)}'
      '${end < body.length ? '...' : ''}';
}

/// Forgets the index, so a test can build it again from other pages.
void resetSiteSearch() => _ready = null;
