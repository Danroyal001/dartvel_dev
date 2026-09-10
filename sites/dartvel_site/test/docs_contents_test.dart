// A contents list that does not take you there is decoration.
//
// This page is a tutorial in nine steps and it opens with a list of them,
// which is what Laravel's docs do and most of why they read as organised
// rather than long. The list is only worth having if tapping it moves the
// page: Flutter has no fragment navigation, so the entries are not anchors
// the browser resolves -- they find an element by key and scroll to it, and
// that is a thing that can silently stop working when a section is renamed.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/docs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpDocs(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: DocsPageGeneratedPage())),
  );
  // Pumped rather than settled: every band on this page reveals itself as it
  // comes into view, so the tree is never completely still and pumpAndSettle
  // waits for a quiet frame that does not arrive.
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('every step is in the contents, and every entry is a step', (
    WidgetTester tester,
  ) async {
    // Both directions. A step missing from the list is a step nobody finds;
    // an entry naming a step that no longer exists scrolls nowhere.
    expect(kDocsTitles.keys.toSet(), kDocsOrder.toSet());
    expect(kDocsSummaries.keys.toSet(), kDocsOrder.toSet());
    expect(kDocsSteps.keys.toSet(), kDocsOrder.toSet());

    await pumpDocs(tester);
    for (final String id in kDocsOrder) {
      expect(find.text(kDocsTitles[id]!), findsWidgets, reason: id);
    }
  });

  testWidgets('dvGoToStep scrolls the page to the step it names', (
    WidgetTester tester,
  ) async {
    // The mechanism on its own, in a scrollable with nothing else going on.
    // The real page reveals every band as it comes into view, so a tap there
    // starts animations that start animations and a test cannot tell a scroll
    // that happened from one that is still happening. What can go wrong in
    // dvGoToStep is that the key names no element and it silently returns --
    // which is what this catches.
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: <Widget>[
                for (final String id in kDocsOrder)
                  SizedBox(
                    key: kDocsSteps[id],
                    height: 900,
                    child: Text(kDocsTitles[id]!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.offset, 0);

    dvGoToStep('building');
    await tester.pumpAndSettle();

    // Eighth of nine, each 900 tall, so it cannot be reached without moving.
    expect(controller.offset, greaterThan(900));
    final RenderBox box = kDocsSteps['building']!.currentContext!
        .findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset.zero).dy, lessThan(100));
  });

  testWidgets('and a step nothing has built yet is a no-op, not a crash', (
    WidgetTester tester,
  ) async {
    // Somebody taps during the first frame, or a section was renamed and the
    // key names nothing. Returning quietly is right; throwing would be a
    // crash on a link that works a moment later.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(() => dvGoToStep('building'), returnsNormally);
    expect(() => dvGoToStep('no-such-step'), returnsNormally);
  });

  testWidgets('the step nobody should skip is not numbered like a step', (
    WidgetTester tester,
  ) async {
    // "Before you depend on it" is not step nine. Numbering it put the one
    // thing a reader should not skip at the end of a queue.
    await pumpDocs(tester);
    expect(find.text('9'), findsNothing);
  });
}
