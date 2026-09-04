// The link a home widget sends, and where it lands.
//
// A widget's tap is a deep link to the route Dartvel generated for it. That
// is the whole of "home widgets can launch and navigate to pages within the
// app" on Android -- and it needs the application to read the URI it was
// launched with, which needs the Activity. Until the Activity was reachable
// there was no deepLinks.initial on Android at all, so the tap opened the
// application's home route: a shortcut, not a widget.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android claims the binding a launch link needs', () {
    // Absent while the Activity was: the launch Intent belongs to it, and
    // the application Context cannot be asked what the application was
    // opened with.
    expect(DVAndroidBindings.implemented, contains('deepLinks.initial'));
  });

  group('the route a widget link carries', () {
    test('a widget link is the route it names', () {
      expect(dvAndroidLaunchRoute('dartvel://widget/widgets/step-counter'),
          '/widgets/step-counter');
    });

    test('a plain http link keeps its path', () {
      // App links arrive this way, and reading only the widget scheme would
      // drop every one of them.
      expect(dvAndroidLaunchRoute('https://example.com/orders/42'),
          '/orders/42');
    });

    test('a launch with no link is no route, not the home page', () {
      // Null rather than '/': the caller decides what to do with a normal
      // launch, and answering '/' would make every cold start look like a
      // deep link to the home page.
      expect(dvAndroidLaunchRoute(null), isNull);
      expect(dvAndroidLaunchRoute(''), isNull);
    });

    test('a link with a query keeps it', () {
      expect(dvAndroidLaunchRoute('dartvel://widget/orders?filter=open'),
          '/orders?filter=open');
    });

    test('something that is not a URI is not a route', () {
      // Whatever an Intent was carrying, it reached this as a string. A
      // route built out of nonsense would be a not-found page on launch.
      expect(dvAndroidLaunchRoute('not a uri at all'), isNull);
    });
  });
}
