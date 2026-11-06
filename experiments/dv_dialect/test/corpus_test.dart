import 'dart:io';

import 'package:dv_dialect/corpus.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_corpus_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  test('one file: counts the semicolons it removed and the ones it kept', () {
    final result = roundTrip('void f() {\n  a(); b();\n}\n');

    expect(result.identical, isTrue);
    expect(result.semicolons, 2);
    expect(result.removed, 1);
  });

  test('a construct insertion cannot represent fails, at its line', () {
    // A call whose arguments start on the next line: insertion reads the
    // ( as a new statement.
    final result = roundTrip('void f() {\n  g\n  (1);\n}\n');

    expect(result.identical, isFalse);
    expect(result.firstDifferenceLine, 2);
  });

  test('a corpus: totals, failures with their place, and unparsable files '
      'counted apart', () {
    write('lib/ok.dart', 'int x = 1;\nint y = 2;\n');
    write('lib/split_call.dart', 'void f() {\n  g\n  (1);\n}\n');
    write('lib/broken.dart', 'void f( {');
    write('lib/notes.md', 'not dart');
    write('.dart_tool/gen.dart', 'int z = 3;\n');

    final report = roundTripCorpus([root]);

    expect(report.files, 2);
    expect(report.identical, 1);
    expect(report.notStandard, 1);
    expect(report.failures.single.path, endsWith('lib/split_call.dart'));
    expect(report.failures.single.line, 2);
    expect(report.semicolons, 3);
    expect(report.removed, 3);
  });
}
