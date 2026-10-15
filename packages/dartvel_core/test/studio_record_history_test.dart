// A data model that keeps a history -- `@DVModel(history: DVHistory())` --
// keeps it for the edits made in Studio too, and Studio shows it and puts a
// record back to an earlier version, as wp-admin restores a revision.
//
// Studio wrote through a record table built without the model's history, so
// its edits were missing from the very log the model declared.
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

const DVStudioModelSpec _article = DVStudioModelSpec(
  model: 'Article',
  table: 'articles',
  key: 'slug',
  history: DVHistory(),
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'slug', type: 'String'),
    DVStudioFieldSpec(name: 'title', type: 'String'),
  ],
);

const DVStudioModelSpec _note = DVStudioModelSpec(
  model: 'Note',
  table: 'notes',
  key: 'id',
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'id', type: 'String'),
    DVStudioFieldSpec(name: 'body', type: 'String'),
  ],
);

void main() {
  late Directory root;
  late DVAdminServer server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_record_history_');
    addTearDown(() => root.deleteSync(recursive: true));
    server = DVAdminServer(
      mount: const DVAdminMount(
        path: '/__studio',
        enabled: true,
        requiresAuth: false,
      ),
      root: root.path,
      database: MemoryDVDatabaseAdapter(),
      models: const <DVStudioModelSpec>[_article, _note],
      caller: (Request _) async => 'ada',
    );
  });

  Future<(int, Map<String, Object?>)> call(
    String method,
    String path, {
    Object? json,
  }) async {
    final Response response = (await server.respond(
      _request(method, '/__studio/api/$path', json: json),
    ))!;
    final Object? body = jsonDecode(utf8.decode(await response.body!.bytes()));
    return (response.status, (body! as Map).cast<String, Object?>());
  }

  test('a model with a history keeps Studio\'s edits in it, and puts one back',
      () async {
    await call('POST', 'models/Article/records', json: <String, Object?>{
      'values': <String, Object?>{'slug': 'hello', 'title': 'Hello'},
    });
    final (_, Map<String, Object?> read) =
        await call('GET', 'models/Article/records/hello');
    await call('PUT', 'models/Article/records/hello', json: <String, Object?>{
      'version': read['version'],
      'values': <String, Object?>{'title': 'Hello, world'},
    });

    final (int status, Map<String, Object?> history) =
        await call('GET', 'models/Article/records/hello/history');
    expect(status, 200);
    final List<Object?> entries = history['history']! as List<Object?>;
    expect(entries, hasLength(2));
    final Map<String, Object?> edit = (entries.last! as Map).cast<String, Object?>();
    expect(edit['actor'], 'ada');
    expect((edit['changes']! as Map)['title'],
        <String, Object?>{'from': 'Hello', 'to': 'Hello, world'});

    final Map<String, Object?> first = (entries.first! as Map).cast<String, Object?>();
    final (_, Map<String, Object?> now) =
        await call('GET', 'models/Article/records/hello');
    final (int reverted, Map<String, Object?> after) = await call(
      'POST',
      'models/Article/records/hello/revert',
      json: <String, Object?>{'to': first['version'], 'version': now['version']},
    );
    expect(reverted, 200);
    expect((after['values']! as Map)['title'], 'Hello');
    // A revert is a change of its own: the history grows, it is not rewound.
    final (_, Map<String, Object?> later) =
        await call('GET', 'models/Article/records/hello/history');
    expect(later['history'], hasLength(3));
  });

  test('a revert from a stale read is refused', () async {
    await call('POST', 'models/Article/records', json: <String, Object?>{
      'values': <String, Object?>{'slug': 'hello', 'title': 'Hello'},
    });
    final (_, Map<String, Object?> read) =
        await call('GET', 'models/Article/records/hello');
    await call('PUT', 'models/Article/records/hello', json: <String, Object?>{
      'version': read['version'],
      'values': <String, Object?>{'title': 'Two'},
    });
    final (int status, _) = await call(
      'POST',
      'models/Article/records/hello/revert',
      json: <String, Object?>{'to': 1, 'version': read['version']},
    );
    expect(status, 409);
  });

  test('a model that keeps no history says so', () async {
    await call('POST', 'models/Note/records', json: <String, Object?>{
      'values': <String, Object?>{'id': 'n1', 'body': 'x'},
    });
    final (int status, Map<String, Object?> body) =
        await call('GET', 'models/Note/records/n1/history');
    expect(status, 200);
    expect(body['history'], isEmpty);
    expect(body['kept'], isFalse);
  });

  test('the model list says which models keep a history', () async {
    final (_, Map<String, Object?> models) = await call('GET', 'models');
    final Map<String, Object?> article = (models['models']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((Map<String, Object?> m) => m['model'] == 'Article');
    expect(article['history'], isTrue);
  });
  test('records deleted at once are in Recent changes, as one deleted alone is',
      () async {
    for (final String id in <String>['n1', 'n2']) {
      await call('POST', 'models/Note/records', json: <String, Object?>{
        'values': <String, Object?>{'id': id, 'body': 'x'},
      });
    }
    await call('POST', 'models/Note/records/delete', json: <String, Object?>{
      'records': <Object?>[
        <String, Object?>{'key': 'n1', 'version': 1},
        <String, Object?>{'key': 'n2', 'version': 1},
      ],
    });
    final (_, Map<String, Object?> overview) = await call('GET', 'overview');
    final Map<String, Object?> latest =
        ((overview['recent']! as List).first! as Map).cast<String, Object?>();
    expect(latest['action'], 'deleted');
    expect(latest['label'], '2 Note records');
  });
}
