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
import 'dart:io';

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

  group('DV-KIOSK-009: onIdle home with sensitive fields in reach', () {
    // An informational display returns to the attract route without
    // clearing anything. If a route the kiosk allows shows a model with a
    // sensitive field, the next person at the screen can see the last
    // person's data. A warning, at analyze time, naming the route.
    late Directory root;

    void model(String name, {required bool sensitive}) {
      File('${root.path}/lib/models/${name.toLowerCase()}.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVModel()
class _$name {
  final String name;
  ${sensitive ? '@DVModel.sensitiveField()' : ''}
  final String card;
  const _$name(this.name, this.card);
}
''');
    }

    void page(String route, String body) {
      final String rel = route == '/' ? 'index' : route.substring(1);
      File('${root.path}/lib/pages/$rel.page.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:app/dartvel_client/dartvel_client.dart';

@DVPage(title: 'p')
Widget _p(BuildContext context) => $body;
''');
    }

    setUp(() => root = Directory.systemTemp.createTempSync('dv_kiosk009_'));
    tearDown(() => root.deleteSync(recursive: true));

    Map<String, Object?> home(List<String> allow) => section(<String, Object?>{
          'enabled': true,
          'session': <String, Object?>{'onIdle': 'home'},
          'routes': <String, Object?>{'allow': allow},
          'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
        });

    test('warns, naming the route and the model', () {
      model('Customer', sensitive: true);
      page('/orders', "Customer.Table()");
      page('/attract', "const DVText('hi')");

      final DVKioskCheck check = DVKioskCheck.run(home(<String>['/orders', '/attract']), <DVKioskTarget>[DVKioskTarget.linuxDesktop], root: root.path);

      expect(check.ok, isTrue, reason: 'a warning, not a failure');
      final String text = check.lines.join('\n');
      expect(text, contains('DV-KIOSK-009'));
      expect(text, contains('/orders'));
      expect(text, contains('Customer'));
      expect(text, isNot(contains('/attract')));
    });

    test('a route the kiosk does not allow is not in reach', () {
      model('Customer', sensitive: true);
      page('/orders', "Customer.Table()");
      final DVKioskCheck check = DVKioskCheck.run(home(<String>['/attract']), <DVKioskTarget>[DVKioskTarget.linuxDesktop], root: root.path);
      expect(check.lines.join('\n'), isNot(contains('DV-KIOSK-009')));
    });

    test('a model with no sensitive field is fine, and so is onIdle reset', () {
      model('Product', sensitive: false);
      page('/catalogue', "Product.Table()");
      expect(DVKioskCheck.run(home(<String>['/catalogue']), <DVKioskTarget>[DVKioskTarget.linuxDesktop], root: root.path).lines.join('\n'),
          isNot(contains('DV-KIOSK-009')));

      model('Customer', sensitive: true);
      page('/orders', "Customer.Table()");
      final Map<String, Object?> reset = section(<String, Object?>{
        'enabled': true,
        'session': <String, Object?>{'onIdle': 'reset', 'clearOnReset': <String>['signals', 'forms']},
        'routes': <String, Object?>{'allow': <String>['/orders']},
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      });
      expect(DVKioskCheck.run(reset, <DVKioskTarget>[DVKioskTarget.linuxDesktop], root: root.path).lines.join('\n'),
          isNot(contains('DV-KIOSK-009')));
    });

    test('with no root there is nothing to scan and nothing is claimed', () {
      expect(DVKioskCheck.run(home(<String>['/orders']), <DVKioskTarget>[DVKioskTarget.linuxDesktop]).lines.join('\n'),
          isNot(contains('DV-KIOSK-009')));
    });
  });
}
