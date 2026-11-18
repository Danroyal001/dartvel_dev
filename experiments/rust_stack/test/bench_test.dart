import 'dart:io';

import 'package:rust_stack_phase0/bench.dart';
import 'package:test/test.dart';

void main() {
  group('summarize', () {
    test('min, median and max of an odd count', () {
      final stats = summarize([3, 1, 2]);
      expect([stats.min, stats.median, stats.max], [1, 2, 3]);
    });

    test('the median of an even count is the mean of the middle two', () {
      expect(summarize([4, 1, 3, 2]).median, 2.5);
    });

    test('no samples is an error, not a zero', () {
      expect(() => summarize([]), throwsArgumentError);
    });
  });

  group('rssKb', () {
    test('reads VmRSS from /proc/<pid>/status', () {
      expect(rssKb('Name:\tdart\nVmHWM:\t  900 kB\nVmRSS:\t  812 kB\n'), 812);
    });

    test('a process with no VmRSS line (a zombie) has none', () {
      expect(rssKb('Name:\tdart\nState:\tZ (zombie)\n'), isNull);
    });
  });

  group('descendants', () {
    test('the whole tree under a root, the root included', () {
      final parents = {10: 1, 11: 10, 12: 11, 13: 10, 20: 1};
      expect(descendants(10, parents), {10, 11, 12, 13});
    });
  });

  group('measure', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bench_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('peak memory covers what the program really allocated', () async {
      final script = File('${dir.path}/alloc.dart')
        ..writeAsStringSync('''
import 'dart:io';
import 'dart:typed_data';
void main() {
  final block = Uint8List(150 * 1024 * 1024);
  for (var i = 0; i < block.length; i += 4096) {
    block[i] = 1;
  }
  sleep(const Duration(milliseconds: 600));
  stdout.write(block[4096]);
}
''');
      final result = await measure([Platform.resolvedExecutable, script.path]);

      expect(result.exitCode, 0);
      expect(result.peakRssKb, greaterThanOrEqualTo(150 * 1024));
      expect(result.wall, greaterThan(const Duration(milliseconds: 600)));
    });

    test(
      'memory in a child process counts, as dart analyze runs a server',
      () async {
        final script = File('${dir.path}/alloc.dart')
          ..writeAsStringSync('''
import 'dart:io';
import 'dart:typed_data';
void main() {
  final block = Uint8List(150 * 1024 * 1024);
  for (var i = 0; i < block.length; i += 4096) {
    block[i] = 1;
  }
  sleep(const Duration(milliseconds: 600));
  stdout.write(block[4096]);
}
''');
        final result = await measure([
          'sh',
          '-c',
          '"${Platform.resolvedExecutable}" "${script.path}"; true',
        ]);

        expect(result.peakRssKb, greaterThanOrEqualTo(150 * 1024));
      },
    );

    test('a failing command is reported, not measured as a success', () async {
      final result = await measure(['sh', '-c', 'exit 3']);
      expect(result.exitCode, 3);
    });
  });
}
