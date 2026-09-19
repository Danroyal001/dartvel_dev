// Studio's server side on a database that runs no SQL.
//
// Who may open Studio, the pages Studio edits, and the published pages an
// installed app fetches were each written as SQL strings, so a web-server
// binary on a document database could not grant anybody, edit a page or
// serve one. They now persist through records, over the adapter each is
// handed.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String method, String path, {Object? json}) => Request(
      method: method,
      url: Uri.parse('http://localhost:8080$path'),
      headers: Headers(<String, String>{
        if (json != null) 'content-type': 'application/json',
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
      }),
      bodyStream: json == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
    );

Future<Object?> _json(Response response) async =>
    jsonDecode(utf8.decode(await response.body!.bytes()));

void main() {
  late DVMemoryRecordEngine engine;

  setUp(() => engine = DVMemoryRecordEngine());

  test('grants', () async {
    int now = 1000;
    final DVStudioGrants grants = DVStudioGrants(engine,
        clock: () => DateTime.fromMillisecondsSinceEpoch(now++, isUtc: true));

    await grants.grant('ada');
    await grants.grant('ada');
    await grants.grant('bo', tenant: 'acme');

    expect(await grants.isGranted('ada'), isTrue);
    expect(await grants.isGranted('bo'), isFalse);
    expect(<String>[for (final g in await grants.list()) g.userId],
        <String>['ada', 'bo']);
    expect(await grants.revoke('ada'), isTrue);
    expect(await grants.revoke('ada'), isFalse);
    expect(await grants.isGranted('ada'), isFalse);
  });

  // A function built in Studio is the server's, as a page is: the builder
  // runs in a browser, which has no database of its own.
  test('Studio stores, lists and removes functions', () async {
    final Directory root =
        Directory.systemTemp.createTempSync('dartvel_studio_functions_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    final DVAdminServer server = DVAdminServer(
      mount: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true),
      root: root.path,
      authenticated: (Request _) async => true,
      models: const <DVStudioModelSpec>[],
      database: engine,
    );
    Future<Response> call(String method, String path, {Object? json}) async =>
        (await server.respond(_request(method, path, json: json)))!;

    final Response put =
        await call('PUT', '/__studio/api/functions', json: <String, Object?>{
      'document': <String, Object?>{
        'name': 'joinOakline',
        'side': 'frontend',
        'parameters': <Object?>[],
        'steps': <Object?>[],
      },
    });
    expect(put.status, 200, reason: '${await _json(put)}');

    final Map<String, Object?> listed =
        (await _json(await call('GET', '/__studio/api/functions')))!
            as Map<String, Object?>;
    final Map<String, Object?> one =
        (listed['functions']! as List<Object?>).single! as Map<String, Object?>;
    expect(one['name'], 'joinOakline');
    expect((one['document']! as Map<String, Object?>)['side'], 'frontend');

    await call('DELETE', '/__studio/api/functions?name=joinOakline');
    final Map<String, Object?> after =
        (await _json(await call('GET', '/__studio/api/functions')))!
            as Map<String, Object?>;
    expect(after['functions'], isEmpty);
  });

  test('Studio edits pages, and an installed app fetches them', () async {
    final Directory root =
        Directory.systemTemp.createTempSync('dartvel_studio_records_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    final DVAdminServer server = DVAdminServer(
      mount: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true),
      root: root.path,
      authenticated: (Request _) async => true,
      models: const <DVStudioModelSpec>[],
      database: engine,
    );
    Future<Response> call(String method, String path, {Object? json}) async =>
        (await server.respond(_request(method, path, json: json)))!;

    final Response put = await call('PUT', '/__studio/api/pages', json: <String, Object?>{
      'document': <String, Object?>{'route': '/about', 'title': 'About'},
    });
    expect(put.status, 200, reason: '${await _json(put)}');

    final Map<String, Object?> listed =
        (await _json(await call('GET', '/__studio/api/pages')))!
            as Map<String, Object?>;
    expect(((listed['pages']! as List<Object?>).single!
            as Map<String, Object?>)['route'],
        '/about');

    final Response published = (await DVPublishedPages(database: () => engine)
        .respond(_request('GET', dvPublishedPagesPath)))!;
    final Object? body = await _json(published);
    expect('$body', contains('/about'));

    await call('DELETE', '/__studio/api/pages?route=%2Fabout');
    final Map<String, Object?> after =
        (await _json(await call('GET', '/__studio/api/pages')))!
            as Map<String, Object?>;
    expect(after['pages'], isEmpty);
  });
}
