// What a page's policy check answers.
//
// The generated router calls this before a route activates. The case that
// matters most is the one with no answerer configured: a page that declares
// a policy in an application that cannot evaluate it must be refused, not
// opened. Treating "nothing decided" as "allow" would reintroduce the exact
// bug this closes -- a page carrying the annotation for guarding it, open to
// everybody -- as a default instead of an omission.
import 'package:dartvel_flutter/src/routing/page_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _State {
  const _State(this.matchedLocation);
  final String matchedLocation;
}

void main() {
  setUp(() => DVPagePolicy.decide = null);
  tearDown(() => DVPagePolicy.decide = null);

  test('with nothing configured to answer, the page is refused', () async {
    expect(
      await DVPagePolicy.check(null, const _State('/admin'), 'viewAdmin'),
      dvUnauthorizedRoute,
    );
  });

  test('an allowed caller gets no redirect at all', () async {
    DVPagePolicy.decide = (String policy, String location) async => true;

    expect(
      await DVPagePolicy.check(null, const _State('/admin'), 'viewAdmin'),
      isNull,
    );
  });

  test('a refused caller is sent to the unauthorized route', () async {
    DVPagePolicy.decide = (String policy, String location) async => false;

    expect(
      await DVPagePolicy.check(null, const _State('/admin'), 'viewAdmin'),
      dvUnauthorizedRoute,
    );
  });

  test('the policy and the path both reach the decision', () async {
    // A check that ignored the route would answer the same for every page
    // under one policy, which is not what a policy means.
    late String seenPolicy;
    late String seenLocation;
    DVPagePolicy.decide = (String policy, String location) async {
      seenPolicy = policy;
      seenLocation = location;
      return true;
    };

    await DVPagePolicy.check(null, const _State('/admin/users'), 'viewAdmin');

    expect(seenPolicy, 'viewAdmin');
    expect(seenLocation, '/admin/users');
  });

  test('a state that names no location still refuses or allows cleanly', () {
    // The router state is taken dynamically, so this must not throw on
    // something that does not carry a matchedLocation.
    DVPagePolicy.decide = (String policy, String location) async => true;

    expect(DVPagePolicy.check(null, Object(), 'viewAdmin'), completes);
  });
}
