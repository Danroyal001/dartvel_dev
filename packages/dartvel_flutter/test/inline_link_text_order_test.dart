// A link inside a sentence stays inside the sentence: "... on Our work." and
// not "... on . Our work" (sigmadev.digital, Dartvel main after 3.47.8: 25
// pages of the server-rendered document read the link after the sentence's
// full stop).
//
// The sentence is one Text.rich with the link in a WidgetSpan. A paragraph
// with placeholders and no tappable text span merges its text and what its
// placeholders say into one semantics node, in reading order. A placeholder
// that is a node of its own (a semantics container) is not merged: it becomes
// a child of the paragraph's node, after all of its text. #303 made every
// DVNavLink a container so a link directly in a page body is named by its own
// words, and with it the link inside a sentence left the sentence: the
// document built from the semantics tree (the paragraph's text, then its
// children) read "on ." and then "Our work".
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWith(Widget page) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => DVPageShell(
            spec: const DVPageScaffoldSpec(title: 'About'),
            child: page,
          ),
        ),
        GoRoute(
          path: '/past-work',
          builder: (BuildContext context, GoRouterState state) => const Text('Past work'),
        ),
      ],
    );

/// The page's words in the order the document built from the semantics tree
/// reads them: each node's own label, then its children's.
String readingOrder(WidgetTester tester) {
  final List<String> words = <String>[];
  void visit(SemanticsNode node) {
    final String label = node.getSemanticsData().label.trim();
    if (label.isNotEmpty) words.add(label);
    for (final SemanticsNode child in node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
      visit(child);
    }
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return words.join(' ').replaceAll(RegExp(r'\s+'), ' ');
}

/// Every semantics node that is a link.
List<SemanticsData> links(WidgetTester tester) {
  final List<SemanticsData> found = <SemanticsData>[];
  void visit(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    if (data.flagsCollection.isLink) found.add(data);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return found;
}

/// A sentence with a link in it, the way a site writes one: the link is a
/// widget in the run of text.
Widget sentence() => const Text.rich(TextSpan(children: <InlineSpan>[
      TextSpan(text: 'You can read what we did for them, by industry, on '),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: DVNavLink(to: DVRouteTarget('/past-work'), padding: EdgeInsets.zero, child: Text('Our work')),
      ),
      TextSpan(text: '.'),
    ]));

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    final GoRouter router = routerWith(page);
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('a link inside a sentence is read before its full stop', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pump(
      tester,
      DVBox.list(<Widget>[
        const DVText('Who we work with'),
        sentence(),
        const DVText('Questions, or a project in mind?'),
      ], spacing: 12),
    );

    expect(readingOrder(tester), contains('by industry, on Our work .'));
    expect(readingOrder(tester), isNot(contains('on . Our work')));
    semantics.dispose();
  });

  testWidgets('and the link still goes where it says, named by its sentence only', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pump(
      tester,
      DVBox.list(<Widget>[
        const DVText('Who we work with'),
        sentence(),
        for (int i = 0; i < 10; i++) DVText('Paragraph $i after the sentence.'),
      ], spacing: 12),
    );

    final List<SemanticsData> found = links(tester);
    expect(found, hasLength(1));
    expect(found.single.linkUrl.toString(), '/past-work');
    // Never the page's other paragraphs (the #303 bug this must not undo).
    expect(found.single.label, isNot(contains('Paragraph')));
    expect(found.single.label, isNot(contains('Who we work with')));
    semantics.dispose();
  });

  testWidgets('a link beside paragraphs, not in a sentence, keeps its own node', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pump(
      tester,
      const DVBox.list(<Widget>[
        DVText('Before'),
        DVNavLink(to: DVRouteTarget('/past-work'), child: DVText('Our work')),
        DVText('After'),
      ], spacing: 12),
    );

    final List<SemanticsData> found = links(tester);
    expect(found, hasLength(1));
    expect(found.single.label, 'Our work');
    semantics.dispose();
  });
}
