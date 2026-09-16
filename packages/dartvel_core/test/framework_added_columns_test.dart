// A column a later release adds to a framework table reaches the tables an
// earlier release already made.
//
// CREATE TABLE IF NOT EXISTS leaves an existing table exactly as it was, so a
// column added to the DDL exists on every fresh install and on no upgraded
// one -- and the first write naming it fails on exactly the deployments that
// have data.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/database/framework_tables.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late SqliteDVDatabaseAdapter db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dartvel_added_columns_');
    db = SqliteDVDatabaseAdapter.file('${dir.path}/app.db');
  });

  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  Future<List<String>> columnsOf(String table) async => <String>[
    for (final Map<String, Object?> row in await db.query(
      'PRAGMA table_info($table)',
    ))
      '${row['name']}',
  ];

  test('an existing table gains the column and keeps its rows', () async {
    await db.execute('CREATE TABLE things (id VARCHAR(255) PRIMARY KEY)');
    await db.execute("INSERT INTO things (id) VALUES ('a')");

    await dvEnsureFrameworkColumns(db, const <DVAddColumn>[
      DVAddColumn('things', 'tenant', type: 'TEXT'),
    ]);

    expect(await columnsOf('things'), <String>['id', 'tenant']);
    expect(await db.query('SELECT id, tenant FROM things'), <Object?>[
      <String, Object?>{'id': 'a', 'tenant': null},
    ]);
  });

  test('a column already there is left alone, however often it runs', () async {
    await db.execute(
      'CREATE TABLE things (id VARCHAR(255) PRIMARY KEY, tenant TEXT)',
    );

    for (int i = 0; i < 2; i++) {
      await dvEnsureFrameworkColumns(db, const <DVAddColumn>[
        DVAddColumn('things', 'tenant', type: 'TEXT'),
      ]);
    }

    expect(await columnsOf('things'), <String>['id', 'tenant']);
  });

  test(
    'a change that would hold the table is not run on one with rows',
    () async {
      // NOT NULL with no default cannot be given to rows that exist; the
      // planner calls it blocking, and the plan is what comes back.
      await db.execute('CREATE TABLE things (id VARCHAR(255) PRIMARY KEY)');
      await db.execute("INSERT INTO things (id) VALUES ('a')");

      await expectLater(
        dvEnsureFrameworkColumns(db, const <DVAddColumn>[
          DVAddColumn('things', 'owner', type: 'TEXT', nullable: false),
        ]),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('things'), contains('owner'), contains('1 row')),
          ),
        ),
      );
      expect(await columnsOf('things'), <String>['id']);
    },
  );

  test('a column with no type is refused before anything runs', () async {
    await db.execute('CREATE TABLE things (id VARCHAR(255) PRIMARY KEY)');

    await expectLater(
      dvEnsureFrameworkColumns(db, const <DVAddColumn>[
        DVAddColumn('things', 'tenant', type: ''),
      ]),
      throwsA(isA<DVFrameworkTableError>()),
    );
    expect(await columnsOf('things'), <String>['id']);
  });

  test('a column a server would refuse is refused here too', () async {
    await db.execute('CREATE TABLE things (id VARCHAR(255) PRIMARY KEY)');

    await expectLater(
      dvEnsureFrameworkColumns(db, const <DVAddColumn>[
        DVAddColumn('things', 'score', type: 'REAL'),
      ]),
      throwsA(isA<DVFrameworkTableError>()),
    );
    expect(await columnsOf('things'), <String>['id']);
  });
}
