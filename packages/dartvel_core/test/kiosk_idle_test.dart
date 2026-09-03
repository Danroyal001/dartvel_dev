// The kiosk session's clock: idle detection, the countdown, and the reset.
//
// A kiosk is left mid-task by someone who walks away. The runtime notices
// the silence, warns for the declared span, and then resets the session --
// clearing what the policy says to clear and sending the app home -- or just
// sends it home, or does nothing, as the policy says. Time is the injected
// clock and the runtime's own tick(), so every case here is deterministic;
// one test checks the periodic timer actually drives tick().
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy policy({String onIdle = 'reset', List<String> clear = const <String>['signals', 'forms']}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'session': <String, Object?>{
          'idleTimeout': '60s',
          'idleWarning': '10s',
          'onIdle': onIdle,
          'clearOnReset': clear,
        },
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  late DateTime now;
  late List<Set<DVKioskClearable>> cleared;
  late List<DVKioskReset> resets;

  DVKioskRuntime runtime(DVKioskPolicy p) {
    final DVKioskRuntime r = DVKioskRuntime(
      p,
      clock: () => now,
      clear: (Set<DVKioskClearable> what) async => cleared.add(what),
    );
    r.resets.listen(resets.add);
    return r;
  }

  setUp(() {
    now = DateTime.utc(2026, 9, 3, 12);
    cleared = <Set<DVKioskClearable>>[];
    resets = <DVKioskReset>[];
  });

  Future<void> pass(DVKioskRuntime r, Duration d) async {
    now = now.add(d);
    await r.tick();
  }

  test('nothing happens while someone is using it', () async {
    final DVKioskRuntime r = runtime(policy());
    await r.resume();
    for (int i = 0; i < 10; i++) {
      await pass(r, const Duration(seconds: 40));
      r.touch();
    }
    expect(r.countdown.value, isNull);
    expect(resets, isEmpty);
    r.stop();
  });

  test('the countdown starts idleWarning before the timeout and counts down', () async {
    final DVKioskRuntime r = runtime(policy());
    await r.resume();
    await pass(r, const Duration(seconds: 49));
    expect(r.countdown.value, isNull);
    await pass(r, const Duration(seconds: 1));
    expect(r.countdown.value, const Duration(seconds: 10));
    await pass(r, const Duration(seconds: 4));
    expect(r.countdown.value, const Duration(seconds: 6));
    expect(resets, isEmpty, reason: 'warned, not yet reset');
    r.stop();
  });

  test('touching during the countdown cancels it', () async {
    final DVKioskRuntime r = runtime(policy());
    await r.resume();
    await pass(r, const Duration(seconds: 55));
    expect(r.countdown.value, isNotNull);
    r.touch();
    await r.tick();
    expect(r.countdown.value, isNull);
    await pass(r, const Duration(seconds: 30));
    expect(resets, isEmpty);
    r.stop();
  });

  test('at the timeout, onIdle: reset clears what the policy says and goes home', () async {
    final DVKioskRuntime r = runtime(policy());
    await r.resume();
    await pass(r, const Duration(seconds: 60));

    expect(cleared, <Set<DVKioskClearable>>[<DVKioskClearable>{DVKioskClearable.signals, DVKioskClearable.forms}]);
    expect(resets, hasLength(1));
    expect(resets.single.reason, DVKioskResetReason.idle);
    expect(resets.single.home, '/welcome');
    expect(resets.single.cleared, cleared.single);
    expect(r.state.value, DVKioskState.active, reason: 'back in service');
    expect(r.countdown.value, isNull);

    // The clock restarts with the reset: no second reset a tick later.
    await pass(r, const Duration(seconds: 1));
    expect(resets, hasLength(1));
    r.stop();
  });

  test('onIdle: home goes home and clears nothing', () async {
    final DVKioskRuntime r = runtime(policy(onIdle: 'home'));
    await r.resume();
    await pass(r, const Duration(seconds: 60));
    expect(cleared, isEmpty);
    expect(resets.single.cleared, isEmpty);
    expect(resets.single.home, '/welcome');
    r.stop();
  });

  test('onIdle: none does nothing, and the countdown is not shown either', () async {
    final DVKioskRuntime r = runtime(policy(onIdle: 'none'));
    await r.resume();
    await pass(r, const Duration(seconds: 55));
    expect(r.countdown.value, isNull);
    await pass(r, const Duration(seconds: 10));
    expect(resets, isEmpty);
    r.stop();
  });

  test('staff mode has no idle clock', () async {
    final DVKioskRuntime r = DVKioskRuntime(
      policy(),
      clock: () => now,
      readSecret: (String _) async => '4821',
      clear: (Set<DVKioskClearable> what) async => cleared.add(what),
    );
    r.resets.listen(resets.add);
    await r.resume();
    expect((await r.exit(const DVKioskExitRequest.pin('4821'))).granted, isTrue);
    await pass(r, const Duration(minutes: 5));
    expect(resets, isEmpty);
    expect(r.countdown.value, isNull);
    r.stop();
  });

  test('an explicit reset does the same as an idle one, now', () async {
    final DVKioskRuntime r = runtime(policy());
    await r.resume();
    final DVKioskReset reset = await r.reset(DVKioskResetReason.explicit);
    expect(reset.reason, DVKioskResetReason.explicit);
    expect(cleared, hasLength(1));
    expect(r.state.value, DVKioskState.active);
    r.stop();
  });

  test('a failing clear leaves the kiosk failed, not silently half-reset', () async {
    final DVKioskRuntime r = DVKioskRuntime(
      policy(),
      clock: () => now,
      clear: (Set<DVKioskClearable> _) async => throw StateError('store down'),
    );
    await r.resume();
    await expectLater(r.reset(DVKioskResetReason.explicit), throwsStateError);
    expect(r.state.value, DVKioskState.failed);
    r.stop();
  });

  test('the periodic timer drives tick() on its own', () async {
    final DVKioskRuntime r = DVKioskRuntime(
      policy(),
      clock: () => now,
      tickEvery: const Duration(milliseconds: 10),
      clear: (Set<DVKioskClearable> what) async => cleared.add(what),
    );
    r.resets.listen(resets.add);
    await r.resume();
    now = now.add(const Duration(seconds: 61));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(resets, hasLength(1));
    r.stop();
    now = now.add(const Duration(seconds: 61));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(resets, hasLength(1), reason: 'stopped means stopped');
  });
}
