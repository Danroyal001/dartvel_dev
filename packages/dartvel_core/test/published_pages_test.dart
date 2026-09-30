// The pages Studio published, served to the application they were published
// for.
//
// Studio on a web-server binary writes a page document to the server's
// dartvel_pages, and the web app read its stored pages from DV.Database in the
// browser tab -- a different database, where nothing was ever published. So a
// page published from Studio was stored and never shown. The server answers
// the app with the documents it holds, at one public path.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _get(String path, {String method = 'GET'}) => Request(
      method: method,
      url: Uri.parse('http://localhost:8080$path'),
      headers: Headers(const <String, String>{}),
      bodyStream: const Stream<List<int>>.empty(),
    );

void main() {
  late MemoryDVDatabaseAdapter database;
  late DVPublishedPages pages;

  setUp(() {
    database = MemoryDVDatabaseAdapter();
    pages = DVPublishedPages(database: () => database);
  });

  Future<void> publish(String route, String title) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $dvStudioPagesTable (route TEXT, '
      'title TEXT, document TEXT)',
    );
    await database.execute(
      'INSERT INTO $dvStudioPagesTable (route, title, document) '
      'VALUES (?, ?, ?)',
      <Object?>[
        route,
        title,
        jsonEncode(<String, Object?>{'route': route, 'title': title}),
      ],
    );
  }

  test('answers the documents stored, to anybody', () async {
    await publish('/menu', 'Menu');

    final Response? response = await pages.respond(_get(dvPublishedPagesPath));

    expect(response?.status, 200);
    expect(response!.headers.get('cache-control'), contains('no-cache'));
    final Map<String, Object?> body =
        jsonDecode(utf8.decode(await response.body!.bytes()))
            as Map<String, Object?>;
    final List<Object?> listed = body['pages']! as List<Object?>;
    expect(listed, hasLength(1));
    expect(
      ((listed.single! as Map<String, Object?>)['document']!
          as Map<String, Object?>)['title'],
      'Menu',
    );
  });

  test('a server nothing was published on answers an empty list', () async {
    final Response? response = await pages.respond(_get(dvPublishedPagesPath));

    expect(response?.status, 200);
    expect(
      jsonDecode(utf8.decode(await response!.body!.bytes())),
      <String, Object?>{'pages': <Object?>[]},
    );
  });

  test('any other path or method is the application\'s', () async {
    expect(await pages.respond(_get('/menu')), isNull);
    expect(
      await pages.respond(_get(dvPublishedPagesPath, method: 'POST')),
      isNull,
    );
  });

  // The web server answers a path no route serves with a 404, and a Studio
  // page is a route the manifest does not list: it asks here first, so a
  // published page is not reported missing to a crawler.
  test('names the routes it holds, and none before anything is published',
      () async {
    expect(await pages.routes(), isEmpty);

    await publish('/menu', 'Menu');

    expect(await pages.routes(), <String>{'/menu'});
  });

  test('a component made in Studio travels with the pages and is no page '
      'of its own', () async {
    // Components are documents the pages that use them are drawn from, so
    // the application needs them; but an address under /_dartvel/ is
    // Dartvel's, and nothing is served there as a page.
    await publish('/menu', 'Menu');
    await publish('/_dartvel/components/Card', 'Card');

    expect(await pages.routes(), <String>{'/menu'});
    final Response? response = await pages.respond(_get(dvPublishedPagesPath));
    final Map<String, Object?> body =
        jsonDecode(utf8.decode(await response!.body!.bytes()))
            as Map<String, Object?>;
    expect(
      <Object?>[
        for (final Object? page in body['pages']! as List<Object?>)
          (page! as Map<String, Object?>)['route'],
      ],
      containsAll(<String>['/menu', '/_dartvel/components/Card']),
    );
    expect(dvStudioIsReservedRoute('/_dartvel/components/Card'), isTrue);
    expect(dvStudioIsReservedRoute('/dartvel'), isFalse);
  });

  test('Studio''s list of the site leaves components out', () {
    final List<DVStudioSitePage> site = dvStudioSitePages(
      compiled: const <Map<String, Object?>>[
        <String, Object?>{'path': '/'},
      ],
      stored: const <String, String?>{
        '/landing': 'Landing',
        '/_dartvel/components/Card': 'Card',
      },
    );
    expect(<String>[for (final DVStudioSitePage p in site) p.path],
        <String>['/', '/landing']);
  });
}
