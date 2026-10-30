import 'dart:convert';

import 'package:oracles/oracles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String corpus;
  late String label;

  setUpAll(() {
    corpus = writeTree(samplePackage());
    label = p.basename(corpus);
  });

  Future<Map<String, List<int>>> run() async {
    final out = tempOut();
    await dump(roots: [corpus], outDir: out, tool: DumpTool.analyze);
    return readTree(out);
  }

  List<Map<String, Object?>> diagnostics(
    Map<String, List<int>> tree,
    String file,
  ) {
    final text = utf8.decode(tree['$label/$file.diagnostics.jsonl']!);
    return [
      for (final line in const LineSplitter().convert(text))
        jsonDecode(line) as Map<String, Object?>,
    ];
  }

  test(
    'records each diagnostic with code, severity, offset, length, message',
    () async {
      final tree = await run();
      final found = diagnostics(tree, 'lib/unused.dart');
      final codes = found.map((d) => d['code']).toList();
      expect(codes, containsAll(['unused_import', 'unused_local_variable']));
      final unusedImport = found.firstWhere(
        (d) => d['code'] == 'unused_import',
      );
      final source = samplePackage()['lib/unused.dart']!;
      expect(unusedImport['offset'], source.indexOf("'dart:async'"));
      expect(unusedImport['length'], "'dart:async'".length);
      expect(unusedImport['severity'], 'warning');
      expect(unusedImport['message'], contains('dart:async'));
      expect(unusedImport.keys.toList(), [
        'offset',
        'code',
        'severity',
        'length',
        'message',
      ]);
    },
  );

  test('a clean file gets an empty diagnostics file', () async {
    final tree = await run();
    expect(tree['$label/lib/src/b.dart.diagnostics.jsonl'], isEmpty);
  });

  test('diagnostics are sorted by offset, then code', () async {
    final tree = await run();
    final found = diagnostics(tree, 'lib/broken.dart');
    expect(found.length, greaterThan(1));
    final keys = found.map((d) => (d['offset'] as int, d['code'] as String));
    final sorted = keys.toList()
      ..sort((a, b) {
        final byOffset = a.$1.compareTo(b.$1);
        return byOffset != 0 ? byOffset : a.$2.compareTo(b.$2);
      });
    expect(keys.toList(), sorted);
  });

  test('no absolute corpus path appears in any output', () async {
    // A part directive naming a missing file puts a path in the message.
    final withPath = writeTree({
      'pubspec.yaml': 'name: parts\nenvironment:\n  sdk: ^3.13.0\n',
      'lib/p.dart': "part 'missing.dart';\n",
    });
    final out = tempOut();
    await dump(roots: [withPath], outDir: out, tool: DumpTool.analyze);
    final tree = readTree(out);
    for (final entry in tree.entries) {
      expect(
        utf8.decode(entry.value),
        isNot(contains(withPath)),
        reason: entry.key,
      );
    }
  });

  test('two dumps of the same corpus are byte-identical', () async {
    final first = await run();
    final second = await run();
    expect(second.keys, first.keys);
    for (final key in first.keys) {
      expect(second[key], first[key], reason: key);
    }
  });

  test('the manifest names the analyzer and counts files', () async {
    final tree = await run();
    final manifest =
        jsonDecode(utf8.decode(tree['manifest.json']!)) as Map<String, Object?>;
    expect(manifest['tool'], 'analyze');
    expect(manifest['fileCount'], 4);
    expect(manifest['errorCount'], 0);
    final versions = manifest['toolVersions'] as Map<String, Object?>;
    expect((versions['analyzer'] as Map)['version'], isA<String>());
  });
}
