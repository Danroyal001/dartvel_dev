// The generated models' tables, applied the way a web-server binary applies
// them when it starts: on a first run against a database it has just
// created, and on every later run against the one it left.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> _notes({bool withPinned = false}) => <String, Object?>{
      'table': 'notes',
      'columns': <String>['id', 'text', if (withPinned) 'pinned'],
      'createSql': 'CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, '
          'text TEXT${withPinned ? ', pinned TEXT' : ''})',
    };

void main() {
  test('a first run creates the tables and says it did', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);

    final DVGeneratedSchemaReport report = await dvApplyGeneratedSchema(
      db,
      <Map<String, Object?>>[_notes()],
      engine: DVDatabaseEngine.sqlite,
    );

    expect(report.created, <String>['notes']);
    await db.execute("INSERT INTO notes (id, text) VALUES ('1', 'kept')");
    expect(await db.query('SELECT text FROM notes'), <Map<String, Object?>>[
      <String, Object?>{'text': 'kept'},
    ]);
  });

  test('a later run keeps the rows and adds what a model gained', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    await dvApplyGeneratedSchema(db, <Map<String, Object?>>[_notes()],
        engine: DVDatabaseEngine.sqlite);
    await db.execute("INSERT INTO notes (id, text) VALUES ('1', 'kept')");

    final DVGeneratedSchemaReport again = await dvApplyGeneratedSchema(
      db,
      <Map<String, Object?>>[_notes(withPinned: true)],
      engine: DVDatabaseEngine.sqlite,
    );

    expect(again.created, isEmpty, reason: 'the table was already there');
    expect(again.added, <String>['notes.pinned']);
    expect(await db.query('SELECT text, pinned FROM notes'),
        <Map<String, Object?>>[
      <String, Object?>{'text': 'kept', 'pinned': null},
    ]);
  });
}
