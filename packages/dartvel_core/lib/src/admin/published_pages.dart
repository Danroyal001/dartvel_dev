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
import 'studio_api.dart' show dvStudioPagesTable;

/// Where the generated backend answers the published page documents.
const String dvPublishedPagesPath = '/_dartvel/pages';

/// Answers [dvPublishedPagesPath] from the application's database.
class DVPublishedPages {
  DVPublishedPages({required DVDatabaseAdapter? Function() database})
      : _database = database;

  final DVDatabaseAdapter? Function() _database;

  /// The documents, or null for a request that is not for them.
  Future<Response?> respond(Request request) async {
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
