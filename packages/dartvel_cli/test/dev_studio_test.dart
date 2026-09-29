// What a development server serves Studio from: the models the generator
// described and the project's own database.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/dev_studio.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart'
    show dvDevBackendEnvironment, dvDevServerSource;
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_dev_studio_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('the models are the ones the generator wrote down', () {
    File(p.join(root.path, '.dart_tool', 'dartvel_studio_models.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(<String, Object?>{
        'models': <Object?>[
          const DVStudioModelSpec(
            model: 'Note',
            table: 'notes',
            key: 'id',
            fields: <DVStudioFieldSpec>[
              DVStudioFieldSpec(name: 'id', type: 'String'),
            ],
          ).toManifest(),
        ],
      }));

    final List<DVStudioModelSpec> models = dvDevStudioModels(root.path);

    expect(models.single.model, 'Note');
    expect(models.single.table, 'notes');
  });

  test('a project that was never generated has no models, not an error', () {
    expect(dvDevStudioModels(root.path), isEmpty);
  });

  test('the database is the SQLite file dartvel.database names', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  database:
    provider: sqlite
    path: data/dev.db
''');
    final DVDatabaseAdapter? database =
        dvDevStudioDatabase(root.path, const <String, String>{});

    expect(database, isNotNull);
    await database!.execute('CREATE TABLE t (a TEXT)');
    expect(File(p.join(root.path, 'data', 'dev.db')).existsSync(), isTrue);
  });

  test('the mount a development server serves Studio at asks for the grant',
      () {
    final DVAdminMount mount = dvDevStudioMount(null);

    expect(mount.path, '/__studio');
    expect(mount.enabled, isTrue);
    expect(mount.requiresAuth, isTrue);
  });

  test('a project that turned the admin off gets none', () {
    expect(
      dvDevStudioMount(<String, Object?>{
        'admin': <String, Object?>{'enabled': false},
      }).enabled,
      isFalse,
    );
  });

  test("the dev backend answers Studio's API at the mount, over the data dev "
      'writes, behind the grant dev hands it', () {
    final String source = dvDevServerSource(
      admin: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true),
      adminRoot: '/project/.dart_tool/dartvel_studio/data',
    );

    expect(
      source,
      contains("admin: const core.DVAdminMount(path: '/__studio', "
          'enabled: true, requiresAuth: true)'),
    );
    expect(source,
        contains("adminRoot: '/project/.dart_tool/dartvel_studio/data'"));
    expect(
      source,
      contains('studioDevGrant: core.DVStudioDevGrant.fromEnvironment('
          'Platform.environment)'),
    );
  });

  test('a project that turned the admin off starts a backend without one', () {
    final String source = dvDevServerSource(
      admin: const DVAdminMount(
          path: '/__studio', enabled: false, requiresAuth: true),
      adminRoot: '/x',
    );

    expect(source, isNot(contains('admin:')));
  });

  test('dev hands the backend the grant it prints', () {
    const DVStudioDevGrant grant =
        DVStudioDevGrant('0123456789abcdef0123456789abcdef');

    expect(
      dvDevBackendEnvironment(const <String, String>{}, studioDevGrant: grant)[
          DVStudioDevGrant.environmentVariable],
      grant.token,
    );
  });

  // Studio in development is the app's own route, as in a deployment. The app
  // runs on Flutter's development server and Studio's API on the development
  // backend, so the app's server passes <mount>/api/ through to the backend:
  // the same origin, the same cookie, and no separately compiled Studio.
  group('Studio in the app dev runs', () {
    const DVAdminMount mount =
        DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);

    test('is compiled into a web app, and into nothing else', () {
      expect(dvDevStudioFlutterArgs(mount, web: true),
          <String>['--dart-define=dartvel.studio=true']);
      expect(dvDevStudioFlutterArgs(mount, web: false), isEmpty);
      expect(
          dvDevStudioFlutterArgs(
              const DVAdminMount(
                  path: '/__studio', enabled: false, requiresAuth: true),
              web: true),
          isEmpty);
    });

    test("reaches Studio's API on the backend through the app's own server",
        () {
      final String? config =
          dvDevStudioProxyConfig(mount, backendPort: 3000, existing: null);
      expect(config, contains(dvDevStudioProxyMarker));
      expect(config, contains('prefix: "/__studio/api/"'));
      expect(config, contains('target: "http://localhost:3000/"'));
      // Only the API: the app's own server answers <mount> with the app.
      expect(config, isNot(contains('prefix: "/__studio/"')));
    });

    test("a web_dev_config.yaml of the project's own is left alone", () {
      expect(
          dvDevStudioProxyConfig(mount,
              backendPort: 3000, existing: 'server:\n  port: 8080\n'),
          isNull);
      // One dev wrote is rewritten, for a moved mount or port.
      final String ours =
          dvDevStudioProxyConfig(mount, backendPort: 3000, existing: null)!;
      expect(
          dvDevStudioProxyConfig(
              const DVAdminMount(
                  path: '/ops', enabled: true, requiresAuth: true),
              backendPort: 4000,
              existing: ours),
          allOf(contains('prefix: "/ops/api/"'),
              contains('target: "http://localhost:4000/"')));
    });

    test('the grant link opens on the app, through the API the app passes on',
        () {
      const DVStudioDevGrant grant =
          DVStudioDevGrant('0123456789abcdef0123456789abcdef');
      expect(dvDevStudioLink('http://localhost:8080', mount, grant),
          'http://localhost:8080/__studio/api/?dev_grant=${grant.token}');
    });
  });
}
