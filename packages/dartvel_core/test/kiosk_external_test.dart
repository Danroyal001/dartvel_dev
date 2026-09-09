// routes.external: the last of the five containment keys nothing read.
//
// The parser pulled `allow` out of `routes` and let the other two fall
// through, so a kiosk that declared `external: block` and a footer link to
// the company website opened a browser on top of itself and the person in
// front of it was out of the application. That is the one thing kiosk mode
// exists to prevent, and the declaration that asked for it changed nothing.
//
// What makes it distinct from `routes.allow`: `allow` says which of this
// application's own routes the kiosk shows, and `external` says whether a URL
// may be handed to something that is not this application at all -- another
// origin, a mail client, a dialler. Two different questions with two
// different answers, which is why the specification made them two keys.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy _policy(Map<String, Object?> routes) => DVKioskPolicy.parse(
      <String, Object?>{
        'kiosk': <String, Object?>{'enabled': true, 'routes': routes},
      },
    );

void main() {
  setUp(dvResetKioskContainment);
  tearDown(dvResetKioskContainment);

  group('the declaration is read', () {
    test('a kiosk that says nothing still blocks the way out', () {
      // The permissive default belongs to `allow`, where it is the
      // specification's own, and it is the opposite question: which of this
      // application's pages the kiosk shows. A link out of the application
      // is the escape hatch, so the closed default is the honest one.
      final DVKioskPolicy policy = _policy(const <String, Object?>{});

      expect(policy.external, DVKioskExternal.block);
      expect(policy.externalAllow, isEmpty);
    });

    test('allowlist and its entries are read', () {
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'allowlist',
        'externalAllow': <String>['https://help.example.com/**'],
      });

      expect(policy.external, DVKioskExternal.allowlist);
      expect(policy.externalAllow, <String>['https://help.example.com/**']);
      expect(policy.problems, isEmpty);
    });

    test('neither key is reported as unread any more', () {
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'allowlist',
        'externalAllow': <String>['https://help.example.com/**'],
      });

      expect(
        policy.problems.where((String p) => p.contains('is not read by')),
        isEmpty,
      );
    });

    test('a value outside the closed set is named', () {
      final DVKioskPolicy policy =
          _policy(<String, Object?>{'external': 'allow'});

      expect(
        policy.problems.singleWhere((String p) => p.contains('routes.external')),
        contains('block, allowlist'),
      );
    });
  });

  group('a declaration that cannot mean what it says', () {
    test('an allowlist under block is refused rather than ignored', () {
      // The list sitting right there reads as agreement. Somebody wrote the
      // addresses the kiosk is allowed to open and forgot the line above
      // them, and every one of those links is refused with the list on
      // screen saying otherwise.
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'block',
        'externalAllow': <String>['https://help.example.com/**'],
      });

      expect(
        policy.problems.singleWhere((String p) => p.contains('externalAllow')),
        contains('block'),
      );
    });

    test('an entry YAML turned into something else is named', () {
      // `externalAllow: [tel:]` written without quotes is a mapping, not a
      // string. Skipping it leaves a list short by one and a dialler the
      // kiosk refuses while the declaration on screen says it allows it.
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'allowlist',
        'externalAllow': <Object?>[
          <String, Object?>{'tel': null},
        ],
      });

      // Naming the entry, not merely the empty list it leaves behind: the
      // author wrote one and needs to be told what happened to it, and "no
      // entry is declared" sends them to look at a line that is there.
      expect(
        policy.problems.join('\n'),
        contains('not a string'),
      );
      expect(policy.allowsExternal('tel:+441234567890'), isFalse);
    });

    test('an empty allowlist is named, because it blocks everything', () {
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'allowlist',
        'externalAllow': const <String>[],
      });

      expect(
        policy.problems.singleWhere((String p) => p.contains('externalAllow')),
        contains('no entry'),
      );
    });
  });

  group('what an entry matches', () {
    DVKioskPolicy withList(List<String> entries) => _policy(<String, Object?>{
          'external': 'allowlist',
          'externalAllow': entries,
        });

    test('scheme and host must both match', () {
      final DVKioskPolicy policy =
          withList(<String>['https://help.example.com/**']);

      expect(policy.allowsExternal('https://help.example.com/faq'), isTrue);
      expect(policy.allowsExternal('http://help.example.com/faq'), isFalse,
          reason: 'a plain-text downgrade is a different address');
      expect(policy.allowsExternal('https://evil.example.com/faq'), isFalse);
    });

    test('a host that merely starts the same does not match', () {
      // The failure this stops is quiet: `help.example.com.attacker.test`
      // passes any prefix test and is somebody else's machine.
      final DVKioskPolicy policy = withList(<String>['https://example.com/**']);

      expect(policy.allowsExternal('https://example.com.attacker.test/'),
          isFalse);
      expect(policy.allowsExternal('https://example.company/'), isFalse);
    });

    test('the path is matched segment by segment, as routes are', () {
      final DVKioskPolicy policy =
          withList(<String>['https://example.com/docs/**']);

      expect(policy.allowsExternal('https://example.com/docs'), isTrue);
      expect(policy.allowsExternal('https://example.com/docs/a/b'), isTrue);
      expect(policy.allowsExternal('https://example.com/docsets'), isFalse);
    });

    test('an entry with no path allows that host and nothing under it', () {
      final DVKioskPolicy policy = withList(<String>['https://example.com']);

      expect(policy.allowsExternal('https://example.com/'), isTrue);
      expect(policy.allowsExternal('https://example.com/docs'), isFalse);
    });

    test('a scheme-only entry allows that scheme', () {
      // A kiosk with a call-us button. The dialler is not a web address and
      // there is no host to name, so the scheme is the whole entry.
      final DVKioskPolicy policy = withList(<String>['tel:']);

      expect(policy.allowsExternal('tel:+441234567890'), isTrue);
      expect(policy.allowsExternal('mailto:hi@example.com'), isFalse);
    });

    test('host comparison ignores case, path does not', () {
      final DVKioskPolicy policy =
          withList(<String>['https://Example.com/Docs/**']);

      expect(policy.allowsExternal('https://EXAMPLE.COM/Docs'), isTrue);
      expect(policy.allowsExternal('https://example.com/docs'), isFalse,
          reason: 'someone else decides whether their paths are case-folded');
    });

    test('block allows nothing at all', () {
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'block',
      });

      expect(policy.allowsExternal('https://example.com/'), isFalse);
      expect(policy.allowsExternal('tel:+441234567890'), isFalse);
    });

    test('a relative path is not an external URL and is not judged here', () {
      // It is a route, and routes.allow is the key that governs it. Judging
      // it here would block every in-app link the moment external did.
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'block',
      });

      expect(policy.allowsExternal('/order/12'), isTrue);
      expect(policy.allowsExternal('order/12'), isTrue);
    });

    test('an unparseable address is refused rather than passed through', () {
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'external': 'allowlist',
        'externalAllow': <String>['https://example.com/**'],
      });

      expect(policy.allowsExternal('https://exa mple.com/ '), isFalse);
    });
  });

  group('the running kiosk is what decides', () {
    DVKioskPolicy policy(String mode, List<String> entries) =>
        _policy(<String, Object?>{'external': mode, 'externalAllow': entries});

    test('nothing is contained until a policy is installed', () {
      expect(dvKioskAllowsExternalUrl('https://example.com/'), isTrue);
    });

    test('an installed blocking policy refuses', () {
      dvApplyKioskContainment(policy('block', const <String>[]));

      expect(dvKioskAllowsExternalUrl('https://example.com/'), isFalse);
    });

    test('an installed allowlist lets its own entries through', () {
      dvApplyKioskContainment(
          policy('allowlist', <String>['https://example.com/**']));

      expect(dvKioskAllowsExternalUrl('https://example.com/docs'), isTrue);
      expect(dvKioskAllowsExternalUrl('https://elsewhere.test/'), isFalse);
    });

    test('staff mode lifts it, the way the other containment keys work',
        () async {
      final DVKioskRuntime kiosk = DVKioskRuntime(
        DVKioskPolicy.parse(<String, Object?>{
          'kiosk': <String, Object?>{
            'enabled': true,
            'routes': <String, Object?>{'external': 'block'},
            'exit': <String, Object?>{
              'method': 'pin',
              'pin': 'secret:KIOSK_EXIT_PIN',
            },
          },
        }),
        readSecret: (String _) async => '4821',
      );

      await kiosk.resume();
      expect(dvKioskAllowsExternalUrl('https://example.com/'), isFalse);

      await kiosk.exit(const DVKioskExitRequest.pin('4821'));
      expect(kiosk.state.value, DVKioskState.staffMode);
      expect(dvKioskAllowsExternalUrl('https://example.com/'), isTrue,
          reason: 'an engineer at the machine has the exit method already');

      kiosk.stop();
    });
  });
}
