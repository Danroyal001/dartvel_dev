// Re-docking a tab is a handover, not a re-creation.
//
// The failure this file exists for is silent. A tab dragged from one window
// into another arrived on screen looking exactly right -- correct route,
// correct label, correct content -- having thrown away everything the person
// had done in it. The half-written note was gone, the list was back at the
// top, the controller behind it was a different object. Nothing threw, nothing
// logged, and a test that checked the tab was in the receiving strip passed.
//
// So every assertion here is about state that survived a move, and never about
// a method having been called. The probe below holds the three things a person
// actually notices losing: what they typed, where they had scrolled to, and
// whether the thing they were looking at is still the same thing.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVRouteTarget orders = DVRouteTarget('/orders');
const DVRouteTarget customers = DVRouteTarget('/customers');
const DVRouteTarget inbox = DVRouteTarget('/inbox');

/// A tab's content, with state a person would notice losing.
class _Probe extends StatefulWidget {
  const _Probe(this.id);

  /// Which tab this is. Taken from the tab's title so two deliberate tabs on
  /// one route are two different probes.
  final String id;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  /// How many times a probe with this id has been constructed from scratch.
  ///
  /// One means the element was reparented. Two means it was rebuilt, which is
  /// the bug even when the text happens to look right.
  static final Map<String, int> inits = <String, int>{};

  final TextEditingController text = TextEditingController();
  final ScrollController scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    inits[widget.id] = (inits[widget.id] ?? 0) + 1;
  }

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(controller: text),
          SizedBox(
            height: 120,
            child: ListView.builder(
              controller: scroll,
              itemCount: 100,
              itemExtent: 20,
              itemBuilder: (BuildContext _, int i) => Text('${widget.id} $i'),
            ),
          ),
        ],
      );
}

Finder probe(String id) =>
    find.byWidgetPredicate((Widget w) => w is _Probe && w.id == id);

Finder fieldOf(String id) =>
    find.descendant(of: probe(id), matching: find.byType(TextField));

_ProbeState _probeState(WidgetTester tester, String id) =>
    tester.state<_ProbeState>(probe(id));

Widget workspace(DVTabWorkspaceController controller) => DVTabWorkspace(
      controller: controller,
      builder: (BuildContext _, DVTab tab) => _Probe(tab.title),
    );

/// Two workspaces in one widget tree.
///
/// That is not a convenience: it is the arrangement two same-engine windows
/// are actually in. `DVWindowHost` renders every window as a `View` in one
/// `ViewCollection`, so both strips share a build owner, which is the whole
/// reason an element can move from one to the other at all.
Future<void> pumpBoth(
  WidgetTester tester,
  DVTabWorkspaceController source,
  DVTabWorkspaceController destination,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(child: workspace(source)),
          Expanded(child: workspace(destination)),
        ],
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() {
    DVWindowManager.reset();
    _ProbeState.inits.clear();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
    );
  });
  tearDown(DVWindowManager.reset);

  group('a re-docked tab keeps what was in it', () {
    testWidgets('what was typed is still typed', (WidgetTester tester) async {
      final DVTabWorkspaceController source = DVTabWorkspaceController(
          tabs: const <DVTab>[DVTab(orders), DVTab(customers)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      await tester.enterText(fieldOf('orders'), 'half-written note');
      await tester.pump();

      await source.moveTo(destination, 0);
      await tester.pump();

      expect(_probeState(tester, 'orders').text.text, 'half-written note');
    });

    testWidgets('the list is still where it was scrolled to',
        (WidgetTester tester) async {
      final DVTabWorkspaceController source = DVTabWorkspaceController(
          tabs: const <DVTab>[DVTab(orders), DVTab(customers)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      _probeState(tester, 'orders').scroll.jumpTo(300);
      await tester.pump();

      await source.moveTo(destination, 0);
      await tester.pump();

      // Both workspaces give the probe the same viewport, so an offset that
      // survived is the offset it had. A rebuilt tab reads 0 here, and looks
      // perfectly fine on screen.
      expect(_probeState(tester, 'orders').scroll.offset, closeTo(300, 0.5));
    });

    testWidgets('it is the same object, not a convincing copy',
        (WidgetTester tester) async {
      // The assertion the other two cannot make. Content rebuilt from a shared
      // model would pass both of them while every controller, every in-flight
      // request and every subscription behind it had been thrown away and
      // started again.
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders), DVTab(customers)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      final _ProbeState before = _probeState(tester, 'orders');

      await source.moveTo(destination, 0);
      await tester.pump();

      expect(identical(_probeState(tester, 'orders'), before), isTrue);
      expect(_ProbeState.inits['orders'], 1,
          reason: 'the tab was handed over, so nothing was built a second time');
    });

    testWidgets('and keeps it on the way back', (WidgetTester tester) async {
      // Re-dock is the round trip: out of a window and back into the one it
      // came from. A handover that only works in one direction is a handover
      // nobody can rely on.
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders), DVTab(customers)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      await tester.enterText(fieldOf('orders'), 'there and back');
      await tester.pump();

      await source.moveTo(destination, 0);
      await tester.pump();
      await destination.moveTo(source, destination.tabs.length - 1);
      await tester.pump();

      expect(_probeState(tester, 'orders').text.text, 'there and back');
      expect(_ProbeState.inits['orders'], 1);
    });
  });

  group('a handover moves one tab and only that tab', () {
    testWidgets('moving a background tab leaves the open one alone',
        (WidgetTester tester) async {
      // The mix-up this catches is silent in the worst way: the tab that moved
      // is fine, and the tab that stayed behind quietly loses its contents.
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders), DVTab(customers)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      await tester.enterText(fieldOf('orders'), 'still being written');
      await tester.pump();

      await source.moveTo(destination, 1);
      await tester.pump();

      expect(_probeState(tester, 'orders').text.text, 'still being written');
      expect(_probeState(tester, 'customers').text.text, isEmpty,
          reason: 'a tab nobody had opened arrives empty, as it always was');
    });

    testWidgets('two deliberate tabs on one route do not share their contents',
        (WidgetTester tester) async {
      // Identity is per tab, not per route. Keyed by route, the second tab
      // would take over the first one's element the moment it was selected and
      // show a note the person had written somewhere else.
      final DVTabWorkspaceController controller = DVTabWorkspaceController(
        tabs: const <DVTab>[
          DVTab(orders, label: 'orders one'),
          DVTab(orders, label: 'orders two', duplicate: true),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: workspace(controller)),
      ));
      await tester.pump();

      await tester.enterText(fieldOf('orders one'), 'only in the first');
      await tester.pump();

      controller.activate(1);
      await tester.pump();

      expect(_probeState(tester, 'orders two').text.text, isEmpty);
    });
  });

  group('what a move reports', () {
    testWidgets('a tab that arrives whole reports a same-engine handover',
        (WidgetTester tester) async {
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      expect(await source.moveTo(destination, 0), DVWindowHandover.sameEngine);
    });

    testWidgets('a tab folded into one the receiver already had says so',
        (WidgetTester tester) async {
      // The receiver keeps its own tab and this one is closed, so nothing
      // crossed. Reporting a handover here would be the lie the whole return
      // value exists to prevent.
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      expect(await source.moveTo(destination, 0), DVWindowHandover.shared);
      expect(destination.tabs.length, 1);
    });

    test('nothing moved reports nothing', () async {
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);

      expect(await source.moveTo(destination, 7), isNull);
      expect(source.tabs.length, 1);
    });

    test('the platform says which kind of handover it can do', () {
      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true, sameEngine: true);
      expect(DV.Platform.Window.handover, DVWindowHandover.sameEngine);

      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true, sameEngine: false);
      expect(DV.Platform.Window.handover, DVWindowHandover.shared);
    });
  });

  group('where a tab can be moved to', () {
    Future<void> pumpTwoWindows(
      WidgetTester tester,
      DVTabWorkspaceController here,
      DVTabWorkspaceController there,
    ) =>
        pumpBoth(tester, here, there);

    testWidgets('a workspace is never a destination for itself',
        (WidgetTester tester) async {
      final DVTabWorkspaceController here =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController there =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      await pumpTwoWindows(tester, here, there);

      expect(here.moveDestinations, isNot(contains(here)));
      expect(here.moveDestinations, contains(there));
    });

    testWidgets('a workspace nobody can see is not a destination',
        (WidgetTester tester) async {
      // An unmounted controller has no strip to drop a tab into. Offering it
      // would move a tab somewhere that is not on screen, which reads to the
      // person who dragged it as the tab having been lost.
      final DVTabWorkspaceController here =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController there =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      await pumpTwoWindows(tester, here, there);
      expect(here.moveDestinations, contains(there));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: workspace(here)),
      ));
      await tester.pump();

      expect(here.moveDestinations, isEmpty);
    });

    testWidgets('another window is offered only where windows share an engine',
        (WidgetTester tester) async {
      // Absent rather than broken, the same rule tear-out follows. On separate
      // engines the other window is another isolate: there is no object in it
      // to hand anything to, and a move that arrives empty is worse than a
      // move that was never offered.
      final DVWindow second = DVWindow(
        route: inbox,
        kind: DVWindowKind.regular,
        presentation: DVWindowPresentation.window,
      );
      final DVTabWorkspaceController here =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController there = DVTabWorkspaceController(
          tabs: const <DVTab>[DVTab(inbox)], window: second);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      await pumpTwoWindows(tester, here, there);

      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true, sameEngine: false);
      expect(here.moveDestinations, isEmpty);

      DVWindowManager.capabilityOverride = const DVWindowingCapability(
          multiWindow: true, sameEngine: true, tearOut: true);
      expect(here.moveDestinations, contains(there));
    });

    testWidgets('a workspace in the same window is offered either way',
        (WidgetTester tester) async {
      // Two strips in one window are two panes of one widget tree whatever the
      // platform can do with windows, so a phone that has no second window at
      // all still moves a tab between them.
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
      final DVTabWorkspaceController here =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController there =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      await pumpTwoWindows(tester, here, there);

      expect(here.moveDestinations, contains(there));
    });

    testWidgets('a person can make the move, not only a controller call',
        (WidgetTester tester) async {
      // The move exists as a gesture someone can actually perform. A strip
      // whose only route to another window was a method on the controller
      // would be the same half-built feature the drag handling was before it:
      // a call a test can make and a person cannot.
      final DVTabWorkspaceController source =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await pumpBoth(tester, source, destination);

      await tester.enterText(fieldOf('orders'), 'moved by hand');
      await tester.pump();

      await tester.longPress(find.byKey(const ValueKey<String>('dv-tab-/orders')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('dv-tab-move-to-0')));
      await tester.pump();

      expect(destination.tabs.map((DVTab t) => t.route.path),
          contains('/orders'));
      expect(_probeState(tester, 'orders').text.text, 'moved by hand',
          reason: 'the same handover, whether a call or a person asked for it');
    });

    testWidgets('the drag itself never crosses a window, and says so',
        (WidgetTester tester) async {
      // Flutter 3.44 routes a drag to the view the pointer went down in, and
      // the OS grabs the pointer for that window until it comes up, so a strip
      // in another window never sees the gesture. The workspace answers that
      // honestly rather than offering a drag that ends nowhere.
      final DVTabWorkspaceController here =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final DVTabWorkspaceController there =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(inbox)]);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      await pumpTwoWindows(tester, here, there);

      expect(here.offersCrossWindowDrag, isFalse);
      expect(here.moveDestinations, isNotEmpty,
          reason: 'the move is still offered, as an action rather than a drag');
    });
  });
}
