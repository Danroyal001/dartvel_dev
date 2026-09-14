// `dartvel inspect adoption`: what is Dartvel-managed and what is not.
//
// Adoption says this exists to make stopping legitimate -- a team that adopts
// routing and models and never adopts the rest has a normal Flutter
// application for the other half. That only works if the count of the other
// half is honest: a report that shows zero unmanaged routes because it could
// not read a path tells a team they have finished when they have not.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/adoption/adoption_inventory.dart';
import 'package:dartvel_cli/src/commands/inspect_command.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Map<String, String> _project = <String, String>{
  'pubspec.yaml': '''
name: halfway
environment:
  sdk: ^3.12.0
dartvel:
  pagesDir: lib/pages
''',
  // Managed: a page, which is a route and a screen.
  'lib/pages/users.dart': '''
import 'package:flutter/material.dart';

@DVPage(title: 'Users')
Widget _usersPage(BuildContext context) => const Scaffold();
''',
  // Not managed: the host router, one readable path and one that is not.
  'lib/router.dart': r'''
import 'package:go_router/go_router.dart';

const String kSettings = '/settings';
final router = GoRouter(routes: [
  GoRoute(path: '/legacy', builder: (c, s) => const LegacyScreen()),
  GoRoute(path: kSettings, builder: (c, s) => const SettingsScreen()),
]);
''',
  // Managed model.
  'lib/models/user.dart': '''
@DVModel()
class _User {
  final String name;
  const _User(this.name);
}
''',
  // Not managed: a freezed class and a drift table.
  'lib/models/address.dart': r'''
@freezed
class Address with _$Address {
  const factory Address({required String line1}) = _Address;
}
''',
  'lib/db/tables.dart': '''
import 'package:drift/drift.dart';

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
}
''',
  // Not managed: a screen outside the pages directory.
  'lib/screens/settings_screen.dart': '''
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}
''',
  // Not a screen: the Scaffold is in a comment.
  'lib/widgets/badge.dart': '''
import 'package:flutter/widgets.dart';

// Used inside a Scaffold( on the settings screen.
class Badge extends StatelessWidget {
  const Badge({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
  // Managed function.
  'lib/backend/functions/health.get.dart': '''
@DVBackendFunction()
Future<String> _health() async => 'ok';
''',
  // Not managed: a shelf_router handler.
  'lib/server.dart': '''
import 'package:shelf_router/shelf_router.dart';

Router api() => Router()..get('/ping', (request) => Response.ok('pong'));
''',
};

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_inspect_adoption_');
    _project.forEach((String rel, String content) {
      File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<DVAdoptionInventory> inventory() async => dvAdoptionInventory(
        root: root.path,
        pagesDir: 'lib/pages',
        graph: await DartvelProjectGraph.build(root: root.path, pkgName: 'halfway'),
      );

  test('routes: generated pages against the host router, unreadable apart',
      () async {
    final DVAdoptionInventory inv = await inventory();

    expect(inv.routes.managed.map((DVAdoptionItem i) => i.name), <String>['/users']);
    expect(inv.routes.unmanaged.map((DVAdoptionItem i) => i.name), <String>['/legacy']);
    expect(inv.routes.unmeasured, hasLength(1),
        reason: 'a path read from a constant is not a route that was counted, '
            'and not one that is absent either');
  });

  test('models: annotated against serializer classes and database tables',
      () async {
    final DVAdoptionInventory inv = await inventory();

    expect(inv.models.managed.map((DVAdoptionItem i) => i.name), <String>['User']);
    expect(inv.models.unmanaged.map((DVAdoptionItem i) => i.name),
        unorderedEquals(<String>['Address', 'Todos']));
  });

  test('screens: pages against files that build a Scaffold elsewhere',
      () async {
    final DVAdoptionInventory inv = await inventory();

    expect(inv.screens.managed, hasLength(1));
    expect(inv.screens.unmanaged.map((DVAdoptionItem i) => i.source),
        <String>['lib/screens/settings_screen.dart:3']);
  });

  test('functions: backend functions against shelf_router handlers', () async {
    final DVAdoptionInventory inv = await inventory();

    expect(inv.functions.managed, hasLength(1));
    expect(inv.functions.unmanaged.map((DVAdoptionItem i) => i.name),
        <String>['GET /ping']);
  });

  group('the command', () {
    Future<String> run(List<String> args) async {
      final Directory previous = Directory.current;
      Directory.current = root;
      final StringBuffer out = StringBuffer();
      try {
        await runZoned(
          () => (CommandRunner<void>('dartvel', 't')..addCommand(InspectCommand()))
              .run(<String>['inspect', 'adoption', ...args]),
          zoneSpecification: ZoneSpecification(
            print: (Zone _, ZoneDelegate __, Zone ___, String line) =>
                out.writeln(line),
          ),
        );
      } finally {
        Directory.current = previous;
      }
      return out.toString();
    }

    test('prints both halves and says what went unmeasured', () async {
      final String out = await run(const <String>[]);

      expect(out, contains('routes'));
      expect(out, contains('/legacy'));
      expect(out, contains('lib/router.dart:6'));
      expect(out, contains('not measured'));
    });

    test('--json is the same inventory', () async {
      final Map<String, Object?> json =
          jsonDecode(await run(const <String>['--json'])) as Map<String, Object?>;

      final Map<String, Object?> routes = json['routes']! as Map<String, Object?>;
      expect((routes['managed']! as List<Object?>).length, 1);
      expect((routes['unmanaged']! as List<Object?>).length, 1);
      expect((routes['unmeasured']! as List<Object?>).length, 1);
    });
  });
}
