// A link has to work in whatever tree it is put in.
//
// The existing DVNavLink suite wraps every subject in a Scaffold, so it only
// ever asked whether links work inside Material. They did. On a real device
// they threw "No Material widget found" before the first frame, and four
// integration tests failed on three platforms while the widget suite stayed
// green.
//
// So these build a link with no Material ancestor at all: no MaterialApp, no
// Scaffold, no Material. That is a legitimate Dartvel tree -- a Cupertino
// page, a DVBox layout, a page with no app bar -- and the primitive cannot
// assume otherwise.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A router whose pages are plain widgets. No Material anywhere in the tree.
GoRouter bareRouter(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              Center(child: subject),
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const Center(child: Text('docs page')),
        ),
      ],
    );

Future<void> pumpBare(WidgetTester tester, Widget subject) async {
  final GoRouter router = bareRouter(subject);
  DVNavigation.attach(router);
  await tester.pumpWidget(WidgetsApp.router(
    routerConfig: router,
    color: const Color(0xFF000000),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a link builds with no Material ancestor', (tester) async {
    await pumpBare(tester, const DVNavLink(
      to: DVRouteTarget('/docs'),
      child: DVText('Docs'),
    ));

    expect(tester.takeException(), isNull,
        reason: 'a link outside Material must still build');
    expect(find.text('Docs'), findsOneWidget);
  });

  testWidgets('it navigates with no Material ancestor', (tester) async {
    await pumpBare(tester, const DVNavLink(
      to: DVRouteTarget('/docs'),
      child: DVText('Docs'),
    ));

    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();

    expect(DV.Navigation.currentPath, '/docs');
  });

  testWidgets('it takes focus and activates from the keyboard', (tester) async {
    // The reason InkWell was reached for in the first place. Whatever
    // replaces it has to keep this, or the fix trades one real bug for
    // another.
    await pumpBare(tester, const DVNavLink(
      to: DVRouteTarget('/docs'),
      autofocus: true,
      child: DVText('Docs'),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(DV.Navigation.currentPath, '/docs',
        reason: 'Enter must activate a focused link');
  });

  testWidgets('it is announced as a link with no Material ancestor',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpBare(tester, const DVNavLink(
      to: DVRouteTarget('/docs'),
      child: DVText('Docs'),
    ));

    expect(
      tester.getSemantics(find.byType(DVNavLink)),
      isSemantics(isLink: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
