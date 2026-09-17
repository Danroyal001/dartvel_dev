// What a development server serves Studio from: the models the generator
// described and the project's own database.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/dev_studio.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart'
    show dvCompileDevStudio, dvDevBackendEnvironment, dvDevServerSource;
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

  test('the dev backend serves Studio at the mount, from where dev compiles '
      'it, behind the grant dev hands it', () {
    final String source = dvDevServerSource(
      admin: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true),
      adminRoot: '/project/.dart_tool/dartvel_studio/admin',
    );

    expect(
      source,
      contains("admin: const core.DVAdminMount(path: '/__studio', "
          'enabled: true, requiresAuth: true)'),
    );
    expect(source,
        contains("adminRoot: '/project/.dart_tool/dartvel_studio/admin'"));
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

  group('compiling Studio for dev', () {
    const DVAdminMount mount =
        DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);

    test('a Studio compiled since dependencies last resolved is not rebuilt',
        () async {
      File(p.join(root.path, 'pubspec.lock')).writeAsStringSync('');
      final String admin = p.join(root.path, 'studio');
      File(p.join(admin, 'main.dart.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('//');
      final List<String> ran = <String>[];
      bool ready = false;

      await dvCompileDevStudio(
        root: root.path,
        mount: mount,
        adminRoot: admin,
        onReady: () => ready = true,
        run: (String exe, List<String> args, {String? workingDirectory}) async {
          ran.add(exe);
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(ran, isEmpty);
      expect(ready, isTrue);
    });

    test('a missing Studio is compiled with flutter build web, and a failed '
        'compile is not reported ready', () async {
      final List<List<String>> ran = <List<String>>[];
      bool ready = false;

      await dvCompileDevStudio(
        root: root.path,
        mount: mount,
        adminRoot: p.join(root.path, 'studio'),
        onReady: () => ready = true,
        run: (String exe, List<String> args, {String? workingDirectory}) async {
          ran.add(<String>[exe, ...args]);
          return ProcessResult(0, 1, '', 'compile error');
        },
      );

      expect(ran.single.take(3), <String>['flutter', 'build', 'web']);
      expect(ran.single, containsAllInOrder(<String>['--base-href', '/__studio/']));
      expect(ready, isFalse);
    });
  });
}
