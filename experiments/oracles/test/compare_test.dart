import 'dart:io';

import 'package:oracles/oracles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String a;
  late String b;

  setUp(() async {
    final corpus = writeTree(samplePackage());
    a = tempOut();
    b = tempOut();
    await dump(roots: [corpus], outDir: a, tool: DumpTool.format);
    await dump(roots: [corpus], outDir: b, tool: DumpTool.format);
  });

  String someOutput(String dir) =>
      readTree(dir).keys.firstWhere((k) => k.endsWith('lib/a.dart.formatted'));

  test('two dumps of the same corpus compare identical', () {
    final result = compareDumps(a, b);
    expect(result.identical, isTrue);
    expect(result.differences, isEmpty);
  });

  test('a single changed byte is found, with its file and line', () {
    final relative = someOutput(b);
    final file = File(p.joinAll([b, ...relative.split('/')]));
    final bytes = file.readAsBytesSync();
    // "void main() {\n  print(1);\n}\n": change the '1' on line 2.
    final index = bytes.indexOf('1'.codeUnitAt(0));
    bytes[index] = '2'.codeUnitAt(0);
    file.writeAsBytesSync(bytes);

    final result = compareDumps(a, b);
    expect(result.identical, isFalse);
    expect(result.differences, hasLength(1));
    final difference = result.differences.single;
    expect(difference.path, relative);
    expect(difference.description, contains('line 2'));
    expect(difference.description, contains('print(1);'));
    expect(difference.description, contains('print(2);'));
  });

  test('a file only one dump has is a difference', () {
    final relative = someOutput(b);
    File(p.joinAll([b, ...relative.split('/')])).deleteSync();
    final result = compareDumps(a, b);
    expect(result.differences.map((d) => d.path), [relative]);
    expect(result.differences.single.description, contains('only in A'));
  });

  test('a difference only in trailing bytes is still found', () {
    final relative = someOutput(b);
    final file = File(p.joinAll([b, ...relative.split('/')]));
    file.writeAsStringSync('\n', mode: FileMode.append);
    final result = compareDumps(a, b);
    expect(result.differences.map((d) => d.path), [relative]);
  });

  test('refuses a directory that is not a dump', () {
    expect(
      () => compareDumps(a, writeTree({'x.txt': ''})),
      throwsA(isA<ArgumentError>()),
    );
  });
}
