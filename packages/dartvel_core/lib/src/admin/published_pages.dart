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
