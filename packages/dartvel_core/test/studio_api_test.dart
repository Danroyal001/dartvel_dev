// Studio's data, served under the admin mount to the same callers who may
// open Studio at all.
//
// The web-server binary served a static read-only manifest at /__studio, so
// the Studio an operator opened could name a model and show none of its
// records. These are the endpoints the full Studio reads and writes through:
// a model's records, the page builder's documents, and the grants. They are
// the admin's, so they sit behind exactly the decision the dashboard's files
// do -- a caller who may not see Studio gets the same nothing.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVAdminMount _guarded = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: true,
);

const List<DVStudioModelSpec> _models = <DVStudioModelSpec>[
  DVStudioModelSpec(
    model: 'User',
    table: 'users',
    key: 'slug',
    fields: <DVStudioFieldSpec>[
      DVStudioFieldSpec(name: 'slug', type: 'String'),
      DVStudioFieldSpec(name: 'name', type: 'String'),
      DVStudioFieldSpec(name: 'age', type: 'int?'),
      DVStudioFieldSpec(name: 'published', type: 'bool'),
      DVStudioFieldSpec(name: 'password', type: 'String', sensitive: true),
    ],
  ),
];

Request _request(
  String method,
  String path, {
  Object? json,
  bool csrf = true,
}) => Request(
  method: method,
  url: Uri.parse('http://localhost:8080$path'),
  headers: Headers(<String, String>{
    if (json != null) 'content-type': 'application/json',
    if (csrf) 'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
  }),
  bodyStream: json == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
);

Future<Object?> _json(Response response) async =>
    jsonDecode(utf8.decode(await response.body!.bytes()));

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer server;
  bool granted = true;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_studio_api_');
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
    granted = true;
    server = DVAdminServer(
      mount: _guarded,
      root: root.path,
      authenticated: (Request _) async => granted,
      models: _models,
      database: database,
    );
    final DVRecordTable users = DVRecordTable(
      table: 'users',
      key: 'slug',
      columns: const <String>['slug', 'name', 'age', 'published', 'password'],
      sensitive: const <String>{'password'},
      database: database,
    );
    await users.ensureSchema();
    await users.write(<String, Object?>{
      'slug': 'ada',
      'name': 'Ada',
      'age': '36',
      'published': 1,
      'password': 'hash-of-a-secret',
    });
  });

  group('who reaches it', () {
    test(
      'a caller who may not open Studio gets nothing, not a refusal',
      () async {
        granted = false;
        for (final Request request in <Request>[
          _request('GET', '/__studio/api/models'),
          _request('GET', '/__studio/api/models/User/records'),
          _request(
            'PUT',
            '/__studio/api/models/User/records/ada',
            json: <String, Object?>{'values': <String, Object?>{}},
          ),
          _request('GET', '/__studio/api/pages'),
        ]) {
          expect(
            await server.respond(request),
            isNull,
            reason: request.url.path,
          );
        }
      },
    );

    test('a write without the CSRF header is refused', () async {
      final Response? response = await server.respond(
        _request(
          'PUT',
          '/__studio/api/models/User/records/ada',
          json: <String, Object?>{
            'version': 1,
            'values': <String, Object?>{'name': 'Forged'},
          },
          csrf: false,
        ),
      );

      expect(response?.status, 403);
      final Response? list = await server.respond(
        _request('GET', '/__studio/api/models/User/records'),
      );
      expect(jsonEncode(await _json(list!)), isNot(contains('Forged')));
    });
  });

  group('models', () {
    test('lists each model with its fields, sensitive ones marked', () async {
      final Response? response = await server.respond(
        _request('GET', '/__studio/api/models'),
      );

      expect(response?.status, 200);
      expect(response!.headers.get('cache-control'), 'no-store');
      final Map<String, Object?> body =
          (await _json(response))! as Map<String, Object?>;
      final List<Object?> models = body['models']! as List<Object?>;
      final Map<String, Object?> user = models.single! as Map<String, Object?>;
      expect(user['model'], 'User');
      expect(user['key'], 'slug');
      expect(
        (user['fields']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .firstWhere(
              (Map<String, Object?> f) => f['name'] == 'password',
            )['sensitive'],
        isTrue,
      );
    });

    test(
      'records come back typed, with their version, and no sensitive value',
      () async {
        final Response? response = await server.respond(
          _request('GET', '/__studio/api/models/User/records'),
        );

        expect(response?.status, 200);
        final String raw = jsonEncode(await _json(response!));
        expect(raw, isNot(contains('hash-of-a-secret')));
        final Map<String, Object?> record =
            ((jsonDecode(raw) as Map)['records'] as List).single
                as Map<String, Object?>;
        expect(record['key'], 'ada');
        expect(record['version'], 1);
        expect(record['values'], <String, Object?>{
          'slug': 'ada',
          'name': 'Ada',
          'age': 36,
          'published': true,
        });
      },
    );

    test(
      'an edit is stored at the version it read, keeping sensitive values',
      () async {
        final Response? response = await server.respond(
          _request(
            'PUT',
            '/__studio/api/models/User/records/ada',
            json: <String, Object?>{
              'version': 1,
              'values': <String, Object?>{
                'name': 'Ada Lovelace',
                'age': 37,
                'published': false,
              },
            },
          ),
        );

        expect(response?.status, 200, reason: '${await _json(response!)}');
        final List<Map<String, Object?>> rows = await database.query(
          'SELECT * FROM users',
        );
        expect(rows.single['name'], 'Ada Lovelace');
        expect(rows.single['published'], 0);
        expect(rows.single['password'], 'hash-of-a-secret');
        expect(rows.single[DVRecordTable.versionColumn], 2);
      },
    );

    test('an edit against a record that has moved is a conflict', () async {
      final Response? response = await server.respond(
        _request(
          'PUT',
          '/__studio/api/models/User/records/ada',
          json: <String, Object?>{
            'version': 7,
            'values': <String, Object?>{'name': 'Stale'},
          },
        ),
      );

      expect(response?.status, 409);
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT * FROM users',
      );
      expect(rows.single['name'], 'Ada');
    });

    test('a sensitive value cannot be written through Studio', () async {
      final Response? response = await server.respond(
        _request(
          'PUT',
          '/__studio/api/models/User/records/ada',
          json: <String, Object?>{
            'version': 1,
            'values': <String, Object?>{'password': 'chosen-by-studio'},
          },
        ),
      );

      expect(response?.status, 400);
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT * FROM users',
      );
      expect(rows.single['password'], 'hash-of-a-secret');
    });

    test('a new record is created, and creating it twice is refused', () async {
      Future<Response?> create() => server.respond(
        _request(
          'POST',
          '/__studio/api/models/User/records',
          json: <String, Object?>{
            'values': <String, Object?>{
              'slug': 'grace',
              'name': 'Grace',
              'published': true,
            },
          },
        ),
      );

      expect((await create())?.status, 201);
      expect((await create())?.status, 409);
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT * FROM users WHERE slug = ?',
        <Object?>['grace'],
      );
      expect(rows.single['name'], 'Grace');
    });

    test('a record is deleted at the version it read', () async {
      final Response? stale = await server.respond(
        _request('DELETE', '/__studio/api/models/User/records/ada?version=3'),
      );
      expect(stale?.status, 409);

      final Response? deleted = await server.respond(
        _request('DELETE', '/__studio/api/models/User/records/ada?version=1'),
      );
      expect(deleted?.status, 200);
      expect(await database.query('SELECT * FROM users'), isEmpty);
    });

    test('a model nobody declared is not found', () async {
      final Response? response = await server.respond(
        _request('GET', '/__studio/api/models/Secret/records'),
      );

      expect(response?.status, 404);
    });
  });

  group('pages', () {
    test('a document published through Studio is listed and stored', () async {
      final Response? saved = await server.respond(
        _request(
          'PUT',
          '/__studio/api/pages',
          json: <String, Object?>{
            'document': <String, Object?>{
              'route': '/about',
              'title': 'About',
              'root': <String, Object?>{'type': 'column'},
            },
          },
        ),
      );
      expect(saved?.status, 200, reason: '${await _json(saved!)}');

      final Response? listed = await server.respond(
        _request('GET', '/__studio/api/pages'),
      );
      final List<Object?> pages =
          ((await _json(listed!))! as Map<String, Object?>)['pages']!
              as List<Object?>;
      expect((pages.single! as Map<String, Object?>)['route'], '/about');
      expect(
        ((pages.single! as Map<String, Object?>)['document']!
            as Map<String, Object?>)['title'],
        'About',
      );

      final Response? removed = await server.respond(
        _request('DELETE', '/__studio/api/pages?route=%2Fabout'),
      );
      expect(removed?.status, 200);
      final Response? after = await server.respond(
        _request('GET', '/__studio/api/pages'),
      );
      expect(
        ((await _json(after!))! as Map<String, Object?>)['pages'],
        isEmpty,
      );
    });
  });

  group('grants', () {
    test('lists who may open Studio', () async {
      await DVStudioGrants(database).grant('owner-1');

      final Response? response = await server.respond(
        _request('GET', '/__studio/api/grants'),
      );

      expect(response?.status, 200);
      final List<Object?> grants =
          ((await _json(response!))! as Map<String, Object?>)['grants']!
              as List<Object?>;
      expect((grants.single! as Map<String, Object?>)['userId'], 'owner-1');
    });
  });
}
