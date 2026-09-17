// What a development server serves Studio from: the models the generator
// described and the project's own database.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/dev_studio.dart';
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
}
