// A database that runs records and no SQL, standing in for a document engine.
//
// A framework store moved off SQL strings has to be shown to work where SQL
// does not: configured with this engine, any surface still writing SQL fails
// naming the statement, and one written against DV.Database.records works.
// That is what a project on MongoDB will see.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVMemoryRecordEngine engine;

  setUp(() => engine = DVMemoryRecordEngine());

  test('finds, orders, pages and projects records', () async {
    for (final (String route, String title) in <(String, String)>[
      ('/b', 'Bakery'),
      ('/a', 'About'),
      ('/c', 'Contact'),
    ]) {
      await engine.insert(
          'pages', <String, Object?>{'route': route, 'title': title});
    }

    final List<Map<String, Object?>> found = await engine.find(
      'pages',
      where: DVFilter.any(<DVFilter>[
        DVFilter.equals('route', '/a'),
        DVFilter.equals('route', '/c'),
      ]),
      orderBy: const <DVSort>[DVSort('title', descending: true)],
      fields: const <String>['title'],
    );
    expect(found, <Map<String, Object?>>[
      <String, Object?>{'title': 'Contact'},
      <String, Object?>{'title': 'About'},
    ]);
    expect(
        (await engine.find('pages',
                orderBy: const <DVSort>[DVSort('route')], limit: 1, offset: 1))
            .single['route'],
        '/b');
    expect(await engine.count('pages'), 3);
  });

  test('updates and deletes answer how many they changed', () async {
    await engine.insert('pages', <String, Object?>{'route': '/a', 'v': 1});

    expect(
        await engine.update('pages', <String, Object?>{'v': 2},
            where: DVFilter.all(<DVFilter>[
              DVFilter.equals('route', '/a'),
              DVFilter.equals('v', 1),
            ])),
        1);
    expect(
        await engine.update('pages', <String, Object?>{'v': 3},
            where: DVFilter.equals('v', 1)),
        0);
    expect(
        await engine.delete('pages', where: DVFilter.equals('route', '/a')), 1);
    expect(await engine.count('pages'), 0);
  });

  test('a record read back is a copy, not the stored one', () async {
    await engine.insert('pages', <String, Object?>{'route': '/a'});
    (await engine.find('pages')).single['route'] = '/changed';

    expect((await engine.find('pages')).single['route'], '/a');
  });

  test('refuses SQL, naming the statement', () async {
    await expectLater(
      engine.query('SELECT * FROM pages'),
      throwsA(isA<UnsupportedError>().having((UnsupportedError e) => e.message,
          'message', contains('SELECT * FROM pages'))),
    );
    await expectLater(
        engine.execute('DELETE FROM pages'), throwsA(isA<UnsupportedError>()));
  });

  test('is what DV.Database.records answers when configured', () {
    const DVDatabase().configure(engine);
    addTearDown(() => const DVDatabase().unconfigure());

    expect(const DVDatabase().records, same(engine));
  });
}
