// Chunking a file for a resumable import.
//
// The generated chunker split every line into chunks and attached none of them
// to a header. For CSV that is two bugs at once: chunk 0 carries the header
// row as if it were a record, and chunks 1..n carry no headers at all, so a
// worker has no way to map a column to a field. Resumable CSV import could not
// work, and nothing said so -- the tests asserted the method's signature.
//
// One implementation, here, so the generator emits a call rather than a copy.
import 'package:dartvel_core/src/data/import_chunking.dart';
import 'package:test/test.dart';

const String _csv = '''
id,name
1,Ada
2,Grace
3,Alan
''';

void main() {
  group('csv', () {
    test('the header is read once and not imported as a row', () {
      final List<DVImportChunkPlan> chunks =
          dvChunkImportRows(_csv, chunkSize: 2, hasHeader: true);

      expect(chunks, hasLength(2));
      expect(chunks.first.rows, <String>['1,Ada', '2,Grace']);
      expect(chunks.last.rows, <String>['3,Alan']);
    });

    test('every chunk carries the header, not just the first', () {
      // The bug that made resumable CSV impossible: a worker handed chunk 2
      // has no column order and cannot build a record.
      final List<DVImportChunkPlan> chunks =
          dvChunkImportRows(_csv, chunkSize: 2, hasHeader: true);

      for (final DVImportChunkPlan chunk in chunks) {
        expect(chunk.header, 'id,name');
      }
    });

    test('startRow points at the source line, so an error names it', () {
      // 1-based and counting the header, because that is what a person sees
      // when they open the file to fix the row the report named.
      final List<DVImportChunkPlan> chunks =
          dvChunkImportRows(_csv, chunkSize: 2, hasHeader: true);

      expect(chunks.first.startRow, 2);
      expect(chunks.last.startRow, 4);
    });

    test('a file with only a header produces no chunks', () {
      // Not one empty chunk. A worker handed nothing to do is a job dispatched
      // for no reason.
      expect(
        dvChunkImportRows('id,name\n', chunkSize: 10, hasHeader: true),
        isEmpty,
      );
    });
  });

  group('ndjson', () {
    test('there is no header, and the first line is data', () {
      final List<DVImportChunkPlan> chunks = dvChunkImportRows(
        '{"a":1}\n{"a":2}\n',
        chunkSize: 10,
        hasHeader: false,
      );

      expect(chunks.single.header, isNull);
      expect(chunks.single.rows, <String>['{"a":1}', '{"a":2}']);
      expect(chunks.single.startRow, 1);
    });
  });

  group('the parts that are easy to get wrong', () {
    test('blank lines are dropped rather than imported as empty records', () {
      final List<DVImportChunkPlan> chunks = dvChunkImportRows(
        'id\n\n1\n   \n2\n',
        chunkSize: 10,
        hasHeader: true,
      );
      expect(chunks.single.rows, <String>['1', '2']);
    });

    test('a chunk size larger than the file is one chunk', () {
      expect(
        dvChunkImportRows(_csv, chunkSize: 1000, hasHeader: true).single.rows,
        hasLength(3),
      );
    });

    test('an empty file produces nothing', () {
      expect(dvChunkImportRows('', chunkSize: 10, hasHeader: true), isEmpty);
      expect(dvChunkImportRows('', chunkSize: 10, hasHeader: false), isEmpty);
    });

    test('a non-positive chunk size is refused', () {
      // Zero would loop forever, and negative would throw somewhere less
      // obvious than here.
      expect(() => dvChunkImportRows(_csv, chunkSize: 0, hasHeader: true),
          throwsArgumentError);
      expect(() => dvChunkImportRows(_csv, chunkSize: -1, hasHeader: true),
          throwsArgumentError);
    });

    test('every row appears exactly once across the chunks', () {
      // The property a chunker exists for. An off-by-one in the stride drops
      // or duplicates records, and a duplicated record is worse than a
      // dropped one because it inserts.
      final String rows = List<String>.generate(
        97,
        (int i) => 'row$i',
      ).join('\n');

      final List<DVImportChunkPlan> chunks =
          dvChunkImportRows('header\n$rows', chunkSize: 10, hasHeader: true);

      final List<String> seen = <String>[
        for (final DVImportChunkPlan chunk in chunks) ...chunk.rows,
      ];
      expect(seen, hasLength(97));
      expect(seen.toSet(), hasLength(97));
      expect(seen.first, 'row0');
      expect(seen.last, 'row96');
    });

    test('windows line endings do not leave a stray carriage return', () {
      // A \r left on the end of the last field silently becomes part of the
      // value, so "Ada\r" is imported and never matches "Ada".
      final List<DVImportChunkPlan> chunks =
          dvChunkImportRows('id,name\r\n1,Ada\r\n', chunkSize: 10, hasHeader: true);

      expect(chunks.single.header, 'id,name');
      expect(chunks.single.rows, <String>['1,Ada']);
    });
  });
}
