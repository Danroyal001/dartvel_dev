// routes.allow, at the moment a route is asked for.
//
// The allow list parsed, doctor scanned it for sensitive fields behind
// allowed routes, and DV-KIOSK-006 was registered for a route outside it
// being blocked. Nothing blocked one. `allowsRoute` had exactly two callers,
// both of them doctor and its tests, so a kiosk declaring
// `allow: [/welcome, /order/**]` served /admin to anyone who could reach it.
//
// Reaching it is not far-fetched, and the specification says so in as many
// words: deep links, notifications and OS intents do not constitute an exit
// path, and are honoured only within routes.allow. A kiosk on Android takes
// an intent, a kiosk on the web takes whatever is in the address bar of the
// browser it is pinned inside, and a kiosk anywhere takes a link on one of
// its own pages that was never meant to be reachable from the attract route.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy _policy({
  List<String> allow = const <String>['/welcome', '/order/**'],
  String home = '/welcome',
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'home': home,
        'routes': <String, Object?>{'allow': allow},
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  setUp(dvResetKioskContainment);
  tearDown(dvResetKioskContainment);

  test('with no kiosk running, every route is somebody else\'s question', () {
    expect(dvKioskRouteRedirect('/admin'), isNull);
  });

  test('a route outside the list is sent to the attract route', () {
    dvApplyKioskContainment(_policy());

    expect(dvKioskRouteRedirect('/admin'), '/welcome');
  });

  test('a route on the list is left alone', () {
    dvApplyKioskContainment(_policy());

    expect(dvKioskRouteRedirect('/order/12'), isNull);
    expect(dvKioskRouteRedirect('/welcome'), isNull);
  });

  test('an empty list still means every route, as the policy says', () {
    // The documented default. Read as "allow nothing" it would send the
    // kiosk to its home route and then refuse the home route.
    dvApplyKioskContainment(_policy(allow: const <String>[]));

    expect(dvKioskRouteRedirect('/anything'), isNull);
  });

  test('home is never redirected, even when the list forgets it', () {
    // The failure this stops is a loop rather than a wrong page: home
    // redirects to home, and go_router gives up with a redirect-limit error
    // on a kiosk that has nothing else to show.
    dvApplyKioskContainment(_policy(allow: const <String>['/order/**']));

    expect(dvKioskRouteRedirect('/welcome'), isNull);
    expect(dvKioskRouteRedirect('/admin'), '/welcome');
  });

  test('staff mode lifts it, the way the rest of the policy lifts', () {
    // An engineer at the machine with the exit method needs the pages the
    // queue must not reach. That is what staff mode is for.
    dvApplyKioskContainment(null);

    expect(dvKioskRouteRedirect('/admin'), isNull);
  });

  test('a query string does not smuggle a route past the list', () {
    dvApplyKioskContainment(_policy());

    expect(dvKioskRouteRedirect('/admin?next=/order/1'), '/welcome');
  });
}
