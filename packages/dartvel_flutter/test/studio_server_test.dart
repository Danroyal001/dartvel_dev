// Studio as a web-server binary serves it: the whole Studio, talking to the
// backend it was served by.
//
// The binary used to serve a static manifest at the admin mount, so the
// Studio an operator opened could name a model and show none of its records,
// and the page builder was not there at all. This is the Flutter half of the
// real one: a client over the admin mount's API, a page store that publishes
// to the server, and the sections that show records, their edit form, the
// project's routes, functions and jobs, and who may open Studio.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One request the fake server saw.
typedef _Call = ({String method, String path, Object? body});

/// A backend, in memory, answering the way the admin mount's API does.
class _FakeServer {
  final List<_Call> calls = <_Call>[];
  final Map<String, Map<String, Object?>> users = <String, Map<String, Object?>>{
    'ada': <String, Object?>{
      'key': 'ada',
      'version': 1,
      'values': <String, Object?>{
        'slug': 'ada',
        'name': 'Ada',
        'age': 36,
        'published': true,
      },
    },
  };
  final Map<String, Map<String, Object?>> pages =
      <String, Map<String, Object?>>{};

  Future<DVStudioReply> call(String method, String path,
      {Object? body}) async {
    // Through JSON both ways, as the network would.
    final Object? sent = body == null ? null : jsonDecode(jsonEncode(body));
    calls.add((method: method, path: path, body: sent));
    DVStudioReply reply(int status, Object? json) =>
        DVStudioReply(status, jsonDecode(jsonEncode(json)));
    if (method == 'GET' && path == 'api/models') {
      return reply(200, <String, Object?>{
        'models': <Object?>[
          <String, Object?>{
            'model': 'User',
            'key': 'slug',
            'versioned': true,
            'fields': <Object?>[
              <String, Object?>{'name': 'slug', 'type': 'String'},
              <String, Object?>{'name': 'name', 'type': 'String'},
              <String, Object?>{'name': 'age', 'type': 'int?'},
              <String, Object?>{'name': 'published', 'type': 'bool'},
              <String, Object?>{
                'name': 'password',
                'type': 'String',
                'sensitive': true,
              },
            ],
          },
        ],
      });
    }
    if (method == 'GET' && path == 'api/models/User/records') {
      return reply(200, <String, Object?>{'records': users.values.toList()});
    }
    if (method == 'PUT' && path == 'api/models/User/records/ada') {
      final Map<String, Object?> sentBody = sent! as Map<String, Object?>;
      if (sentBody['version'] != users['ada']!['version']) {
        return reply(409, <String, Object?>{
          'error': 'conflict',
          'message': 'The record changed after it was read.',
        });
      }
      final Map<String, Object?> stored = users['ada']!;
      stored['version'] = (stored['version']! as int) + 1;
      (stored['values']! as Map<String, Object?>)
          .addAll(sentBody['values']! as Map<String, Object?>);
      return reply(200, stored);
    }
    if (method == 'GET' && path == 'api/pages') {
      return reply(200, <String, Object?>{'pages': pages.values.toList()});
    }
    if (method == 'PUT' && path == 'api/pages') {
      final Map<String, Object?> document = (sent! as Map)['document'] as Map<String, Object?>;
      pages['${document['route']}'] = <String, Object?>{
        'route': document['route'],
        'title': document['title'],
        'document': document,
      };
      return reply(200, <String, Object?>{'route': document['route']});
    }
    if (method == 'GET' && path == 'api/grants') {
      return reply(200, <String, Object?>{
        'grants': <Object?>[
          <String, Object?>{
            'userId': 'owner-1',
            'tenant': 'default',
            'grantedAt': '2026-09-17T10:00:00.000Z',
          },
        ],
      });
    }
    if (method == 'GET' && path == 'graph.json') {
      return reply(200, <String, Object?>{
        'models': <Object?>[],
        'routes': <Object?>[
          <String, Object?>{
            'path': '/menu',
            'page': 'MenuPage',
            'source': 'lib/pages/menu.page.dart',
          },
        ],
        'functions': <Object?>[
          <String, Object?>{
            'name': 'placeOrder',
            'method': 'POST',
            'path': '/orders',
            'source': 'lib/backend/orders.post.dart:3',
          },
        ],
        'jobs': <Object?>[],
      });
    }
    return reply(404, <String, Object?>{'error': 'not_found'});
  }
}

Widget _host(DVStudioClient client) => DVStudioApp(client: client);

void main() {
  late _FakeServer server;
  late DVStudioClient client;

  setUp(() {
    server = _FakeServer();
    client = DVStudioClient(server.call);
    DVPageStore.resetCache();
  });

  group('the client', () {
    test('an edit is sent with the version it was read at', () async {
      final DVStudioRecordData ada =
          (await client.records('User')).single;

      final DVStudioRecordData saved = await client
          .update('User', ada, <String, Object?>{'name': 'Ada Lovelace'});

      expect(server.calls.last.method, 'PUT');
      expect(server.calls.last.body, <String, Object?>{
        'version': 1,
        'values': <String, Object?>{'name': 'Ada Lovelace'},
      });
      expect(saved.version, 2);
      expect(saved.values['name'], 'Ada Lovelace');
    });

    test('a refusal is thrown with what the server said', () async {
      final DVStudioRecordData ada =
          (await client.records('User')).single;
      await client.update('User', ada, <String, Object?>{'name': 'First'});

      await expectLater(
        client.update('User', ada, <String, Object?>{'name': 'Stale'}),
        throwsA(isA<DVStudioRemoteError>()
            .having((DVStudioRemoteError e) => e.status, 'status', 409)
            .having((DVStudioRemoteError e) => e.message, 'message',
                contains('changed'))),
      );
    });

    test('the page store publishes to the server, not DV.Database', () async {
      final DVStudioRemotePageStore store = DVStudioRemotePageStore(client);
      final DVPageDocument document =
          DVPageDocument(route: '/about', title: 'About');

      await store.save(document);

      expect(server.pages.keys, <String>['/about']);
      expect(await store.routes(), <String>['/about']);
      expect((await store.load('/about'))?.title, 'About');
    });
  });

  group('the app', () {
    testWidgets('opens on the page builder, with the server sections beside it',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(client));
      await tester.pumpAndSettle();

      for (final String section in <String>[
        'Pages',
        'Models',
        'Routes',
        'Functions',
        'Jobs',
        'Access',
      ]) {
        expect(find.text(section), findsWidgets, reason: section);
      }
      expect(server.calls.map((_Call c) => c.path), contains('api/pages'));
    });

    testWidgets('a model shows its records, with no sensitive column',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(client));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-section-models')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('dv-studio-model-User')),
          findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
      expect(find.text('password'), findsNothing);
    });

    testWidgets('a record opens in a form, and saving sends what changed',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(client));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-section-models')));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-record-ada')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dv-studio-field-name')),
          matching: find.byType(EditableText),
        ),
        'Ada Lovelace',
      );
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-record-save')));
      await tester.pumpAndSettle();

      final _Call put =
          server.calls.lastWhere((_Call c) => c.method == 'PUT');
      expect(put.path, 'api/models/User/records/ada');
      expect(put.body, <String, Object?>{
        'version': 1,
        'values': <String, Object?>{'name': 'Ada Lovelace'},
      });
      expect(find.text('Ada Lovelace'), findsWidgets);
    });

    testWidgets('routes and functions come from the build\'s manifest',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(client));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-section-routes')));
      await tester.pumpAndSettle();
      expect(find.text('/menu'), findsOneWidget);
      expect(find.text('lib/pages/menu.page.dart'), findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-section-functions')));
      await tester.pumpAndSettle();
      expect(find.text('placeOrder'), findsOneWidget);
    });

    testWidgets('access lists who may open Studio',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(client));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-section-access')));
      await tester.pumpAndSettle();

      expect(find.text('owner-1'), findsOneWidget);
    });
  });
}
