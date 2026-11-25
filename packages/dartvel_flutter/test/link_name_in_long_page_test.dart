// A link sitting directly in a long page body is announced by its own words,
// not by the whole page's (Tori and Learnacer, Dartvel 3.47.7: a screen
// reader read a body link as "link, Long home page, Body link to second,
// Home paragraph 0 ..." -- every paragraph of the page).
//
// The link's semantics were not a node of their own. Flutter merges the
// semantics of widgets that are not containers into their parent's node when
// nothing conflicts, and plain paragraphs conflict with nothing: the page's
// text and the link's flag, address and tap became one node, a link the size
// of the page whose name was all of it. On the web that node is an <a> over
// the page.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

GoRouter routerWith(Widget page) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => DVPageShell(
            spec: const DVPageScaffoldSpec(title: 'Home'),
            child: page,
          ),
        ),
        GoRoute(
          path: '/second',
          builder: (BuildContext context, GoRouterState state) => const Text('Second'),
        ),
      ],
    );

/// Every semantics node that is a link, with what it is called.
List<SemanticsNode> linkNodes(WidgetTester tester) {
  final List<SemanticsNode> links = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isLink) links.add(node);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return links;
}

Widget longBody() => DVBox.list(<Widget>[
      const DVText('Long home page'),
      const DVNavLink(to: DVRouteTarget('/second'), child: DVText('Body link to second')),
      for (int i = 0; i < 30; i++) DVText('Home paragraph $i about records.'),
    ], spacing: 12);

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    final GoRouter router = routerWith(page);
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('a link among paragraphs is named by its own words', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pump(tester, longBody());

    final List<SemanticsNode> links = linkNodes(tester);
    expect(links, hasLength(1));
    expect(links.single.getSemanticsData().label, 'Body link to second');
    semantics.dispose();
  });

  testWidgets('and in a layout that is one scrollable list', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pump(
      tester,
      DVBox.list(<Widget>[
        const DVText('Header'),
        longBody(),
        const DVText('Footer'),
      ], spacing: 0).scrollable(),
    );

    final List<SemanticsNode> links = linkNodes(tester);
    expect(links, hasLength(1));
    expect(links.single.getSemanticsData().label, 'Body link to second');
    semantics.dispose();
  });

  testWidgets('beside a plain paragraph, outside any page', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: <Widget>[
        Text('Paragraph before'),
        DVNavLink(to: DVRouteTarget('/second'), child: Text('The link')),
        Text('Paragraph after'),
      ]),
    ));

    final List<SemanticsNode> links = linkNodes(tester);
    expect(links, hasLength(1));
    expect(links.single.getSemanticsData().label, 'The link');
    semantics.dispose();
  });
}
