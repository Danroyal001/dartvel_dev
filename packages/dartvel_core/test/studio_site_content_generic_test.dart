// Menus, forms and settings are the project's, and Studio is the same for
// every project. So a new project starts with none of somebody else's: no
// sample menus linking to pages it may not have, no contact form it did not
// make, no social links of the framework's. And what Studio says it saved is
// what the database holds -- a write that failed is an error, not a 200 with
// the change kept in one process's memory until the next restart.
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

/// A database whose writes fail after it was read, as a full disk does.
class _ReadOnly extends MemoryDVDatabaseAdapter {
  bool failing = false;

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    final String verb = sql.trimLeft().split(' ').first.toUpperCase();
    if (failing && const <String>{'INSERT', 'UPDATE', 'DELETE'}.contains(verb)) {
      return Future<int>.error(StateError('disk full'));
    }
    return super.execute(sql, params);
  }
}

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;

  DVAdminServer serve(DVDatabaseAdapter? db) => DVAdminServer(
    mount: const DVAdminMount(
      path: '/__studio',
      enabled: true,
      requiresAuth: false,
    ),
    root: root.path,
    database: db,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_generic_');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
  });

  Future<(int, Map<String, Object?>)> call(
    DVAdminServer server,
    String method,
    String path, {
    Object? json,
  }) async {
    final Response response = (await server.respond(
      _request(method, '/__studio/api/$path', json: json),
    ))!;
    final String text = utf8.decode(await response.body!.bytes());
    final Object? body = text.isEmpty ? null : jsonDecode(text);
    return (
      response.status,
      body is Map ? body.cast<String, Object?>() : <String, Object?>{},
    );
  }

  test('a new project has no menus and no forms of anybody else\'s', () async {
    final DVAdminServer server = serve(database);
    expect((await call(server, 'GET', 'menus')).$2['menus'], isEmpty);
    expect((await call(server, 'GET', 'forms')).$2['forms'], isEmpty);
  });

  test('a new project\'s settings carry nothing of the framework\'s', () async {
    final Map<String, Object?> settings =
        (await call(serve(database), 'GET', 'settings')).$2;
    final String text = jsonEncode(settings).toLowerCase();
    expect(text, isNot(contains('dartvel')));
    expect(text, isNot(contains('github.com')));
    expect(text, isNot(contains('x.com')));
  });

  test('a deleted menu stays deleted', () async {
    final DVAdminServer server = serve(database);
    await call(server, 'PUT', 'menus', json: <String, Object?>{
      'id': 'main',
      'name': 'Main',
      'items': <Object?>[],
    });
    expect((await call(server, 'GET', 'menus')).$2['menus'], hasLength(1));
    await call(server, 'DELETE', 'menus?id=main');
    expect((await call(serve(database), 'GET', 'menus')).$2['menus'], isEmpty);
  });

  test('a deleted form stays deleted after a restart', () async {
    final DVAdminServer server = serve(database);
    await call(server, 'POST', 'forms', json: <String, Object?>{
      'id': 'enquiry',
      'name': 'Enquiry',
      'fields': <Object?>[
        <String, Object?>{'id': 'email', 'label': 'Email', 'type': 'email'},
      ],
    });
    await call(server, 'DELETE', 'forms?id=enquiry');
    expect((await call(serve(database), 'GET', 'forms')).$2['forms'], isEmpty);
  });

  test('a write the database refused is an error, not a 200', () async {
    final _ReadOnly failing = _ReadOnly();
    final DVAdminServer server = serve(failing);
    // Read first, so the tables exist.
    await call(server, 'GET', 'menus');
    await call(server, 'GET', 'settings');
    failing.failing = true;
    final (int menu, _) = await call(server, 'PUT', 'menus', json: <String, Object?>{
      'id': 'main',
      'name': 'Main',
      'items': <Object?>[],
    });
    expect(menu, greaterThanOrEqualTo(500));
    final (int settings, _) = await call(server, 'PUT', 'settings', json: <String, Object?>{
      'siteTitle': 'Harbour',
    });
    expect(settings, greaterThanOrEqualTo(500));
    failing.failing = false;
    expect((await call(server, 'GET', 'menus')).$2['menus'], isEmpty,
        reason: 'the refused menu was kept somewhere and shown');
  });

  test('with no database, nothing is said to be saved', () async {
    final DVAdminServer server = serve(null);
    final (int status, _) = await call(server, 'PUT', 'menus', json: <String, Object?>{
      'id': 'main',
      'name': 'Main',
      'items': <Object?>[],
    });
    expect(status, 503);
  });
}
