// The Flutter half of the browser's find: what the page has drawn, and
// scrolling to the paragraph a match means.
//
// On the web the browser matches text in a hidden copy of the page and fires
// `beforematch`; everything after that is here, and none of it needs a
// browser. The web glue (find_platform_web.dart) writes the copy from
// [DVFindInPage.paragraphs] and calls [DVFindInPage.reveal] with the text of
// the element the browser named. The browser half is proven in
// find_in_page_browser_test.dart and end to end against a built app.
import 'package:dartvel_core/dartvel.dart' show DVFindBlock;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long page: a heading, then sixty paragraphs, most of them below the
/// fold of an 800x600 test screen.
Widget longPage({bool findable = true}) => MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Policy', findable: findable),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                headingLevel: 1,
                child: const Text('Retention policy'),
              ),
              for (int i = 0; i < 60; i++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Paragraph $i says something about records.'),
                ),
              const Text('Records are deleted after seven years.'),
            ],
          ),
        ),
      ),
    );

bool onScreen(WidgetTester tester, Finder finder) {
  final Rect rect = tester.getRect(finder);
  final Size screen =
      tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 && rect.bottom <= screen.height;
}

void main() {
  testWidgets('the paragraphs are what the page drew, in order',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());

    final List<DVFindBlock> blocks =
        DVFindInPage.paragraphs().map((DVFoundParagraph p) => p.block).toList();
    expect(blocks.first, const DVFindBlock('Retention policy', headingLevel: 1));
    expect(blocks[1].text, 'Paragraph 0 says something about records.');
    expect(blocks.last.text, 'Records are deleted after seven years.');
    // Every paragraph, built or scrolled away: a SingleChildScrollView
    // builds them all.
    expect(blocks, hasLength(62));
  });

  testWidgets('a match below the fold scrolls the page to it',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());
    final Finder target = find.text('Records are deleted after seven years.');
    expect(onScreen(tester, target), isFalse, reason: 'starts below the fold');

    final Future<bool> revealed =
        DVFindInPage.reveal('Records are deleted after seven years.');
    await tester.pumpAndSettle();

    expect(await revealed, isTrue);
    expect(onScreen(tester, target), isTrue);
  });

  testWidgets('the paragraph is highlighted, briefly',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());

    final Future<bool> revealed = DVFindInPage.reveal('Paragraph 40 says '
        'something about records.');
    // Past the scroll (its ticker starts on the first frame), inside the
    // highlight.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(DVFindInPage.highlightKey), findsOneWidget);

    final Rect highlight = tester.getRect(find.byKey(DVFindInPage.highlightKey));
    final Rect paragraph =
        tester.getRect(find.text('Paragraph 40 says something about records.'));
    expect(highlight.overlaps(paragraph), isTrue,
        reason: 'the highlight is on the paragraph that matched');

    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    expect(find.byKey(DVFindInPage.highlightKey), findsNothing,
        reason: 'gone again, not left over the page');
  });

  testWidgets('the index a runtime mirror wrote picks between repeats',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(),
        child: ListView(
          children: <Widget>[
            for (int i = 0; i < 40; i++)
              SizedBox(height: 100, child: Text(i.isEven ? 'Read more' : 'Item $i')),
          ],
        ),
      ),
    ));

    final List<DVFoundParagraph> paragraphs = DVFindInPage.paragraphs();
    final int hint = paragraphs.lastIndexWhere(
        (DVFoundParagraph p) => p.block.text == 'Read more');
    expect(hint, greaterThan(4), reason: 'a repeat below the fold');

    final Future<bool> revealed = DVFindInPage.reveal('Read more', hint: hint);
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    expect(
        onScreen(tester, find.byElementPredicate(
            (Element e) => identical(e, paragraphs[hint].context))),
        isTrue);
  });

  testWidgets('words the page does not have move nothing',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage());
    final ScrollPosition position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    final Future<bool> revealed =
        DVFindInPage.reveal('Quarterly revenue by region');
    await tester.pumpAndSettle();

    expect(await revealed, isFalse);
    expect(position.pixels, 0);
  });

  testWidgets('a page that opted out gives nothing to mirror or reveal',
      (WidgetTester tester) async {
    await tester.pumpWidget(longPage(findable: false));

    expect(DVFindInPage.active, isNotNull);
    expect(DVFindInPage.active!.findable, isFalse);
    expect(DVFindInPage.paragraphs(), isEmpty);
    final Future<bool> revealed =
        DVFindInPage.reveal('Records are deleted after seven years.');
    await tester.pumpAndSettle();
    expect(await revealed, isFalse);
  });

  testWidgets('the page on top is the one searched, not the one under it',
      (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const DVPageShell(
        spec: DVPageScaffoldSpec(),
        child: Text('The page underneath'),
      ),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const DVPageShell(
        spec: DVPageScaffoldSpec(),
        child: Text('The page on top'),
      ),
    ));
    await tester.pumpAndSettle();

    final List<String> texts = DVFindInPage.paragraphs()
        .map((DVFoundParagraph p) => p.block.text)
        .toList();
    expect(texts, contains('The page on top'));
    expect(texts, isNot(contains('The page underneath')));
  });

  testWidgets('no page, nothing to find', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('no shell')));
    expect(DVFindInPage.active, isNull);
    expect(DVFindInPage.paragraphs(), isEmpty);
  });
}
