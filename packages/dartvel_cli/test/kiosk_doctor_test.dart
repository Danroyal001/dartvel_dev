// `dartvel doctor` on a kiosk policy.
//
// The specification says doctor validates that the declared policy is
// enforceable on each configured target. Without it, the refusals the policy
// parser produces -- a literal exit PIN, `auth` in a display-scope reset --
// were computed and then dropped on the floor, which is the same as not
// checking.
//
// A kiosk is also the one place where "your target cannot do what you asked"
// has to be said out loud rather than degraded around, because there is no
// other way to lock a device.
import 'package:dartvel_cli/src/doctor/kiosk_check.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> section(Map<String, Object?> body) =>
    <String, Object?>{'kiosk': body};

void main() {
  group('a project with no kiosk', () {
    test('says nothing and passes', () {
      final DVKioskCheck check = DVKioskCheck.run(null, <DVKioskTarget>[]);
      expect(check.ok, isTrue);
      expect(check.lines, isEmpty);
    });
  });

  group('a policy that cannot be honoured', () {
    test('a literal exit PIN fails the check', () {
      final DVKioskCheck check = DVKioskCheck.run(
        section(<String, Object?>{
          'enabled': true,
          'exit': <String, Object?>{'method': 'pin', 'pin': '4821'},
        }),
        <DVKioskTarget>[DVKioskTarget.sonyELinux],
      );

      expect(check.ok, isFalse);
      expect(check.lines.join('\n'), contains('secret:'));
    });

    test('and the PIN itself is never printed', () {
      // doctor output gets pasted into issues.
      final DVKioskCheck check = DVKioskCheck.run(
        section(<String, Object?>{
          'enabled': true,
          'exit': <String, Object?>{'method': 'pin', 'pin': '4821'},
        }),
        <DVKioskTarget>[DVKioskTarget.sonyELinux],
      );

      expect(check.lines.join('\n'), isNot(contains('4821')));
    });

    test('auth in a display-scope reset fails it', () {
      final DVKioskCheck check = DVKioskCheck.run(
        section(<String, Object?>{
          'enabled': true,
          'scope': 'display',
          'session': <String, Object?>{'clearOnReset': <String>['auth']},
        }),
        <DVKioskTarget>[DVKioskTarget.linuxDesktop],
      );

      expect(check.ok, isFalse);
      expect(check.lines.join('\n'), contains('auth'));
    });
  });

  group('what each target will actually do', () {
    final Map<String, Object?> good = section(<String, Object?>{
      'enabled': true,
      'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
    });

    test('a target that locks the device says so, and passes', () {
      final DVKioskCheck check =
          DVKioskCheck.run(good, <DVKioskTarget>[DVKioskTarget.sonyELinux]);

      expect(check.ok, isTrue);
      expect(check.lines.join('\n'), contains('device'));
    });

    test('a weaker target is reported but does not fail the check', () {
      // It is a real deployment choice, not a mistake: a Linux desktop kiosk
      // is supervised and someone may well want that.
      final DVKioskCheck check =
          DVKioskCheck.run(good, <DVKioskTarget>[DVKioskTarget.linuxDesktop]);

      expect(check.ok, isTrue);
      expect(check.lines.join('\n'), contains('DV-KIOSK-001'));
      expect(check.lines.join('\n'), contains('supervised'));
    });

    test('a target that cannot be a kiosk at all fails it', () {
      // Nothing about the configuration is wrong; shipping it to a watch is.
      final DVKioskCheck check =
          DVKioskCheck.run(good, <DVKioskTarget>[DVKioskTarget.watch]);

      expect(check.ok, isFalse);
      expect(check.lines.join('\n'), contains('DV-KIOSK-004'));
    });

    test('every configured target gets a line', () {
      final DVKioskCheck check = DVKioskCheck.run(good, <DVKioskTarget>[
        DVKioskTarget.sonyELinux,
        DVKioskTarget.linuxDesktop,
        DVKioskTarget.web,
      ]);

      for (final String name in <String>['sonyELinux', 'linuxDesktop', 'web']) {
        expect(check.lines.join('\n'), contains(name));
      }
    });

    test('no configured targets still validates the policy itself', () {
      final DVKioskCheck check = DVKioskCheck.run(
        section(<String, Object?>{
          'enabled': true,
          'exit': <String, Object?>{'method': 'pin', 'pin': 'nope'},
        }),
        <DVKioskTarget>[],
      );

      expect(check.ok, isFalse);
    });
  });
}
