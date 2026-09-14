// The two build errors Adoption defines for a project that already had a
// router and a serializer before it had Dartvel.
//
// DV-ADOPT-002: a route defined by both the host router and a generated page.
// Not a precedence rule, because whichever one loses is a page that stops
// being reachable and nobody notices.
//
// DV-ADOPT-003: an annotated model that already has a generated serializer.
// Two `toJson`s for one type is a bug that shows up as data rather than as a
// stack trace. It was worse than that here: the model generator's pattern
// steps over `@pragma` and nothing else, so `@DVModel()` over `@freezed`
// generated no model at all and said nothing.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:dartvel_cli/src/adoption/adoption_build_checks.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';

@DVPage(title: 'Page')
Widget _page(BuildContext context) => const SizedBox();
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_adopt_build_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String rel, String content) {
    File(p.join(root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  DVAdoptionBuildReport check() =>
      dvAdoptionBuildCheck(root: root.path, pagesDir: 'lib/pages');

  group('DV-ADOPT-002: a route both routers define', () {
    test('names both sources', () {
      write('lib/pages/users.dart', _page);
      write('lib/router.dart', '''
import 'package:go_router/go_router.dart';

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home()),
  GoRoute(path: '/users', builder: (c, s) => const Users()),
]);
''');

      final DVAdoptionBuildReport report = check();

      expect(report.errors, hasLength(1));
      final String error = report.errors.single;
      expect(error, contains('DV-ADOPT-002'));
      expect(error, contains('/users'));
      expect(error, contains('lib/router.dart:5'));
      expect(error, contains('lib/pages/users.dart'));
    });

    test('a nested route is joined to its parent', () {
      write('lib/pages/account/settings.dart', _page);
      write('lib/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(
    path: '/account',
    builder: (c, s) => const Account(),
    routes: [
      GoRoute(path: 'settings', builder: (c, s) => const Settings()),
    ],
  ),
]);
''');

      expect(check().errors.single, contains('/account/settings'));
    });

    test('a shell route does not prefix its children', () {
      write('lib/pages/inbox.dart', _page);
      write('lib/router.dart', '''
final router = GoRouter(routes: [
  ShellRoute(
    builder: (c, s, child) => Frame(child: child),
    routes: [GoRoute(path: '/inbox', builder: (c, s) => const Inbox())],
  ),
]);
''');

      expect(check().errors.single, contains('/inbox'));
    });

    test('parameter names do not hide the same route', () {
      write('lib/pages/users/[id].dart', _page);
      write('lib/router.dart', '''
final r = GoRouter(routes: [GoRoute(path: "/users/:userId/", builder: b)]);
''');

      expect(check().errors, hasLength(1));
    });

    test('routes that do not overlap are not an error', () {
      write('lib/pages/users.dart', _page);
      write('lib/router.dart', '''
final r = GoRouter(routes: [GoRoute(path: '/legacy', builder: b)]);
''');

      final DVAdoptionBuildReport report = check();
      expect(report.errors, isEmpty);
      expect(report.hostRoutes.map((DVHostRoute r) => r.path), <String>['/legacy']);
    });

    test('a commented-out route is not a route', () {
      write('lib/pages/users.dart', _page);
      write('lib/router.dart', '''
final r = GoRouter(routes: [
  // GoRoute(path: '/users', builder: b),
  /* GoRoute(path: '/users', builder: b), */
  GoRoute(path: '/other', builder: b),
]);
''');

      expect(check().errors, isEmpty);
    });

    test('a path that is not a literal is reported unchecked, not passed', () {
      write('lib/pages/users.dart', _page);
      write('lib/router.dart', r'''
const String usersPath = '/users';
final r = GoRouter(routes: [
  GoRoute(path: usersPath, builder: b),
  GoRoute(path: '/u/$section', builder: b),
]);
''');

      final DVAdoptionBuildReport report = check();
      expect(report.errors, isEmpty);
      expect(report.unchecked, hasLength(2));
      expect(report.unchecked.first, contains('lib/router.dart:3'));
    });

    test('the generated client is not the host router', () {
      write('lib/pages/users.dart', _page);
      write('lib/dartvel_client/router.g.dart', '''
final r = GoRouter(routes: [GoRoute(path: '/users', builder: b)]);
''');

      expect(check().errors, isEmpty);
    });

    test('a page file with no @DVPage is not a generated route', () {
      write('lib/pages/users.dart', 'class UsersScreen {}\n');
      write('lib/router.dart', '''
final r = GoRouter(routes: [GoRoute(path: '/users', builder: b)]);
''');

      expect(check().errors, isEmpty);
    });
  });

  group('DV-ADOPT-003: a model that already has a serializer', () {
    test('@freezed under @DVModel', () {
      write('lib/models/user.dart', r'''
@DVModel()
@freezed
class _User with _$User {
  const factory _User({required String name}) = __User;
}
''');

      final List<String> errors = check().errors;
      expect(errors, hasLength(1));
      expect(errors.single, contains('DV-ADOPT-003'));
      expect(errors.single, contains('lib/models/user.dart:1'));
      expect(errors.single, contains('freezed'));
    });

    test('@JsonSerializable above @DVModel', () {
      write('lib/models/user.dart', r'''
@JsonSerializable()
@DVModel(table: 'users')
class _User {
  final String name;
  const _User(this.name);
}
''');

      expect(check().errors.single, contains('DV-ADOPT-003'));
    });

    test('a hand-wired generated fromJson counts', () {
      write('lib/models/user.dart', r'''
part 'user.g.dart';

@DVModel()
class _User {
  final String name;
  const _User(this.name);
  factory _User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);
}
''');

      expect(check().errors.single, contains('DV-ADOPT-003'));
    });

    test('a plain model is fine, beside a freezed class in the same file', () {
      write('lib/models/user.dart', r'''
@DVModel()
class _User {
  final String name;
  const _User(this.name);
}

@freezed
class Address with _$Address {
  const factory Address({required String line1}) = _Address;
  factory Address.fromJson(Map<String, Object?> json) => _$AddressFromJson(json);
}
''');

      expect(check().errors, isEmpty);
    });

    test('a doc comment mentioning freezed is not a serializer', () {
      write('lib/models/user.dart', r'''
/// Was @freezed until the Dartvel migration.
@DVModel()
class _User {
  final String name;
  const _User(this.name);
}
''');

      expect(check().errors, isEmpty);
    });
  });

  group('generation', () {
    test('stops before writing anything when a check fails', () async {
      write('pubspec.yaml', '''
name: adopt_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
  prodBackendHost: https://example.com
''');
      write('lib/pages/users.dart', _page);
      write('lib/router.dart', '''
final r = GoRouter(routes: [GoRoute(path: '/users', builder: b)]);
''');

      await expectLater(
        routes.generate(root_: root.path),
        throwsA(predicate<Object>(
            (Object e) => e.toString().contains('DV-ADOPT-002'))),
      );
      expect(Directory(p.join(root.path, 'lib', 'dartvel_client')).existsSync(),
          isFalse,
          reason: 'a build that is going to fail must not leave half a client');
    });
  });
}
