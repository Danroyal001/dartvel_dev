// Schema Evolution: the planner and the deploy gate.
//
// A blocking change is refused as written and the safe version planned
// instead, where one exists (DV-SCHEMA-001). A change the adapter cannot
// classify is blocking (DV-SCHEMA-006). A blocking change reaching production
// is refused unless an explicit, logged override accompanies it
// (DV-SCHEMA-002). And the classification a developer sees against a
// snapshot is the one production's server would apply, not the one their
// empty local database implies.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DVPostgresSchemaRules postgres16 = DVPostgresSchemaRules(
  DVDatabaseServerVersion.parse('16.2'),
);
final DVSqliteSchemaRules sqlite = DVSqliteSchemaRules(
  DVDatabaseServerVersion.parse('3.45.1'),
);

const DVChangeColumnType totalToInteger = DVChangeColumnType(
  'orders',
  'total',
  from: 'TEXT',
  to: 'INTEGER',
);

void main() {
  const DVSchemaPlanner planner = DVSchemaPlanner();

  group('classifying a plan', () {
    test('each step carries the class the adapter gave it', () async {
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        const DVAddColumn('orders', 'note'),
        const DVAddIndex('orders', <String>['customer']),
      ], postgres16);

      expect(
        plan.steps.map((DVSchemaPlanStep s) => s.changeClass),
        <DVSchemaChangeClass>[
          DVSchemaChangeClass.instant,
          DVSchemaChangeClass.online,
        ],
      );
      expect(plan.findings, isEmpty);
      expect(plan.blocking, isEmpty);
    });

    test(
      'a change the adapter cannot classify is blocking, and says so',
      () async {
        const DVRawSchemaChange raw = DVRawSchemaChange(
          'orders',
          'ALTER TABLE orders ADD CONSTRAINT positive CHECK (total > 0)',
        );
        final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
          raw,
        ], postgres16);

        final DVSchemaPlanStep step = plan.steps.single;
        expect(step.changeClass, DVSchemaChangeClass.blocking);
        expect(step.classifiedByAdapter, isFalse);
        expect(plan.blocking, <DVSchemaPlanStep>[step]);
        final DVSchemaFinding finding = plan.findings.single;
        expect(finding.code, 'DV-SCHEMA-006');
        expect(finding.level, 'warning');
        expect(finding.change, raw);
      },
    );

    test('with no adapter rules at all, nothing is assumed cheap', () async {
      // An unknown provider in a snapshot. Every change, even the most
      // harmless one, is blocking until something that knows the server says
      // otherwise.
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        const DVAddColumn('orders', 'note'),
      ], null);
      expect(plan.steps.single.changeClass, DVSchemaChangeClass.blocking);
      expect(plan.findings.single.code, 'DV-SCHEMA-006');
    });

    test('planning through an adapter asks the adapter', () async {
      final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
      addTearDown(db.close);

      final DVSchemaPlan plan = await planner.planFor(db, <DVSchemaChange>[
        const DVAddIndex('orders', <String>['customer']),
      ]);
      // SQLite holds the write lock for an index build; PostgreSQL does not.
      expect(plan.steps.single.changeClass, DVSchemaChangeClass.blocking);
      expect(plan.steps.single.classifiedByAdapter, isTrue);
    });
  });

  group('expand and contract', () {
    test(
      'a blocking type change is refused as written and planned safely',
      () async {
        final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
          totalToInteger,
        ], postgres16);

        final DVSchemaPlanStep step = plan.steps.single;
        expect(step.changeClass, DVSchemaChangeClass.blocking);
        expect(step.refusedAsWritten, isTrue);
        // Nothing in the plan runs blocking: the expand runs instead.
        expect(plan.blocking, isEmpty);

        final DVExpandContractPlan safe = step.expandContract!;
        expect(safe.sourceColumn, 'total');
        expect(safe.targetColumn, isNot('total'));
        final DVAddColumn expand = safe.expand;
        expect(expand.table, 'orders');
        expect(expand.column, safe.targetColumn);
        expect(expand.type, 'INTEGER');
        expect(expand.nullable, isTrue);
        expect(safe.expandClass, DVSchemaChangeClass.instant);
        expect(safe.contract.map((DVSchemaChange c) => c.description), <String>[
          'drop column orders.total',
          'rename column orders.${safe.targetColumn} to total',
        ]);

        final DVSchemaFinding finding = plan.findings.single;
        expect(finding.code, 'DV-SCHEMA-001');
        expect(finding.level, 'warning');
      },
    );

    test('the plan says what its own contract step will cost', () async {
      // On SQLite the eventual drop is itself a rebuild. The plan still helps
      // -- the expand and backfill hold nothing -- but a plan that hid the
      // cost of its last step would be the surprise it exists to prevent.
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        totalToInteger,
      ], sqlite);
      expect(
        plan.steps.single.expandContract!.contractClass,
        DVSchemaChangeClass.blocking,
      );
    });

    test('no plan is offered when the expand would block too', () async {
      // A safe version that is not safe on this server is not a plan.
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        totalToInteger,
      ], _AddColumnBlocks());
      final DVSchemaPlanStep step = plan.steps.single;
      expect(step.expandContract, isNull);
      expect(step.refusedAsWritten, isFalse);
      expect(plan.blocking, <DVSchemaPlanStep>[step]);
      expect(
        plan.findings.map((DVSchemaFinding f) => f.code),
        isNot(contains('DV-SCHEMA-001')),
      );
    });

    test('a blocking change with no safe version is not given one', () async {
      // An index build on SQLite: there is no expand/contract for it, so it
      // stays a blocking step for the gate to decide on.
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        const DVAddIndex('orders', <String>['customer']),
      ], sqlite);
      expect(plan.steps.single.expandContract, isNull);
      expect(plan.blocking, hasLength(1));
      expect(plan.findings, isEmpty);
    });
  });

  group('the deploy gate', () {
    const DVSchemaDeployGate gate = DVSchemaDeployGate();

    Future<DVSchemaPlan> blockingPlan() => planner.plan(<DVSchemaChange>[
      const DVAddIndex('orders', <String>['customer']),
    ], sqlite);

    test('a blocking change against production is refused', () async {
      final DVSchemaGateResult result = gate.check(
        await blockingPlan(),
        production: true,
      );

      expect(result.allowed, isFalse);
      final DVSchemaFinding finding = result.findings.single;
      expect(finding.code, 'DV-SCHEMA-002');
      expect(finding.level, 'error');
      expect(finding.message, contains('add index on orders (customer)'));
      expect(result.overrideRecord, isNull);
    });

    test('outside production it is allowed', () async {
      final DVSchemaGateResult result = gate.check(
        await blockingPlan(),
        production: false,
      );
      expect(result.allowed, isTrue);
      expect(result.findings, isEmpty);
    });

    test('an explicit override lets it through and is recorded', () async {
      final DateTime at = DateTime.utc(2026, 9, 14, 3);
      final DVSchemaGateResult result = gate.check(
        await blockingPlan(),
        production: true,
        override: DVSchemaOverride(
          reason: 'maintenance window, customers told',
          by: 'daniel',
          at: at,
        ),
      );

      expect(result.allowed, isTrue);
      final Map<String, Object?> record = result.overrideRecord!;
      expect(record['code'], 'DV-SCHEMA-002');
      expect(record['reason'], 'maintenance window, customers told');
      expect(record['by'], 'daniel');
      expect(record['at'], at.toIso8601String());
      expect(record['changes'], <String>['add index on orders (customer)']);
    });

    test('an override with no reason is not an override', () async {
      final DVSchemaGateResult result = gate.check(
        await blockingPlan(),
        production: true,
        override: DVSchemaOverride(reason: '   ', at: DateTime.utc(2026)),
      );
      expect(result.allowed, isFalse);
      expect(result.findings.single.code, 'DV-SCHEMA-002');
    });

    test('an unclassifiable change is gated like any blocking one', () async {
      final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
        const DVAddColumn('orders', 'note'),
      ], null);
      expect(gate.check(plan, production: true).allowed, isFalse);
    });

    test(
      'a change planned as expand/contract does not need an override',
      () async {
        final DVSchemaPlan plan = await planner.plan(<DVSchemaChange>[
          totalToInteger,
        ], postgres16);
        final DVSchemaGateResult result = gate.check(plan, production: true);
        expect(result.allowed, isTrue);
      },
    );
  });

  group('a snapshot of production', () {
    const Map<String, Object?> json = <String, Object?>{
      'provider': 'postgres',
      'serverVersion': '10.23',
      'tables': <String, Object?>{
        'orders': <String, Object?>{
          'columns': <String>['id', 'total'],
          'rows': 120000000,
        },
      },
    };

    test('classifies as production would, not as the laptop does', () async {
      final DVSchemaSnapshot snapshot = DVSchemaSnapshot.fromJson(json);
      const DVAddColumn withDefault = DVAddColumn(
        'orders',
        'status',
        defaultSql: "'open'",
      );

      final DVSchemaPlan rehearsal = await planner.plan(
        <DVSchemaChange>[withDefault],
        snapshot.classifier,
        rows: snapshot.rows,
      );
      // Instant on the developer's PostgreSQL 16, a rewrite on production's
      // PostgreSQL 10.
      expect(
        (await planner.plan(<DVSchemaChange>[
          withDefault,
        ], postgres16)).steps.single.changeClass,
        DVSchemaChangeClass.instant,
      );
      expect(rehearsal.steps.single.changeClass, DVSchemaChangeClass.blocking);
      expect(rehearsal.steps.single.rows, 120000000);
      expect(rehearsal.describe(), contains('120000000 rows'));
    });

    test('carries columns and row counts both ways', () {
      final DVSchemaSnapshot snapshot = DVSchemaSnapshot.fromJson(json);
      expect(snapshot.tables['orders']!.columns, <String>['id', 'total']);
      expect(
        DVSchemaSnapshot.fromJson(snapshot.toJson()).toJson(),
        snapshot.toJson(),
      );
    });

    test('knows which provider rules to read', () {
      DVSchemaClassifier? rulesFor(String provider, String version) =>
          DVSchemaSnapshot(
            provider: provider,
            serverVersion: version,
            tables: const <String, DVSchemaSnapshotTable>{},
          ).classifier;

      expect(rulesFor('postgresql', '16.1'), isA<DVPostgresSchemaRules>());
      expect(rulesFor('mysql', '8.0.36'), isA<DVMySqlSchemaRules>());
      expect(rulesFor('turso', '3.45.0'), isA<DVSqliteSchemaRules>());
      // Out of scope as an operational database, so nothing here can say.
      expect(rulesFor('mongodb', '7.0'), isNull);
      // A version it cannot read is not a version it guesses.
      expect(rulesFor('postgres', 'unknown'), isNull);
    });

    test('a snapshot missing its provider is refused, not defaulted', () {
      expect(
        () => DVSchemaSnapshot.fromJson(const <String, Object?>{'tables': {}}),
        throwsFormatException,
      );
    });
  });
}

/// A server where adding any column blocks.
class _AddColumnBlocks implements DVSchemaClassifier {
  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) => switch (change) {
    DVAddColumn() => DVSchemaChangeClass.blocking,
    _ => DVSchemaChangeClass.blocking,
  };
}
