// The kiosk policy: what a declaration means, and what it refuses to mean.
//
// A kiosk runs one application for whoever walks up to it, and the policy is
// what makes "cannot be left by the user" true. Nothing parsed it, so every
// key in the specification was documentation.
//
// The refusals matter more than the parsing here. A policy that quietly
// accepted a literal exit PIN would put it in the built artifact; one that
// accepted `auth` in a display-scope reset would sign the cashier out when the
// customer display timed out. Both look like working configuration.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> kiosk(Map<String, Object?> body) =>
    <String, Object?>{'kiosk': body};

void main() {
  group('defaults', () {
    test('an absent kiosk section is not a kiosk', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(null);
      expect(policy.enabled, isFalse);
      expect(policy.problems, isEmpty);
    });

    test('an enabled kiosk defaults to device scope', () {
      final DVKioskPolicy policy =
          DVKioskPolicy.parse(kiosk(<String, Object?>{'enabled': true}));
      expect(policy.enabled, isTrue);
      expect(policy.scope, DVKioskScope.device);
    });

    test('the documented input and session defaults apply', () {
      final DVKioskPolicy policy =
          DVKioskPolicy.parse(kiosk(<String, Object?>{'enabled': true}));

      expect(policy.blockSystemGestures, isTrue);
      expect(policy.blockShortcuts, isTrue);
      expect(policy.onIdle, DVKioskIdleAction.reset);
      expect(policy.fullscreen, isTrue);
      expect(policy.exitMethod, DVKioskExitMethod.none);
      expect(policy.maxAttempts, 5);
    });

    test('an unlisted route allowlist means every application route', () {
      // The documented default. An empty allowlist read as "allow nothing"
      // would make a kiosk show its home route and refuse every link on it.
      final DVKioskPolicy policy =
          DVKioskPolicy.parse(kiosk(<String, Object?>{'enabled': true}));

      expect(policy.allowsRoute('/anything'), isTrue);
    });
  });

  group('the route allowlist', () {
    DVKioskPolicy withAllow(List<String> allow) =>
        DVKioskPolicy.parse(kiosk(<String, Object?>{
          'enabled': true,
          'routes': <String, Object?>{'allow': allow},
        }));

    test('an exact route matches only itself', () {
      final DVKioskPolicy policy = withAllow(<String>['/welcome']);
      expect(policy.allowsRoute('/welcome'), isTrue);
      expect(policy.allowsRoute('/welcome/extra'), isFalse);
      expect(policy.allowsRoute('/welcomes'), isFalse,
          reason: 'a prefix is not a path segment');
    });

    test('a ** glob matches below it', () {
      final DVKioskPolicy policy = withAllow(<String>['/order/**']);
      expect(policy.allowsRoute('/order/1'), isTrue);
      expect(policy.allowsRoute('/order/1/items'), isTrue);
      expect(policy.allowsRoute('/orders'), isFalse);
    });

    test('a ** glob also matches the branch itself', () {
      // /order/** with /order refused would allow every child of a page the
      // user cannot reach.
      expect(withAllow(<String>['/order/**']).allowsRoute('/order'), isTrue);
    });

    test('a blocked route is reported as DV-KIOSK-006', () {
      expect(DVDiagnostics.find('DV-KIOSK-006')!.level, 'debug');
    });

    test('trailing slashes do not change the answer', () {
      final DVKioskPolicy policy = withAllow(<String>['/help']);
      expect(policy.allowsRoute('/help/'), isTrue);
    });
  });

  group('what it refuses', () {
    test('an exit PIN written as a value, not a secret reference', () {
      // It would otherwise sit in the built artifact, readable by anyone with
      // the image -- which is the one thing the exit method exists to prevent.
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'exit': <String, Object?>{'method': 'pin', 'pin': '4821'},
      }));

      expect(policy.problems, isNotEmpty);
      expect(policy.problems.first, contains('pin'));
      expect(policy.problems.first, contains('secret:'));
    });

    test('a secret reference is accepted', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'exit': <String, Object?>{
          'method': 'pin',
          'pin': 'secret:KIOSK_EXIT_PIN',
        },
      }));

      expect(policy.problems, isEmpty);
      expect(policy.exitPinSecret, 'KIOSK_EXIT_PIN');
    });

    test('a pin method with no pin at all', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'exit': <String, Object?>{'method': 'pin'},
      }));

      expect(policy.problems, isNotEmpty);
    });

    test('auth in a display-scope reset', () {
      // The customer display timing out must not sign the cashier out: the
      // session belongs to the staff window.
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'scope': 'display',
        'session': <String, Object?>{
          'clearOnReset': <String>['signals', 'auth'],
        },
      }));

      expect(policy.problems, isNotEmpty);
      expect(policy.problems.first, contains('auth'));
      expect(policy.clearOnReset, isNot(contains(DVKioskClearable.auth)),
          reason: 'refused, not merely reported');
    });

    test('auth in a device-scope reset is fine', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'scope': 'device',
        'session': <String, Object?>{
          'clearOnReset': <String>['auth'],
        },
      }));

      expect(policy.problems, isEmpty);
      expect(policy.clearOnReset, contains(DVKioskClearable.auth));
    });

    test('an unknown exit method, scope or idle action', () {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        <String, Object?>{'enabled': true, 'scope': 'somewhere'},
        <String, Object?>{
          'enabled': true,
          'exit': <String, Object?>{'method': 'vibes'},
        },
        <String, Object?>{
          'enabled': true,
          'session': <String, Object?>{'onIdle': 'panic'},
        },
      ]) {
        expect(DVKioskPolicy.parse(kiosk(body)).problems, isNotEmpty,
            reason: '$body');
      }
    });

    test('a malformed section does not throw', () {
      expect(() => DVKioskPolicy.parse(kiosk(<String, Object?>{})),
          returnsNormally);
      expect(() => DVKioskPolicy.parse(<String, Object?>{'kiosk': 'yes'}),
          returnsNormally);
      expect(DVKioskPolicy.parse('nonsense').enabled, isFalse);
    });
  });

  group('durations', () {
    test('the documented forms are read', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'session': <String, Object?>{
          'idleTimeout': '90s',
          'idleWarning': '15s',
        },
        'exit': <String, Object?>{'lockoutFor': '10m'},
      }));

      expect(policy.idleTimeout, const Duration(seconds: 90));
      expect(policy.idleWarning, const Duration(seconds: 15));
      expect(policy.lockoutFor, const Duration(minutes: 10));
      expect(policy.problems, isEmpty);
    });

    test('a warning longer than the timeout is refused', () {
      // The countdown would start before the clock did, so the user would see
      // it immediately and never get the time the timeout promises.
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'session': <String, Object?>{
          'idleTimeout': '10s',
          'idleWarning': '30s',
        },
      }));

      expect(policy.problems, isNotEmpty);
    });

    test('an unparseable duration is reported, not silently zero', () {
      // Zero would reset the kiosk continuously.
      final DVKioskPolicy policy = DVKioskPolicy.parse(kiosk(<String, Object?>{
        'enabled': true,
        'session': <String, Object?>{'idleTimeout': 'soon'},
      }));

      expect(policy.problems, isNotEmpty);
      expect(policy.idleTimeout, greaterThan(Duration.zero));
    });
  });
}
