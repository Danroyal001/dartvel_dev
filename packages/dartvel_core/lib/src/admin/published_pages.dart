/// The pages Studio published, for the application they were published for.
///
/// Studio on a web-server binary stores a page document in the server's
/// `dartvel_pages`. The web application read its stored pages from
/// `DV.Database` in the browser -- another database, where nothing was ever
/// published -- so a page published from Studio was kept and never shown.
/// The generated backend answers [dvPublishedPagesPath] with every document
/// it holds, and the web application reads them from there when the server
/// that served it is its own.
///
/// Public, deliberately: a published page is what the site shows to anybody.
/// A draft is never in this table (Content Workflow keeps drafts beside it),
/// so nothing here is something a visitor could not already see.
library;

import 'dart:convert';

import '../database/adapter.dart';
import '../database/records.dart';
import '../http/wintercg.dart';
import '../storage/adapters.dart' show DVFileStorageAdapter;
import '../web/page_data.dart' show DVPageData, dvApplyPageExtras, dvCanonicalUrl;
import '../web/page_text.dart' show dvApplyPageText;
import '../web/seo_head.dart' show dvAbsoluteAsset, dvSeoApply, dvSeoHead;
import 'studio_media_files.dart';
import 'studio_api.dart' show dvStudioPagesTable;
import 'studio_site.dart' show dvStudioIsReservedRoute;

/// Where the generated backend answers the published page documents.
const String dvPublishedPagesPath = '/_dartvel/pages';

/// Answers [dvPublishedPagesPath] from the application's database.
class DVPublishedPages {
  DVPublishedPages({
    required DVDatabaseAdapter? Function() database,
    this.media,
  }) : _database = database;

  final DVDatabaseAdapter? Function() _database;

  /// Where Studio's media library keeps its files, which visitors are served
  /// at `/_dartvel/media/<name>` as a site's uploads are. Null serves none.
  final DVFileStorageAdapter? media;

  /// What the page published at [route] says about itself, or null when
  /// nothing is published there.
  Future<DVPublishedPageSeo?> seo(String route) async {
    final DVDatabaseAdapter? database = _database();
    if (database == null || dvStudioIsReservedRoute(route)) return null;
    try {
      final List<Map<String, Object?>> rows =
          await DVRecordAdapter.over(database).find(
        dvStudioPagesTable,
        where: DVFilter.equals('route', route),
        fields: const <String>['document'],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final Object? document = jsonDecode('${rows.first['document']}');
      return document is Map
          ? DVPublishedPageSeo.fromDocument(document.cast<String, Object?>())
          : null;
    } on Object {
      // No table yet: nothing has been published.
      return null;
    }
  }

  /// The published routes a sitemap lists: those that ask to be, and are
  /// not asking crawlers to stay away.
  Future<List<String>> sitemapRoutes() async {
    final List<String> listed = <String>[];
    for (final String route in await routes()) {
      final DVPublishedPageSeo? page = await seo(route);
      if (page != null && page.inSitemap && !page.noindex) listed.add(route);
    }
    return listed..sort();
  }

  /// A file of the media library, for anybody: a site's pictures are what it
  /// shows everybody. Only files inside the library, of a type it takes.
  Future<Response?> _media(Request request) async {
    final DVFileStorageAdapter? storage = media;
    final String path = request.url.path;
    if (storage == null || !path.startsWith(dvStudioPublicMediaPath)) {
      return null;
    }
    final String method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') return null;
    final String name;
    try {
      name = Uri.decodeComponent(path.substring(dvStudioPublicMediaPath.length));
    } on ArgumentError {
      return Response(404);
    }
    final String key = '$dvStudioMediaPrefix$name';
    final String? type = dvStudioMediaTypeFor(name);
    if (type == null || !dvStudioIsMediaKey(key) || !await storage.exists(key)) {
      return Response(404);
    }
    return Response(
      200,
      headers: Headers(dvStudioMediaHeaders(type, public: true)),
      body: method == 'HEAD'
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(await storage.get(key)),
    );
  }

  /// The routes a document is published for.
  ///
  /// A Studio page is a route no manifest lists, so the web server asks here
  /// before it answers a path with a 404.
  Future<Set<String>> routes() async {
    final DVDatabaseAdapter? database = _database();
    if (database == null) return const <String>{};
    try {
      final List<Map<String, Object?>> rows =
          await DVRecordAdapter.over(database)
              .find(dvStudioPagesTable, fields: const <String>['route']);
      return <String>{
        for (final Map<String, Object?> row in rows)
          // A component is a document pages are drawn from, not a page.
          if (!dvStudioIsReservedRoute('${row['route']}')) '${row['route']}',
      };
    } on Object {
      // No table yet: nothing has been published.
      return const <String>{};
    }
  }

  /// The documents, or null for a request that is not for them.
  Future<Response?> respond(Request request) async {
    if (await _media(request) case final Response file) return file;
    if (request.url.path != dvPublishedPagesPath) return null;
    final String method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') return null;
    final List<Object?> pages = <Object?>[];
    final DVDatabaseAdapter? database = _database();
    if (database != null) {
      try {
        final List<Map<String, Object?>> rows =
            await DVRecordAdapter.over(database).find(
          dvStudioPagesTable,
          fields: const <String>['route', 'title', 'document'],
        );
        for (final Map<String, Object?> row in rows) {
          final Object? document = jsonDecode('${row['document']}');
          if (document is! Map) continue;
          pages.add(<String, Object?>{
            'route': '${row['route']}',
            'title': row['title'] == null ? null : '${row['title']}',
            'document': document,
          });
        }
      } on Object {
        // No table yet: nothing has been published, which is an answer.
      }
    }
    return Response(
      200,
      headers: Headers(const <String, String>{
        'content-type': 'application/json; charset=utf-8',
        // Revalidated on every load, so a page published or reverted a
        // moment ago is what the next visitor gets.
        'cache-control': 'no-cache',
      }),
      body: method == 'HEAD'
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(
              utf8.encode(jsonEncode(<String, Object?>{'pages': pages}))),
    );
  }
}

/// What a page built in Studio says about itself: its title, description,
/// picture, indexing rule, canonical address and structured-data type, and
/// the words on it. Read from the published document, so what a crawler is
/// served is what was published.
class DVPublishedPageSeo {
  const DVPublishedPageSeo({
    required this.title,
    this.description,
    this.image,
    this.robots,
    this.canonical,
    this.schemaType,
    this.inSitemap = true,
    this.text = const <String>[],
  });

  /// From a page document's JSON, as Studio saves it.
  factory DVPublishedPageSeo.fromDocument(Map<String, Object?> document) {
    String? named(String key) {
      final Object? value = document[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final List<String> text = <String>[];
    void walk(Object? node) {
      if (node is! Map) return;
      final Object? properties = node['properties'];
      if (properties is Map) {
        for (final String key in const <String>['text', 'label']) {
          final Object? value = properties[key];
          if (value is String && value.trim().isNotEmpty) text.add(value.trim());
        }
      }
      final Object? children = node['children'];
      if (children is List) children.forEach(walk);
    }

    walk(document['root']);
    return DVPublishedPageSeo(
      title: named('title') ?? '${document['route'] ?? ''}',
      description: named('description'),
      image: named('image'),
      robots: named('robots'),
      canonical: named('canonicalUrl'),
      schemaType: named('schemaType'),
      inSitemap: document['sitemap'] != false,
      text: text,
    );
  }

  final String title;
  final String? description;
  final String? image;

  /// `noindex, follow` and the like; null says nothing, which is index.
  final String? robots;

  /// The address the page names as its own, when not the one it is at.
  final String? canonical;

  /// The schema.org type its structured data names: `Article`, `Product`.
  final String? schemaType;

  /// Whether the page asks to be listed in the sitemap.
  final bool inSitemap;

  /// The words on the page, for a reader without scripts.
  final List<String> text;

  /// Whether the page asks crawlers not to index it.
  bool get noindex => robots?.toLowerCase().contains('noindex') ?? false;
}

/// [shell] as the page at [path] that Studio published, with what [seo]
/// says about it in its head -- the site's description and picture where
/// the page names none -- its structured data, and its words in the body.
///
/// Every value is the page's, and so somebody's input: the head writer
/// escapes it, and the structured data cannot close its script.
String dvRenderPublishedPage({
  required String shell,
  required String path,
  required DVPublishedPageSeo seo,
  String? siteUrl,
  String? siteName,
  String? siteDescription,
  String? siteImage,
}) {
  final String? canonical =
      seo.canonical ?? (siteUrl == null ? null : dvCanonicalUrl(siteUrl, path));
  final String? image = dvAbsoluteAsset(seo.image ?? siteImage, siteUrl);
  String html = dvSeoApply(
    shell,
    dvSeoHead(
      title: seo.title,
      description: seo.description ?? siteDescription,
      siteUrl: canonical,
      image: image,
      siteName: siteName,
      robots: seo.robots,
    ),
  );
  html = dvApplyPageExtras(
    html,
    DVPageData(
      title: seo.title,
      structuredData: <String, Object?>{
        '@context': 'https://schema.org',
        '@type': seo.schemaType ?? 'WebPage',
        'name': seo.title,
        'description': ?(seo.description ?? siteDescription),
        'url': ?canonical,
        'image': ?image,
      },
    ),
  );
  return dvApplyPageText(html, seo.text, path: path);
}

/// [sitemap] -- the one the build wrote, or none -- with a `<url>` for each
/// of [routes] it does not list yet, at [siteUrl].
String dvSitemapWithRoutes(
  String? sitemap,
  Iterable<String> routes, {
  required String siteUrl,
}) {
  final String base = sitemap != null && sitemap.contains('</urlset>')
      ? sitemap
      : '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            '</urlset>\n';
  const HtmlEscape escape = HtmlEscape(HtmlEscapeMode.element);
  final StringBuffer added = StringBuffer();
  for (final String route in routes) {
    final String loc = escape.convert(dvCanonicalUrl(siteUrl, route));
    if (base.contains('<loc>$loc</loc>')) continue;
    added.write('<url><loc>$loc</loc></url>\n');
  }
  final int end = base.lastIndexOf('</urlset>');
  return '${base.substring(0, end)}$added${base.substring(end)}';
}
