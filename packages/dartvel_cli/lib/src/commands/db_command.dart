import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

class DbCommand extends Command<void> {
  @override
  final String name = 'db';
  @override
  final String description =
      'Manage the Dartvel database schemas, migrations, and seeding.';

  DbCommand() {
    addSubcommand(DbMigrateSubcommand());
    addSubcommand(DbPushSubcommand());
    addSubcommand(DbPullSubcommand());
    addSubcommand(DbSeedSubcommand());
  }
}

class DbMigrateSubcommand extends Command<void> {
  @override
  final String name = 'migrate';
  @override
  final String description = 'Run pending database schema migrations.';

  @override
  Future<void> run() async {
    Logger.log('Running database migrations...');
    final root = Directory.current.path;
    final schema = discoverLocalSchema(root);
    for (final table in schema.tables) {
      Logger.log('  [+] Migrated table: ${table.name}');
    }
    writeLocalSchemaSnapshot(root, schema);
    Logger.log(
      'Migration complete. ${schema.tables.length} tables synced successfully.',
    );
  }
}

class DbPushSubcommand extends Command<void> {
  @override
  final String name = 'push';
  @override
  final String description =
      'Push local schema changes directly to the database.';

  @override
  Future<void> run() async {
    Logger.log('Pushing local schemas to database...');
    final root = Directory.current.path;
    final snapshot = localSchemaSnapshotFile(root);
    if (!snapshot.existsSync()) {
      Logger.log(
        '❌ No local schema snapshot found. Run `dartvel db migrate` first.',
        isError: true,
      );
      exitCode = 1;
      return;
    }
    final remote = remoteSchemaSnapshotFile(root);
    remote.parent.createSync(recursive: true);
    snapshot.copySync(remote.path);
    Logger.log('Pushed schema snapshot to ${p.relative(remote.path, from: root)}.');
  }
}

class DbPullSubcommand extends Command<void> {
  @override
  final String name = 'pull';
  @override
  final String description = 'Pull remote database schema and generate models.';

  @override
  Future<void> run() async {
    Logger.log('Pulling remote schema...');
    final root = Directory.current.path;
    final remote = remoteSchemaSnapshotFile(root);
    if (!remote.existsSync()) {
      Logger.log(
        '❌ No remote schema snapshot found at ${p.relative(remote.path, from: root)}.',
        isError: true,
      );
      exitCode = 1;
      return;
    }
    final pulled = pulledSchemaSnapshotFile(root);
    pulled.parent.createSync(recursive: true);
    remote.copySync(pulled.path);
    Logger.log('Pulled schema snapshot to ${p.relative(pulled.path, from: root)}.');
  }
}

class DbSeedSubcommand extends Command<void> {
  @override
  final String name = 'seed';
  @override
  final String description = 'Seed the database with test data.';

  @override
  Future<void> run() async {
    Logger.log('Seeding database...');
    final root = Directory.current.path;
    final seeds = discoverSeedFiles(root);
    if (seeds.isEmpty) {
      Logger.log(
        '❌ No seed files found. Add lib/database/seed.dart, lib/database/seeds.dart, lib/seeds/*.dart, or tool/seed.dart.',
        isError: true,
      );
      exitCode = 1;
      return;
    }
    for (final seed in seeds) {
      final relative = p.relative(seed.path, from: root);
      Logger.log('  [*] Running seed: $relative');
      final result = await Process.run(
        'dart',
        <String>['run', relative],
        workingDirectory: root,
        runInShell: true,
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      if (result.exitCode != 0) {
        Logger.log('❌ Seed failed: $relative', isError: true);
        exitCode = result.exitCode;
        return;
      }
    }
    Logger.log('Database seeded successfully from ${seeds.length} file(s).');
  }
}

class DartvelDbSchema {
  const DartvelDbSchema({required this.tables});

  final List<DartvelDbTable> tables;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'tables': tables.map((table) => table.toJson()).toList(growable: false),
      };
}

class DartvelDbTable {
  const DartvelDbTable({
    required this.name,
    required this.model,
    required this.source,
  });

  final String name;
  final String model;
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'model': model,
        'source': source,
      };
}

DartvelDbSchema discoverLocalSchema(String root) {
  final glob = Glob('lib/models/**.dart');
  const fs = LocalFileSystem();
  final tables = <DartvelDbTable>[];
  for (final entity in glob.listFileSystemSync(
    fs,
    root: root,
    followLinks: false,
  )) {
    if (entity.basename.endsWith('.dart') == false) continue;
    final sourceFile = File(entity.path);
    final content = sourceFile.readAsStringSync();
    final matches = RegExp(
      r'@DVModel\s*\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)',
      dotAll: true,
    ).allMatches(content);
    for (final match in matches) {
      final sourceClassName = match.group(1)!;
      if (!sourceClassName.startsWith('_')) {
        throw StateError(
          'Dartvel model generation inputs must be private. Rename '
          '$sourceClassName to _$sourceClassName before running db commands.',
        );
      }
      final model = sourceClassName.substring(1);
      tables.add(
        DartvelDbTable(
          name: '${model.toLowerCase()}s',
          model: model,
          source: p.relative(sourceFile.path, from: root).replaceAll(r'\', '/'),
        ),
      );
    }
  }
  tables.sort((left, right) => left.name.compareTo(right.name));
  return DartvelDbSchema(tables: List<DartvelDbTable>.unmodifiable(tables));
}

File localSchemaSnapshotFile(String root) =>
    File(p.join(root, '.dart_tool', 'dartvel_db', 'schema.snapshot.json'));

File remoteSchemaSnapshotFile(String root) => File(
      Platform.environment['DARTVEL_DB_REMOTE_SCHEMA'] ??
          p.join(root, '.dartvel', 'db', 'remote_schema.snapshot.json'),
    );

File pulledSchemaSnapshotFile(String root) =>
    File(p.join(root, '.dart_tool', 'dartvel_db', 'pulled_schema.snapshot.json'));

void writeLocalSchemaSnapshot(String root, DartvelDbSchema schema) {
  final output = localSchemaSnapshotFile(root);
  output.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  output.writeAsStringSync('${encoder.convert(schema.toJson())}\n');
}

List<File> discoverSeedFiles(String root) {
  final candidates = <File>[
    File(p.join(root, 'lib', 'database', 'seed.dart')),
    File(p.join(root, 'lib', 'database', 'seeds.dart')),
    File(p.join(root, 'tool', 'seed.dart')),
  ];
  final seedsDir = Directory(p.join(root, 'lib', 'seeds'));
  if (seedsDir.existsSync()) {
    candidates.addAll(
      seedsDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    );
  }
  final found = candidates.where((file) => file.existsSync()).toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return List<File>.unmodifiable(found);
}
