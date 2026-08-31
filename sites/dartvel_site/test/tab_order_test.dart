// What Tab reaches, on the real page rather than on a header in isolation.
//
// The browser said the first Tab goes nowhere and the second reaches the first
// link. A test that pumps only the header cannot see that: whatever is taking
// the stop lives in the page around it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_site/components/site.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

    expect(stops.first, 'link /docs',
        reason: 'Tab reached $stops — the first stop should be the first link');
  });
}
