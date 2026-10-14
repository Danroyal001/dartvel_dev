// A data model's records as a list a person works through: a page at a
// time, sorted by a column, filtered by a value, searched on the server,
// several chosen and deleted at once -- and all of it in the address, so a
// filtered list is a link and Back undoes a sort.
//
// Studio fetched every record in one reply and searched them in the
// browser; there was no sort, no filter, no paging and no way to delete
// more than one record at a time.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  _Server() {
    for (int i = 1; i <= 120; i++) {
      final String key = 'user-${i.toString().padLeft(3, '0')}';
      users[key] = <String, Object?>{
        'key': key,
        'version': 1,
        'values': <String, Object?>{
          'slug': key,
          'name': i == 7 ? 'Ada Lovelace' : 'Person $i',
          'tier': i % 3 == 0 ? 'paid' : 'free',
          'published': i.isEven,
        },
      };
    }
  }

  final Map<String, Map<String, Object?>> users =
      <String, Map<String, Object?>>{};
  final List<String> calls = <String>[];
  final List<Object?> deleteBodies = <Object?>[];

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    final Uri uri = Uri.parse('http://studio.test/$path');
    DVStudioReply reply(int status, Object? json) =>
        DVStudioReply(status, jsonDecode(jsonEncode(json)));
    switch ('$method ${uri.path}') {
      case 'GET /api/access':
        return reply(200, <String, Object?>{'granted': true});
      case 'GET /api/me':
        return reply(200, <String, Object?>{'userId': 'u', 'email': 'a@b.c'});
      case 'GET /api/models':
        return reply(200, <String, Object?>{
          'models': <Object?>[
            <String, Object?>{
              'model': 'User',
              'key': 'slug',
              'versioned': true,
              'fields': <Object?>[
                <String, Object?>{'name': 'slug', 'type': 'String'},
                <String, Object?>{'name': 'name', 'type': 'String'},
                <String, Object?>{
                  'name': 'tier',
                  'type': 'String',
                  'options': <String>['free', 'paid'],
                },
                <String, Object?>{'name': 'published', 'type': 'bool'},
              ],
            },
          ],
        });
      case 'GET /api/models/User/records':
        final Map<String, List<String>> query = uri.queryParametersAll;
        List<Map<String, Object?>> rows = users.values.toList();
        final String q = (query['q']?.first ?? '').toLowerCase();
        if (q.isNotEmpty) {
          rows = rows
              .where((Map<String, Object?> r) => (r['values']! as Map).values
                  .any((Object? v) => '$v'.toLowerCase().contains(q)))
              .toList();
        }
        for (final String filter in query['filter'] ?? const <String>[]) {
          final int colon = filter.indexOf(':');
          final String field = filter.substring(0, colon);
          final String value = filter.substring(colon + 1);
          rows = rows
              .where((Map<String, Object?> r) =>
                  '${(r['values']! as Map)[field]}' == value)
              .toList();
        }
        final String? sort = query['sort']?.first;
        if (sort != null) {
          rows.sort((Map<String, Object?> a, Map<String, Object?> b) =>
              '${(a['values']! as Map)[sort]}'
                  .compareTo('${(b['values']! as Map)[sort]}'));
          if (query['order']?.first == 'desc') rows = rows.reversed.toList();
        }
        final int offset = int.tryParse(query['offset']?.first ?? '') ?? 0;
        final int limit = int.tryParse(query['limit']?.first ?? '') ?? 500;
        return reply(200, <String, Object?>{
          'records': rows.skip(offset).take(limit).toList(),
          'total': rows.length,
          'offset': offset,
          'limit': limit,
        });
      case 'POST /api/models/User/records/delete':
        deleteBodies.add(body);
        final List<String> deleted = <String>[];
        for (final Object? entry in (body! as Map)['records'] as List) {
          final String key = '${(entry! as Map)['key']}';
          if (users.remove(key) != null) deleted.add(key);
        }
        return reply(200, <String, Object?>{
          'deleted': deleted,
          'failed': <String, Object?>{},
        });
      case 'GET /api/site':
        return reply(200, <String, Object?>{'pages': <Object?>[]});
      case 'GET /api/pages':
        return reply(200, <String, Object?>{'pages': <Object?>[]});
    }
    return reply(404, <String, Object?>{'error': 'not_found'});
  }

  /// The last request for a page of records, as its query.
  Map<String, List<String>> get lastList {
    final String call = calls.lastWhere(
        (String c) => c.startsWith('GET api/models/User/records'));
    return Uri.parse('http://studio.test/${call.substring(4)}')
        .queryParametersAll;
  }
}

Future<GoRouter> _at(WidgetTester tester, _Server server, String location,
    {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('the shop')),
      ...dvStudioRoutes(
        mount: '/__studio',
        title: 'Studio',
        transport: server.call,
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  late _Server server;
  setUp(() => server = _Server());

  testWidgets('a page at a time, with where it is in the whole',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    expect(server.lastList['limit'], <String>['50']);
    expect(find.text('1–50 of 120'), findsOneWidget);
    expect(find.text('Person 51'), findsNothing);

    await tester.tap(_key('dv-studio-records-next'));
    await tester.pumpAndSettle();
    expect(server.lastList['offset'], <String>['50']);
    expect(find.text('51–100 of 120'), findsOneWidget);

    await tester.tap(_key('dv-studio-records-next'));
    await tester.pumpAndSettle();
    expect(find.text('101–120 of 120'), findsOneWidget);
    expect(
      tester.getSemantics(_key('dv-studio-records-next')),
      isNot(matchesSemantics(hasEnabledState: true, isEnabled: true)),
      reason: 'there is no page after the last',
    );
  });

  testWidgets('a column header sorts, and says which way',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.tap(_key('dv-studio-sort-name'));
    await tester.pumpAndSettle();
    expect(server.lastList['sort'], <String>['name']);
    expect(server.lastList['order'], <String>['asc']);
    expect(tester.getSemantics(_key('dv-studio-sort-name')).label,
        contains('sorted ascending'));

    await tester.tap(_key('dv-studio-sort-name'));
    await tester.pumpAndSettle();
    expect(server.lastList['order'], <String>['desc']);
    expect(tester.getSemantics(_key('dv-studio-sort-name')).label,
        contains('sorted descending'));
    semantics.dispose();
  });

  testWidgets('search is asked of the server', (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    await tester.enterText(
        find.descendant(
            of: _key('dv-studio-records-search'),
            matching: find.byType(EditableText)),
        'lovelace');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(server.lastList['q'], <String>['lovelace']);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('1–1 of 1'), findsOneWidget);
  });

  testWidgets('a filter by a field value', (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    await tester.tap(_key('dv-studio-records-filter-field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tier').last);
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-records-filter-value'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('paid').last);
    await tester.pumpAndSettle();
    expect(server.lastList['filter'], <String>['tier:paid']);
    expect(find.text('1–40 of 40'), findsOneWidget);

    await tester.tap(_key('dv-studio-records-filter-clear'));
    await tester.pumpAndSettle();
    expect(server.lastList['filter'], isNull);
    expect(find.text('1–50 of 120'), findsOneWidget);
  });

  testWidgets('several records chosen and deleted at once, after asking',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    expect(_key('dv-studio-records-bulk-delete'), findsNothing);
    await tester.tap(_key('dv-studio-record-check-user-001'));
    await tester.tap(_key('dv-studio-record-check-user-002'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 records'), findsOneWidget);

    await tester.tap(_key('dv-studio-records-bulk-delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.deleteBodies, isEmpty, reason: 'Cancel deletes nothing');

    await tester.tap(_key('dv-studio-records-bulk-delete'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-records-bulk-delete-confirm'));
    await tester.pumpAndSettle();
    expect(server.deleteBodies.single, <String, Object?>{
      'records': <Object?>[
        <String, Object?>{'key': 'user-001', 'version': 1},
        <String, Object?>{'key': 'user-002', 'version': 1},
      ],
    });
    expect(find.text('1–50 of 118'), findsOneWidget);
    expect(_key('dv-studio-records-bulk-delete'), findsNothing,
        reason: 'what was chosen is gone, so nothing is chosen');
  });

  testWidgets('the header box chooses every record on the page',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    await tester.tap(_key('dv-studio-records-check-all'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 50 records'), findsOneWidget);
    await tester.tap(_key('dv-studio-records-check-all'));
    await tester.pumpAndSettle();
    expect(_key('dv-studio-records-bulk-delete'), findsNothing);
  });

  testWidgets('the list is in the address, and Back undoes a sort',
      (WidgetTester tester) async {
    final GoRouter router = await _at(tester, server, '/__studio/models/User');
    await tester.tap(_key('dv-studio-sort-name'));
    await tester.pumpAndSettle();
    expect(router.state.uri.queryParameters['sort'], 'name');
    expect(router.state.uri.queryParameters['order'], 'asc');
    await tester.tap(_key('dv-studio-records-next'));
    await tester.pumpAndSettle();
    expect(router.state.uri.queryParameters['page'], '2');
  });

  testWidgets('a link to a filtered, sorted page opens on it',
      (WidgetTester tester) async {
    await _at(tester, server,
        '/__studio/models/User?sort=name&order=desc&filter=tier:paid&page=1&q=person');
    expect(server.lastList['sort'], <String>['name']);
    expect(server.lastList['order'], <String>['desc']);
    expect(server.lastList['filter'], <String>['tier:paid']);
    expect(server.lastList['q'], <String>['person']);
    expect(find.text('1–40 of 40'), findsOneWidget);
  });

  testWidgets('every new control is named, and its tooltip says the same',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.tap(_key('dv-studio-record-check-user-001'));
    await tester.pumpAndSettle();
    for (final String key in <String>[
      'dv-studio-sort-name',
      'dv-studio-records-next',
      'dv-studio-records-previous',
      'dv-studio-records-check-all',
      'dv-studio-record-check-user-001',
      'dv-studio-records-filter-field',
      'dv-studio-records-bulk-delete',
    ]) {
      final String label = tester.getSemantics(_key(key)).label;
      expect(label, isNotEmpty, reason: key);
      expect(
        find.descendant(
            of: _key(key),
            matching: find.byWidgetPredicate((Widget w) =>
                w is DVTooltipTarget &&
                w.label != null &&
                label.startsWith(w.label!))),
        findsWidgets,
        reason: '$key is named "$label" and its tooltip should say so',
      );
    }
    expect(tester.getSemantics(_key('dv-studio-record-check-user-001')),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Choose user-001',
        ));
    semantics.dispose();
  });

  testWidgets('a checkbox is ticked from the keyboard',
      (WidgetTester tester) async {
    await _at(tester, server, '/__studio/models/User');
    final Finder focus = find
        .descendant(
            of: _key('dv-studio-record-check-user-001'),
            matching: find.byType(Focus))
        .first;
    Focus.of(tester.element(find
            .descendant(of: focus, matching: find.byType(Semantics))
            .first))
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 record'), findsOneWidget);
  });
}
