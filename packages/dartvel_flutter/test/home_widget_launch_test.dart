// What happens after a home widget is tapped.
//
// The specification's sentence is that a home widget "can launch and navigate
// to pages within the app". Launching was built on both platforms and
// navigating was not, and the two failures look identical from the home
// screen: the application comes up, and it comes up somewhere else.
//
// Two separate faults are covered here, because they had nothing in common
// except the symptom.
//
// The first is the URL shape. A `dartvel://` link folds its host into the
// path -- `dartvel://orders/42` is `/orders/42`, which is the point -- and a
// widget's link carries a host of its own to say what kind of link it is. Run
// through the general rule, `dartvel://widget/widgets/order-status` came out
// as `/widget/widgets/order-status`, a route no application has.
//
// The second is that on Android and iOS nothing asked for the link at all.
// The capture exists at both ends -- the Activity's intent on one, the two
// AppDelegate overrides the build writes on the other -- and the launch path
// left them alone, because it starts on desktop and returns immediately
// everywhere else. Every piece of that chain was built and the value at the
// end of it was read by nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVAppLaunch.resetForTest);

  test('a widget link resolves to the route the widget was generated for', () {
    final String route = dvHomeWidgetRoute('order-status');

    expect(
      DVAppLaunch.routeFor(dvHomeWidgetLaunchUrl('dartvel', route)),
      route,
    );
  });

  test('an ordinary dartvel link still keeps its host as a segment', () {
    // The widget case is a special case, and a special case that swallowed
    // the general one would be worse than the bug it fixes: every
    // `dartvel://orders/42` link would land a segment short.
    expect(DVAppLaunch.routeFor('dartvel://orders/42'), '/orders/42');
  });

  test('a launch that carried a widget link opens that widget route',
      () async {
    final String route = dvHomeWidgetRoute('order-status');
    final List<String> opened = <String>[];

    final String? taken = await DVAppLaunch.openLaunchLink(
      link: () async => dvHomeWidgetLaunchUrl('dartvel', route),
      open: (String value) async => opened.add(value),
    );

    expect(taken, route);
    expect(opened, <String>[route]);
  });

  test('a launch that carried no link opens nothing', () async {
    // The ordinary launch: somebody tapped the application's own icon. A
    // navigation here would take them off their home screen to whichever
    // page was last linked to.
    final List<String> opened = <String>[];

    expect(
      await DVAppLaunch.openLaunchLink(
        link: () async => null,
        open: (String value) async => opened.add(value),
      ),
      isNull,
    );
    expect(opened, isEmpty);
  });

  test('a platform with no binding for the launch link opens nothing',
      () async {
    // `deepLinks.initial` is registered on Android and iOS and on the three
    // desktops, and a target without it must not take the application down
    // at startup. Throwing here would be a crash on first launch on whatever
    // platform is next.
    final List<String> opened = <String>[];

    expect(
      await DVAppLaunch.openLaunchLink(
        link: () async => throw StateError('no binding'),
        open: (String value) async => opened.add(value),
      ),
      isNull,
    );
    expect(opened, isEmpty);
  });

  test('the link a launch carried is what deep-link callers read back',
      () async {
    // DV.Platform.deepLinks is the application's own view of this, and an
    // application that reads the initial link itself has to see the same one
    // the router acted on. Two answers to "what launched this" is a page
    // opened twice, or opened and then navigated away from.
    final String link = dvHomeWidgetLaunchUrl('dartvel', '/widgets/steps');

    await DVAppLaunch.openLaunchLink(
      link: () async => link,
      open: (String _) async {},
    );

    expect(DVAppLaunch.initialLink, link);
  });

  testWidgets('the whole chain lands the application on the widget page',
      (WidgetTester tester) async {
    // The two calls the generated runtime makes, run against a real router
    // and a real binding rather than described. Every piece of this existed
    // separately and the join did not, so a test of the pieces would have
    // stayed green through the entire bug.
    //
    // The native capture is what is left out, and it is the one part that
    // cannot be run here: on a device it is the Activity's intent or the
    // AppDelegate override that puts the URL where `deepLinks.initial`
    // finds it.
    addTearDown(() => DVNativeBridge.unregister('deepLinks.initial'));
    DVNativeBridge.register(
      'deepLinks.initial',
      (Object? _) => dvHomeWidgetLaunchUrl(
          dvHomeWidgetLaunchScheme, dvHomeWidgetRoute('order-status')),
    );

    final GoRouter router = GoRouter(routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const Text('home'),
      ),
      GoRoute(
        path: '/widgets/order-status',
        builder: (BuildContext context, GoRouterState state) =>
            const Text('order status'),
      ),
    ]);
    addTearDown(router.dispose);
    addTearDown(DVNavigation.detach);
    DVNavigation.attach(router);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('home'), findsOneWidget);

    await DVAppLaunch.openLaunchLink(
      link: () => DVNativeBridge.invoke<String>('deepLinks.initial'),
      open: (String route) async =>
          DV.Navigation.navigate(DVRouteTarget(route)),
    );
    await tester.pumpAndSettle();

    expect(find.text('order status'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/widgets/order-status');
  });
}
