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
import '../http/client_address.dart' show DVClientAddress;
import 'studio_form_inbox.dart';
import 'studio_media_files.dart';
import 'studio_api.dart' show dvStudioPagesTable, dvStudioStoredSettings;
import 'studio_settings.dart' show DVStudioSettings;
import 'studio_site.dart' show dvStudioIsReservedRoute;

/// Where the generated backend answers the published page documents.
const String dvPublishedPagesPath = '/_dartvel/pages';

/// Answers [dvPublishedPagesPath] from the application's database.
class DVPublishedPages {
  DVPublishedPages({
    required DVDatabaseAdapter? Function() database,
    this.media,
    Future<bool> Function(Request request)? passesMaintenance,
  })  : _database = database,
        _passesMaintenance = passesMaintenance;

  /// Whether a request sees the site as it is while it is in maintenance:
  /// somebody who may open Studio, to check the work before it is lifted.
  final Future<bool> Function(Request request)? _passesMaintenance;

  DVStudioSettings? _settings;
  DateTime? _settingsRead;

  /// The settings saved in Studio, read at most every few seconds: they are
  /// asked on every page request, and a change shows within that.
  Future<DVStudioSettings?> _storedSettings() async {
    final DateTime now = DateTime.now();
    final DateTime? read = _settingsRead;
    if (read != null && now.difference(read) < const Duration(seconds: 5)) {
      return _settings;
    }
    final DVDatabaseAdapter? database = _database();
    try {
      _settings = database == null ? null : await dvStudioStoredSettings(database);
    } on Object {
      _settings = null;
    }
    _settingsRead = now;
    return _settings;
  }

  /// What the site is called and says about itself by default, from Studio's
  /// Settings, or null when none were saved there. A page's own title and
  /// description come first; these fill in what a page does not say.
  Future<DVStudioSiteDefaults?> siteDefaults() async {
    final DVStudioSettings? settings = await _storedSettings();
    if (settings == null) return null;
    String? named(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    return (
      name: named(settings.siteTitle),
      title: named(settings.defaultSeoTitle),
      description: named(settings.defaultSeoDescription),
      image: named(settings.defaultSeoImage),
      favicon: named(settings.favicon),
    );
  }

  /// The maintenance page, for a page request while Studio's Settings say the
  /// site is in maintenance. Not for what the framework serves itself under
  /// `/_dartvel/`, and not for somebody who may open Studio.
  Future<Response?> maintenance(Request request) async {
    final String method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') return null;
    if (request.url.path.startsWith('/_dartvel/')) return null;
    final DVStudioSettings? settings = await _storedSettings();
    if (settings == null || !settings.maintenanceMode) return null;
    if (await _passesMaintenance?.call(request) ?? false) return null;
    const HtmlEscape text = HtmlEscape(HtmlEscapeMode.element);
    final String name = settings.siteTitle.trim();
    final String message = (settings.maintenanceMessage ?? '').trim().isEmpty
        ? 'This site is down for maintenance. Please come back soon.'
        : settings.maintenanceMessage!.trim();
    final String html = '<!DOCTYPE html>\n<html lang="en"><head>'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="robots" content="noindex">'
        '<title>${text.convert(name.isEmpty ? 'Maintenance' : name)}</title>'
        '<style>body{font:16px/1.5 system-ui,sans-serif;margin:0;'
        'display:grid;place-items:center;min-height:100vh;padding:16px;'
        'box-sizing:border-box}main{max-width:32rem}</style>'
        '</head><body><main>'
        '${name.isEmpty ? '' : '<h1>${text.convert(name)}</h1>'}'
        '<p>${text.convert(message)}</p>'
        '</main></body></html>\n';
    return Response(
      503,
      headers: Headers(<String, String>{
        'content-type': 'text/html; charset=utf-8',
        // Asked again soon, and never kept: the site comes back.
        'retry-after': '300',
        'cache-control': 'no-store',
      }),
      body: method == 'HEAD'
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(html)),
    );
  }

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

  /// The largest answer to a form that is read.
  static const int maxFormBytes = 32 * 1024;

  /// How many answers one source may send in [formWindow].
  static const int formsPerWindow = 10;
  static const Duration formWindow = Duration(minutes: 1);

  /// When each source last answered, per source, within [formWindow]. In
  /// this process: a limit for a single server, not for a fleet.
  final Map<String, List<DateTime>> _answers = <String, List<DateTime>>{};

  /// A form built in Studio, at `/_dartvel/forms/<id>`: read with GET, as
  /// visitors are given it, and answered with POST.
  Future<Response?> _form(Request request) async {
    const String prefix = '/_dartvel/forms/';
    final String path = request.url.path;
    if (!path.startsWith(prefix)) return null;
    final String id = Uri.decodeComponent(path.substring(prefix.length));
    final String method = request.method.toUpperCase();
    final DVDatabaseAdapter? database = _database();
    if (id.isEmpty || id.contains('/')) return _formReply(404, 'not_found', 'No such form.');
    if (database == null) {
      return _formReply(503, 'no_database', 'This site keeps no answers.');
    }
    final DVStudioFormInbox inbox = DVStudioFormInbox(database);
    try {
      if (method == 'GET' || method == 'HEAD') {
        final form = await inbox.form(id);
        if (form == null) return _formReply(404, 'not_found', 'No such form.');
        return _json(200, DVStudioFormInbox.publicJson(form));
      }
      if (method != 'POST') return _formReply(405, 'method', 'Use POST.');
      // JSON only: a page on another site can post a form to this one, but
      // not with this content type without asking first.
      final String type = request.headers.get('content-type') ?? '';
      if (!type.toLowerCase().startsWith('application/json')) {
        return _formReply(415, 'unsupported_type', 'Send the answer as JSON.');
      }
      final int? declared = int.tryParse(request.headers.get('content-length') ?? '');
      if (declared != null && declared > maxFormBytes) {
        return _formReply(413, 'too_large', 'The answer is too long.');
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in request.body.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maxFormBytes) {
          return _formReply(413, 'too_large', 'The answer is too long.');
        }
      }
      final String source = DVClientAddress.sourceOf(request);
      final DateTime now = DateTime.now().toUtc();
      final List<DateTime> recent = (_answers[source] ?? <DateTime>[])
        ..removeWhere((DateTime at) => now.difference(at) > formWindow);
      if (recent.length >= formsPerWindow) {
        return Response(
          429,
          headers: Headers(<String, String>{
            'content-type': 'application/json; charset=utf-8',
            'retry-after': '${formWindow.inSeconds}',
            'cache-control': 'no-store',
          }),
          body: Stream<List<int>>.value(utf8.encode(jsonEncode(<String, Object?>{
            'error': 'too_many',
            'message': 'Too many answers from here. Try again in a minute.',
          }))),
        );
      }
      final Object? answer;
      try {
        answer = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return _formReply(400, 'bad_body', 'The answer is not JSON.');
      }
      if (answer is! Map) {
        return _formReply(400, 'bad_body', 'The answer is not a JSON object.');
      }
      final DVStudioFormReceipt receipt = await inbox.submit(
        id,
        answer.cast<String, Object?>(),
        source: source,
        userAgent: request.headers.get('user-agent'),
      );
      _answers[source] = recent..add(now);
      if (_answers.length > 10000) _answers.remove(_answers.keys.first);
      return _json(201, <String, Object?>{'ok': true, 'message': receipt.message});
    } on DVStudioFormRefusal catch (refused) {
      return _formReply(refused.status, refused.code, refused.message);
    }
  }

  static Response _formReply(int status, String code, String message) =>
      _json(status, <String, Object?>{'error': code, 'message': message});

  static Response _json(int status, Object? body) => Response(
    status,
    headers: Headers(<String, String>{
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    }),
    body: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
  );

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
    if (await maintenance(request) case final Response closed) return closed;
    if (await _media(request) case final Response file) return file;
    if (await _form(request) case final Response form) return form;
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

/// What Studio's Settings say about the whole site: its name, and the title,
/// description, picture and icon a page has when it names none of its own.
typedef DVStudioSiteDefaults = ({
  String? name,
  String? title,
  String? description,
  String? image,
  String? favicon,
});

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
