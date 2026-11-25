// A layout with a header that stays put and a page and footer that scroll
// beneath it, with no scroll code in the app (owner, 17 Nov 2026). sigmadev
// wrote that by hand -- a DVBox.scrollableList in an Expanded, under the
// header -- and so did dartvel.dev, with a SingleChildScrollView in every
// page. A layout now says what its header and footer are and the framework
// scrolls the rest.
//
// And the page scrollbar is left out where scrolling is a finger's (a phone,
// a tablet, Android, iOS) and kept on desktop, which sigmadev also did by
// hand.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/page_viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Layout extends DartvelLayout {
  const _Layout({required super.child, super.pageScrollToTop});

  @override
  Widget? get header => const SizedBox(height: 60, child: Text('Header'));

  @override
  Widget? get footer => const SizedBox(height: 80, child: Text('Footer'));
}

Widget longPage() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int row = 0; row < 40; row++) SizedBox(height: 50, child: Text('Row $row')),
      ],
    );

Widget shell(Widget page) => MaterialApp(home: DVPageShell(spec: const DVPageScaffoldSpec(), child: page));

List<ScrollPosition> scrolling(WidgetTester tester) => <ScrollPosition>[
      for (final ScrollableState state in tester.stateList<ScrollableState>(find.byType(Scrollable)))
        if (state.position.hasContentDimensions && state.position.maxScrollExtent > 0) state.position,
    ];

void main() {
  setUp(DVPageScrollMemory.reset);
  tearDown(DVPageScrollMemory.reset);

  testWidgets('the header stays put; the page and footer scroll beneath it', (WidgetTester tester) async {
    await tester.pumpWidget(shell(_Layout(child: longPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(scrolling(tester), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Header')).dy, 0);
    // The footer comes after the page and is reached by scrolling.
    expect(tester.getRect(find.text('Footer')).bottom, lessThanOrEqualTo(600));
    expect(tester.getTopLeft(find.text('Footer')).dy, greaterThan(tester.getTopLeft(find.text('Row 39')).dy));
  });

  testWidgets('on a short page the footer sits at the bottom of the screen', (WidgetTester tester) async {
    await tester.pumpWidget(shell(const _Layout(child: Text('Short'))));
    await tester.pumpAndSettle();
    expect(scrolling(tester), isEmpty);
    expect(tester.getBottomLeft(find.ancestor(of: find.text('Footer'), matching: find.byType(SizedBox)).first).dy, 600);
  });

  testWidgets('a page in the layout that scrolls itself is not scrolled twice', (WidgetTester tester) async {
    await tester.pumpWidget(shell(_Layout(child: ListView(children: <Widget>[
      for (int row = 0; row < 60; row++) SizedBox(height: 50, child: Text('Item $row')),
    ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(scrolling(tester), hasLength(1));
    // The footer stays under the page, on screen.
    expect(tester.getRect(find.text('Footer')).bottom, lessThanOrEqualTo(600));
  });

  testWidgets('the back-to-top button moves the layout body', (WidgetTester tester) async {
    await tester.pumpWidget(shell(_Layout(pageScrollToTop: true, child: longPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('To the bottom'));
    await tester.pumpAndSettle();
    final ScrollPosition position = scrolling(tester).single;
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('a screen reader sees one scroll container', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(shell(_Layout(child: longPage())));
    await tester.pumpAndSettle();
    int count = 0;
    void visit(SemanticsNode node) {
      final SemanticsData data = node.getSemanticsData();
      if (data.hasAction(SemanticsAction.scrollUp) || data.hasAction(SemanticsAction.scrollDown)) count++;
      node.visitChildren((SemanticsNode child) {
        visit(child);
        return true;
      });
    }

    visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(count, 1);
    semantics.dispose();
  });

  group('the page scrollbar', () {
    Future<int> scrollbars(WidgetTester tester, {required TargetPlatform platform, Size size = const Size(1366, 768), bool touch = false}) async {
      dvPrimaryPointerIsTouch = () => touch;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: DVPageShell(spec: const DVPageScaffoldSpec(), child: longPage()),
      ));
      await tester.pumpAndSettle();
      // Material's scrollbar is a subclass of RawScrollbar, which byType misses.
      return tester.widgetList(find.byWidgetPredicate((Widget widget) => widget is RawScrollbar)).length;
    }

    testWidgets('is kept on desktop', variant: TargetPlatformVariant.only(TargetPlatform.linux), (WidgetTester tester) async {
      expect(await scrollbars(tester, platform: TargetPlatform.linux), 1);
    });

    testWidgets('is left out on a phone-width screen', variant: TargetPlatformVariant.only(TargetPlatform.linux), (WidgetTester tester) async {
      expect(await scrollbars(tester, platform: TargetPlatform.linux, size: const Size(390, 844)), 0);
    });

    testWidgets('is kept in a desktop window from 782 wide', variant: TargetPlatformVariant.only(TargetPlatform.linux), (WidgetTester tester) async {
      expect(await scrollbars(tester, platform: TargetPlatform.linux, size: const Size(800, 900)), 1);
    });

    testWidgets('is left out in a touch browser, an iPad reporting macOS', variant: TargetPlatformVariant.only(TargetPlatform.macOS), (WidgetTester tester) async {
      expect(await scrollbars(tester, platform: TargetPlatform.macOS, size: const Size(1024, 1366), touch: true), 0);
    });
  });
}
