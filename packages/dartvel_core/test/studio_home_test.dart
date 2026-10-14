// Studio's Home: the screen the mount opens on, as wp-admin opens on its
// Dashboard and Webflow on a site's overview. What the project holds at a
// glance, whether it is healthy, what changed lately and the things a person
// most often came to do -- each a link to the screen that does it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

const DVAdminMount _open = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: false,
);

const DVStudioModelSpec _product = DVStudioModelSpec(
  model: 'Product',
  table: 'products',
  key: 'slug',
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'slug', type: 'String'),
    DVStudioFieldSpec(name: 'name', type: 'String'),
    DVStudioFieldSpec(name: 'secretNote', type: 'String', sensitive: true),
  ],
);

const String _shell =
    '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="UTF-8">\n'
    '<title>Shop</title>\n</head>\n<body>\n'
    '<script src="flutter_bootstrap.js" async></script>\n</body>\n</html>\n';

const String _graph = '''
{
  "models": [{"name": "Product", "source": "lib/product.dart", "fields": ["slug", "name"]}],
  "routes": [
    {"path": "/", "page": "HomePage", "source": "lib/pages/home.dart", "kind": "page"},
    {"path": "/about", "page": "AboutPage", "source": "lib/pages/about.dart", "kind": "page"}
  ],
  "functions": [
    {"name": "sendInvoice", "method": "POST", "path": "/api/invoice", "source": "lib/api/invoice.dart", "annotated": true}
  ],
  "jobs": [{"name": "syncOrders", "queue": "default", "source": "lib/jobs/sync.dart"}],
  "modules": []
}
''';

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

Future<String> _text(Response response) async =>
    utf8.decode(await response.body!.bytes());

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(await _text(response)) as Map).cast<String, Object?>();

void main() {
  late Directory root;
  late Directory web;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer server;

  setUp(() async {
    final Directory parent = Directory.systemTemp.createTempSync(
      'dartvel_studio_home_',
    );
    addTearDown(() => parent.deleteSync(recursive: true));
    root = Directory('${parent.path}/admin')..createSync();
    File('${root.path}/graph.json').writeAsStringSync(_graph);
    web = Directory('${parent.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync(_shell);
    database = MemoryDVDatabaseAdapter();
    server = DVAdminServer(
      mount: _open,
      root: root.path,
      webRoot: web.path,
      title: 'Studio · Shop',
      models: const <DVStudioModelSpec>[_product],
      database: database,
    );
    final DVRecordTable products = DVRecordTable(
      table: 'products',
      key: 'slug',
      columns: const <String>['slug', 'name', 'secretNote'],
      sensitive: const <String>{'secretNote'},
      database: database,
    );
    await products.ensureSchema();
    for (final String slug in <String>['roast-1', 'roast-2', 'roast-3']) {
      await products.write(<String, Object?>{
        'slug': slug,
        'name': 'House blend $slug',
        'secretNote': 'supplier price 4.10',
      });
    }
  });

  tearDown(DVObservability.health.clear);

  Future<String> document(String path) async =>
      _text((await server.respond(_request('GET', path)))!);

  Future<Map<String, Object?>> overview() async =>
      _json((await server.respond(_request('GET', '/__studio/api/overview')))!);

  group('the screen', () {
    test('Home is the first screen, and the mount opens on it', () async {
      expect(dvStudioScreens.first.id, 'home');
      expect(dvStudioScreens.first.label, 'Home');
      for (final String path in <String>['/__studio', '/__studio/home']) {
        final String html = await document(path);
        expect(html, contains('<h1>Home</h1>'), reason: path);
        // The rail still marks where the reader is.
        expect(html, contains('href="/__studio/home" aria-current="page"'));
      }
    });

    test('Pages keeps its own address', () async {
      expect(await document('/__studio/pages'), contains('<h1>Pages</h1>'));
    });
  });

  group('at a glance', () {
    test('the API counts what the project holds', () async {
      final Map<String, Object?> body = await overview();
      final Map<String, Object?> glance =
          (body['glance']! as Map).cast<String, Object?>();
      expect(glance['pages'], 2);
      expect(glance['models'], 1);
      expect(glance['records'], 3);
      expect(glance['functions'], 1);
      expect(glance['tasks'], 1);
    });

    test('the document says the same, each line a link to its screen',
        () async {
      final String html = await document('/__studio');
      expect(html, contains('<h2>At a glance</h2>'));
      expect(html, contains('href="/__studio/pages">2 pages</a>'));
      expect(html, contains('href="/__studio/models">1 data model</a>'));
      expect(html, contains('3 records'));
      expect(html, contains('href="/__studio/functions">1 backend function</a>'));
    });
  });

  group('site health', () {
    test('a healthy project says so, check by check', () async {
      final List<Map<String, Object?>> health = <Map<String, Object?>>[
        for (final Object? check in (await overview())['health']! as List)
          (check! as Map).cast<String, Object?>(),
      ];
      final Map<String, Object?> data =
          health.firstWhere((Map<String, Object?> c) => c['id'] == 'database');
      expect(data['status'], 'good');
      expect(health.map((Map<String, Object?> c) => c['id']),
          contains('graph'));
      for (final Map<String, Object?> check in health) {
        // Every check is in words: a title and what it means.
        expect('${check['title']}', isNotEmpty);
        expect('${check['detail']}', isNotEmpty);
        expect(<String>['good', 'recommended', 'critical'],
            contains(check['status']));
      }
    });

    test("the application's own health checks are on it, a failing one "
        'critical', () async {
      DVObservability.health.register(
        'payments',
        () async => DVHealthResult.down('The payment provider timed out.'),
      );
      final List<Object?> health = (await overview())['health']! as List;
      final Map<Object?, Object?> payments = health
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> c) => c['id'] == 'check:payments');
      expect(payments['status'], 'critical');
      expect('${payments['detail']}', contains('timed out'));
      final String html = await document('/__studio');
      expect(html, contains('<h2>Site health</h2>'));
      expect(html, contains('payments'));
      expect(html, contains('Needs attention now'));
    });

    test('a build with no project graph is a recommendation, not an error',
        () async {
      File('${root.path}/graph.json').deleteSync();
      final List<Object?> health = (await overview())['health']! as List;
      final Map<Object?, Object?> graph = health
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> c) => c['id'] == 'graph');
      expect(graph['status'], 'recommended');
    });

    test('a stored page with no title is pointed out', () async {
      await server.respond(_request('PUT', '/__studio/api/pages', json: {
        'document': {'route': '/sale', 'title': '', 'children': <Object?>[]},
      }));
      final List<Object?> health = (await overview())['health']! as List;
      final Map<Object?, Object?> titles = health
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> c) => c['id'] == 'page-titles');
      expect(titles['status'], 'recommended');
      expect('${titles['detail']}', contains('/sale'));
    });
  });

  group('recent changes', () {
    test('nothing changed yet says so', () async {
      expect((await overview())['recent'], isEmpty);
      final String html = await document('/__studio');
      expect(html, contains('<h2>Recent changes</h2>'));
      expect(html, contains('No changes made in Studio yet.'));
    });

    test('a page saved and a record written are listed newest first, each '
        'with the address that opens it', () async {
      await server.respond(_request('PUT', '/__studio/api/pages', json: {
        'document': {'route': '/sale', 'title': 'Summer sale', 'children': []},
      }));
      final Response? created = await server.respond(_request(
        'POST',
        '/__studio/api/models/Product/records',
        json: {
          'values': {'slug': 'roast-9', 'name': 'Night roast'},
        },
      ));
      expect(created!.status, 201);
      final List<Map<Object?, Object?>> recent = <Map<Object?, Object?>>[
        for (final Object? row in (await overview())['recent']! as List)
          row! as Map<Object?, Object?>,
      ];
      expect(recent, hasLength(2));
      expect(recent.first['kind'], 'record');
      expect(recent.first['action'], 'created');
      expect(recent.first['screen'], 'models');
      expect(recent.first['object'], 'Product/roast-9');
      expect(recent.last['kind'], 'page');
      expect(recent.last['label'], 'Summer sale');
      expect(recent.last['screen'], 'pages');
      expect(recent.last['object'], 'sale');
      expect(recent.last['at'], isA<int>());
    });

    test("the document names a changed record by its model, never by a "
        'value or its key', () async {
      await server.respond(_request(
        'POST',
        '/__studio/api/models/Product/records',
        json: {
          'values': {
            'slug': 'roast-9',
            'name': 'Night roast',
            'secretNote': 'supplier price 3.90',
          },
        },
      ));
      final String html = await document('/__studio');
      expect(html, contains('A Product record'));
      expect(html, contains('href="/__studio/models/Product"'));
      expect(html, isNot(contains('roast-9')));
      expect(html, isNot(contains('Night roast')));
      expect(html, isNot(contains('3.90')));
    });

    test('a deleted page is a change too', () async {
      await server.respond(_request('PUT', '/__studio/api/pages', json: {
        'document': {'route': '/sale', 'title': 'Summer sale', 'children': []},
      }));
      await server.respond(
        _request('DELETE', '/__studio/api/pages?route=/sale'),
      );
      final List<Object?> recent = (await overview())['recent']! as List;
      expect((recent.first! as Map)['action'], 'deleted');
    });

    test('keeps the latest changes and lets the oldest go', () async {
      for (int i = 0; i < dvStudioActivityKept + 5; i++) {
        await server.respond(_request('PUT', '/__studio/api/pages', json: {
          'document': {'route': '/p$i', 'title': 'Page $i', 'children': []},
        }));
      }
      final DVRecordAdapter records = DVRecordAdapter.over(database);
      expect(
        await records.count(dvStudioActivityTable),
        dvStudioActivityKept,
      );
      final List<Object?> recent = (await overview())['recent']! as List;
      expect((recent.first! as Map)['label'], 'Page ${dvStudioActivityKept + 4}');
    });
  });

  group('quick actions', () {
    test('each is a link to the screen that does it', () async {
      final String html = await document('/__studio');
      expect(html, contains('<h2>Quick actions</h2>'));
      expect(html, contains('href="/__studio/pages">Add a page</a>'));
      expect(html, contains('href="/__studio/models">Design a data model</a>'));
      expect(html, contains('href="/__studio/access">Add a teammate</a>'));
      expect(html, contains('href="/">View the site</a>'));
    });
  });

  test('the overview is behind the grant like the rest of the API', () async {
    final DVAdminServer guarded = DVAdminServer(
      mount: const DVAdminMount(
        path: '/__studio',
        enabled: true,
        requiresAuth: true,
      ),
      root: root.path,
      authenticated: (Request _) async => false,
      database: database,
    );
    final Response? response =
        await guarded.respond(_request('GET', '/__studio/api/overview'));
    expect(response == null || response.status == 404, isTrue);
  });
}
