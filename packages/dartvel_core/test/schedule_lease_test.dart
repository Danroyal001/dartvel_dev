// A schedule fires once per cluster, not once per process.
//
// Two processes that both tick the schedules -- two cron units after a
// botched deploy, or the old cron process still draining while the new one
// starts -- each see the same occurrence come due, and each runs it. Nothing
// throws: the nightly invoice run simply happens twice. So these run two
// schedulers against one shared store with one fake clock, and count what
// the handler did, with the unguarded pair as the control that proves the
// count can go wrong.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A store two schedulers share, with the compare-and-set a distributed
/// cache gives. Single-isolate Dart makes the check-then-write atomic.
class SharedStore implements DVAtomicCacheAdapter {
  SharedStore(this.now);

  final DateTime Function() now;
  final Map<String, ({Object? value, DateTime? expiresAt})> entries =
      <String, ({Object? value, DateTime? expiresAt})>{};
  bool failing = false;

  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async {
    if (failing) throw StateError('store unreachable');
    final existing = entries[key];
    if (existing != null &&
        (existing.expiresAt == null || now().isBefore(existing.expiresAt!))) {
      return false;
    }
    entries[key] = (
      value: value,
      expiresAt: ttl == null ? null : now().add(ttl),
    );
    return true;
  }
}

void main() {
  late DateTime now;
  late List<String> ran;
  late SharedStore store;

  DVScheduler process({DVScheduleLease? lease}) {
    final DVScheduler scheduler = DVScheduler(clock: () => now, lease: lease)
      ..register('invoices', '0 3 * * *', () async => ran.add('invoices'));
    return scheduler;
  }

  setUp(() {
    now = DateTime.utc(2026, 9, 1, 2, 59);
    ran = <String>[];
    store = SharedStore(() => now);
  });

  test(
    'without a lease two processes fire the same occurrence twice',
    () async {
      // The control. If this ever reads once, the test below proves nothing.
      final DVScheduler a = process();
      final DVScheduler b = process();
      now = DateTime.utc(2026, 9, 1, 3, 0);
      await Future.wait(<Future<void>>[a.tick(), b.tick()]);
      expect(ran, <String>['invoices', 'invoices']);
    },
  );

  test('with a shared lease the occurrence fires once', () async {
    final DVScheduler a = process(lease: DVCacheScheduleLease(store));
    final DVScheduler b = process(lease: DVCacheScheduleLease(store));
    now = DateTime.utc(2026, 9, 1, 3, 0);
    await Future.wait(<Future<void>>[a.tick(), b.tick()]);
    // And ticking again within the minute is still once, on both.
    await Future.wait(<Future<void>>[a.tick(), b.tick()]);
    expect(ran, <String>['invoices']);
  });

  test(
    'the next occurrence fires once again, whichever process wins it',
    () async {
      final DVScheduler a = process(lease: DVCacheScheduleLease(store));
      final DVScheduler b = process(lease: DVCacheScheduleLease(store));
      now = DateTime.utc(2026, 9, 1, 3, 0, 20);
      await Future.wait(<Future<void>>[a.tick(), b.tick()]);
      now = DateTime.utc(2026, 9, 2, 3, 0, 20);
      await Future.wait(<Future<void>>[b.tick(), a.tick()]);
      expect(ran, <String>['invoices', 'invoices']);
    },
  );

  test(
    'a process ticking late does not re-run what another already ran',
    () async {
      final DVScheduler a = process(lease: DVCacheScheduleLease(store));
      final DVScheduler b = process(lease: DVCacheScheduleLease(store));
      now = DateTime.utc(2026, 9, 1, 3, 0, 1);
      await a.tick();
      // b's timer lands 19 seconds later, the same occurrence still due for it.
      now = DateTime.utc(2026, 9, 1, 3, 0, 20);
      await b.tick();
      expect(ran, <String>['invoices']);
    },
  );

  test('one instant is one claim, however a process spells it', () async {
    // The lease names the instant, so a process whose clock hands it local
    // DateTimes and one handing it UTC ones claim the same key for one run.
    // A key built from the spelling would give "03:05:00.000" and
    // "03:05:00.000Z" two claims, even on a host whose zone is UTC.
    final DVScheduleLease a = DVCacheScheduleLease(store);
    final DVScheduleLease b = DVCacheScheduleLease(store);
    final DateTime instant = DateTime.utc(2026, 9, 1, 3, 5);
    expect(await a.claim('sweep', instant), isTrue);
    expect(await b.claim('sweep', instant.toLocal()), isFalse);
  });

  test(
    'catch-up claims each occurrence, so a pair still runs each once',
    () async {
      final DVScheduler a =
          DVScheduler(clock: () => now, lease: DVCacheScheduleLease(store))
            ..register(
              'rollup',
              '0 * * * *',
              () async => ran.add('a'),
              catchUp: true,
            );
      final DVScheduler b =
          DVScheduler(clock: () => now, lease: DVCacheScheduleLease(store))
            ..register(
              'rollup',
              '0 * * * *',
              () async => ran.add('b'),
              catchUp: true,
            );
      now = DateTime.utc(2026, 9, 1, 6, 0);
      await Future.wait(<Future<void>>[a.tick(), b.tick()]);
      // 03:00, 04:00, 05:00 and 06:00 came due since 02:59.
      expect(ran, hasLength(4));
    },
  );

  test('a lease that cannot be claimed runs nothing and says so', () async {
    // Running unguarded when the store is down is the double fire this is
    // here to prevent; skipping and recording the failure is the other
    // choice, and the only one that is visible.
    final DVScheduler a = process(lease: DVCacheScheduleLease(store));
    store.failing = true;
    now = DateTime.utc(2026, 9, 1, 3, 0);
    await a.tick();
    expect(ran, isEmpty);
    expect(a.failures.single.name, 'invoices');
    expect('${a.failures.single.error}', contains('store unreachable'));
  });

  test('two schedules sharing an occurrence do not share a claim', () async {
    final DVScheduleLease lease = DVCacheScheduleLease(store);
    final DVScheduler a = DVScheduler(clock: () => now, lease: lease)
      ..register('one', '0 3 * * *', () async => ran.add('one'))
      ..register('two', '0 3 * * *', () async => ran.add('two'));
    now = DateTime.utc(2026, 9, 1, 3, 0);
    await a.tick();
    expect(ran, unorderedEquals(<String>['one', 'two']));
  });
}
