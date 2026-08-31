// The scheduler that runs what the cron annotations declare.
//
// @DVBackendCron and @DVClientCron generated a list of entries and nothing
// ran one. A schedule that is parsed but never fired is documentation.
//
// The behaviours under test are the ones that matter when a process is not
// running continuously -- which is always true of a client, and true of a
// backend during a deploy.
import 'package:dartvel_core/dartvel.dart' show DVCronEntry, DVCronTarget;
import 'package:dartvel_core/src/scheduling/scheduler.dart';
import 'package:test/test.dart';

DateTime at(int y, int mo, int d, int h, int mi) => DateTime(y, mo, d, h, mi);

void main() {
  late DVScheduler scheduler;
  late List<String> ran;
  late DateTime now;

  setUp(() {
    ran = <String>[];
    now = at(2026, 4, 1, 0, 0);
    scheduler = DVScheduler(clock: () => now);
  });

  test('a due task runs', () async {
    scheduler.register('nightly', '30 2 * * *', () async => ran.add('nightly'));

    now = at(2026, 4, 1, 2, 30);
    await scheduler.tick();

    expect(ran, <String>['nightly']);
  });

  test('a task that is not due does not run', () async {
    scheduler.register('nightly', '30 2 * * *', () async => ran.add('nightly'));

    now = at(2026, 4, 1, 2, 29);
    await scheduler.tick();

    expect(ran, isEmpty);
  });

  test('it does not run twice in the same minute', () async {
    // A scheduler ticking every few seconds sees the same minute repeatedly.
    // Firing on each is how a nightly email goes out twelve times.
    scheduler.register('nightly', '30 2 * * *', () async => ran.add('nightly'));

    now = at(2026, 4, 1, 2, 30);
    await scheduler.tick();
    await scheduler.tick();
    await scheduler.tick();

    expect(ran, <String>['nightly']);
  });

  test('it runs again the next day', () async {
    scheduler.register('nightly', '30 2 * * *', () async => ran.add('nightly'));

    now = at(2026, 4, 1, 2, 30);
    await scheduler.tick();
    now = at(2026, 4, 2, 2, 30);
    await scheduler.tick();

    expect(ran, <String>['nightly', 'nightly']);
  });

  test('a missed occurrence runs once when the process comes back', () async {
    // The case a client makes unavoidable: the app was closed at 02:30 and
    // opens at 09:00. Running nothing loses the work; running once per missed
    // occurrence sends four days of digests at once.
    scheduler.register('nightly', '30 2 * * *', () async => ran.add('nightly'));
    await scheduler.tick();

    now = at(2026, 4, 5, 9, 0);
    await scheduler.tick();

    expect(ran, <String>['nightly'],
        reason: 'four missed days should not send four digests');
  });

  test('catch-up can be asked for where it is wanted', () async {
    // Some work does want every occurrence -- an hourly rollup that writes a
    // row per hour. Opt in rather than default, because the default should
    // not surprise anyone with a burst.
    scheduler.register(
      'rollup',
      '0 * * * *',
      () async => ran.add('rollup'),
      catchUp: true,
    );
    await scheduler.tick();

    now = at(2026, 4, 1, 4, 0);
    await scheduler.tick();

    expect(ran.length, 4, reason: 'the four hours that were missed');
  });

  test('catch-up is bounded, so a long absence is not a stampede', () async {
    scheduler.register(
      'rollup',
      '* * * * *',
      () async => ran.add('rollup'),
      catchUp: true,
      maxCatchUp: 10,
    );
    await scheduler.tick();

    now = at(2026, 4, 3, 0, 0);
    await scheduler.tick();

    expect(ran.length, 10);
  });

  test('a task that throws does not stop the others', () async {
    // One bad job must not silence every schedule in the process.
    scheduler
      ..register('bad', '* * * * *', () async => throw StateError('boom'))
      ..register('good', '* * * * *', () async => ran.add('good'));

    now = at(2026, 4, 1, 0, 1);
    await scheduler.tick();

    expect(ran, <String>['good']);
    expect(scheduler.failures, hasLength(1));
    expect(scheduler.failures.single.name, 'bad');
  });

  test('a task that throws still runs next time', () async {
    // A failure must not disable the schedule; the next occurrence is a fresh
    // attempt.
    int attempts = 0;
    scheduler.register('flaky', '* * * * *', () async {
      attempts += 1;
      if (attempts == 1) throw StateError('boom');
      ran.add('flaky');
    });

    now = at(2026, 4, 1, 0, 1);
    await scheduler.tick();
    now = at(2026, 4, 1, 0, 2);
    await scheduler.tick();

    expect(ran, <String>['flaky']);
  });

  test('an overrunning task does not overlap itself', () async {
    // A five-minute job on a one-minute schedule. Without this the process
    // accumulates copies until it falls over.
    int running = 0;
    int maxConcurrent = 0;
    scheduler.register('slow', '* * * * *', () async {
      running += 1;
      maxConcurrent = running > maxConcurrent ? running : maxConcurrent;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      running -= 1;
    });

    now = at(2026, 4, 1, 0, 1);
    final Future<void> first = scheduler.tick();
    now = at(2026, 4, 1, 0, 2);
    final Future<void> second = scheduler.tick();
    await Future.wait(<Future<void>>[first, second]);

    expect(maxConcurrent, 1);
  });

  test('an invalid expression is refused at registration', () async {
    // Not at the first tick, hours later, in a log nobody reads.
    expect(
      () => scheduler.register('bad', 'not a cron', () async {}),
      throwsFormatException,
    );
  });

  test('a duplicate name is refused', () async {
    // Two tasks under one name means one of them silently never runs.
    scheduler.register('nightly', '@daily', () async {});
    expect(
      () => scheduler.register('nightly', '@hourly', () async {}),
      throwsArgumentError,
    );
  });

  test('the next run is reportable', () {
    scheduler.register('nightly', '30 2 * * *', () async {});
    expect(scheduler.nextRunOf('nightly'), at(2026, 4, 1, 2, 30));
  });

  test('entries can be built from the generated list', () {
    // The generated metadata is the point of the whole thing: a schedule
    // declared with @DVClientCron has to reach the scheduler without the
    // application copying the expression out by hand.
    final DVScheduler built = DVScheduler(clock: () => now)
      ..registerAll(
        const <DVCronEntry>[
          DVCronEntry(
            name: 'sync',
            cron: '*/5 * * * *',
            target: DVCronTarget.client,
            importUri: 'package:app/jobs.dart',
            filePath: 'lib/jobs.dart',
          ),
        ],
        handlers: <String, Future<void> Function()>{
          'sync': () async => ran.add('sync'),
        },
      );

    expect(built.names, <String>['sync']);
  });

  test('an entry with no handler is refused rather than skipped', () async {
    // Silently skipping is how a job appears scheduled and never runs.
    expect(
      () => DVScheduler(clock: () => now).registerAll(
        const <DVCronEntry>[
          DVCronEntry(
            name: 'sync',
            cron: '@daily',
            target: DVCronTarget.client,
            importUri: 'package:app/jobs.dart',
            filePath: 'lib/jobs.dart',
          ),
        ],
        handlers: const <String, Future<void> Function()>{},
      ),
      throwsArgumentError,
    );
  });
}
