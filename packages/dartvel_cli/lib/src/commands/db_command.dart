import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:dartvel_core/dartvel.dart'
    show SqliteDVDatabaseAdapter;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/annotation_args.dart';
import '../graph/module_mounts.dart';
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
    writeLocalSchemaSnapshot(root, schema);

    // What actually happened, rather than a line per table found.
    //
    // This printed "[+] Migrated table: orders" for every model and
    // "Migration complete. N tables synced successfully" while touching no
    // database at all: it read a list of names and wrote a snapshot. The
    // statements existed -- one per model, correct, carrying the tenant
    // column -- and nothing anywhere called them.
    final DVMigrationReport report = await dvApplyMigrations(root);

    if (report.skippedReason != null) {
      Logger.log('  Schema snapshot written for ${schema.tables.length} '
          'table(s).');
      Logger.log('  ! ${report.skippedReason}');
      return;
    }

    for (final String table in report.applied) {
      Logger.log('  [+] $table');
    }
    if (report.applied.isEmpty) {
      Logger.log(
        'No tables to migrate: this project declares no @DVModel inputs, or '
        'they have not been generated yet. Run dartvel routes first.',
      );
      return;
    }
    Logger.log(
      'Migration complete. ${report.applied.length} table(s) created or '
      'already present.',
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
    this.module,
  });

  final String name;
  final String model;

  /// The model file, relative to the project that declares it.
  final String source;

  /// The module this table came from, or null for the application's own.
  ///
  /// Recorded so a snapshot says why the database has a table no model in
  /// this project declares.
  final String? module;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'model': model,
        'source': source,
        if (module != null) 'module': module,
      };
}

DartvelDbSchema discoverLocalSchema(String root) {
  final tables = <DartvelDbTable>[
    ..._tablesIn(root, module: null),
    for (final DVModuleMount mount in _modulesInThisDatabase(root))
      ..._tablesIn(
        p.join(root, mount.sourcePath),
        module: mount.id,
        // Schema-isolated means the parent's database and the module's own
        // tables within it, so the name carries the module id. This has to
        // be the same rule DVModule.table applies at run time: the day the
        // migration and the query disagree is the day the table is created
        // and never read.
        prefix: mount.data == 'schema-isolated' ? '${mount.id}_' : '',
      ),
  ];
  final claimed = <String, DartvelDbTable>{};
  for (final DartvelDbTable table in tables) {
    final DartvelDbTable? first = claimed[table.name];
    if (first == null) {
      claimed[table.name] = table;
      continue;
    }
    String owner(DartvelDbTable t) =>
        t.module == null ? 'the application' : 'module ${t.module}';
    // One database, one table of that name. Two models writing to it would
    // read each other's rows, and the columns of whichever lost would simply
    // not be there.
    throw StateError(
      'dartvel: ${owner(first)} and ${owner(table)} both declare the table '
      '${table.name}. Rename one of the models, or give the module a data '
      'mode of its own.',
    );
  }
  tables.sort((left, right) => left.name.compareTo(right.name));
  return DartvelDbSchema(tables: List<DartvelDbTable>.unmodifiable(tables));
}

/// The modules whose tables live in this application's database.
///
/// Only the ones compiled into it -- a federated or split-backend module runs
/// its own -- and only where the module's data mode puts its tables here.
/// Shared puts them here under the model's own name; schema-isolated puts
/// them here under the module's. A module with its own database or a remote
/// one keeps its tables there, and creating empty copies here would look
/// like its data had been lost.
List<DVModuleMount> _modulesInThisDatabase(String root) =>
    dvDiscoverModuleMounts(root)
        .where((DVModuleMount mount) =>
            mount.mounted &&
            (mount.data == 'shared' || mount.data == 'schema-isolated') &&
            (mount.deployment == DVModuleDeployment.embedded ||
                mount.deployment == DVModuleDeployment.backendOnly))
        .toList(growable: false);

List<DartvelDbTable> _tablesIn(
  String root, {
  required String? module,
  String prefix = '',
}) {
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
    ).allMatches(dvMaskAnnotationArgs(content, 'DVModel'));
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
          name: '$prefix${model.toLowerCase()}s',
          model: model,
          source: p.relative(sourceFile.path, from: root).replaceAll(r'\', '/'),
          module: module,
        ),
      );
    }
  }
  return tables;
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

/// What a migration run actually did.
///
/// `dartvel db migrate` said it had migrated and had touched no database. It
/// discovered a list of table names, printed "[+] Migrated table: orders" for
/// each one and "Migration complete. N tables synced successfully", and wrote
/// a JSON snapshot. No statement was ever executed, and the generated
/// `createTableSql` -- one per model, correct, carrying the tenant column --
/// was called by nothing anywhere in the repository.
///
/// This is what it does now, and [skippedReason] is the honest half: the CLI
/// has no connection to a managed Postgres or MySQL, and saying so with the
/// statements written out is worth more than a green line.
class DVMigrationReport {
  const DVMigrationReport({
    required this.applied,
    this.skippedReason,
    this.sqlFile,
  });

  /// Tables whose statement ran.
  final List<String> applied;

  /// Why nothing ran, or null when something did.
  final String? skippedReason;

  /// Where the statements were written when they could not be run.
  final String? sqlFile;
}

/// The statements the generator wrote down, or an empty list.
///
/// Read rather than rebuilt. A second parser deciding what a table's columns
/// are is how a migration comes to create one shape while the queries read
/// another, with neither side noticing.
List<Map<String, Object?>> dvGeneratedSchema(String root) {
  final File file = File(p.join(root, '.dart_tool', 'dartvel_schema.g.json'));
  if (!file.existsSync()) return const <Map<String, Object?>>[];
  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return const <Map<String, Object?>>[];
  final Object? tables = decoded['tables'];
  if (tables is! List) return const <Map<String, Object?>>[];
  return tables.whereType<Map<String, Object?>>().toList(growable: false);
}

/// `dartvel.database` from pubspec.yaml: the provider and where it lives.
({String provider, String path}) dvDatabaseSettings(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return (provider: 'sqlite', path: 'dartvel.db');
  // Deliberately not the YAML package's full loader: this is two scalars and
  // the command already reads the file for nothing else.
  final Object? loaded = loadYaml(pubspec.readAsStringSync());
  final Object? dartvel = loaded is Map ? loaded['dartvel'] : null;
  final Object? database = dartvel is Map ? dartvel['database'] : null;
  final Object? provider = database is Map ? database['provider'] : null;
  final Object? path = database is Map ? database['path'] : null;
  return (
    provider: (provider ?? 'sqlite').toString(),
    path: (path ?? 'dartvel.db').toString(),
  );
}

/// Runs the generated statements against the configured database.
///
/// SQLite is applied here because it is the one the framework can reach: the
/// specification makes local development zero-config with SQLite, and the
/// file is beside the project. Anything else is written out with the reason
/// it was not run, because the alternative is what this replaces -- a
/// success message for work that did not happen.
Future<DVMigrationReport> dvApplyMigrations(String root) async {
  final List<Map<String, Object?>> tables = dvGeneratedSchema(root);
  if (tables.isEmpty) {
    return const DVMigrationReport(applied: <String>[]);
  }

  final ({String provider, String path}) settings = dvDatabaseSettings(root);
  final List<String> statements = <String>[
    for (final Map<String, Object?> table in tables)
      if (table['createSql'] is String) table['createSql']! as String,
  ];

  if (settings.provider != 'sqlite') {
    final File sql = File(
      p.join(root, '.dart_tool', 'dartvel_migration.sql'),
    );
    sql.parent.createSync(recursive: true);
    sql.writeAsStringSync('${statements.map((String s) => '$s;').join('\n')}\n');
    return DVMigrationReport(
      applied: const <String>[],
      skippedReason:
          'dartvel db migrate applies SQLite here and this project uses '
          '${settings.provider}. The CLI has no connection to it, so the '
          'statements are in ${p.relative(sql.path, from: root)} to run '
          'against your database.',
      sqlFile: sql.path,
    );
  }

  final String file = p.isAbsolute(settings.path)
      ? settings.path
      : p.join(root, settings.path);
  // The framework's own adapter, not a second sqlite3 dependency here. Two
  // ways to open the same file is how the migration comes to enable
  // foreign keys and the application not to.
  final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(file);
  final List<String> applied = <String>[];
  try {
    for (final Map<String, Object?> table in tables) {
      final Object? create = table['createSql'];
      if (create is! String) continue;
      await db.execute(create);
      applied.add('${table['table']}');
    }
  } finally {
    db.close();
  }
  return DVMigrationReport(applied: applied);
}

/// The columns a SQLite table actually has.
///
/// The question a migration has to be able to ask: CREATE TABLE IF NOT EXISTS
/// is a no-op against a table that is already there, so a model that gained a
/// column since the table was made does not get it, and every query naming
/// that column fails against a database the migration just reported as
/// migrated.
Future<List<String>> dvSqliteColumns(String file, String table) async {
  if (!File(file).existsSync()) return const <String>[];
  final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(file);
  try {
    final List<Map<String, Object?>> rows =
        await db.query('PRAGMA table_info($table)');
    return rows
        .map((Map<String, Object?> row) => '${row['name']}')
        .toList(growable: false);
  } finally {
    db.close();
  }
}
