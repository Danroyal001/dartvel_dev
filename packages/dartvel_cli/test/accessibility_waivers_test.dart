// A documented waiver for an accessibility finding accepted on purpose.
//
// The gate fails a release on a finding. Sometimes a finding is right and the
// page is still shipping -- a legacy route mid-migration, a heading structure
// a designer has signed off on for a launch. Without a waiver the only ways
// past the gate are to weaken the rule for everyone or to disable the gate,
// and both are how a gate stops being read.
//
// So a waiver names the route, the rule and a reason. No reason, no waiver:
// "waived" with nothing after it is exactly the silent exception the gate
// exists to prevent. A waiver that matches nothing is reported too, because
// it is either a typo or a finding that was fixed, and either way it should
// not sit in the file forever.
import 'package:dartvel_cli/src/build/accessibility_audit.dart';
import 'package:test/test.dart';

DVA11yFinding finding(String route, String rule) =>
    DVA11yFinding(route: route, rule: rule, message: 'm');

void main() {
  group('reading waivers from configuration', () {
    test('a waiver has a route, a rule and a reason', () {
      final DVA11yWaivers w = DVA11yWaivers.parse(<String, Object?>{
        'accessibility': <String, Object?>{
          'waivers': <Object?>[
            <String, Object?>{
              'route': '/legacy',
              'rule': 'heading-order',
              'reason': 'Mid-migration; tracked in DV-1234.',
            },
          ],
        },
      });
      expect(w.entries, hasLength(1));
      expect(w.problems, isEmpty);
    });

    test('a waiver with no reason is refused', () {
      final DVA11yWaivers w = DVA11yWaivers.parse(<String, Object?>{
        'accessibility': <String, Object?>{
          'waivers': <Object?>[
            <String, Object?>{'route': '/legacy', 'rule': 'heading-order'},
          ],
        },
      });
      expect(w.entries, isEmpty);
      expect(w.problems.single, contains('reason'));
    });

    test('a waiver naming a rule that does not exist is refused', () {
      // A misspelt rule would waive nothing and look like it waived
      // something.
      final DVA11yWaivers w = DVA11yWaivers.parse(<String, Object?>{
        'accessibility': <String, Object?>{
          'waivers': <Object?>[
            <String, Object?>{'route': '/x', 'rule': 'heading-orders', 'reason': 'r'},
          ],
        },
      });
      expect(w.entries, isEmpty);
      expect(w.problems.single, contains('heading-orders'));
    });

    test('no configuration is no waivers, and no complaint', () {
      final DVA11yWaivers w = DVA11yWaivers.parse(null);
      expect(w.entries, isEmpty);
      expect(w.problems, isEmpty);
    });

    test('a malformed section does not throw', () {
      expect(() => DVA11yWaivers.parse(<String, Object?>{'accessibility': 'yes'}),
          returnsNormally);
      expect(
          () => DVA11yWaivers.parse(<String, Object?>{
                'accessibility': <String, Object?>{'waivers': 'nope'},
              }),
          returnsNormally);
    });
  });

  group('applying waivers', () {
    final DVA11yWaivers waivers = DVA11yWaivers.parse(<String, Object?>{
      'accessibility': <String, Object?>{
        'waivers': <Object?>[
          <String, Object?>{'route': '/legacy', 'rule': 'heading-order', 'reason': 'r'},
        ],
      },
    });

    test('a waived finding is set aside, and counted as waived', () {
      final DVA11yVerdict v = waivers.apply(<DVA11yFinding>[
        finding('/legacy', 'heading-order'),
        finding('/home', 'link-name'),
      ]);
      expect(v.failing.map((DVA11yFinding f) => f.route), <String>['/home']);
      expect(v.waived, hasLength(1));
    });

    test('the same rule on another route is not waived', () {
      // A waiver is for one page, not for the rule.
      final DVA11yVerdict v = waivers.apply(<DVA11yFinding>[
        finding('/other', 'heading-order'),
      ]);
      expect(v.failing, hasLength(1));
    });

    test('a waiver that matched nothing is reported', () {
      // Either a typo or a finding that has since been fixed; either way it
      // should not sit in the file forever.
      final DVA11yVerdict v = waivers.apply(<DVA11yFinding>[
        finding('/home', 'link-name'),
      ]);
      expect(v.unused, hasLength(1));
      expect(v.unused.single.route, '/legacy');
    });

    test('a route waiver can name every rule with *', () {
      final DVA11yWaivers all = DVA11yWaivers.parse(<String, Object?>{
        'accessibility': <String, Object?>{
          'waivers': <Object?>[
            <String, Object?>{'route': '/legacy', 'rule': '*', 'reason': 'whole page mid-migration'},
          ],
        },
      });
      final DVA11yVerdict v = all.apply(<DVA11yFinding>[
        finding('/legacy', 'heading-order'),
        finding('/legacy', 'link-name'),
        finding('/home', 'link-name'),
      ]);
      expect(v.failing, hasLength(1));
      expect(v.waived, hasLength(2));
    });

    test('the build fails only on what is not waived', () {
      expect(waivers.apply(<DVA11yFinding>[finding('/legacy', 'heading-order')]).ok, isTrue);
      expect(waivers.apply(<DVA11yFinding>[finding('/home', 'link-name')]).ok, isFalse);
    });
  });
}
