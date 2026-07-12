import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift_dev/src/services/schema/verifier_common.dart';
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SchemaVerifier verifier;
  GeneratedDatabase Function(QueryExecutor db, int version) openReference =
      _TestDatabase.new;

  setUp(() {
    verifier = SchemaVerifier(
      _TestHelper((db, version) => openReference(db, version)),
      setup: (rawDb) => rawDb.createFunction(
          functionName: 'test_function', function: (args) => 1),
    );
  });

  group('startAt', () {
    test('starts at the requested version', () async {
      final db = (await verifier.startAt(17)).executor;
      await db.ensureOpen(_DelegatedUser(17, (_, details) async {
        expect(details.wasCreated, isFalse, reason: 'was opened before');
        expect(details.hadUpgrade, isFalse, reason: 'no upgrade expected');
      }));
    });

    test('registers custom functions', () async {
      final db = (await verifier.startAt(17)).executor;
      await db.ensureOpen(_DelegatedUser(17, (_, details) async {}));
      await db.runSelect('select test_function()', []);
    });

    test('disables double-quoted string literals', () async {
      final db = (await verifier.startAt(17)).executor;
      await db.ensureOpen(_DelegatedUser(17, (_, details) async {}));
      await expectLater(db.runSelect('select "why_would_this_be_a_string"', []),
          throwsA(isA<SqliteException>()));
    });
  });

  group('migrateAndValidate', () {
    test('invokes a migration', () async {
      OpeningDetails? capturedDetails;

      final connection = await verifier.startAt(3);
      final db = _TestDatabase(connection.executor, 7)
        ..migration = MigrationStrategy(onUpgrade: (m, from, to) async {
          capturedDetails = OpeningDetails(from, to);
        });

      await verifier.migrateAndValidate(db, 4);
      expect(capturedDetails!.versionBefore, 3);
      expect(capturedDetails!.versionNow, 4);
    });

    test('can skip validating column constraints', () async {
      openReference = (db, version) {
        final ref = _TestDatabase(db, version);

        ref.migration = MigrationStrategy(onCreate: (m) async {
          if (version == 1) {
            await ref
                .customStatement('CREATE TABLE users (name TEXT NOT NULL);');
          } else {
            await ref.customStatement('CREATE TABLE users (name TEXT);');
          }
        });

        return ref;
      };

      // Should throw with an empty migration due to constraint mismatch
      var connection = await verifier.startAt(1);
      var db = _TestDatabase(connection.executor, 2)
        ..migration = MigrationStrategy(
          onUpgrade: (m, from, to) async {},
        );
      await expectLater(() => verifier.migrateAndValidate(db, 2),
          throwsA(isA<SchemaMismatch>()));

      // Which can be disabled with an option.
      connection = await verifier.startAt(1);
      db = _TestDatabase(connection.executor, 2)
        ..migration = MigrationStrategy(
          onUpgrade: (m, from, to) async {},
        );
      await verifier.migrateAndValidate(db, 2,
          options: ValidationOptions(validateColumnConstraints: false));

      // that is also respected in testWithDataIntegrity
      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        createOld: (ex) => openReference(ex, 1),
        newVersion: 2,
        createNew: (ex) => openReference(ex, 2),
        openTestedDatabase: (e) => _TestDatabase(e, 2)
          ..migration = MigrationStrategy(
            onUpgrade: (m, from, to) async {},
          ),
        createItems: (batch, old) async {},
        validateItems: (_) async {},
        options: ValidationOptions(validateColumnConstraints: false),
      );
    });
  });

  group('collectSchemaInput', () {
    test('contains only user-defined entities', () async {
      final db = _TestDatabase(NativeDatabase.memory(), 1);
      addTearDown(db.close);

      await db.customStatement('CREATE TABLE x1 (bar UNIQUE);');
      await db.customStatement('CREATE VIEW x2 AS SELECT * FROM x1;');
      await db.customStatement('CREATE INDEX x3 ON x1 (bar);');
      await db.customStatement('CREATE TRIGGER x4 AFTER INSERT ON x1 BEGIN '
          'DELETE FROM x1;'
          'END;');
      await db
          .customStatement('CREATE TRIGGER x5 INSTEAD OF INSERT ON x2 BEGIN '
              'DELETE FROM x1;'
              'END;');

      final inputs = await db.collectSchemaInput(const []);
      expect(inputs.map((e) => e.name), ['x1', 'x2', 'x3', 'x4', 'x5']);
    });

    test('does not contain shadow tables', () async {
      final db = _TestDatabase(NativeDatabase.memory(), 1);
      addTearDown(db.close);

      await db.customStatement('CREATE VIRTUAL TABLE x USING fts5(foo, bar);');
      await db
          .customStatement('INSERT INTO x VALUES (?, ?)', ['test', 'another']);

      final inputs = await db.collectSchemaInput(const ['x']);
      expect(inputs.map((e) => e.name), ['x']);
    });
  });
}

class _TestHelper implements SchemaInstantiationHelper {
  final GeneratedDatabase Function(QueryExecutor db, int version) resolve;

  _TestHelper(this.resolve);

  @override
  GeneratedDatabase databaseForVersion(QueryExecutor db, int version) {
    return resolve(db, version);
  }
}

class _TestDatabase extends GeneratedDatabase {
  @override
  final int schemaVersion;

  @override
  MigrationStrategy migration = MigrationStrategy();

  _TestDatabase(super.executor, this.schemaVersion);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables {
    return const Iterable.empty();
  }
}

class _DelegatedUser extends QueryExecutorUser {
  @override
  final int schemaVersion;
  final Future<void> Function(QueryExecutor, OpeningDetails) _beforeOpen;

  _DelegatedUser(this.schemaVersion, this._beforeOpen);

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) {
    return _beforeOpen(executor, details);
  }
}
