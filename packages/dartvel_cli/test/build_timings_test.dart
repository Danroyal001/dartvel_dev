import 'package:dartvel_cli/src/build/build_timings.dart';
import 'package:dartvel_cli/src/build/capture_completeness.dart' show DVCaptureRun;
import 'package:dartvel_cli/src/build/semantics_capture.dart' show dvCaptureTimesSummary;
import 'package:test/test.dart';

void main() {
  group('dvFlutterTargetTimes', () {
    test('sums the relative stamps between a target starting and completing', () {
      const String log = '''
[  +10 ms] web_templated_files: Starting due to {InvalidatedReasonKind.outputMissing: x}
[ +904 ms] web_static_assets: Starting due to {InvalidatedReasonKind.outputMissing: y}
[+1136 ms] web_static_assets: Complete
[  +16 ms] dart2wasm: Starting due to {InvalidatedReasonKind.inputChanged: z}
[  +20 ms] executing: dart compile wasm a b c
[   +9 ms] dart2js: Starting due to {InvalidatedReasonKind.inputChanged: z}
[        ] executing: dart compile js a b c
[ +258 ms] web_templated_files: Complete
[+300000 ms] dart2js: Complete
[ +2000 ms] dart2wasm: Complete
[  +1 ms] web_release_bundle: Starting due to {}
''';
      final Map<String, Duration> times = dvFlutterTargetTimes(log);
      expect(times['web_static_assets'], const Duration(milliseconds: 1136));
      expect(times['web_templated_files'], const Duration(milliseconds: 904 + 1136 + 16 + 20 + 9 + 258));
      expect(times['dart2js'], const Duration(milliseconds: 258 + 300000));
      expect(times['dart2wasm'], const Duration(milliseconds: 20 + 9 + 258 + 300000 + 2000));
      // Started and never completed: a failed build says nothing about it.
      expect(times.containsKey('web_release_bundle'), isFalse);
    });

    test('a log without stamps gives no times rather than wrong ones', () {
      expect(dvFlutterTargetTimes('Compiling lib/main.dart for the Web...\ndart2js: Complete'), isEmpty);
    });
  });

  group('DVBuildTimings', () {
    test('records each phase with its own elapsed time, also when it throws', () async {
      DateTime now = DateTime(2026);
      final DVBuildTimings timings = DVBuildTimings(clock: () => now);
      await timings.time<void>('generate', () async {
        now = now.add(const Duration(seconds: 3));
      });
      await expectLater(
        timings.time<void>('flutter build web', () async {
          now = now.add(const Duration(seconds: 7));
          throw StateError('compile failed');
        }),
        throwsStateError,
      );
      timings.add('dart2wasm', const Duration(seconds: 5), beside: true, depth: 1);
      expect(timings.phases.map((DVBuildPhase phase) => phase.name), <String>['generate', 'flutter build web', 'dart2wasm']);
      expect(timings.phases[0].elapsed, const Duration(seconds: 3));
      expect(timings.phases[1].elapsed, const Duration(seconds: 7));
      expect(timings.total, const Duration(seconds: 10));
      final List<String> table = timings.table();
      expect(table.first, startsWith('Phase'));
      expect(table, contains(matches(RegExp(r'^generate\s+3\.0$'))));
      expect(table, contains(matches(RegExp(r'^  dart2wasm\s+5\.0  \(beside\)$'))));
      expect(table.last, matches(RegExp(r'^Total\s+10\.0$')));
      expect(timings.toJson()['totalSeconds'], 10);
    });
  });

  test("the read says how many pages it kept open, the typical route and the slowest", () {
    final String summary = dvCaptureTimesSummary(
      const DVCaptureRun(
        captured: 4,
        browserAvailable: true,
        pages: 3,
        layoutTime: Duration(seconds: 8),
        routeTimes: <String, Duration>{
          "/": Duration(seconds: 2),
          "/about": Duration(seconds: 4),
          "/blog": Duration(seconds: 30),
          "/contact": Duration(seconds: 3),
        },
      ),
      reused: 5,
    );
    expect(summary, "4 read, 3 pages at once, 5 reused; median 3.0 s a route, slowest /blog 30.0 s, /about 4.0 s, /contact 3.0 s; SSR-first layout 8.0 s of 39.0 s route time");
  });
}
