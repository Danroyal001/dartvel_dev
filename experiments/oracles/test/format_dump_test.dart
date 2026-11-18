import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:oracles/oracles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String corpus;
  late String label;

  setUp(() {
    corpus = writeTree(samplePackage());
    label = p.basename(corpus);
  });

  Future<Map<String, List<int>>> run({String? languageVersion}) async {
    final out = tempOut();
    await dump(
      roots: [corpus],
      outDir: out,
      tool: DumpTool.format,
      languageVersion: languageVersion,
    );
    return readTree(out);
  }

  test('writes the formatter output per file at a relative path', () async {
    final tree = await run();
    expect(
      utf8.decode(tree['$label/lib/a.dart.formatted']!),
      'void main() {\n  print(1);\n}\n',
    );
    expect(
      utf8.decode(tree['$label/lib/src/b.dart.formatted']!),
      'int f(int x) => x + 1;\n',
    );
  });

  test('a file that does not parse is recorded, not fatal', () async {
    final tree = await run();
    expect(tree.containsKey('$label/lib/broken.dart.formatted'), isFalse);
    final error = utf8.decode(tree['$label/lib/broken.dart.format-error']!);
    expect(error, contains('Could not format'));
    // The file is named relative to the corpus, never by absolute path.
    expect(error, contains('$label/lib/broken.dart'));
    expect(error, isNot(contains(corpus)));
    // Everything else was still formatted.
    expect(tree.containsKey('$label/lib/unused.dart.formatted'), isTrue);
  });

  test('two dumps of the same corpus are byte-identical', () async {
    final first = await run();
    final second = await run();
    expect(second.keys, first.keys);
    for (final key in first.keys) {
      expect(second[key], first[key], reason: key);
    }
  });

  test('the manifest records the run and no machine-specific path', () async {
    final tree = await run();
    final text = utf8.decode(tree['manifest.json']!);
    expect(text, isNot(contains(corpus)));
    expect(text, isNot(contains(Directory.systemTemp.path)));
    final manifest = jsonDecode(text) as Map<String, Object?>;
    expect(manifest['tool'], 'format');
    expect(manifest['corpusRoots'], [label]);
    expect(manifest['fileCount'], 4);
    expect(manifest['errorCount'], 1);
    expect(manifest['dartSdk'], Platform.version.split(' ').first);
    final versions = manifest['toolVersions'] as Map<String, Object?>;
    expect((versions['dart_style'] as Map)['version'], isA<String>());
  });

  test('the manifest hashes every output file and the whole dump', () async {
    final tree = await run();
    final manifest =
        jsonDecode(utf8.decode(tree['manifest.json']!)) as Map<String, Object?>;
    final files = (manifest['files'] as List).cast<Map<String, Object?>>();
    final outputs = tree.keys.where((k) => k != 'manifest.json').toList();
    expect(files.map((f) => f['output']).toList(), outputs);
    final lines = StringBuffer();
    for (final entry in files) {
      final output = entry['output'] as String;
      final hash = sha256.convert(tree[output]!).toString();
      expect(entry['sha256'], hash, reason: output);
      lines.write('$output\t$hash\n');
    }
    expect(
      manifest['overallSha256'],
      sha256.convert(utf8.encode(lines.toString())).toString(),
    );
  });

  test('language version comes from the package pubspec', () async {
    // Before 3.7 the formatter used the short style, which keeps this
    // trailing comma's argument list split one per line.
    final old = writeTree({
      'pubspec.yaml': 'name: old\nenvironment:\n  sdk: ">=2.19.0 <3.0.0"\n',
      'lib/c.dart': 'var x = f(1,);\n',
    });
    final out = tempOut();
    await dump(roots: [old], outDir: out, tool: DumpTool.format);
    final tree = readTree(out);
    final oldLabel = p.basename(old);
    expect(
      utf8.decode(tree['$oldLabel/lib/c.dart.formatted']!),
      'var x = f(\n  1,\n);\n',
    );
    final manifest =
        jsonDecode(utf8.decode(tree['manifest.json']!)) as Map<String, Object?>;
    final entry = (manifest['files'] as List).single as Map;
    expect(entry['languageVersion'], '2.19');
  });

  test('a fixed language version overrides the pubspec', () async {
    final tree = await run(languageVersion: '3.6');
    final manifest =
        jsonDecode(utf8.decode(tree['manifest.json']!)) as Map<String, Object?>;
    final versions = (manifest['files'] as List)
        .map((e) => (e as Map)['languageVersion'])
        .toSet();
    expect(versions, {'3.6'});
  });

  test('page width and trailing commas come from analysis_options', () async {
    // 89 columns: split at the default width of 80, kept whole at 100.
    const longLine =
        'var x = f(aaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbb, cccccccccccccccccccc, ddddddddddd);\n';
    final files = {
      'pubspec.yaml': 'name: wide\nenvironment:\n  sdk: ^3.13.0\n',
      'lib/long.dart': longLine,
      'lib/comma.dart': 'var y = f(1,);\n',
    };
    final plain = writeTree(files);
    final configured = writeTree({
      ...files,
      'analysis_options.yaml':
          'formatter:\n  page_width: 100\n  trailing_commas: preserve\n',
    });

    Future<Map<String, String>> formatted(String corpus) async {
      final out = tempOut();
      await dump(roots: [corpus], outDir: out, tool: DumpTool.format);
      final tree = readTree(out);
      final label = p.basename(corpus);
      final manifest = jsonDecode(utf8.decode(tree['manifest.json']!)) as Map;
      final entry = (manifest['files'] as List).first as Map;
      return {
        'long': utf8.decode(tree['$label/lib/long.dart.formatted']!),
        'comma': utf8.decode(tree['$label/lib/comma.dart.formatted']!),
        'pageWidth': '${entry['pageWidth']}',
        'trailingCommas': '${entry['trailingCommas']}',
      };
    }

    final defaults = await formatted(plain);
    expect(defaults['long'], isNot(longLine));
    expect(defaults['comma'], 'var y = f(1);\n');
    expect(defaults['pageWidth'], '80');
    expect(defaults['trailingCommas'], 'automate');

    final wide = await formatted(configured);
    expect(wide['long'], longLine);
    expect(wide['comma'], 'var y = f(\n  1,\n);\n');
    expect(wide['pageWidth'], '100');
    expect(wide['trailingCommas'], 'preserve');
  });

  test('replaces a previous dump but refuses a non-dump directory', () async {
    final out = tempOut();
    await dump(roots: [corpus], outDir: out, tool: DumpTool.format);
    File(p.join(out, 'stale.txt')).writeAsStringSync('stale');
    await dump(roots: [corpus], outDir: out, tool: DumpTool.format);
    expect(File(p.join(out, 'stale.txt')).existsSync(), isFalse);

    final notADump = writeTree({'keep.txt': 'mine'});
    await expectLater(
      dump(roots: [corpus], outDir: notADump, tool: DumpTool.format),
      throwsA(isA<StateError>()),
    );
    expect(File(p.join(notADump, 'keep.txt')).existsSync(), isTrue);
  });
}
