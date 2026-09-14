// Schema Evolution: every change is classified, and by the adapter.
//
// The same one-line model edit is instant on one server and a forty-minute
// table lock on another, so the class has to come from the adapter that knows
// the server and its version, never from rules baked into the planner. The
// silent failure worth the most effort here is an unknown change classified
// as cheap: that is an outage nobody predicted, so an unclassifiable change
// is treated as blocking and says so (DV-SCHEMA-006).
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVSchemaChangeClass instant = DVSchemaChangeClass.instant;
const DVSchemaChangeClass online = DVSchemaChangeClass.online;
const DVSchemaChangeClass blocking = DVSchemaChangeClass.blocking;

const DVAddColumn addNullable = DVAddColumn('orders', 'note');
const DVAddColumn addWithDefault = DVAddColumn(
  'orders',
  'status',
  defaultSql: "'open'",
);
const DVAddIndex addIndex = DVAddIndex('orders', <String>['customer']);
const DVAddNotNull addNotNull = DVAddNotNull('orders', 'customer');
const DVChangeColumnType changeType = DVChangeColumnType(
  'orders',
  'total',
  from: 'TEXT',
  to: 'INTEGER',
);
const DVRenameColumn rename = DVRenameColumn(
  'orders',
  from: 'qty',
  to: 'quantity',
);
const DVDropColumn drop = DVDropColumn('orders', 'legacy');

/// Expands the specification's table row by row, so a divergence names the
/// cell rather than failing on the first.
void expectTable(
  DVSchemaClassifier rules,
  Map<DVSchemaChange, DVSchemaChangeClass?> expected,
) {
  expected.forEach((DVSchemaChange change, DVSchemaChangeClass? want) {
    expect(rules.classify(change), want, reason: '$rules: $change');
  });
}

void main() {
  group('server versions', () {
    test('read from the strings servers actually report', () {
      expect(DVDatabaseServerVersion.parse('16.2').major, 16);
      expect(
        DVDatabaseServerVersion.parse('10.23 (Debian 10.23-1.pgdg110+1)'),
        const DVDatabaseServerVersion(10, 23, 0),
      );
      expect(
        DVDatabaseServerVersion.parse('8.0.36-0ubuntu0.22.04.1'),
        const DVDatabaseServerVersion(8, 0, 36),
      );
      expect(
        DVDatabaseServerVersion.parse('3.45.1'),
        const DVDatabaseServerVersion(3, 45, 1),
      );
    });

    test('compare numerically, not as text', () {
      expect(
        const DVDatabaseServerVersion(8, 0, 9) <
            const DVDatabaseServerVersion(8, 0, 12),
        isTrue,
      );
      expect(
        const DVDatabaseServerVersion(11, 0, 0) >=
            const DVDatabaseServerVersion(10, 23, 0),
        isTrue,
      );
    });

    test('an unreadable version is null, not zero', () {
      // Zero would read as "very old" and quietly pick a rule.
      expect(DVDatabaseServerVersion.tryParse('banana'), isNull);
    });
  });

  group('PostgreSQL', () {
    test('the specification table, on a current server', () {
      expectTable(
        DVPostgresSchemaRules(DVDatabaseServerVersion.parse('16.2')),
        <DVSchemaChange, DVSchemaChangeClass?>{
          addNullable: instant,
          addWithDefault: instant,
          addIndex: online,
          addNotNull: online,
          changeType: blocking,
          rename: instant,
          drop: instant,
        },
      );
    });

    test('a default is a table rewrite before 11', () {
      final DVPostgresSchemaRules ten = DVPostgresSchemaRules(
        DVDatabaseServerVersion.parse('10.23'),
      );
      expect(ten.classify(addWithDefault), blocking);
      expect(
        DVPostgresSchemaRules(
          DVDatabaseServerVersion.parse('11.0'),
        ).classify(addWithDefault),
        instant,
      );
    });

    test('NOT NULL is only online through a validated check from 12', () {
      expect(
        DVPostgresSchemaRules(
          DVDatabaseServerVersion.parse('11.9'),
        ).classify(addNotNull),
        blocking,
      );
      expect(
        DVPostgresSchemaRules(
          DVDatabaseServerVersion.parse('12.0'),
        ).classify(addNotNull),
        online,
      );
    });
  });

  group('MySQL 8', () {
    test('the specification table', () {
      expectTable(
        DVMySqlSchemaRules(DVDatabaseServerVersion.parse('8.0.36')),
        <DVSchemaChange, DVSchemaChangeClass?>{
          addNullable: instant,
          addWithDefault: instant,
          addIndex: online,
          addNotNull: blocking,
          changeType: blocking,
          rename: instant,
          drop: instant,
        },
      );
    });

    test(
      'INSTANT arrived in point releases, and earlier 8.0 rebuilds online',
      () {
        final DVMySqlSchemaRules early = DVMySqlSchemaRules(
          DVDatabaseServerVersion.parse('8.0.11'),
        );
        expect(early.classify(addNullable), online);
        expect(early.classify(rename), online);
        expect(early.classify(drop), online);
      },
    );

    test('a server it does not know is not guessed at', () {
      // MariaDB reports a 5.5.5- prefix and its own version after it, and a
      // 5.7 server has different rules entirely. Neither is the table above.
      expect(
        DVMySqlSchemaRules(
          DVDatabaseServerVersion.parse('5.7.44'),
        ).classify(addNullable),
        isNull,
      );
      expect(
        DVMySqlSchemaRules.forServer(
          '5.5.5-10.11.2-MariaDB',
        ).classify(addNullable),
        isNull,
      );
    });
  });

  group('SQLite and Turso', () {
    test('the specification table', () {
      expectTable(
        DVSqliteSchemaRules(DVDatabaseServerVersion.parse('3.45.1')),
        <DVSchemaChange, DVSchemaChangeClass?>{
          addNullable: instant,
          addWithDefault: instant,
          addIndex: blocking,
          addNotNull: blocking,
          changeType: blocking,
          rename: instant,
          drop: blocking,
        },
      );
    });

    test('rename is a table rebuild before 3.25', () {
      expect(
        DVSqliteSchemaRules(
          DVDatabaseServerVersion.parse('3.24.0'),
        ).classify(rename),
        blocking,
      );
    });
  });

  group('a change no rule covers', () {
    test('every shipped adapter declines to classify raw SQL', () {
      const DVRawSchemaChange raw = DVRawSchemaChange(
        'orders',
        'ALTER TABLE orders ADD CONSTRAINT positive CHECK (total > 0)',
      );
      for (final DVSchemaClassifier rules in <DVSchemaClassifier>[
        DVPostgresSchemaRules(DVDatabaseServerVersion.parse('16.0')),
        DVMySqlSchemaRules(DVDatabaseServerVersion.parse('8.0.36')),
        DVSqliteSchemaRules(DVDatabaseServerVersion.parse('3.45.0')),
      ]) {
        expect(rules.classify(raw), isNull, reason: '$rules');
      }
    });

    test('a new table is instant everywhere', () {
      const DVCreateTable create = DVCreateTable('invoices', <String>[
        'id',
        'total',
      ]);
      expect(
        DVSqliteSchemaRules(
          DVDatabaseServerVersion.parse('3.45.0'),
        ).classify(create),
        instant,
      );
    });
  });

  group('the adapter answers for the server it is connected to', () {
    test('SQLite reports the library it actually linked', () async {
      final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);

      expect(db.schemaRules.version.major, 3);
      expect(await db.classify(addIndex), blocking);
      expect(await db.classify(addNullable), instant);
    });

    test(
      'an adapter with no classification answers null through the contract',
      () async {
        // The in-memory development adapter runs no ALTER TABLE at all; the
        // contract's answer for it is "cannot classify", never a guess.
        final DVDatabaseAdapter memory = MemoryDVDatabaseAdapter();
        expect(await memory.classify(addNullable), isNull);
      },
    );

    test('an adapter written elsewhere can teach the planner', () async {
      final DVDatabaseAdapter custom = _EverythingOnline();
      expect(await custom.classify(changeType), online);
    });
  });
}

/// An adapter somebody else wrote, whose server does every change online.
class _EverythingOnline implements DVDatabaseAdapter, DVSchemaClassifier {
  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) => online;

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async => 0;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async => const <Map<String, Object?>>[];
}
