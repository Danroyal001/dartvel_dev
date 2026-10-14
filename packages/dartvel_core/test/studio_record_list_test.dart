// A data model's records as a list a person works through, the way the
// Posts screen of a CMS is one: searched, sorted, filtered, a page at a
// time, and several deleted at once.
//
// Studio fetched every record of a model in one reply and searched them in
// the browser, so a model with ten thousand rows sent ten thousand rows to
// show fifty, and there was no sort, no filter and no way to delete more
// than one record at a time.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

const DVAdminMount _mount = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: true,
);

const DVStudioModelSpec _user = DVStudioModelSpec(
  model: 'User',
  table: 'users',
  key: 'slug',
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'slug', type: 'String'),
    DVStudioFieldSpec(name: 'name', type: 'String'),
    DVStudioFieldSpec(name: 'age', type: 'int?'),
    DVStudioFieldSpec(name: 'published', type: 'bool'),
    DVStudioFieldSpec(
      name: 'tier',
      type: 'String',
      options: <String>['free', 'paid'],
    ),
    DVStudioFieldSpec(name: 'password', type: 'String', sensitive: true),
  ],
);

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

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
        .cast<String, Object?>();

void main() {
  late Directory root;
  late DVAdminServer server;

  Future<Response> get(String query) async => (await server.respond(
    _request('GET', '/__studio/api/models/User/records$query'),
  ))!;

  List<String> keys(Map<String, Object?> body) => <String>[
    for (final Object? record in body['records']! as List)
      '${(record! as Map)['key']}',
  ];

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_record_list_');
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    addTearDown(() => root.deleteSync(recursive: true));
    final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
    server = DVAdminServer(
      mount: _mount,
      root: root.path,
      authenticated: (Request _) async => true,
      models: const <DVStudioModelSpec>[_user],
      database: database,
    );
    final DVRecordTable users = DVRecordTable(
      table: 'users',
      key: 'slug',
      columns: const <String>[
        'slug',
        'name',
        'age',
        'published',
        'tier',
        'password',
      ],
      sensitive: const <String>{'password'},
      database: database,
    );
    await users.ensureSchema();
    for (int i = 1; i <= 120; i++) {
      await users.write(<String, Object?>{
        'slug': 'user-${i.toString().padLeft(3, '0')}',
        'name': i == 7 ? 'Ada Lovelace' : 'Person $i',
        'age': '${i % 50}',
        'published': i.isEven ? 1 : 0,
        'tier': i % 3 == 0 ? 'paid' : 'free',
        'password': 'secret-$i',
      });
    }
  });

  test('with nothing asked, every record and the total', () async {
    final Map<String, Object?> body = await _json(await get(''));
    expect(body['total'], 120);
    expect(keys(body), hasLength(120),
        reason: 'existing callers asked for every record and still get it');
  });

  test('a page at a time, with the total', () async {
    final Map<String, Object?> body =
        await _json(await get('?limit=50&offset=100'));
    expect(body['total'], 120);
    expect(body['offset'], 100);
    expect(body['limit'], 50);
    expect(keys(body), hasLength(20));
  });

  test('a limit above the most is held to it', () async {
    final Map<String, Object?> body = await _json(await get('?limit=100000'));
    expect(body['limit'], 500);
  });

  test('searched across what may be seen, never the sensitive field',
      () async {
    final Map<String, Object?> found = await _json(await get('?q=lovelace'));
    expect(keys(found), <String>['user-007']);
    expect(found['total'], 1);
    final Map<String, Object?> secret = await _json(await get('?q=secret-7'));
    expect(keys(secret), isEmpty,
        reason: 'a search that matched a password would tell a person '
            'what it is one letter at a time');
  });

  test('sorted by a field, as its type sorts', () async {
    final Map<String, Object?> asc =
        await _json(await get('?sort=age&order=asc&limit=3'));
    expect(<Object?>[
      for (final Object? r in asc['records']! as List)
        ((r! as Map)['values'] as Map)['age'],
    ], <Object?>[0, 0, 1], reason: 'numbers sort as numbers, not as text');
    final Map<String, Object?> desc =
        await _json(await get('?sort=age&order=desc&limit=1'));
    expect(((desc['records']! as List).first as Map)['values']['age'], 49);
  });

  test('filtered by a field value', () async {
    final Map<String, Object?> paid = await _json(await get('?filter=tier:paid'));
    expect(paid['total'], 40);
    final Map<String, Object?> published =
        await _json(await get('?filter=published:true&filter=tier:paid'));
    expect(published['total'], 20, reason: 'two filters both apply');
  });

  test('a sensitive or unknown field cannot be sorted or filtered by',
      () async {
    for (final String query in <String>[
      '?sort=password',
      '?sort=nope',
      '?filter=password:secret-1',
      '?filter=nope:1',
      '?filter=tier',
      '?order=sideways&sort=age',
    ]) {
      final Response response = await get(query);
      expect(response.status, 400, reason: query);
      final Map<String, Object?> body = await _json(response);
      expect('${body['message']}', isNot(contains('Exception')), reason: query);
    }
  });

  test('several records deleted at once, each answered for itself', () async {
    final Map<String, Object?> one = await _json(await get('?limit=1'));
    final Map<String, Object?> first =
        ((one['records']! as List).first as Map).cast<String, Object?>();
    final Response response = (await server.respond(_request(
      'POST',
      '/__studio/api/models/User/records/delete',
      json: <String, Object?>{
        'records': <Object?>[
          <String, Object?>{'key': first['key'], 'version': first['version']},
          <String, Object?>{'key': 'user-002', 'version': 1},
          <String, Object?>{'key': 'nobody', 'version': 1},
          <String, Object?>{'key': 'user-003', 'version': 99},
        ],
      },
    )))!;
    expect(response.status, 200);
    final Map<String, Object?> body = await _json(response);
    expect(body['deleted'], <Object?>[first['key'], 'user-002']);
    final Map<String, Object?> failed =
        (body['failed']! as Map).cast<String, Object?>();
    expect(failed.keys, unorderedEquals(<String>['nobody', 'user-003']));
    expect('${failed['user-003']}', contains('changed'));
    expect((await _json(await get('')))['total'], 118);
  });
}
