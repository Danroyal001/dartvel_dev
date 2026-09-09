// dartvel.tenancy in pubspec.yaml, reaching the runtime.
//
// Everything tenancy needed to be told was settable only from Dart that no
// generated entrypoint runs. DVMiddlewareSettings.requireTenant gated a
// refusal and nothing anywhere set it to true. DVTenants.configure chose
// between the three isolation strategies and no project had a place to call
// it, so schema-per-tenant and database-per-tenant -- the two an application
// picks precisely to keep tenants apart -- could not be selected at all, and
// every deployment ran the shared-database default whether it wanted it or
// not.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the declared isolation and source reach the runtime', () async {
    final Directory root = await _project('''
name: tenancy_app
dartvel:
  tenancy:
    isolation: schema-per-tenant
    source: header
    header: X-Account
    ignoredHostLabels: [www, app]
''');
    try {
      await _generate(root);

      final String prelude = _prelude(root);
      expect(prelude, contains('core.DVTenantIsolation.schemaPerTenant'));
      expect(prelude, contains('core.DVTenantSource.header'));
      // Lower-cased: header names are case-insensitive on the wire and the
      // resolver looks the name up in a lower-cased map, so X-Account
      // written through would never match a request.
      expect(prelude, contains("headerName: 'x-account'"));
      expect(prelude, contains("'www', 'app'"));

      // And the file it is emitted into still parses. Configuration written
      // as a broken literal is a generated file that does not compile, with
      // an error naming a line nobody wrote.
      final ProcessResult parsed = Process.runSync(
        Platform.resolvedExecutable,
        <String>[
          'format',
          '--output=none',
          p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
        ],
      );
      expect(parsed.exitCode, 0, reason: '${parsed.stderr}');
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('require refuses a request that names no tenant', () async {
    final Directory root = await _project('''
name: tenancy_app
dartvel:
  tenancy:
    require: true
''');
    try {
      await _generate(root);

      expect(
        _prelude(root),
        contains('core.DVMiddlewareSettings.requireTenant = true'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a project that declares no tenancy is left alone', () async {
    // A single-tenant application should not have configuration emitted at
    // it, and the shared-database default is what it already runs.
    final Directory root = await _project('name: plain_app\n');
    try {
      await _generate(root);

      expect(_prelude(root), isNot(contains('DVTenants().configure')));
      expect(
        _prelude(root),
        isNot(contains('DVMiddlewareSettings.requireTenant')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('an isolation nobody implements fails the build and says what is',
      () async {
    // The failure this prevents is the quiet one. A misspelling dropped on
    // the floor leaves the application on shared-database while its pubspec
    // says schema-per-tenant, and every query returns rows, so nothing about
    // running it looks wrong.
    final Directory root = await _project('''
name: tenancy_app
dartvel:
  tenancy:
    isolation: schema-per-tenat
''');
    try {
      await expectLater(
        () => _generate(root),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('schema-per-tenat'),
              contains('schema-per-tenant'),
              contains('database-per-tenant'),
            ),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a source nobody implements fails the build too', () async {
    final Directory root = await _project('''
name: tenancy_app
dartvel:
  tenancy:
    source: subdomian
''');
    try {
      await expectLater(
        () => _generate(root),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('subdomian'), contains('subdomain')),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

String _prelude(Directory root) =>
    File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
        .readAsStringSync();

Future<Directory> _project(String pubspec) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_tenancy_config_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
      .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> ping() async => <String, bool>{'ok': true};
''');
  return root;
}

Future<void> _generate(Directory root) {
  return BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'tenancy_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
}
