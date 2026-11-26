// The long-page button's semantics node is its own drawn box, not the page.
//
// sigmadev.digital (3.47.11 to 3.47.13) published "To the bottom" as a node
// the size of the whole window with every link of the page inside it: the
// button's Semantics was not a node of its own, so Flutter merged its name,
// role and tap up into the page shell's node. In the browser that node took
// every click: a click on the header logo scrolled to the bottom, the next one
// back to the top, and the link never opened. #326 kept the server-rendered
// document from drawing that node over the page, but the app's own semantics
// tree, after takeover, still had it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// sigmadev's layout: a header with a link over a page that scrolls itself.
class _SiteLayout extends DartvelLayout {
  const _SiteLayout({required super.child}) : super(pageScrollToTop: true);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 70,
            child: const DVNavLink.external('https://example.com/', child: Text('Home')),
          ),
          Expanded(child: child),
        ],
      );
}

class _LongPage extends StatelessWidget {
  const _LongPage();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int row = 0; row < 80; row++) SizedBox(height: 50, child: Text('Row $row')),
          ],
        ),
      );
}

/// [node]'s box in window coordinates.
Rect globalRect(SemanticsNode node) {
  Rect rect = node.rect;
  for (SemanticsNode? at = node; at != null; at = at.parent) {
    if (at.transform != null) rect = MatrixUtils.transformRect(at.transform!, rect);
  }
  return rect;
}

bool hasLabel(SemanticsNode node, String label) {
  if (node.label == label) return true;
  bool found = false;
  node.visitChildren((SemanticsNode child) {
    found = found || hasLabel(child, label);
    return !found;
  });
  return found;
}

void main() {
  floatingControlTests();
  for (final Size size in const <Size>[Size(1366, 900), Size(390, 844)]) {
    testWidgets('at ${size.width.toInt()} px the button node is its 44 px circle, holding nothing of the page',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Long'), child: const _SiteLayout(child: _LongPage())),
      ));
      await tester.pump();
      await tester.pump();

      final SemanticsNode button = tester.getSemantics(find.bySemanticsLabel('To the bottom'));
      final Rect box = globalRect(button);
      expect(box.width, lessThanOrEqualTo(48), reason: 'node box $box');
      expect(box.height, lessThanOrEqualTo(48), reason: 'node box $box');
      expect(box.right, greaterThan(size.width - 80), reason: 'node box $box');
      expect(box.bottom, greaterThan(size.height - 80), reason: 'node box $box');
      expect(hasLabel(button, 'Home'), isFalse, reason: 'the header link is inside the button node');
      expect(hasLabel(button, 'Row 0'), isFalse, reason: 'the page is inside the button node');
      semantics.dispose();
    });
  }
}

/// Any tappable Dartvel control laid over the page, alone in its layer, keeps
/// a node of its own: the same merge took the long-page button's tap up into
/// the window-sized node, and would do it to a floating chat or cookie button.
class _FloatingControlPage extends StatelessWidget {
  const _FloatingControlPage({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          const Positioned.fill(child: _LongPage()),
          Positioned(
            right: 20,
            bottom: 20,
            child: DVText('Chat').modifier(DVModifier().onTap(onTap)),
          ),
        ],
      );
}

void floatingControlTests() {
  testWidgets('a tappable control floating over the page keeps its own small node', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _FloatingControlPage(onTap: () {}))));
    await tester.pump();
    final SemanticsNode control = tester.getSemantics(find.bySemanticsLabel('Chat'));
    final Rect box = globalRect(control);
    expect(box.width, lessThan(200), reason: 'node box $box');
    expect(box.height, lessThan(200), reason: 'node box $box');
    expect(hasLabel(control, 'Row 0'), isFalse, reason: 'the page is inside the control node');
    semantics.dispose();
  });
}
