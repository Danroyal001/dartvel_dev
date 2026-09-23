// DVFilter.any on the database a project gets with no configuration.
//
// The record layer offers an "any" filter and the SQL engine compiles it to
// `(a = ? OR b = ?)`. The in-memory development database read a WHERE as
// conditions joined by AND and refused anything holding a parenthesis or an
// OR, so a filter the layer publishes threw on the database `dartvel dev`
// uses when a project has configured none -- named in docs/spec-status.json
// as a gap in Storage-Neutral Records.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVRecordShape _shape = DVRecordShape(
  collection: 'tickets',
  key: 'id',
  fields: <String, DVFieldType>{
    'id': DVFieldType.text,
    'state': DVFieldType.text,
    'owner': DVFieldType.text,
  },
);

Future<DVRecordAdapter> _seeded() async {
  final DVRecordAdapter records =
      DVRecordAdapter.over(MemoryDVDatabaseAdapter());
  await records.ensure(_shape);
  for (final (String id, String state, String owner) in <(String, String, String)>[
    ('1', 'open', 'ada'),
    ('2', 'closed', 'ada'),
    ('3', 'open', 'grace'),
    ('4', 'archived', 'grace'),
  ]) {
    await records.insert('tickets', <String, Object?>{
      'id': id,
      'state': state,
      'owner': owner,
    });
  }
  return records;
}

void main() {
  test('an any filter picks the records matching either side', () async {
    final DVRecordAdapter records = await _seeded();

    final List<Map<String, Object?>> found = await records.find(
      'tickets',
      where: DVFilter.any(<DVFilter>[
        DVFilter.equals('state', 'closed'),
        DVFilter.equals('state', 'archived'),
      ]),
      orderBy: const <DVSort>[DVSort('id')],
    );

    expect(<Object?>[for (final Map<String, Object?> r in found) r['id']],
        <String>['2', '4']);
  });

  test('an any nested under an all narrows it', () async {
    final DVRecordAdapter records = await _seeded();

    final List<Map<String, Object?>> found = await records.find(
      'tickets',
      where: DVFilter.all(<DVFilter>[
        DVFilter.equals('owner', 'grace'),
        DVFilter.any(<DVFilter>[
          DVFilter.equals('state', 'open'),
          DVFilter.equals('state', 'closed'),
        ]),
      ]),
    );

    expect(<Object?>[for (final Map<String, Object?> r in found) r['id']],
        <String>['3'], reason: 'grace, and open or closed');
  });

  test('counting and deleting take the same filter', () async {
    final DVRecordAdapter records = await _seeded();
    final DVFilter openOrArchived = DVFilter.any(<DVFilter>[
      DVFilter.equals('state', 'open'),
      DVFilter.equals('state', 'archived'),
    ]);

    expect(await records.count('tickets', where: openOrArchived), 3);
    expect(await records.delete('tickets', where: openOrArchived), 3);
    expect(await records.count('tickets'), 1);
  });

  test('a keyword inside a name is not a keyword', () async {
    // "actor = ?" holds an "or", and a parser that looked only at the far
    // side of the word cut the comparison in half there. Every
    // agreement-acceptance test failed at once on it.
    final DVRecordAdapter records =
        DVRecordAdapter.over(MemoryDVDatabaseAdapter());
    await records.ensure(const DVRecordShape(
      collection: 'signatures',
      key: 'actor',
      fields: <String, DVFieldType>{'actor': DVFieldType.text},
    ));
    await records.insert('signatures', <String, Object?>{'actor': 'ada'});

    expect(
      await records.find('signatures',
          where: DVFilter.equals('actor', 'ada')),
      hasLength(1),
    );
  });

  test('a value holding and or or is a value', () async {
    // The words are only keywords between comparisons. Inside quotes they
    // are somebody's company name, and breaking there reads half of it.
    final DVRecordAdapter records =
        DVRecordAdapter.over(MemoryDVDatabaseAdapter());
    await records.ensure(const DVRecordShape(
      collection: 'firms',
      key: 'name',
      fields: <String, DVFieldType>{'name': DVFieldType.text},
    ));
    await records.insert('firms', <String, Object?>{'name': 'Smith and Sons'});
    await records.insert('firms', <String, Object?>{'name': 'Or Else Ltd'});

    expect(
      await records.find('firms',
          where: DVFilter.equals('name', 'Smith and Sons')),
      hasLength(1),
    );
    expect(
      await records.find('firms', where: DVFilter.equals('name', 'Or Else Ltd')),
      hasLength(1),
    );
  });

  test('a statement the subset still does not understand is refused', () {
    // The point of the in-memory database is that it answers what it
    // understands and names what it does not. Widening it to OR must not
    // widen it to everything: a join is still refused.
    expect(
      MemoryDVDatabaseAdapter().query(
        'SELECT * FROM tickets JOIN people ON people.id = tickets.owner',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
