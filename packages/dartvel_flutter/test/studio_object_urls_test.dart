// Every Studio screen and the thing open in it has an address of its own:
// a tab of Settings, the Roles of the team, a form's submissions, a menu.
// Back walks back through them, a reload lands on the same one, and a link
// to one opens it -- which a tab kept only in a widget's state cannot do.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  final List<String> calls = <String>[];

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    final Uri uri = Uri.parse('http://studio.test/$path');
    DVStudioReply reply(Object? json) =>
        DVStudioReply(200, jsonDecode(jsonEncode(json)));
    switch ('$method ${uri.path}') {
      case 'GET /api/access':
        return reply(<String, Object?>{'granted': true});
      case 'GET /api/me':
        return reply(<String, Object?>{'userId': 'u1', 'email': 'a@b.c'});
      case 'GET /api/team':
        return reply(<String, Object?>{
          'grants': <Object?>[
            <String, Object?>{'userId': 'u1', 'email': 'a@b.c', 'tenant': 'default', 'role': 'admin'},
          ],
          'roles': <Object?>[
            <String, Object?>{'id': 'admin', 'name': 'Administrator', 'permissions': <String>['team:write'], 'isBuiltIn': true},
            <String, Object?>{'id': 'viewer', 'name': 'Viewer', 'permissions': <String>[], 'isBuiltIn': true},
          ],
          'entitlements': <String, Object?>{'rolesEnabled': true, 'customRolesEnabled': true},
        });
      case 'GET /api/settings':
        return reply(<String, Object?>{'siteTitle': 'Harbour', 'maintenanceMode': false});
      case 'GET /api/forms':
        return reply(<String, Object?>{
          'forms': <Object?>[
            <String, Object?>{'id': 'enquiry', 'name': 'Enquiry', 'fields': <Object?>[]},
            <String, Object?>{'id': 'booking', 'name': 'Booking', 'fields': <Object?>[]},
          ],
        });
      case 'GET /api/forms/submissions':
        return reply(<String, Object?>{'submissions': <Object?>[], 'total': 0, 'unread': 0});
      case 'GET /api/menus':
        return reply(<String, Object?>{
          'menus': <Object?>[
            <String, Object?>{'id': 'main', 'name': 'Main', 'location': 'header', 'items': <Object?>[]},
            <String, Object?>{'id': 'foot', 'name': 'Foot', 'location': 'footer', 'items': <Object?>[]},
          ],
          'locations': <String>['header', 'footer'],
        });
    }
    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

Future<GoRouter> _at(WidgetTester tester, String location) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final _Server server = _Server();
  final GoRouter router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('the site')),
      ...dvStudioRoutes(mount: '/__studio', transport: server.call),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// Whether the tab at [key] says, to a screen reader, that it is the one open.
bool _selected(WidgetTester tester, String key) =>
    tester.widget<Semantics>(_key(key)).properties.selected ?? false;

void main() {
  testWidgets('a Settings tab is an address', (WidgetTester tester) async {
    final GoRouter router = await _at(tester, '/__studio/settings/seo');
    expect(_selected(tester, 'dv-studio-settings-tab-seo'), isTrue);

    await tester.tap(_key('dv-studio-settings-tab-maintenance'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/__studio/settings/maintenance');
    expect(_selected(tester, 'dv-studio-settings-tab-maintenance'), isTrue);
    expect(find.byTooltip('Maintenance Mode'), findsOneWidget);
  });

  testWidgets('the team\'s roles are an address', (WidgetTester tester) async {
    final GoRouter router = await _at(tester, '/__studio/access/roles');
    expect(_key('dv-studio-role-card-admin'), findsOneWidget);

    await tester.tap(_key('dv-studio-tab-teammates'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/__studio/access');
  });

  testWidgets('a form\'s submissions are an address', (WidgetTester tester) async {
    final GoRouter router =
        await _at(tester, '/__studio/forms/booking/submissions');
    // The inbox, for that form: not the first form's settings.
    expect(_key('dv-studio-forms-inbox'), findsOneWidget);
    expect(router.state.uri.path, '/__studio/forms/booking/submissions');
  });

  testWidgets('Back moves between menus', (WidgetTester tester) async {
    final GoRouter router = await _at(tester, '/__studio/menus/main');
    router.go('/__studio/menus/foot');
    await tester.pumpAndSettle();
    expect(find.text('Foot'), findsWidgets);
    expect(tester.widget<DVStudioMenusSection>(find.byType(DVStudioMenusSection)).selectedMenuId, 'foot');
  });
}
