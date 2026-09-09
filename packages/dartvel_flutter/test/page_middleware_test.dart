// What a page's declared middleware answers, before the route activates.
//
// The generated router calls this. Two failure modes here are silent rather
// than loud, and both get their own test:
//
//   * a redirect target that is itself guarded. Sending an unauthenticated
//     visitor to the sign-in page, and then guarding the sign-in page with
//     the same check, is an infinite redirect -- go_router gives up with an
//     exception the developer reads as a router bug.
//   * a maintenance default of "down". Nothing configures the hook until an
//     application sets one, so defaulting the wrong way would take every
//     application offline on the build that added the feature.
import 'package:dartvel_flutter/src/routing/page_middleware.dart';
import 'package:flutter_test/flutter_test.dart';

class _State {
  const _State(this.matchedLocation);
  final String matchedLocation;
}

void main() {
  setUp(dvResetPageMiddleware);
  tearDown(dvResetPageMiddleware);

  group('auth', () {
    test('with nothing configured to answer, the page is refused', () async {
      // The same default DVPagePolicy takes, for the same reason: a page
      // that declared authentication and got none is not a public page.
      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/checkout'),
          const <String>['auth'],
        ),
        dvSignInRoute,
      );
    });

    test('a signed-in visitor gets no redirect at all', () async {
      DVPageMiddleware.isSignedIn = () async => true;

      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/checkout'),
          const <String>['auth'],
        ),
        isNull,
      );
    });

    test('a signed-out visitor is sent to the sign-in route', () async {
      DVPageMiddleware.isSignedIn = () async => false;

      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/checkout'),
          const <String>['auth'],
        ),
        dvSignInRoute,
      );
    });

    test('the sign-in route is never redirected away from itself', () async {
      // The loop. A sign-in page that declares auth -- or sits under a
      // folder whose pages all do -- would otherwise redirect to itself
      // forever, and the exception names the router rather than the page.
      DVPageMiddleware.isSignedIn = () async => false;

      expect(
        await DVPageMiddleware.check(
          null,
          _State(dvSignInRoute),
          const <String>['auth'],
        ),
        isNull,
      );
    });
  });

  group('maintenance', () {
    test('with nothing configured, the application is up', () async {
      // The opposite default to auth, and deliberately. Nobody sets this
      // hook until they have a maintenance window; a framework that read
      // silence as "down" would black out every application that upgraded.
      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/checkout'),
          const <String>['maintenance'],
        ),
        isNull,
      );
    });

    test('a page is held back while the application is down', () async {
      DVPageMiddleware.isDown = () async => true;

      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/checkout'),
          const <String>['maintenance'],
        ),
        dvMaintenanceRoute,
      );
    });

    test('the maintenance route itself stays reachable while down', () async {
      DVPageMiddleware.isDown = () async => true;

      expect(
        await DVPageMiddleware.check(
          null,
          _State(dvMaintenanceRoute),
          const <String>['maintenance'],
        ),
        isNull,
      );
    });

    test('a path the application kept open stays open', () async {
      DVPageMiddleware.isDown = () async => true;
      DVPageMiddleware.maintenanceAllows = const <String>['/status'];

      expect(
        await DVPageMiddleware.check(
          null,
          const _State('/status'),
          const <String>['maintenance'],
        ),
        isNull,
      );
    });
  });

  group('the order the keys were declared in', () {
    test('the first refusal wins and the rest never run', () async {
      // Order is the declared order, and it is observable: a maintenance
      // check that ran after an auth check would send a signed-out visitor
      // to sign in to an application that is not serving anybody.
      var authAsked = false;
      DVPageMiddleware.isDown = () async => true;
      DVPageMiddleware.isSignedIn = () async {
        authAsked = true;
        return false;
      };

      final String? to = await DVPageMiddleware.check(
        null,
        const _State('/checkout'),
        const <String>['maintenance', 'auth'],
      );

      expect(to, dvMaintenanceRoute);
      expect(authAsked, isFalse);
    });

    test('the other order asks auth first', () async {
      var downAsked = false;
      DVPageMiddleware.isDown = () async {
        downAsked = true;
        return true;
      };
      DVPageMiddleware.isSignedIn = () async => false;

      final String? to = await DVPageMiddleware.check(
        null,
        const _State('/checkout'),
        const <String>['auth', 'maintenance'],
      );

      expect(to, dvSignInRoute);
      expect(downAsked, isFalse);
    });
  });

  test('a page declaring nothing does no work and goes nowhere', () async {
    expect(
      await DVPageMiddleware.check(null, const _State('/'), const <String>[]),
      isNull,
    );
  });

  test('a key a page cannot run throws rather than being skipped', () async {
    // The generator refuses these at build time, so one arriving here means
    // a generated router is older than the framework running it. Letting the
    // route through as though the middleware had applied is the silence this
    // whole feature exists to end.
    await expectLater(
      () => DVPageMiddleware.check(
        null,
        const _State('/checkout'),
        const <String>['bodyLimit'],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a state that names no location still answers cleanly', () async {
    // The router state is read dynamically, so an object without a
    // matchedLocation must not throw on the way to a decision.
    DVPageMiddleware.isSignedIn = () async => true;

    expect(
      DVPageMiddleware.check(null, Object(), const <String>['auth']),
      completes,
    );
  });
}
