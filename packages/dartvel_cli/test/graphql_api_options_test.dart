// dartvel.api.graphql, read by `dartvel routes`.
//
// The runtime had depth and cost budgets, an introspection policy and
// persisted-query enforcement, and the CLI read none of it from pubspec.yaml.
// So `persistedQueries: require` written down by somebody locking the
// endpoint to known documents did nothing: the generated server answered
// every ad-hoc document at the default budgets, and nothing said so.
//
// The silent failures:
//  * a misspelt key (`persistedQuery:`) dropped, leaving the default in place
//    for somebody who believes they turned enforcement on;
//  * a quoted or negative budget read as auto;
//  * the value parsed and emitted and never installed, or installed after the
//    first route could answer;
//  * the route still reading no persisted-query hash, so a hash-only request
//    ran an empty document.
import 'dart:io';

import 'package:dartvel_cli/src/build/graphql_options.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_core/dartvel.dart'
    show DVGraphQLIntrospection, DVPersistedQueryMode;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? _dv(String yaml) => (loadYaml(yaml) as YamlMap)['dartvel'];

Matcher _refusedNaming(String text) => throwsA(
      isA<FormatException>()
          .having((FormatException e) => e.message, 'message', contains(text)),
    );

void main() {
  group('what dartvel.api.graphql says', () {
    test('a project that says nothing declares nothing', () {
      expect(DVGraphQLApiOptions.parse(_dv('dartvel:\n  pagesDir: x\n')),
          isNull);
      expect(DVGraphQLApiOptions.parse(null), isNull);
    });

    test('every key reaches the runtime values it names', () {
      final DVGraphQLApiOptions options = DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql:
      maxDepth: 7
      maxCost: auto
      introspection: authenticated
      persistedQueries: require
'''))!;

      expect(options.maxDepth, 7);
      expect(options.maxCost, isNull);
      expect(options.introspection, DVGraphQLIntrospection.authenticated);
      expect(options.persistedQueries, DVPersistedQueryMode.require);
    });

    test('an empty graphql section is the specification\'s defaults', () {
      final DVGraphQLApiOptions options = DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql: {}
'''))!;

      expect(options.maxDepth, isNull);
      expect(options.maxCost, isNull);
      expect(options.introspection, DVGraphQLIntrospection.development);
      expect(options.persistedQueries, DVPersistedQueryMode.off);
    });

    test('a key nothing reads stops the build', () {
      expect(
        () => DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql:
      persistedQuery: require
''')),
        _refusedNaming('dartvel.api.graphql.persistedQuery'),
      );
      expect(
        () => DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    grapql:
      maxDepth: 3
''')),
        _refusedNaming('dartvel.api.grapql'),
      );
    });

    test('a budget that is not auto or a positive whole number stops the build',
        () {
      for (final String value in <String>['"7"', '0', '-1', '2.5', 'lots']) {
        expect(
          () => DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql:
      maxCost: $value
''')),
          _refusedNaming('dartvel.api.graphql.maxCost'),
          reason: value,
        );
      }
    });

    test('an introspection or persisted-query mode the runtime lacks stops it',
        () {
      expect(
        () => DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql:
      introspection: always
''')),
        _refusedNaming('dartvel.api.graphql.introspection'),
      );
      expect(
        () => DVGraphQLApiOptions.parse(_dv('''
dartvel:
  api:
    graphql:
      persistedQueries: true
''')),
        _refusedNaming('dartvel.api.graphql.persistedQueries'),
      );
    });
  });

  group('what the generated backend serves GraphQL with', () {
    Future<String> routesFor(String pubspec) async {
      final Directory root =
          await Directory.systemTemp.createTemp('dartvel_graphql_options_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> handler() async => 'pong';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'graphql_options_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      return File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
    }

    test('the declared budgets and mode are installed before any route',
        () async {
      final String routes = await routesFor('''
name: graphql_options_app
dartvel:
  api:
    graphql:
      maxDepth: 7
      introspection: never
      persistedQueries: require
''');

      final int builder = routes.indexOf('dv.Router buildBackendRouter() {');
      final int limits = routes.indexOf(
          'core.DVGraphQL.limits = core.DVGraphQLLimits(maxDepth: 7, '
          'maxCost: null, defaultPageSize: core.DVGraphQL.limits.defaultPageSize, '
          'introspection: core.DVGraphQLIntrospection.never);');
      final int mode = routes.indexOf(
          'core.DVGraphQL.persistedQueries = core.DVGraphQL.persistedQueries'
          '.withMode(core.DVPersistedQueryMode.require);');
      final int firstRoute = routes.indexOf('router.', builder);

      expect(limits, greaterThan(builder));
      expect(mode, greaterThan(builder));
      expect(limits, lessThan(firstRoute));
      expect(mode, lessThan(firstRoute));
    });

    test('a project that declares nothing leaves the runtime\'s own settings',
        () async {
      final String routes = await routesFor('name: graphql_options_app\n');

      expect(routes, isNot(contains('core.DVGraphQL.limits =')));
      expect(routes, isNot(contains('core.DVGraphQL.persistedQueries =')));
    });

    test('both GraphQL routes hand the whole body over, hash included',
        () async {
      final String routes = await routesFor('name: graphql_options_app\n');

      expect(routes, contains('core.DVGraphQL.executeRequest('));
      expect(routes, contains('core.DVGraphQL.subscribeRequest('));
      // The body is no longer taken apart in the route, which is where the
      // hash was dropped.
      expect(routes, isNot(contains("map['query']")));
    });

    test('a value the runtime cannot use stops the generator', () async {
      await expectLater(
        routesFor('''
name: graphql_options_app
dartvel:
  api:
    graphql:
      maxDepth: deep
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });
  test('dartvel routes stops on it before writing anything', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('dartvel_graphql_routes_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: graphql_routes_probe
publish_to: none
environment:
  sdk: ^3.13.0
dartvel:
  api:
    graphql:
      persistedQuery: require
''');

    await expectLater(
      routes.generate(root_: dir.path),
      throwsA(isA<FormatException>().having((FormatException e) => e.message,
          'message', contains('dartvel.api.graphql.persistedQuery'))),
    );
    expect(
      Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
      isFalse,
    );
  });
}
