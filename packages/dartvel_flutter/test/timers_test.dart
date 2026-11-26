// DV.Timers: countdowns that ring, survive a reload and reach the person
// through the platform's notifications.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MemoryStore implements DVTimerStore {
  String? kept;

  @override
  String? read() => kept;

  @override
  void write(String value) => kept = value;
}

final class _RecordingDelivery implements DVTimerDelivery {
  final List<String> calls = <String>[];
  final StreamController<DVTimerAction> actionsController =
      StreamController<DVTimerAction>.broadcast(sync: true);
  DVTimerPermission answer = DVTimerPermission.granted;

  @override
  DVTimerReach get reach => DVTimerReach.whileOpen;

  @override
  Stream<DVTimerAction> get actions => actionsController.stream;

  @override
  Future<DVTimerPermission> permission() async => answer;

  @override
  Future<DVTimerPermission> requestPermission() async {
    calls.add('ask');
    return answer;
  }

  @override
  void prime() => calls.add('prime');

  @override
  Future<void> schedule(DVTimer timer) async => calls.add('schedule ${timer.id} ${timer.endsAt!.toIso8601String()}');

  @override
  Future<void> cancel(String id) async => calls.add('cancel $id');

  @override
  Future<void> ring(DVTimer timer) async => calls.add('ring ${timer.id}');

  @override
  Future<void> silence(String id) async => calls.add('silence $id');
}

void main() {
  late DateTime clock;
  late _MemoryStore store;
  late _RecordingDelivery delivery;

  DVTimers fresh() => DVTimers.forTest(store: store, delivery: delivery, now: () => clock);

  setUp(() {
    clock = DateTime.utc(2026, 11, 26, 18);
    store = _MemoryStore();
    delivery = _RecordingDelivery();
  });

  group('starting', () {
    test('a started timer runs, counts down and is kept', () async {
      final DVTimers timers = fresh();
      final DVTimer eggs = await timers.start('Boil the eggs', const Duration(minutes: 15));
      expect(eggs.label, 'Boil the eggs');
      expect(eggs.stateAt(clock), DVTimerState.running);
      expect(eggs.remainingAt(clock), const Duration(minutes: 15));
      clock = clock.add(const Duration(minutes: 4, seconds: 30));
      expect(timers.all.single.remainingAt(clock), const Duration(minutes: 10, seconds: 30));
      expect(store.kept, contains('Boil the eggs'));
      expect(delivery.calls, contains('prime'));
      expect(delivery.calls, contains('schedule ${eggs.id} 2026-11-26T18:15:00.000Z'));
      timers.dispose();
    });

    test('several run at once, soonest first', () async {
      final DVTimers timers = fresh();
      await timers.start('Rice', const Duration(minutes: 20));
      await timers.start('Plantain', const Duration(minutes: 5));
      await timers.start('Stew', const Duration(minutes: 30));
      expect(timers.all.map((DVTimer t) => t.label), <String>['Plantain', 'Rice', 'Stew']);
      timers.dispose();
    });

    test('starting a timer with an id already running gives the running one', () async {
      final DVTimers timers = fresh();
      final DVTimer first = await timers.start('Step 2', const Duration(minutes: 15), id: 'yam/2');
      clock = clock.add(const Duration(minutes: 1));
      final DVTimer again = await timers.start('Step 2', const Duration(minutes: 15), id: 'yam/2');
      expect(again.endsAt, first.endsAt);
      expect(timers.all, hasLength(1));
      timers.dispose();
    });

    test('a zero or negative duration is refused', () async {
      final DVTimers timers = fresh();
      expect(() => timers.start('Nothing', Duration.zero), throwsArgumentError);
      timers.dispose();
    });

    test('asks for notification permission once, when it has not been answered', () async {
      delivery.answer = DVTimerPermission.notAsked;
      final DVTimers timers = fresh();
      await timers.start('Eggs', const Duration(minutes: 15));
      expect(delivery.calls.where((String c) => c == 'ask'), hasLength(1));
      timers.dispose();
    });
  });

  group('ringing', () {
    test('rings once when due, and keeps ringing state until dismissed', () async {
      final DVTimers timers = fresh();
      final DVTimer eggs = await timers.start('Eggs', const Duration(minutes: 15));
      clock = clock.add(const Duration(minutes: 15));
      timers.checkDue();
      timers.checkDue();
      expect(delivery.calls.where((String c) => c == 'ring ${eggs.id}'), hasLength(1));
      expect(timers.all.single.stateAt(clock), DVTimerState.ringing);
      expect(timers.ringing, hasLength(1));
      timers.dispose();
    });

    test('snooze moves a ringing timer to now plus the snooze, and silences it', () async {
      final DVTimers timers = fresh();
      final DVTimer eggs = await timers.start('Eggs', const Duration(minutes: 15));
      clock = clock.add(const Duration(minutes: 16));
      timers.checkDue();
      await timers.snooze(eggs.id, const Duration(minutes: 5));
      final DVTimer snoozed = timers.all.single;
      expect(snoozed.stateAt(clock), DVTimerState.running);
      expect(snoozed.endsAt, clock.add(const Duration(minutes: 5)));
      expect(snoozed.alertedAt, isNull);
      expect(delivery.calls, containsAllInOrder(<String>['silence ${eggs.id}', 'schedule ${eggs.id} ${clock.add(const Duration(minutes: 5)).toIso8601String()}']));
      clock = clock.add(const Duration(minutes: 5));
      timers.checkDue();
      expect(delivery.calls.where((String c) => c == 'ring ${eggs.id}'), hasLength(2));
      timers.dispose();
    });

    test('adding time to a running timer extends it', () async {
      final DVTimers timers = fresh();
      final DVTimer rice = await timers.start('Rice', const Duration(minutes: 10));
      await timers.snooze(rice.id, const Duration(minutes: 1));
      expect(timers.all.single.remainingAt(clock), const Duration(minutes: 11));
      timers.dispose();
    });

    test('dismiss removes it, silences it and cancels the platform alarm', () async {
      final DVTimers timers = fresh();
      final DVTimer eggs = await timers.start('Eggs', const Duration(minutes: 15));
      clock = clock.add(const Duration(minutes: 15));
      timers.checkDue();
      await timers.dismiss(eggs.id);
      expect(timers.all, isEmpty);
      expect(delivery.calls, containsAll(<String>['silence ${eggs.id}', 'cancel ${eggs.id}']));
      expect(fresh().all, isEmpty, reason: 'gone after a reload too');
      timers.dispose();
    });

    test('a notification action reaches the timer it names', () async {
      final DVTimers timers = fresh();
      final DVTimer eggs = await timers.start('Eggs', const Duration(minutes: 15));
      clock = clock.add(const Duration(minutes: 15));
      timers.checkDue();
      delivery.actionsController.add(DVTimerAction(eggs.id, DVTimerActionKind.snooze, const Duration(minutes: 1)));
      await pumpEventQueue();
      expect(timers.all.single.endsAt, clock.add(const Duration(minutes: 1)));
      delivery.actionsController.add(DVTimerAction(eggs.id, DVTimerActionKind.dismiss));
      await pumpEventQueue();
      expect(timers.all, isEmpty);
      timers.dispose();
    });
  });

  group('pausing', () {
    test('a paused timer keeps what was left and resumes from it', () async {
      final DVTimers timers = fresh();
      final DVTimer stew = await timers.start('Stew', const Duration(minutes: 30));
      clock = clock.add(const Duration(minutes: 10));
      await timers.pause(stew.id);
      expect(delivery.calls, contains('cancel ${stew.id}'));
      clock = clock.add(const Duration(hours: 1));
      expect(timers.all.single.stateAt(clock), DVTimerState.paused);
      expect(timers.all.single.remainingAt(clock), const Duration(minutes: 20));
      timers.checkDue();
      expect(delivery.calls.where((String c) => c.startsWith('ring')), isEmpty);
      await timers.resume(stew.id);
      expect(timers.all.single.endsAt, clock.add(const Duration(minutes: 20)));
      timers.dispose();
    });
  });

  group('surviving a reload', () {
    test('a running timer comes back and rings at its time', () async {
      final DVTimers before = fresh();
      final DVTimer eggs = await before.start('Eggs', const Duration(minutes: 15));
      before.dispose();
      clock = clock.add(const Duration(minutes: 5));
      final DVTimers after = fresh();
      expect(after.all.single.id, eggs.id);
      expect(after.all.single.remainingAt(clock), const Duration(minutes: 10));
      clock = clock.add(const Duration(minutes: 10));
      after.checkDue();
      expect(delivery.calls, contains('ring ${eggs.id}'));
      after.dispose();
    });

    test('one that fell due while closed rings on load, once', () async {
      final DVTimers before = fresh();
      await before.start('Eggs', const Duration(minutes: 15));
      before.dispose();
      clock = clock.add(const Duration(minutes: 40));
      final DVTimers after = fresh();
      after.checkDue();
      expect(after.ringing, hasLength(1));
      expect(after.ringing.single.overdueAt(clock), const Duration(minutes: 25));
      after.dispose();
      final DVTimers third = fresh();
      third.checkDue();
      expect(delivery.calls.where((String c) => c.startsWith('ring')), hasLength(1),
          reason: 'it rang already; a second reload shows it, quietly');
      third.dispose();
    });

    test('a damaged store reads as no timers, not as an error', () {
      store.kept = '{"timers": [{"id": 3}, "nonsense"]}';
      expect(fresh().all, isEmpty);
      store.kept = 'not json';
      expect(fresh().all, isEmpty);
    });
  });

  group('changes', () {
    test('every change is announced to listeners', () async {
      final DVTimers timers = fresh();
      final List<int> counts = <int>[];
      final StreamSubscription<List<DVTimer>> listening =
          timers.changes.listen((List<DVTimer> all) => counts.add(all.length));
      final DVTimer eggs = await timers.start('Eggs', const Duration(minutes: 15));
      await timers.dismiss(eggs.id);
      await pumpEventQueue();
      expect(counts, <int>[1, 0]);
      await listening.cancel();
      timers.dispose();
    });
  });

  group('words', () {
    test('the clock reads minutes and seconds, and hours when there are any', () {
      expect(dvTimerClock(const Duration(minutes: 14, seconds: 5)), '14:05');
      expect(dvTimerClock(const Duration(seconds: 9)), '0:09');
      expect(dvTimerClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(dvTimerClock(const Duration(milliseconds: 14999)), '0:15', reason: 'a countdown rounds up');
    });

    test('the spoken countdown changes rarely, so a screen reader is not flooded', () {
      expect(dvTimerSpoken(const Duration(minutes: 14, seconds: 59)), '15 minutes left');
      expect(dvTimerSpoken(const Duration(minutes: 14, seconds: 1)), '15 minutes left');
      expect(dvTimerSpoken(const Duration(minutes: 1, seconds: 1)), '2 minutes left');
      expect(dvTimerSpoken(const Duration(seconds: 59)), '1 minute left');
      expect(dvTimerSpoken(const Duration(seconds: 30)), '30 seconds left');
      expect(dvTimerSpoken(const Duration(seconds: 29)), '30 seconds left');
      expect(dvTimerSpoken(const Duration(seconds: 10)), '10 seconds left');
      expect(dvTimerSpoken(const Duration(seconds: 3)), '10 seconds left');
      expect(dvTimerSpoken(Duration.zero), 'Done');
      expect(dvTimerSpoken(const Duration(hours: 1, minutes: 30)), '1 hour 30 minutes left');
    });

    test('a short phrase names a duration', () {
      expect(dvTimerLength(const Duration(minutes: 15)), '15 min');
      expect(dvTimerLength(const Duration(seconds: 90)), '1 min 30 s');
      expect(dvTimerLength(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
    });
  });

  group('DVTimerCountdown', () {
    testWidgets('shows the clock and speaks the coarse phrase politely', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final DVTimer timer = DVTimer(
        id: 'a',
        label: 'Eggs',
        duration: const Duration(minutes: 15),
        endsAt: clock.add(const Duration(minutes: 14, seconds: 5)),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: DVTimerCountdown(timer, now: clock),
      ));
      expect(find.text('14:05'), findsOneWidget);
      final SemanticsNode live = tester.getSemantics(find.byType(DVTimerCountdown));
      final SemanticsData data = live.getSemanticsData();
      expect(data.label, contains('Eggs, 15 minutes left'));
      expect(data.flagsCollection.isLiveRegion, isTrue);
      expect(data.label, isNot(contains('14:05')), reason: 'the ticking digits are not read out');
      semantics.dispose();
    });
  });
}
