// What a lazy list has not built reaches a screen reader and the browser's
// find without anyone scrolling (Tori and Learnacer, Dartvel 3.47.7).
//
// A row that is not built has no semantics node and no text. A screen reader
// reading a page line by line (NVDA's or JAWS's virtual cursor, VoiceOver's
// VO+Right on the web) reads the document Flutter writes from the semantics
// tree, and stopped at the last row built: the footer of a layout that is one
// scrollable DVBox list, and the bottom of a long page, were never read. The
// browser's find, after a navigation inside the app, searches a copy written
// from what the page drew, and missed the same rows.
//
// On the web the rows still waiting are now built while the page is idle
// (backfill.dart). These tests turn that on, as the web has it, and drive it
// a step at a time.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:dartvel_flutter/src/lists/backfill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Header, page and footer as one scrollable DVBox list: Learnacer's layout.
Widget layoutPage({required String page, int paragraphs = 80}) => DVBox.list(<Widget>[
      const Text('Site header'),
      DVBox.list(<Widget>[
        for (int i = 0; i < paragraphs; i++) Text('$page paragraph $i about records and how long they are kept.'),
        Text('$page last paragraph'),
      ], spacing: 12),
      const Text('Footer made by somebody'),
    ], spacing: 0).scrollable();

/// Every label in the semantics tree, joined.
String semanticsText(WidgetTester tester) {
  final StringBuffer text = StringBuffer();
  void visit(SemanticsNode node) {
    text.writeln(node.getSemanticsData().label);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return text.toString();
}

/// A card of a catalogue: a link with a title, a sentence and a footer line,
/// a few dozen render objects, as a tool on sigmadev.digital is.
class ToolCardForTest extends StatelessWidget {
  const ToolCardForTest(this.number, {super.key, this.opened});

  final int number;
  final List<int>? opened;

  /// How many times any card has been built.
  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Semantics(
      link: true,
      label: 'Tool $number',
      child: GestureDetector(
        onTap: () => opened?.add(number),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Text('Tool $number')),
              Container(padding: const EdgeInsets.all(4), color: const Color(0xFF000000), child: const Text('FREE')),
            ]),
            const SizedBox(height: 8),
            Text('What tool $number does, in a sentence.'),
            const SizedBox(height: 8),
            for (int line = 0; line < 4; line++) const Padding(padding: EdgeInsets.all(2), child: SizedBox(height: 2)),
            const DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide())), child: Text('CALCULATORS')),
          ]),
        ),
      ),
    );
  }
}

/// [count] cards in a page: rows past the first screens wait (DVNearScreen).
Widget catalogue(int count, {List<int>? opened}) => DVBox.list(<Widget>[
      for (int i = 0; i < count; i++) ToolCardForTest(i, opened: opened),
    ], spacing: 12);

/// The semantics node labelled [label] exactly.
SemanticsNode semanticsNode(WidgetTester tester, String label) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (found != null) return false;
    if (node.getSemanticsData().label == label) {
      found = node;
      return false;
    }
    node.visitChildren(visit);
    return true;
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  if (found == null) fail('no semantics node labelled "$label"');
  return found!;
}

/// What the page on top drew, as the find runtime reads it.
String foundText() => DVFindInPage.paragraphs().map((DVFoundParagraph p) => p.block.text).join('\n');

/// Lets the idle-time building run to the end, a frame per step.
Future<void> idle(WidgetTester tester) async {
  for (int steps = 0; steps < 500 && DVLazyBackfill.step(); steps++) {
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  setUp(() => DVLazyBackfill.enabled = true);
  tearDown(DVLazyBackfill.reset);

  Widget screen(Widget child) => MaterialApp(
        home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Long page'), child: child),
      );

  testWidgets('a screen reader reaches the footer of a layout that is one lazy list', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(layoutPage(page: 'Home')));
    await tester.pumpAndSettle();
    // The first frame is as lazy as it was.
    expect(semanticsText(tester), isNot(contains('Footer made by somebody')));

    await idle(tester);
    final String read = semanticsText(tester);
    expect(read, contains('Home last paragraph'));
    expect(read, contains('Footer made by somebody'));
    expect(tester.getTopLeft(find.text('Site header')).dy, lessThan(100), reason: 'nothing scrolled');
    semantics.dispose();
  });

  testWidgets('a screen reader reaches the last rows of a long collection in a page', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(DVBox.list(<Widget>[
      for (int i = 0; i < 60; i++) Text('Tool number $i'),
    ], spacing: 12)));
    await tester.pumpAndSettle();
    expect(semanticsText(tester), isNot(contains('Tool number 59')));

    await idle(tester);
    expect(semanticsText(tester), contains('Tool number 59'));
    semantics.dispose();
  });

  testWidgets('the browser find reaches the rows of a page navigated to', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Home'), child: layoutPage(page: 'Home')),
    ));
    await tester.pumpAndSettle();
    await idle(tester);

    unawaitedPush(navigator.currentState!, MaterialPageRoute<void>(
      builder: (BuildContext context) =>
          DVPageShell(spec: const DVPageScaffoldSpec(title: 'Second'), child: layoutPage(page: 'Second')),
    ));
    await tester.pumpAndSettle();
    expect(foundText(), isNot(contains('Second last paragraph')), reason: 'the premise: not built at first');

    await idle(tester);
    final String found = foundText();
    expect(found, contains('Second paragraph 79'));
    expect(found, contains('Second last paragraph'));
    expect(found, contains('Footer made by somebody'));
    expect(found, isNot(contains('Home last paragraph')), reason: 'only the page on top');
  });

  // A catalogue of cards, each a few dozen render objects: sigmadev.digital's
  // 177 tools. Built whole while the page was idle, the catalogue took the
  // phone's JS heap from 15-21 MB to 50-58 MB and the frame rate in the
  // fifteen seconds after the first frame from 39-48 to 4-7 (Dartvel 3.47.9
  // risk check). What is waiting is now read for its words and let go again:
  // a screen reader and find reach every card, and only a few stay built.
  testWidgets('a long catalogue is read for its words, and few of its cards stay built', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(catalogue(200)));
    await tester.pumpAndSettle();
    expect(semanticsText(tester), isNot(contains('Tool 199')), reason: 'the first frame is as lazy as it was');

    await idle(tester);
    final String read = semanticsText(tester);
    expect(read, contains('Tool 199'));
    expect(read, contains('What tool 199 does, in a sentence.'));
    expect(foundText(), contains('What tool 199 does, in a sentence.'));
    expect(find.byType(ToolCardForTest, skipOffstage: false).evaluate().length, lessThan(60),
        reason: 'a catalogue read for its words, not kept built');
    expect(tester.getTopLeft(find.text('Tool 0')).dy, lessThan(200), reason: 'nothing scrolled');
    semantics.dispose();
  });

  testWidgets('a card read for its words reads as the link it is', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(screen(catalogue(200)));
    await tester.pumpAndSettle();
    await idle(tester);
    final SemanticsNode node = semanticsNode(tester, 'Tool 150');
    expect(node.getSemanticsData().hasFlag(SemanticsFlag.isLink), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('opening a card read for its words builds the real one and opens it', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<int> opened = <int>[];
    await tester.pumpWidget(screen(catalogue(200, opened: opened)));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(find.text('What tool 150 does, in a sentence.', skipOffstage: false), findsNothing,
        reason: 'the premise: read for its words, not built');

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsNode(tester, 'Tool 150').id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.text('What tool 150 does, in a sentence.', skipOffstage: false), findsOneWidget);
    expect(opened, <int>[150]);
    semantics.dispose();
  });

  testWidgets('find lands on a card read for its words and builds it', (WidgetTester tester) async {
    await tester.pumpWidget(screen(catalogue(200)));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(find.text('What tool 180 does, in a sentence.', skipOffstage: false), findsNothing,
        reason: 'the premise: read for its words, not built');

    final Future<bool> revealed = DVFindInPage.reveal('What tool 180 does, in a sentence.');
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    final Finder card = find.text('What tool 180 does, in a sentence.');
    expect(card, findsOneWidget);
    final double top = tester.getTopLeft(card).dy;
    expect(top, inInclusiveRange(0, 600), reason: 'scrolled to it');
  });

  testWidgets('one idle step builds no more than a few rows', (WidgetTester tester) async {
    await tester.pumpWidget(screen(catalogue(200)));
    await tester.pumpAndSettle();
    final int before = ToolCardForTest.builds;
    DVLazyBackfill.step();
    await tester.pump();
    await tester.pump();
    expect(ToolCardForTest.builds - before, lessThanOrEqualTo(DVLazyBackfill.perStep));
  });

  testWidgets('a short page has nothing to build later', (WidgetTester tester) async {
    await tester.pumpWidget(screen(DVBox.list(const <Widget>[Text('One'), Text('Two')]).scrollable()));
    await tester.pumpAndSettle();
    expect(DVLazyBackfill.step(), isFalse);
  });

  testWidgets('off the web, nothing is built ahead', (WidgetTester tester) async {
    DVLazyBackfill.enabled = false;
    await tester.pumpWidget(screen(layoutPage(page: 'Home')));
    await tester.pumpAndSettle();
    expect(DVLazyBackfill.pending, isFalse);
    expect(find.text('Footer made by somebody', skipOffstage: false), findsNothing);
  });
}

void unawaitedPush(NavigatorState navigator, Route<void> route) {
  navigator.push(route);
}
