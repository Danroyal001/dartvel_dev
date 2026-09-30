// Studio's documents that a build bundled from the project's studio/ files,
// seeded into a server's store when it starts.
//
// A release ships what was committed: a server started on an empty
// database has the pages, components and shortcuts the repository holds. A
// newer commit updates a document nobody changed in Studio since it was
// seeded; one somebody changed on the server is left as it is.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String _doc(String route, String text) => jsonEncode(<String, Object?>{
      'route': route,
      'title': route,
      'root': <String, Object?>{
        'id': 'root',
        'type': 'box',
        'properties': <String, Object?>{'text': text},
      },
    });

void main() {
  late MemoryDVDatabaseAdapter database;
  late DVRecordAdapter records;

  setUp(() {
    database = MemoryDVDatabaseAdapter();
    records = DVRecordAdapter.over(database);
  });

  Future<Map<String, String>> stored() async {
    await records.ensure(dvStudioPagesShape);
    return <String, String>{
      for (final Map<String, Object?> row in await records.find(dvStudioPagesTable))
        '${row['route']}': '${row['document']}',
    };
  }

  test('an empty server gets every bundled document', () async {
    final int seeded = await dvSeedStudioDocuments(database, <String>[
      _doc('/landing', 'Hello'),
      _doc('/_dartvel/components/Card', 'Card'),
    ]);
    expect(seeded, 2);
    expect((await stored()).keys, containsAll(<String>['/landing', '/_dartvel/components/Card']));
  });

  test('a newer commit updates what nobody changed in Studio, and leaves '
      'what somebody did', () async {
    await dvSeedStudioDocuments(database, <String>[
      _doc('/landing', 'Hello'),
      _doc('/about', 'About'),
    ]);
    // Somebody changes /about in Studio on the server.
    await records.delete(dvStudioPagesTable, where: DVFilter.equals('route', '/about'));
    await records.insert(dvStudioPagesTable, <String, Object?>{
      'route': '/about',
      'title': '/about',
      'document': _doc('/about', 'Changed on the server'),
    });

    await dvSeedStudioDocuments(database, <String>[
      _doc('/landing', 'Hello, from the next commit'),
      _doc('/about', 'About, from the next commit'),
    ]);
    final Map<String, String> now = await stored();
    expect(now['/landing'], contains('from the next commit'));
    expect(now['/about'], contains('Changed on the server'));
  });

  test('the same bundle twice writes nothing the second time, and a '
      'document deleted on the server stays deleted', () async {
    await dvSeedStudioDocuments(database, <String>[_doc('/landing', 'Hello')]);
    await records.delete(dvStudioPagesTable, where: DVFilter.equals('route', '/landing'));
    expect(await dvSeedStudioDocuments(database, <String>[_doc('/landing', 'Hello')]), 0);
    expect((await stored()).containsKey('/landing'), isFalse);
  });

  test('a document that is not JSON, or names no route, is skipped', () async {
    expect(await dvSeedStudioDocuments(database, <String>['{', '{"title":"x"}']), 0);
  });
}
