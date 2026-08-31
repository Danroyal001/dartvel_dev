// What Tab reaches, on the real page rather than on a header in isolation.
//
// The browser said the first Tab goes nowhere and the second reaches the first
// link. A test that pumps only the header cannot see that: whatever is taking
// the stop lives in the page around it.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String describeFocus() {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (context == null) return 'nothing';
  String? found;
  context.visitAncestorElements((Element element) {
    final widget = element.widget;
    if (widget is DVNavLink) {
      found = 'link ${widget.to.path}';
      return false;
    }
    if (widget is Scrollable) {
      found = 'the scroll view';
      return false;
    }
    return true;
  });
  return found ?? node!.debugLabel ?? node.runtimeType.toString();
}

void main() {
  testWidgets('the first Tab reaches the first link', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          // The layout supplies the header, exactly as the generated router
          // does, so the nav under test is the real one.
          builder: (BuildContext context, GoRouterState state) =>
              const DVPageShell(
            spec: DVPageScaffoldSpec(title: 'Home'),
            child: Layout(
              child: Section(children: <Widget>[Heading('Hello')]),
            ),
          ),
        ),
        for (final String p in const <String>['/docs', '/features', '/cloud'])
          GoRoute(
            path: p,
            builder: (BuildContext context, GoRouterState state) =>
                Scaffold(body: Text('at $p')),
          ),
      ],
    );
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    final stops = <String>[];
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      stops.add(describeFocus());
    }

    // The bug this exists for: the first Tab went nowhere, and the second
    // reached the first link -- something in the page around the header was
    // taking a stop. So what matters is that the first stop is a link at all,
    // and that the stops then follow reading order.
    //
    // It used to name '/docs' as the first stop, which was over-specific: the
    // wordmark is a link to home and sits before the nav, so it is the first
    // link in reading order and should be the first stop. It reaching focus
    // is an improvement -- a header whose logo cannot be reached by keyboard
    // is a header with an unreachable link.
    expect(stops.first, isNot('nothing'),
        reason: 'Tab reached $stops — the first stop should be a link');
    expect(stops, <String>['link /', 'link /docs', 'link /features'],
        reason: 'the header links should be reached in reading order');
  });
}
