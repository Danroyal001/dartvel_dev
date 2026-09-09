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

  group('a key nobody reads is not silently accepted', () {
    // NEW_SPEC lists routes.external, input.clipboard, input.textSelection,
    // display.hideCursor and screenDim. The parser read the routes, input
    // and display maps and pulled three named children out of them, so all
    // five were read past and dropped. An unrecognised enum value already
    // produced a problem; an unrecognised key produced nothing, which is the
    // worse of the two failures -- the developer believes the kiosk is
    // locked down and it is not.
    //
    // All five are built now, so what this group protects is the rule rather
    // than the list: a key the parser does not read says so, whatever it is
    // called. The list of five kept shrinking and the rule did not move.
    test('an unparsed containment key is reported', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(
        kiosk(<String, Object?>{
          'enabled': true,
          'routes': <String, Object?>{'externalDeny': <Object?>['/x']},
        }),
      );

      expect(policy.problems, isNotEmpty);
      expect(
        policy.problems.join('\n'),
        contains('dartvel.kiosk.routes.externalDeny'),
      );
    });

    test('a key that is read is not reported', () {
      // The other half of the rule, and the half that goes wrong silently:
      // a key that does something and still says it does nothing sends
      // somebody looking for a bug that is not there.
      final DVKioskPolicy policy = DVKioskPolicy.parse(
        kiosk(<String, Object?>{
          'enabled': true,
          'input': <String, Object?>{
            'clipboard': 'disabled',
            'textSelection': 'disabled',
          },
          'display': <String, Object?>{'hideCursor': 'always'},
        }),
      );

      expect(policy.problems, isEmpty);
      expect(policy.blockClipboard, isTrue);
      expect(policy.blockTextSelection, isTrue);
      expect(policy.hideCursor, DVKioskCursor.always);
    });

    test('every unparsed key is named, not just the first', () {
      final DVKioskPolicy policy = DVKioskPolicy.parse(
        kiosk(<String, Object?>{
          'enabled': true,
          'routes': <String, Object?>{
            'allow': <Object?>['/'],
            'externalDeny': <Object?>['/x'],
          },
          'display': <String, Object?>{'fullscreen': true},
          // Not a containment key at all, and that is the point: the rule is
          // about any key the parser does not read, not about a list of five
          // that keeps shrinking.
          'session': <String, Object?>{'dimAfterHours': 3},
        }),
      );

      final String said = policy.problems.join('\n');
      expect(said, contains('dartvel.kiosk.routes.externalDeny'));
      expect(said, contains('dartvel.kiosk.session.dimAfterHours'));
      // The keys that are parsed are not reported, or the message becomes
      // noise and the real one is lost in it.
      expect(said, isNot(contains('routes.allow')));
      expect(said, isNot(contains('display.fullscreen')));
    });

    test('a top-level key nobody reads is reported too', () {
      // screenDim under display is read now. Written at the top of the kiosk
      // section instead it is still nothing -- and the near miss is the case
      // worth reporting, because the value is right and the place is wrong,
      // which reads as the feature being broken rather than misplaced.
      final DVKioskPolicy policy = DVKioskPolicy.parse(
        kiosk(<String, Object?>{'enabled': true, 'screenDim': '30s'}),
      );

      expect(
        policy.problems.join('\n'),
        contains('dartvel.kiosk.screenDim'),
      );
      expect(policy.screenDim, isNull);
    });

    test('a fully understood policy still reports nothing', () {
      // The check is only worth having if it stays quiet on valid input.
      final DVKioskPolicy policy = DVKioskPolicy.parse(
        kiosk(<String, Object?>{
          'enabled': true,
          'scope': 'device',
          'home': '/',
          'routes': <String, Object?>{
            'allow': <Object?>['/', '/help'],
          },
          'input': <String, Object?>{
            'systemGestures': 'block',
            'hardwareKeys': 'block',
            'shortcuts': 'block',
          },
          'display': <String, Object?>{'fullscreen': true},
        }),
      );

      expect(policy.problems, isEmpty);
    });
  });
}
