// Adopting Dartvel keeps the router an app already has: go_router,
// auto_route or Flutter's own Navigator. Any other router is named, with
// the three Dartvel mounts into.
import 'dart:io';

import 'package:dartvel_cli/src/adoption/host_router.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'module_backend_registration_test.dart' show generate, read, workspace;

void main() {
  group('which router the app uses', () {
    test('auto_route, go_router, or Flutter\'s Navigator when neither', () {
      expect(dvDetectHostRouter(<Object?, Object?>{
        'dependencies': <Object?, Object?>{'auto_route': '^11.0.0'},
      }).router, DVHostRouter.autoRoute);
      expect(dvDetectHostRouter(<Object?, Object?>{
        'dependencies': <Object?, Object?>{'go_router': '^14.0.0'},
      }).router, DVHostRouter.goRouter);
      expect(dvDetectHostRouter(<Object?, Object?>{
        'dependencies': <Object?, Object?>{'flutter': null},
      }).router, DVHostRouter.navigator);
    });

    test('another router is named, with the three Dartvel mounts into', () {
      final DVHostRouterDetection beamer = dvDetectHostRouter(<Object?, Object?>{
        'dependencies': <Object?, Object?>{'beamer': '^1.6.0', 'go_router': '^14.0.0'},
      });
      expect(beamer.router, isNull);
      for (final String named in <String>[
        'beamer', 'go_router', 'auto_route', 'Navigator',
        'dartvelOnGenerateRoute', 'dartvelPageFor', 'dartvelAutoRoutes',
      ]) {
        expect(beamer.message, contains(named));
      }
    });
  });

  group('the generated client', () {
    test('mounts into Navigator 1.0 and 2.0 in every project', () async {
      final Directory root = workspace();
      await generate(root);
      final String router = read(root, 'router.g.dart');
      expect(router, contains('Route<Object?>? dartvelOnGenerateRoute('));
      expect(router, contains('Page<Object?>? dartvelPageFor('));
      expect(router, isNot(contains('auto_route')));
    });

    test('and into auto_route in a project that depends on it', () async {
      final Directory root = workspace();
      final File pubspec = File(p.join(root.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(pubspec.readAsStringSync().replaceFirst(
          'name: shopfront\n',
          'name: shopfront\ndependencies:\n  auto_route: ^11.2.0\n'));
      await generate(root);
      final String router = read(root, 'router.g.dart');
      expect(router,
          contains("import 'package:auto_route/auto_route.dart' as auto_route;"));
      expect(router, contains('List<auto_route.AutoRoute> dartvelAutoRoutes('));
      expect(router, contains(r"path: '$at/*'"));
    });
  });
}
