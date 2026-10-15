// Drafts, revisions, restore and scheduled publishing for the pages Studio
// builds, as wp-admin keeps a post's drafts and revisions and Webflow keeps a
// site's backups and scheduled publishes.
//
// The served page is the published version and nothing else: saving a draft,
// which is what autosave does, never changes what a visitor gets.
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

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
        .cast<String, Object?>();

Map<String, Object?> _page(String route, String title) => <String, Object?>{
  'route': route,
  'title': title,
  'children': <Object?>[],
};

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;
  late DateTime now;
  late DVAdminServer server;

  DVAdminServer serve() => DVAdminServer(
    mount: const DVAdminMount(
      path: '/__studio',
      enabled: true,
      requiresAuth: false,
    ),
    root: root.path,
    database: database,
    caller: (Request _) async => 'ada',
    clock: () => now,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_drafts_');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
    now = DateTime.utc(2026, 10, 15, 9);
    server = serve();
  });

  Future<Map<String, Object?>> call(
    String method,
    String path, {
    Object? json,
    int status = 200,
  }) async {
    final Response response = (await server.respond(
      _request(method, '/__studio/api/$path', json: json),
    ))!;
    final Map<String, Object?> body = await _json(response);
    expect(response.status, status, reason: '$method $path: $body');
    return body;
  }

  /// What a visitor is served: the published pages, by route.
  Future<Map<String, String?>> served() async {
    final Response response = (await DVPublishedPages(
      database: () => database,
    ).respond(_request('GET', dvPublishedPagesPath)))!;
    final Object? body = jsonDecode(
      utf8.decode(await response.body!.bytes()),
    );
    return <String, String?>{
      for (final Object? page in (body! as Map)['pages'] as List<Object?>)
        '${(page! as Map)['route']}': (page as Map)['title'] as String?,
    };
  }

  List<Map<String, Object?>> versionsOf(Map<String, Object?> reply) =>
      <Map<String, Object?>>[
        for (final Object? v in reply['versions']! as List<Object?>)
          (v! as Map).cast<String, Object?>(),
      ];

  test('a saved draft is not served; publishing it is', () async {
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/sale', 'Autumn sale'),
    });
    expect(await served(), isEmpty, reason: 'a draft reached visitors');

    final Map<String, Object?> listed = await call('GET', 'pages');
    final Map<String, Object?> page =
        ((listed['pages']! as List<Object?>).single! as Map)
            .cast<String, Object?>();
    expect(page['route'], '/sale');
    expect(page['published'], isFalse);
    expect(((page['draft']! as Map)['document']! as Map)['title'],
        'Autumn sale');

    await call('POST', 'pages/publish', json: <String, Object?>{
      'route': '/sale',
    });
    expect(await served(), <String, String?>{'/sale': 'Autumn sale'});
  });

  test('editing a published page keeps the live one until published', () async {
    await call('PUT', 'pages', json: <String, Object?>{
      'document': _page('/sale', 'Autumn sale'),
    });
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/sale', 'Winter sale'),
    });
    // Autosave writes the same draft again rather than opening another.
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/sale', 'Winter sale!'),
    });
    expect(await served(), <String, String?>{'/sale': 'Autumn sale'});

    final List<Map<String, Object?>> versions = versionsOf(
      await call('GET', 'pages/versions?route=%2Fsale'),
    );
    expect(
      <String>[for (final Map<String, Object?> v in versions) '${v['state']}'],
      <String>['published', 'draft'],
    );
  });

  test('every publish is a revision, and restoring one serves it again',
      () async {
    for (final String title in <String>['One', 'Two', 'Three']) {
      await call('PUT', 'pages', json: <String, Object?>{
        'document': _page('/about', title),
      });
    }
    expect(await served(), <String, String?>{'/about': 'Three'});

    final List<Map<String, Object?>> versions = versionsOf(
      await call('GET', 'pages/versions?route=%2Fabout'),
    );
    expect(
      <String>[for (final Map<String, Object?> v in versions) '${v['state']}'],
      <String>['superseded', 'superseded', 'published'],
    );
    expect(versions.first['author'], 'ada');

    await call('POST', 'pages/restore', json: <String, Object?>{
      'id': versions.first['id'],
    });
    expect(await served(), <String, String?>{'/about': 'One'});

    final List<Object?> history =
        (await call('GET', 'pages/history?route=%2Fabout'))['history']!
            as List<Object?>;
    // The first version was published twice: once, and again by restore.
    expect(
      <Object?>[
        for (final Object? t in history)
          if ((t! as Map)['version'] == 1 && (t as Map)['to'] == 'published') t,
      ],
      hasLength(2),
    );
  });

  test('a scheduled draft is published at its time, not before', () async {
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/launch', 'Launch'),
    });
    final DateTime at = now.add(const Duration(hours: 2));
    await call('POST', 'pages/schedule', json: <String, Object?>{
      'route': '/launch',
      'at': at.toIso8601String(),
    });
    expect(await server.api.runDueSchedules(), 0);
    expect(await served(), isEmpty);

    // A restart in between: the schedule is in the database, not a timer.
    server = serve();
    now = at.add(const Duration(seconds: 30));
    expect(await server.api.runDueSchedules(), 1);
    expect(await served(), <String, String?>{'/launch': 'Launch'});
  });

  test('a schedule can be cancelled, and a past slot is refused', () async {
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/launch', 'Launch'),
    });
    await call(
      'POST',
      'pages/schedule',
      json: <String, Object?>{
        'route': '/launch',
        'at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
      },
      status: 400,
    );
    await call('POST', 'pages/schedule', json: <String, Object?>{
      'route': '/launch',
      'at': now.add(const Duration(hours: 1)).toIso8601String(),
    });
    await call('POST', 'pages/unschedule', json: <String, Object?>{
      'route': '/launch',
    });
    now = now.add(const Duration(hours: 1, seconds: 1));
    expect(await server.api.runDueSchedules(), 0);
    expect(await served(), isEmpty);
  });

  test('discarding a draft leaves the published page alone', () async {
    await call('PUT', 'pages', json: <String, Object?>{
      'document': _page('/about', 'About'),
    });
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/about', 'About us'),
    });
    await call('POST', 'pages/discard', json: <String, Object?>{
      'route': '/about',
    });
    expect(await served(), <String, String?>{'/about': 'About'});
    final Map<String, Object?> page =
        (((await call('GET', 'pages'))['pages']! as List<Object?>).single!
                as Map)
            .cast<String, Object?>();
    expect(page['draft'], isNull);
  });

  test('a transition on a version somebody has moved since is refused',
      () async {
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/about', 'About'),
    });
    final Map<String, Object?> read = versionsOf(
      await call('GET', 'pages/versions?route=%2Fabout'),
    ).single;
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/about', 'About us'),
    });
    await call(
      'POST',
      'pages/publish',
      json: <String, Object?>{'id': read['id'], 'expect': read['recordVersion']},
      status: 409,
    );
    expect(await served(), isEmpty);
  });

  test('on a database that keeps no versions, Studio says so', () async {
    // The content workflow's versions are SQL tables; a document engine
    // publishes directly and has no drafts to save into, which Studio has to
    // know so that autosave never falls back to publishing.
    final DVMemoryRecordEngine engine = DVMemoryRecordEngine();
    server = DVAdminServer(
      mount: const DVAdminMount(
        path: '/__studio',
        enabled: true,
        requiresAuth: false,
      ),
      root: root.path,
      database: engine,
      caller: (Request _) async => 'ada',
    );
    final Map<String, Object?> refused = await call(
      'PUT',
      'pages/draft',
      json: <String, Object?>{'document': _page('/about', 'About')},
      status: 501,
    );
    expect(refused['code'], 'no_versions');
    await call('PUT', 'pages', json: <String, Object?>{
      'document': _page('/about', 'About'),
    });
    final Map<String, Object?> listed = await call('GET', 'pages');
    expect(listed['versions'], isFalse);
    expect((listed['pages']! as List<Object?>).single, isA<Map>());
  });

  test('the page list says when drafts are kept', () async {
    expect((await call('GET', 'pages'))['versions'], isTrue);
  });

  test('a version travels as JSON and comes back the same snapshot', () async {
    await call('PUT', 'pages/draft', json: <String, Object?>{
      'document': _page('/about', 'About'),
    });
    final Map<String, Object?> json = versionsOf(
      await call('GET', 'pages/versions?route=%2Fabout'),
    ).single;
    final DVContentVersion<Map<String, Object?>> version =
        DVContentVersion<Map<String, Object?>>.fromJson(
          json,
          (Map<String, Object?> document) => document,
        );
    expect(version.documentId, '/about');
    expect(version.state, DVContentState.draft);
    expect(version.document['title'], 'About');
    expect(version.editors, <String>{'ada'});
    expect(
      version.toJson((Map<String, Object?> d) => d),
      json,
    );
  });
}
