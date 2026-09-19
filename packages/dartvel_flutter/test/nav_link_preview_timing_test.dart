// A preview never gets in the way of a click.
//
// The owner's report: "link seems to be slowing down navigation, cos it tries
// to load the preview first". A preview renders the destination page, which is
// a whole page built in one frame, and it was scheduled half a second after
// the pointer arrived -- about the time a reader takes to click. Resting on a
// link is a deliberate act and now waits longer; and when the wait is over the
// preview is built as an idle task, so it cannot land in the frame a click
// needs. A press cancels it either way.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int docsVisits = 0;

String? _count(BuildContext context, GoRouterState state) {
  if (state.uri.path == '/docs') docsVisits++;
  return null;
}

Future<void> pumpPage(WidgetTester tester) async {
  docsVisits = 0;
  final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: _count,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext c, GoRouterState s) => const Scaffold(
          body: Center(
            child: DVNavLink(
              to: DVRouteTarget('/docs'),
              preload: DVLinkPreload.none,
              child: DVText('Docs'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/docs',
        builder: (BuildContext c, GoRouterState s) =>
            const Scaffold(body: Text('docs page')),
      ),
    ],
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  setUp(() {
    DVRoutePreviews.clear();
    DVRoutePreviews.register(
      '/docs',
      (BuildContext context) => const Text('the docs preview'),
    );
  });
  tearDown(DVRoutePreviews.clear);

  testWidgets('a reader who clicks while hovering navigates, with no preview',
      (WidgetTester tester) async {
    await pumpPage(tester);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Docs')));
    // Long enough to have shown a preview under the old half-second wait.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('the docs preview'), findsNothing);

    await mouse.down(tester.getCenter(find.text('Docs')));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(docsVisits, 1);
    await tester.idle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('the docs preview'), findsNothing,
        reason: 'a cancelled preview must not arrive after the navigation');
  });

  testWidgets('resting long enough shows it, once the app is idle',
      (WidgetTester tester) async {
    await pumpPage(tester);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Docs')));
    await tester.pump(dvLinkPreviewDelay + const Duration(milliseconds: 50));
    await tester.idle();
    await tester.pump();

    expect(find.text('the docs preview'), findsOneWidget);
    expect(docsVisits, 0, reason: 'a preview is not a navigation');
  });

  test('the wait is long enough to be deliberate', () {
    expect(dvLinkPreviewDelay.inMilliseconds, greaterThanOrEqualTo(800));
  });
}
