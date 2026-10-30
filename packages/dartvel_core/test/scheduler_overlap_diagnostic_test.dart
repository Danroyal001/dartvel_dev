// DV-CRON-003: a run was skipped because the previous one was still running.
//
// The scheduler already refuses to start a second copy of a task that is
// still in flight -- a five-minute job on a one-minute schedule would
// otherwise pile up copies -- and it did so in silence, so a schedule that
// quietly ran half as often as declared looked exactly like one that ran.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late List<(String, String)> reported;
  late DVScheduler scheduler;
  late Completer<void> release;
  late int runs;

  setUp(() {
    now = DateTime.utc(2026, 10, 30, 12, 0, 30);
    reported = <(String, String)>[];
    release = Completer<void>();
    runs = 0;
    scheduler = DVScheduler(
      clock: () => now,
      onDiagnostic: (String code, String message) =>
          reported.add((code, message)),
    );
    scheduler.register('rollup', '* * * * *', () async {
      runs++;
      await release.future;
    });
  });

  test('a tick that finds the task still running reports DV-CRON-003',
      () async {
    now = now.add(const Duration(minutes: 1));
    final Future<void> first = scheduler.tick();
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1);

    now = now.add(const Duration(minutes: 1));
    await scheduler.tick();

    expect(runs, 1);
    expect(reported.map(((String, String) r) => r.$1), <String>['DV-CRON-003']);
    expect(reported.single.$2, contains('rollup'));
    release.complete();
    await first;
  });

  test('reported once per occurrence, however often it ticks', () async {
    now = now.add(const Duration(minutes: 1));
    final Future<void> first = scheduler.tick();
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(minutes: 1));
    await scheduler.tick();
    now = now.add(const Duration(seconds: 10));
    await scheduler.tick();
    now = now.add(const Duration(seconds: 10));
    await scheduler.tick();
    expect(reported, hasLength(1));

    now = now.add(const Duration(minutes: 1));
    await scheduler.tick();
    expect(reported, hasLength(2));
    release.complete();
    await first;
  });

  test('nothing is reported when nothing overlaps', () async {
    release.complete();
    now = now.add(const Duration(minutes: 1));
    await scheduler.tick();
    now = now.add(const Duration(minutes: 1));
    await scheduler.tick();
    expect(runs, 2);
    expect(reported, isEmpty);
  });

  test('the registry has DV-CRON-003 at debug', () {
    expect(DVDiagnostics.find('DV-CRON-003')?.level, 'debug');
  });
}
