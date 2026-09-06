// A page that declares a policy is guarded by it.
//
// @DVPage takes a policy. It has taken one since the annotation was written,
// the specification gives it as the usage example, and the generator has
// never read it: 'policy' is parsed in exactly one place, and that place is
// the backend function generator. Route guards come from a directory
// convention instead, so
//
//     @DVPage(policy: DVPolicies.viewAdmin)
//     Widget _adminPage(BuildContext context) => AdminDashboard();
//
// produces a page anybody can open, and nothing anywhere says so.
//
// That is the worst shape this can take. An unguarded page that looks
// unguarded is a decision somebody made. An unguarded page carrying the
// annotation for guarding it is a developer who has already ticked this off
// -- it fails open, silently, at the one place the API invited them to
// trust it.
import 'package:dartvel_cli/src/generators/page_policy.dart';
import 'package:test/test.dart';

void main() {
  group('what a declared policy generates', () {
    test('a page with one gets a redirect that checks it', () {
      // Not a comment, not a TODO: a route the router will actually refuse.
      final String guard = dvPagePolicyGuard('DVPolicies.viewAdmin');

      expect(guard, contains('redirect:'));
      expect(guard, contains('DVPolicies.viewAdmin'));
    });

    test('it calls the one shared checker, not an inlined auth call', () {
      // The generator emitting DV.Auth.authorization.can(...) directly would
      // pin the exact shape of that surface into every generated router, and
      // the first version of this did that against two symbols that do not
      // exist. What the checker then does -- ask the same default-deny
      // authorization surface every other policy is answered by -- is
      // asserted where the checker lives.
      expect(dvPagePolicyGuard('DVPolicies.viewAdmin'),
          contains('DVPagePolicy.check(context, state,'));
    });

    test('a page with none generates nothing at all', () {
      // Every page without a policy must keep the route it has, with no
      // redirect and no runtime cost.
      expect(dvPagePolicyGuard(null), isEmpty);
      expect(dvPagePolicyGuard(''), isEmpty);
    });

    test('a refused page goes somewhere rather than rendering nothing', () {
      // A redirect that returns null on refusal lets the page render. The
      // guard has to send the request elsewhere or it is not a guard.
      final String guard = dvPagePolicyGuard('DVPolicies.viewAdmin');

      expect(guard, contains('return '));
      expect(guard, isNot(contains('return null;\n      },\n')),
          reason: 'a guard whose only return is null refuses nobody');
    });
  });

  group('what it refuses to generate', () {
    test('a policy that is not an identifier is refused at build time', () {
      // The value is emitted into generated Dart. Anything that is not a
      // reference would either not compile -- which at least fails loudly --
      // or, worse, compile into something nobody wrote.
      expect(() => dvPagePolicyGuard('viewAdmin(); doSomethingElse()'),
          throwsA(isA<ArgumentError>()));
      expect(() => dvPagePolicyGuard('4'), throwsA(isA<ArgumentError>()));
    });

    test('a dotted reference is fine, because that is the normal shape', () {
      expect(() => dvPagePolicyGuard('DVPolicies.viewAdmin'), returnsNormally);
      expect(() => dvPagePolicyGuard('viewAdmin'), returnsNormally);
    });
  });

  group('the guard chain', () {
    test('a directory guard and a page policy both run', () {
      // They are different mechanisms and a page can be under both. If the
      // policy replaced the directory chain, moving a page into a guarded
      // folder would silently drop the folder's guard.
      final String chained = dvPageGuardChain(
        directoryGuards: <String>['AdminGuard'],
        policy: 'DVPolicies.viewAdmin',
      );

      expect(chained, contains('AdminGuard'));
      expect(chained, contains('DVPolicies.viewAdmin'));
      expect(chained.indexOf('AdminGuard'),
          lessThan(chained.indexOf('DVPolicies.viewAdmin')),
          reason: 'the directory guard is the outer one and runs first');
    });

    test('neither is nothing', () {
      expect(
        dvPageGuardChain(directoryGuards: const <String>[], policy: null),
        isEmpty,
      );
    });

    test('a directory guard alone is unchanged from what it always was', () {
      // Every existing application depends on this exact shape.
      final String only =
          dvPageGuardChain(directoryGuards: <String>['AdminGuard'], policy: null);

      expect(only, contains('AdminGuard.guard(context, state)'));
      expect(only, isNot(contains('DVPagePolicy')));
    });
  });
}
