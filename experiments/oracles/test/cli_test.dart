import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

Future<ProcessResult> dart(List<String> args) =>
    Process.run(Platform.resolvedExecutable, args);

void main() {
  // Each run compiles the analyzer from source, which takes a while.
  const slow = Timeout(Duration(minutes: 4));

  test(
    'dump then compare: identical exits 0, a changed byte exits 1',
    () async {
      final corpus = writeTree(samplePackage());
      final a = tempOut();
      final b = tempOut();
      for (final out in [a, b]) {
        final result = await dart([
          'bin/dump.dart',
          corpus,
          '--out',
          out,
          '--tool',
          'format',
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      }
      final same = await dart(['bin/compare.dart', a, b]);
      expect(same.exitCode, 0, reason: '${same.stdout}${same.stderr}');

      final changed = File(
        p.join(b, p.basename(corpus), 'lib', 'a.dart.formatted'),
      );
      changed.writeAsStringSync('${changed.readAsStringSync()} ');
      final different = await dart(['bin/compare.dart', a, b]);
      expect(different.exitCode, 1);
      expect(different.stdout, contains('lib/a.dart.formatted'));
    },
    timeout: slow,
  );

  test('bad usage exits 64', () async {
    final result = await dart(['bin/dump.dart', '--tool', 'nonsense']);
    expect(result.exitCode, 64);
    final compare = await dart(['bin/compare.dart', 'only-one']);
    expect(compare.exitCode, 64);
  }, timeout: slow);
}
