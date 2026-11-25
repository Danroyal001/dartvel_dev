// Every Dartvel page scrolls, with no app code (owner, 17 Nov 2026: "DVPages
// should already be scrollable"). The shell had no scroll view: a page that
// did not bring its own was cut off at the bottom of the screen, which is how
// port22-watch's /hits page shipped. dartvel.dev only scrolled because every
// page wrapped itself in a SingleChildScrollView.
//
// The shell is the page's scroll view when the page needs one, and steps aside
// when the page scrolls itself or fills the screen, so there is never a second
// scroll inside the first.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/page_viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A page as an application writes it: forty rows in a column, no scroll
/// view anywhere, taller than the 600-point test screen.
Widget longColumn() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int row = 0; row < 40; row++)
          SizedBox(height: 50, child: Text('Row $row')),
        const SizedBox(height: 50, child: Text('The end')),
      ],
    );

Widget shell(Widget page, {DVPageScaffoldSpec spec = const DVPageScaffoldSpec(title: 'Long')}) =>
    MaterialApp(home: DVPageShell(spec: spec, child: page));

/// Every scroll position on screen that has somewhere to go.
List<ScrollPosition> scrolling(WidgetTester tester) => <ScrollPosition>[
      for (final ScrollableState state in tester.stateList<ScrollableState>(find.byType(Scrollable)))
        if (state.position.hasContentDimensions && state.position.maxScrollExtent > 0) state.position,
    ];

void main() {
  setUp(DVPageScrollMemory.reset);
  tearDown(DVPageScrollMemory.reset);

  group('a page taller than the screen scrolls with no app code', () {
    testWidgets('it is laid out whole, not squeezed or overflowing', (WidgetTester tester) async {
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(scrolling(tester), hasLength(1));
      expect(scrolling(tester).single.maxScrollExtent, greaterThan(1000));
    });

    testWidgets('by mouse wheel', (WidgetTester tester) async {
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(200, 300)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 400)));
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, 400);
    });

    testWidgets('by touch', (WidgetTester tester) async {
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, greaterThan(200));
    });

    testWidgets('by keyboard: Page Down, End, Home', (WidgetTester tester) async {
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final ScrollPosition position = scrolling(tester).single;
      expect(position.pixels, greaterThan(300));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.getRect(find.text('The end')).bottom, lessThanOrEqualTo(600));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
    });

    testWidgets('Tab to a control below the screen scrolls it into view', (WidgetTester tester) async {
      await tester.pumpWidget(shell(Column(children: <Widget>[
        const SizedBox(height: 1500),
        TextButton(onPressed: () {}, child: const Text('Far down')),
      ])));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final Rect button = tester.getRect(find.text('Far down'));
      expect(button.top, greaterThanOrEqualTo(0));
      expect(button.bottom, lessThanOrEqualTo(600));
    });

    testWidgets('a short page still fills the screen, so centring still centres', (WidgetTester tester) async {
      await tester.pumpWidget(shell(const Center(child: Text('Middle'))));
      await tester.pumpAndSettle();
      expect(scrolling(tester), isEmpty);
      expect(tester.getCenter(find.text('Middle')).dy, closeTo(300, 1));
    });

    testWidgets('a long DVBox list in the page builds rows only as they come near', (WidgetTester tester) async {
      await tester.pumpWidget(shell(DVBox.list(<Widget>[
        for (int row = 0; row < 300; row++) SizedBox(height: 50, child: Text('Item $row')),
      ])));
      await tester.pumpAndSettle();
      expect(scrolling(tester), hasLength(1));
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 299', skipOffstage: false), findsNothing);
    });

    testWidgets('the selection menu still offers Select all with nothing selected', (WidgetTester tester) async {
      // A Scrollable between the text and the selection area made a selection
      // container of its own, and the menu lost Select all.
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      final TestGesture mouse = await tester.startGesture(tester.getCenter(find.text('Row 2')),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Select all'), findsOneWidget);
    });

    testWidgets('a screen reader sees one scroll container', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      expect(_scrollContainers(tester), 1);
      semantics.dispose();
    });
  });

  group('no double scrolling when the page brings its own', () {
    testWidgets('a SingleChildScrollView page scrolls itself; the shell adds nothing', (WidgetTester tester) async {
      final ScrollController own = ScrollController();
      addTearDown(own.dispose);
      await tester.pumpWidget(shell(SingleChildScrollView(controller: own, child: longColumn())));
      await tester.pumpAndSettle();
      expect(scrolling(tester), <ScrollPosition>[own.position]);
      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(200, 300)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 250)));
      await tester.pumpAndSettle();
      expect(own.offset, 250);
    });

    testWidgets('one scrollbar, not two', variant: TargetPlatformVariant.only(TargetPlatform.linux), (WidgetTester tester) async {
      await tester.pumpWidget(shell(SingleChildScrollView(child: longColumn())));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Row 3'), const Offset(0, -200), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      // Material's scrollbar is a subclass of RawScrollbar, which byType misses.
      final int painted = tester.widgetList(find.byWidgetPredicate((Widget widget) => widget is RawScrollbar)).length;
      expect(painted, 1);
    });

    testWidgets('a lazy ListView page stays lazy and scrolls itself', (WidgetTester tester) async {
      await tester.pumpWidget(shell(ListView.builder(
        itemCount: 1000,
        itemBuilder: (BuildContext context, int index) => SizedBox(height: 50, child: Text('Item $index')),
      )));
      await tester.pumpAndSettle();
      expect(scrolling(tester), hasLength(1));
      expect(find.text('Item 999', skipOffstage: false), findsNothing);
    });

    testWidgets('a header over an Expanded scroll view (the dartvel.dev layout)', (WidgetTester tester) async {
      await tester.pumpWidget(shell(Column(children: <Widget>[
        const SizedBox(height: 60, child: Text('Header')),
        Expanded(child: SingleChildScrollView(child: longColumn())),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(scrolling(tester), hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      // The header stays put: only the page under it moved.
      expect(tester.getTopLeft(find.text('Header')).dy, 0);
    });

    testWidgets('a page that fills the screen with Expanded is laid out at the screen height', (WidgetTester tester) async {
      await tester.pumpWidget(shell(const Column(children: <Widget>[
        Expanded(child: ColoredBox(color: Colors.red, child: Text('Fill'))),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(scrolling(tester), isEmpty);
      expect(tester.getSize(find.byType(ColoredBox).last).height, 600);
    });

    testWidgets('a page with its own Scaffold, or SizedBox.expand (a map, a canvas)', (WidgetTester tester) async {
      for (final Widget page in <Widget>[
        const Scaffold(body: Text('Own scaffold')),
        const SizedBox.expand(child: Text('Canvas')),
      ]) {
        await tester.pumpWidget(shell(page));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(scrolling(tester), isEmpty);
      }
    });

    testWidgets('a page that loads, then shows a ListView, changes over by itself', (WidgetTester tester) async {
      final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);
      addTearDown(loaded.dispose);
      await tester.pumpWidget(shell(ValueListenableBuilder<bool>(
        valueListenable: loaded,
        builder: (BuildContext context, bool ready, Widget? _) => ready
            ? ListView(children: <Widget>[for (int i = 0; i < 50; i++) SizedBox(height: 50, child: Text('L$i'))])
            : const Center(child: Text('Loading')),
      )));
      await tester.pumpAndSettle();
      loaded.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(scrolling(tester), hasLength(1));
      expect(scrolling(tester).single.context.notificationContext!.widget, isNot(isA<DVPageViewport>()));
    });

    testWidgets('a screen reader sees the page\'s own scroll container and no other', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(shell(SingleChildScrollView(child: longColumn())));
      await tester.pumpAndSettle();
      expect(_scrollContainers(tester), 1);
      semantics.dispose();
    });

    testWidgets('@DVPage(scroll: false) turns it off', (WidgetTester tester) async {
      await tester.pumpWidget(shell(
        const SizedBox(height: 3000, child: Text('Kiosk')),
        spec: const DVPageScaffoldSpec(scroll: false),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DVPageViewport), findsNothing);
      expect(scrolling(tester), isEmpty);
    });
  });

  group('back to top and scroll restoration', () {
    testWidgets('the back-to-top button works on a page the shell scrolls', (WidgetTester tester) async {
      await tester.pumpWidget(shell(DVPageScrollFrame(child: longColumn())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('To the bottom'), findsOneWidget);
      await tester.tap(find.byTooltip('To the bottom'));
      await tester.pumpAndSettle();
      final ScrollPosition position = scrolling(tester).single;
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byTooltip('Back to top'), findsOneWidget);
    });

    testWidgets('and on a page that scrolls itself', (WidgetTester tester) async {
      await tester.pumpWidget(shell(DVPageScrollFrame(child: SingleChildScrollView(child: longColumn()))));
      await tester.pumpAndSettle();
      expect(find.byTooltip('To the bottom'), findsOneWidget);
      await tester.tap(find.byTooltip('To the bottom'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to top'), findsOneWidget);
    });

    // On the web the shell rebuilds its selection area when the browser's
    // own menu is switched on or off, which moves the page into a new scroll
    // view. The button's frame stayed with the old one, and dartvel.dev lost
    // its button on every web-server build while every VM test still found it.
    testWidgets('the button stays when the page moves into a new scroll view', (WidgetTester tester) async {
      addTearDown(() => DVBrowserMenu.debugSetNativeMenuOn(true));
      await tester.pumpWidget(shell(DVPageScrollFrame(child: SingleChildScrollView(child: longColumn()))));
      await tester.pumpAndSettle();
      expect(find.byTooltip('To the bottom'), findsOneWidget);
      DVBrowserMenu.debugSetNativeMenuOn(!DVBrowserMenu.nativeMenuOn.value);
      await tester.pumpAndSettle();
      expect(find.byTooltip('To the bottom'), findsOneWidget);
      await tester.tap(find.byTooltip('To the bottom'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to top'), findsOneWidget);
    });

    testWidgets('a page covered by a pushed route keeps its place when it is popped', (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: DVPageShell(spec: const DVPageScaffoldSpec(), child: longColumn()),
      ));
      await tester.pumpAndSettle();
      scrolling(tester).single.jumpTo(700);
      navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (BuildContext context) => const DVPageShell(spec: DVPageScaffoldSpec(), child: Text('Other')),
      ));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, 700);
    });

    testWidgets('back and forward in a browser put a rebuilt page back where it was', (WidgetTester tester) async {
      String? popped;
      DVPageScrollMemory.takeHistoryNavigation = () {
        final String? address = popped;
        popped = null;
        return address;
      };
      final GoRouter router = GoRouter(routes: <RouteBase>[
        GoRoute(path: '/', builder: (BuildContext context, GoRouterState state) => DVPageShell(spec: const DVPageScaffoldSpec(), child: longColumn())),
        GoRoute(path: '/other', builder: (BuildContext context, GoRouterState state) => const DVPageShell(spec: DVPageScaffoldSpec(), child: Text('Other'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      scrolling(tester).single.jumpTo(900);
      await tester.pump();

      router.go('/other');
      await tester.pumpAndSettle();
      // The browser's back: the page is built again from nothing.
      popped = 'http://localhost/';
      router.go('/');
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, 900);

      // A link to the same page is a new visit, and starts at the top.
      router.go('/other');
      await tester.pumpAndSettle();
      router.go('/');
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, 0);
    });

    testWidgets('taking over from the server-rendered document keeps its scroll position', (WidgetTester tester) async {
      double handed = 640;
      DVPageScrollMemory.takeTakeoverScroll = () {
        final double offset = handed;
        handed = 0;
        return offset;
      };
      await tester.pumpWidget(shell(longColumn()));
      await tester.pumpAndSettle();
      expect(scrolling(tester).single.pixels, 640);
    });
  });
}

/// How many semantics nodes a screen reader can scroll.
int _scrollContainers(WidgetTester tester) {
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
  return count;
}
