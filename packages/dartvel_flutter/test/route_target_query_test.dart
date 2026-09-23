// A route with a query string is still a typed route.
//
// Signing in and coming back needed /sign-in?from=/account, and a target
// holds only a path, so every one of those call sites wrote the whole
// location out as a string. Both halves then drift when either page moves,
// and neither is a compile error -- which is the thing typed routes exist
// to prevent.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a query is added to a generated target', () {
    const DVRouteTarget signIn = DVRouteTarget('/sign-in');

    expect(
      signIn.withQuery(<String, String>{'from': '/account'}).path,
      '/sign-in?from=%2Faccount',
    );
  });

  test('a value that needs encoding is encoded', () {
    const DVRouteTarget search = DVRouteTarget('/search');

    expect(
      search.withQuery(<String, String>{'q': 'flat white & a bun'}).path,
      '/search?q=flat+white+%26+a+bun',
    );
  });

  test('more than one parameter keeps the order it was given', () {
    const DVRouteTarget settings = DVRouteTarget('/settings');

    expect(
      settings.withQuery(<String, String>{'tab': 'billing', 'open': 'plan'})
          .path,
      '/settings?tab=billing&open=plan',
    );
  });

  test('an empty query changes nothing', () {
    const DVRouteTarget home = DVRouteTarget('/');

    expect(home.withQuery(const <String, String>{}).path, '/');
  });

  test('a target that already carries a query gains the new parameters', () {
    const DVRouteTarget signIn = DVRouteTarget('/sign-in?next=1');

    expect(
      signIn.withQuery(<String, String>{'from': '/orders'}).path,
      '/sign-in?next=1&from=%2Forders',
    );
  });
}
