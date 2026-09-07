// A backend function that declares a policy is guarded by it.
//
// @DVBackendFunction(policy: DVPolicies.refund) is the specification's own
// example and nothing read it -- on either side. The specification is
// explicit at NEW_SPEC.md:914 that backend functions enforce policies "even
// if UI guards are bypassed", which makes this the half that matters: a page
// guard without a function guard is a lock on the front door of a building
// with open windows.
//
// These assert on what the generator extracts and on what the router emits.
// The page version of this feature shipped with a correct guard builder, a
// correct runtime checker, a unit test for each, and no caller -- both tests
// passed because both asserted on a string returned by a function nothing
// called. That is the mistake this file is shaped to avoid.
import 'package:dartvel_cli/src/generators/page_policy.dart';
import 'package:test/test.dart';

void main() {
  group('reading the annotation', () {
    test('the documented shape is found', () {
      const String source = '''
@DVBackendFunction(policy: DVPolicies.refund)
Future<Refund> _refundOrder(Order order) async => Refund.create(order);
''';

      expect(dvBackendPolicyFromSource(source), 'DVPolicies.refund');
    });

    test('a function alongside other arguments still gives its policy', () {
      expect(
        dvBackendPolicyFromSource(
            '@DVBackendFunction(rawPath: /pay, policy: DVPolicies.refund)\n'
            'Future<int> _f() async => 1;'),
        'DVPolicies.refund',
      );
    });

    test('a function that declares none has none', () {
      expect(
        dvBackendPolicyFromSource(
            '@DVBackendFunction()\nFuture<int> _f() async => 1;'),
        isNull,
      );
      expect(dvBackendPolicyFromSource('Future<int> _f() async => 1;'), isNull);
    });

    test('an explicit null is none rather than the word null', () {
      // Emitted into a string, `null` would become a policy nobody
      // registered -- which refuses everybody rather than nobody, but for
      // the wrong reason and with a baffling message.
      expect(
        dvBackendPolicyFromSource(
            '@DVBackendFunction(policy: null)\nFuture<int> _f() async => 1;'),
        isNull,
      );
    });

    test('the page parser and this one do not answer for each other', () {
      // One annotation each. A backend function reading the page parser
      // would find nothing, and a page reading this one likewise -- which
      // is the failure that looks like the feature simply not working.
      const String page = "@DVPage(policy: DVPolicies.viewAdmin)\nWidget _p(c) => x;";
      const String fn = '@DVBackendFunction(policy: DVPolicies.refund)\n'
          'Future<int> _f() async => 1;';

      expect(dvBackendPolicyFromSource(page), isNull);
      expect(dvPagePolicyFromSource(fn), isNull);
    });
  });
}
