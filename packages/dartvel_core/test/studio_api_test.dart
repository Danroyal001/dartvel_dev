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
    late DVDatabaseAuthProvider accounts;
    late String owner;
    late String colleague;
    late DVAdminServer asOwner;

    setUp(() async {
      accounts = DVDatabaseAuthProvider(
        database,
        hasher: DVPasswordHasher(iterations: 1000),
      );
      owner = (await accounts.signUp('owner@example.com', 'a-long-password'))!
          .id;
      colleague =
          (await accounts.signUp('sam@example.com', 'a-long-password'))!.id;
      await DVStudioGrants(database).grant(owner);
      asOwner = DVAdminServer(
        mount: _guarded,
        root: root.path,
        authenticated: (Request _) async => true,
        caller: (Request _) async => owner,
        accounts: accounts,
        models: _models,
        database: database,
      );
    });

    Future<List<Map<String, Object?>>> listed() async {
      final Response? response = await asOwner.respond(
        _request('GET', '/__studio/api/grants'),
      );
      return <Map<String, Object?>>[
        for (final Object? grant
            in ((await _json(response!))! as Map<String, Object?>)['grants']!
                as List<Object?>)
          (grant! as Map).cast<String, Object?>(),
      ];
    }

    test('each grant names the account\'s address and marks the caller',
        () async {
      final List<Map<String, Object?>> grants = await listed();

      expect(grants.single['userId'], owner);
      expect(grants.single['email'], 'owner@example.com');
      expect(grants.single['you'], isTrue);
    });

    test('an account is granted by its address', () async {
      final Response? response = await asOwner.respond(
        _request(
          'POST',
          '/__studio/api/grants',
          json: <String, Object?>{'account': 'Sam@Example.com'},
        ),
      );

      expect(response?.status, 201, reason: '${await _json(response!)}');
      expect(await DVStudioGrants(database).isGranted(colleague), isTrue);
      expect(
        (await listed()).map((Map<String, Object?> g) => g['email']),
        containsAll(<String>['owner@example.com', 'sam@example.com']),
      );
    });

    test('an address nobody signed up with is refused, and nothing is granted',
        () async {
      final Response? response = await asOwner.respond(
        _request(
          'POST',
          '/__studio/api/grants',
          json: <String, Object?>{'account': 'nobody@example.com'},
        ),
      );

      expect(response?.status, 404);
      expect(await DVStudioGrants(database).list(), hasLength(1));
    });

    test('a grant or revoke without the CSRF header is refused', () async {
      final Response? grant = await asOwner.respond(
        _request(
          'POST',
          '/__studio/api/grants',
          json: <String, Object?>{'account': 'sam@example.com'},
          csrf: false,
        ),
      );
      final Response? revoke = await asOwner.respond(
        _request(
          'DELETE',
          '/__studio/api/grants?userId=$owner&confirm=true',
          csrf: false,
        ),
      );

      expect(grant?.status, 403);
      expect(revoke?.status, 403);
      expect(await DVStudioGrants(database).isGranted(colleague), isFalse);
      expect(await DVStudioGrants(database).isGranted(owner), isTrue);
    });

    test('a caller who may not open Studio cannot grant', () async {
      granted = false;
      final Response? response = await server.respond(
        _request(
          'POST',
          '/__studio/api/grants',
          json: <String, Object?>{'account': 'sam@example.com'},
        ),
      );

      expect(response, isNull);
      expect(await DVStudioGrants(database).isGranted(colleague), isFalse);
    });

    test('a colleague\'s grant is revoked', () async {
      await DVStudioGrants(database).grant(colleague);

      final Response? response = await asOwner.respond(
        _request('DELETE', '/__studio/api/grants?userId=$colleague'),
      );

      expect(response?.status, 200, reason: '${await _json(response!)}');
      expect(await DVStudioGrants(database).isGranted(colleague), isFalse);
    });

    test('revoking your own grant needs confirmation', () async {
      await DVStudioGrants(database).grant(colleague);

      final Response? unconfirmed = await asOwner.respond(
        _request('DELETE', '/__studio/api/grants?userId=$owner'),
      );
      expect(unconfirmed?.status, 409);
      expect(
        ((await _json(unconfirmed!))! as Map<String, Object?>)['error'],
        'confirm_self',
      );
      expect(await DVStudioGrants(database).isGranted(owner), isTrue);

      final Response? confirmed = await asOwner.respond(
        _request('DELETE', '/__studio/api/grants?userId=$owner&confirm=true'),
      );
      expect(confirmed?.status, 200);
      expect(await DVStudioGrants(database).isGranted(owner), isFalse);
    });

    test('revoking the last grant needs confirmation', () async {
      // Nobody could open Studio afterwards, from Studio.
      final Response? unconfirmed = await asOwner.respond(
        _request('DELETE', '/__studio/api/grants?userId=$owner'),
      );
      expect(unconfirmed?.status, 409);
      expect(
        ((await _json(unconfirmed!))! as Map<String, Object?>)['error'],
        'confirm_last',
      );
      expect(await DVStudioGrants(database).isGranted(owner), isTrue);
    });

    test('lists who may open Studio', () async {
      await DVStudioGrants(database).grant('owner-1');

      final Response? response = await server.respond(
        _request('GET', '/__studio/api/grants'),
      );

      expect(response?.status, 200);
      final List<Object?> grants =
          ((await _json(response!))! as Map<String, Object?>)['grants']!
              as List<Object?>;
      expect(
        grants.map((Object? g) => (g! as Map<String, Object?>)['userId']),
        contains('owner-1'),
      );
    });
  });
}
