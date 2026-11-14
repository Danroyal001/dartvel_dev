import 'dart:io';

import 'package:oracles/oracles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('finds only .dart files, sorted, with label-relative / paths', () {
    final root = writeTree({
      'z.dart': '',
      'a/b.dart': '',
      'a/README.md': '',
      'B.dart': '',
      'a/c.dart.txt': '',
    });
    final corpus = Corpus.discover([root]);
    final label = p.basename(root);
    expect(corpus.files.map((f) => f.relativePath).toList(), [
      '$label/B.dart',
      '$label/a/b.dart',
      '$label/z.dart',
    ]);
    expect(corpus.rootsByLabel, {label: p.normalize(p.absolute(root))});
    for (final file in corpus.files) {
      expect(p.isAbsolute(file.absolutePath), isTrue);
      expect(File(file.absolutePath).existsSync(), isTrue);
    }
  });

  test('skips hidden directories such as .dart_tool', () {
    final root = writeTree({
      'lib/a.dart': '',
      '.dart_tool/build/gen.dart': '',
      'lib/.hidden/x.dart': '',
    });
    final corpus = Corpus.discover([root]);
    expect(
      corpus.files.map((f) => f.relativePath.split('/').skip(1).join('/')),
      ['lib/a.dart'],
    );
  });

  test('two roots with the same basename get distinct labels', () {
    final parentA = writeTree({'lib/a.dart': ''});
    final parentB = writeTree({'lib/a.dart': ''});
    final corpus = Corpus.discover([
      p.join(parentA, 'lib'),
      p.join(parentB, 'lib'),
    ]);
    final paths = corpus.files.map((f) => f.relativePath).toList();
    expect(paths.toSet(), hasLength(2));
    expect(paths, ['lib/a.dart', 'lib~2/a.dart']);
  });

  test('a missing root is an error, not an empty corpus', () {
    expect(
      () => Corpus.discover(['/definitely/not/here']),
      throwsA(isA<ArgumentError>()),
    );
  });
}
