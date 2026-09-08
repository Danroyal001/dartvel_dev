// The kiosk dims its screen, which display.screenDim asked for and nothing
// did.
//
// A kiosk shows one attract screen for months. Burn-in is what that does to
// a panel, and the specification gives the key a duration and a comment --
// "burn-in / power; 0 disables". The parser walked past it, so a lobby
// display configured to dim never did, and the record said so.
//
// What is built is the burn-in half: after the configured idle the surface
// is darkened, and any touch or key brings it back. The power half is not
// and cannot be from here -- turning a backlight down needs a platform
// binding -- and that is said rather than implied by a feature that looks
// like it saves power and does not.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy policy({
  String? screenDim,
  String idleTimeout = '90s',
  String onIdle = 'reset',
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'session': <String, Object?>{
          'idleTimeout': idleTimeout,
          'onIdle': onIdle,
        },
        'display': <String, Object?>{
          if (screenDim != null) 'screenDim': screenDim,
        },
      },
    });

void main() {
  group('reading the key', () {
    test('a duration is a duration', () {
      expect(policy(screenDim: '5m').screenDim, const Duration(minutes: 5));
    });

    test('zero disables it, which is what the specification says', () {
      expect(policy(screenDim: '0s').screenDim, isNull);
    });

    test('a project that says nothing does not dim', () {
      expect(policy().screenDim, isNull);
    });

    test('it is no longer reported as a key nobody reads', () {
      expect(
        policy(screenDim: '30s', idleTimeout: '90s').problems.join(' '),
        isNot(contains('screenDim')),
      );
    });
  });

  group('a dim that could never happen is reported', () {
    test('dimming later than the session resets is refused', () {
      // The reset returns the kiosk to its attract route and restarts the
      // clock, so a dim set beyond the idle timeout never arrives -- ever,
      // not merely usually. Configured, accepted, and dead.
      final DVKioskPolicy p =
          policy(screenDim: '5m', idleTimeout: '90s', onIdle: 'reset');

      expect(
        p.problems.join(' '),
        allOf(contains('screenDim'), contains('idleTimeout')),
      );
    });

    test('with no idle action there is nothing to lose to', () {
      final DVKioskPolicy p =
          policy(screenDim: '5m', idleTimeout: '90s', onIdle: 'none');

      expect(p.problems.join(' '), isNot(contains('screenDim')));
    });

    test('dimming before the reset is the ordinary case', () {
      final DVKioskPolicy p =
          policy(screenDim: '30s', idleTimeout: '90s', onIdle: 'reset');

      expect(p.problems, isEmpty);
    });
  });

  group('the clock dims and wakes', () {
    late DateTime now;
    DVKioskRuntime build({String onIdle = 'reset'}) {
      now = DateTime(2026, 1, 1, 9);
      return DVKioskRuntime(
        policy(screenDim: '30s', idleTimeout: '90s', onIdle: onIdle),
        clock: () => now,
      );
    }

    test('it dims after the configured idle', () async {
      final DVKioskRuntime kiosk = build();
      addTearDown(kiosk.stop);
      await kiosk.resume();

      expect(kiosk.dimmed.value, isFalse);

      now = now.add(const Duration(seconds: 31));
      await kiosk.tick();

      expect(kiosk.dimmed.value, isTrue);
    });

    test('a touch wakes it', () async {
      final DVKioskRuntime kiosk = build();
      addTearDown(kiosk.stop);
      await kiosk.resume();
      now = now.add(const Duration(seconds: 31));
      await kiosk.tick();

      kiosk.touch();

      expect(kiosk.dimmed.value, isFalse);
    });

    test('it dims even when nothing happens on idle', () async {
      // onIdle: none used to return from the tick before anything else ran,
      // so a display that only wanted to dim never got that far.
      final DVKioskRuntime kiosk = build(onIdle: 'none');
      addTearDown(kiosk.stop);
      await kiosk.resume();

      now = now.add(const Duration(seconds: 31));
      await kiosk.tick();

      expect(kiosk.dimmed.value, isTrue);
    });

    test('a reset leaves the screen awake', () async {
      // The session went back to the attract route because somebody walked
      // away; the panel is showing that route and the clock starts again.
      final DVKioskRuntime kiosk = build();
      addTearDown(kiosk.stop);
      await kiosk.resume();
      now = now.add(const Duration(seconds: 31));
      await kiosk.tick();
      expect(kiosk.dimmed.value, isTrue);

      await kiosk.reset(DVKioskResetReason.staff);

      expect(kiosk.dimmed.value, isFalse);
    });

    test('a kiosk with no dim configured never dims', () async {
      final DVKioskRuntime kiosk = DVKioskRuntime(
        policy(idleTimeout: '90s'),
        clock: () => now,
      );
      addTearDown(kiosk.stop);
      now = DateTime(2026, 1, 1, 9);
      await kiosk.resume();

      now = now.add(const Duration(seconds: 89));
      await kiosk.tick();

      expect(kiosk.dimmed.value, isFalse);
    });
  });
}
