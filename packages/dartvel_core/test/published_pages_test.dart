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
}
