// A right-click on a link offers what a link offers.
//
// The page's selection menu answered every right-click, so a link's own
// actions -- open beside this page, copy the address -- were not there, and
// the browser's menu, which has them, is off so that Flutter's can show.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late List<String> clipboard;
late List<String> opened;

Future<void> pumpPage(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext c, GoRouterState s) => const DVPageShell(
          spec: DVPageScaffoldSpec(),
          child: Center(
            child: DVNavLink(
              to: DVRouteTarget('/docs'),
              preload: DVLinkPreload.none,
              preview: DVLinkPreview.none,
              child: DVText('The docs'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/docs',
        builder: (BuildContext c, GoRouterState s) => const Text('docs'),
      ),
    ],
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

Future<void> rightClick(WidgetTester tester, Finder target) async {
  final TestGesture mouse = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    DVBrowserMenu.debugIsWeb = true;
    clipboard = <String>[];
    opened = <String>[];
    DVLinkOpener.install(
        (String url, {bool newTab = false}) =>
            opened.add('${newTab ? 'beside ' : ''}$url'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    DVBrowserMenu.debugReset();
    DVLinkOpener.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a right-click on a link offers the link\'s own actions',
      (WidgetTester tester) async {
    await pumpPage(tester);

    await rightClick(tester, find.text('The docs'));

    expect(find.text('Open in a new tab'), findsOneWidget);
    expect(find.text('Copy link address'), findsOneWidget);
    // And still the page's own, so nothing is lost by right-clicking a link.
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('copying the address copies where the link goes',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await rightClick(tester, find.text('The docs'));

    await tester.tap(find.text('Copy link address'));
    await tester.pumpAndSettle();

    expect(clipboard.single, endsWith('/docs'));
  });

  testWidgets('opening beside this page does not leave it',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await rightClick(tester, find.text('The docs'));

    await tester.tap(find.text('Open in a new tab'));
    await tester.pumpAndSettle();

    expect(opened.single, 'beside /docs');
    expect(find.text('The docs'), findsOneWidget, reason: 'still on the page');
  });

  testWidgets('a right-click away from a link keeps the page menu',
      (WidgetTester tester) async {
    await pumpPage(tester);

    // A corner of the page, well away from the centred link.
    final TestGesture mouse = await tester.startGesture(
      tester.getTopLeft(find.byType(DVPageShell)) + const Offset(30, 60),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('Open in a new tab'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });
}
