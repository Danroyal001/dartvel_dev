// Studio's own chrome is reachable and is described.
//
// Every page of a Dartvel application comes with the accessibility the
// framework carries, because the page shell declares it: Ctrl+F has text to
// match, a drag selects, the arrows scroll, a remote's D-pad and switch
// control move the focus. Studio is a page of the application like any other
// (see `studio_routes.dart`), so the page-level half came with the shell.
//
// The controls inside it did not. A button drawn as a `GestureDetector` around
// a `Container` is a picture of a button: Tab skips it, Enter does nothing, and
// a screen reader reads the words on it without ever saying it is a button.
// This file is about the two widgets every control in Studio is drawn from --
// `DVStudioIconButton` (every rail item and toolbar action) and
// `DVStudioControl` (every button) -- so one fix reaches all of them, and about
// the screen they are in, because a fix that only works on a control in
// isolation is not the same as a fix that works in Studio.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Tab, the key a keyboard and a switch-control scanner both use to move on.
Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

/// Whether a control under [finder] is holding the focus, and saying so on
/// screen: the ring is drawn on the control, because focus nobody can see is
/// focus nobody can follow.
///
/// Read from the box decoration the control draws itself, so the assertion is
/// about what a person sees rather than about which widget drew it. The
/// **width** is what separates the two: the primary control is accented too,
/// with a one-pixel border, so a colour check alone would read every Create
/// button in Studio as focused and the walk would stop on the wrong thing.
bool _focusRing(Finder finder) {
  final List<Decoration?> decorations = <Decoration?>[
    ...find
        .descendant(of: finder, matching: find.byType(Container))
        .evaluate()
        .map((Element element) => (element.widget as Container).decoration),
    ...find
        .descendant(of: finder, matching: find.byType(DecoratedBox))
        .evaluate()
        .map((Element element) => (element.widget as DecoratedBox).decoration),
  ];
  return decorations.whereType<BoxDecoration>().any((BoxDecoration box) {
    final BorderSide top = box.border?.top ?? BorderSide.none;
    return top.color == DVStudioStyle.accent && top.width == 2;
  });
}

void _nothing() {}

/// A switch drawn as the track and thumb it would really draw, so the focus
/// ring has the shape it would really be drawn around. What it is made of is
/// the widget's business; that it is a box the reader can see is the test's.
Widget _blankSwitch(BuildContext context, bool value, Color track) =>
    Container(
      width: 36,
      height: 20,
      decoration: BoxDecoration(color: track, borderRadius: .circular(99)),
    );

/// Studio's API, answering only what the rail and the first screen need.
class _Server {
  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    switch ('$method $path') {
      case 'GET api/access':
        return const DVStudioReply(200, <String, Object?>{'granted': true});
      case 'GET api/pages':
        return const DVStudioReply(200, <String, Object?>{'pages': <Object?>[]});
      case 'GET api/site':
        return const DVStudioReply(200, <String, Object?>{'pages': <Object?>[]});
    }
    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

Future<GoRouter> _studio(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final _Server server = _Server();
  final GoRouter router = GoRouter(
    initialLocation: '/__studio',
    routes: <RouteBase>[
      ...dvStudioRoutes(mount: '/__studio', transport: server.call),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// The Pages screen on its own, with a store behind it: the routed Studio needs
/// a server answering, and the parts of Studio a person presses first are on
/// Pages.
Future<void> _screen(WidgetTester tester) async {
  final SqliteDVDatabaseAdapter database = SqliteDVDatabaseAdapter.memory();
  DV.Database.configure(database);
  DVPageStore.resetCache();
  addTearDown(() {
    database.close();
    DVPageStore.resetCache();
  });
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Material(child: DVStudioScreen())),
  );
  await tester.pumpAndSettle();
}

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: route);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

void main() {
  // The rail walks the real Studio, which is a Flutter app in itself.
  setUpAll(dvStudioLoadLibrariesForTest);

  group('DVStudioIconButton', () {
    testWidgets('is a button, is named by its tooltip, and is focusable', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: _nothing,
            ),
          ),
        ),
      ));

      // Exactly what a Material button announces, which is the bar: a role, a
      // name, an enabled state, and the two actions a reader needs -- take
      // focus, and activate.
      expect(
        tester.getSemantics(find.byType(DVStudioIconButton)),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasFocusAction: true,
          hasTapAction: true,
          label: 'Refresh',
        ),
      );
      handle.dispose();
    });

    testWidgets('Tab reaches it, Enter does what the tap does, and the focus '
        'is visible', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: () => taps++,
            ),
          ),
        ),
      ));

      final Finder button = find.byType(DVStudioIconButton);
      expect(_focusRing(button), isFalse);

      await _tab(tester);
      expect(_focusRing(button), isTrue,
          reason: 'focus nobody can see is focus nobody can follow');

      await _enter(tester);
      expect(taps, 1, reason: 'the keyboard has to reach the button at all');
    });

    testWidgets('Enter activates it where Enter is a button key, as on the web',
        (WidgetTester tester) async {
      // The web binds Enter to `ButtonActivateIntent` and Space to
      // `ActivateIntent`; every other platform binds Enter to
      // `ActivateIntent`. A control that answers only one of the two is a
      // control that does nothing on the other platform, and the web is where
      // Studio is mostly used.
      //
      // `kIsWeb` is a compile-time constant, so a test cannot turn the web on.
      // The web's own bindings are installed here instead, which is the thing
      // the control has to answer to.
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.enter):
                const ButtonActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.space):
                const ActivateIntent(),
          },
          child: Scaffold(
            body: Center(
              child: DVStudioIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ));

      await _tab(tester);
      await _enter(tester);
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(taps, 2, reason: 'and Space, which is the other one');
    });

    testWidgets('one that does nothing is not a button anybody can reach', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh',
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(DVStudioIconButton)),
        matchesSemantics(label: 'Refresh'),
      );
      handle.dispose();
    });
  });

  group('DVStudioControl', () {
    testWidgets('is a button, is named by its label, and is focusable', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioControl(
              label: 'Create page',
              enabled: true,
              primary: true,
              icon: Icons.add,
              onTap: () => taps++,
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(DVStudioControl)),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasFocusAction: true,
          hasTapAction: true,
          label: 'Create page',
        ),
      );

      await _tab(tester);
      expect(_focusRing(find.byType(DVStudioControl)), isTrue,
          reason: 'and the reader has to be able to see where they are');

      await _enter(tester);
      expect(taps, 1, reason: 'Enter has to do what the mouse does');
      handle.dispose();
    });

    testWidgets('says so when it does nothing', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioControl(label: 'Publish', enabled: false),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(DVStudioControl)),
        matchesSemantics(label: 'Publish'),
      );
      handle.dispose();
    });

    testWidgets('the mouse still works on it', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioControl(
              label: 'Create page',
              enabled: true,
              onTap: () => taps++,
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(DVStudioControl));
      expect(taps, 1);
    });
  });

  group('DVStudioSwitch', () {
    testWidgets('is a switch, says which way it is set, and can be reached', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioSwitch(
              label: 'Debug override',
              on: false,
              onTap: _nothing,
              builder: _blankSwitch,
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(DVStudioSwitch)),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasFocusAction: true,
          hasTapAction: true,
          label: 'Debug override, off',
        ),
      );
      handle.dispose();
    });

    testWidgets('Tab reaches it, Space turns it, and the focus is visible', (
      WidgetTester tester,
    ) async {
      bool on = false;
      await tester.pumpWidget(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: DVStudioSwitch(
                label: 'Debug override',
                on: on,
                onTap: () => setState(() => on = !on),
                builder: (BuildContext context, bool value, Color track) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ));

      final Finder toggle = find.byType(DVStudioSwitch);
      expect(_focusRing(toggle), isFalse);
      await _tab(tester);
      expect(_focusRing(toggle), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(on, isTrue, reason: 'a switch nobody can reach is a switch off');
    });

    testWidgets('one that cannot be turned is not a control anybody reaches', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVStudioSwitch(
              label: 'Debug override',
              on: false,
              builder: _blankSwitch,
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(DVStudioSwitch)),
        matchesSemantics(label: 'Debug override, off'),
      );
      expect(_focusRing(find.byType(DVStudioSwitch)), isFalse);
      handle.dispose();
    });
  });

  group('Studio\'s rail', () {
    testWidgets('a Tab from the screen reaches a section and Enter opens it', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await _studio(tester);

      // How many times Tab to walk off the page's own focusables and into the
      // rail: however many it is, the section must be reachable, so the test
      // walks until it arrives rather than counting what is there today.
      const Key siteMap = ValueKey<String>('dv-studio-section-routes');
      bool reached = false;
      for (int i = 0; i < 20 && !reached; i++) {
        await _tab(tester);
        reached = _focusRing(find.byKey(siteMap));
      }
      expect(reached, isTrue,
          reason: 'Tab has to reach the rail, which is how a keyboard or a '
              'switch-control user changes screen at all');

      await _enter(tester);
      expect(router.state.uri.path, '/__studio/routes');
    });
  });

  group('the buttons on the screen, not only the widget in a test', () {
    // The two tests above say the widgets behave. This says Studio does: the
    // controls a person actually meets are drawn from them, so the keyboard
    // works on the screen rather than on a demo of it.

    testWidgets('Tab reaches Create page and Enter makes the page', (
      WidgetTester tester,
    ) async {
      await _screen(tester);

      // The route first, the way a person works: Create page refuses a blank
      // route rather than making one at nothing.
      await tester.enterText(find.byType(EditableText).first, '/pricing');
      await tester.pumpAndSettle();

      const Key create = ValueKey<String>('dv-studio-create');
      await _tabTo(tester, create);
      expect(_focusRing(find.byKey(create)), isTrue,
          reason: 'the one action an empty Studio has to be reachable');

      await _enter(tester);
      await tester.pumpAndSettle();

      expect(find.text('/pricing'), findsWidgets,
          reason: 'Enter on Create page has to do what the mouse does');
    });

    testWidgets('the toolbar undo is reachable once there is something to undo, '
        'and skipped while there is not', (WidgetTester tester) async {
      final SqliteDVDatabaseAdapter database =
          SqliteDVDatabaseAdapter.memory();
      DV.Database.configure(database);
      DVPageStore.resetCache();
      addTearDown(() {
        database.close();
        DVPageStore.resetCache();
      });

      await const DVPageStore().save(documentFor('/pricing', 'Plans'));
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVStudioScreen()),
      ));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-route-/pricing')));
      await tester.pumpAndSettle();

      // Nothing has been changed yet, so Undo does nothing and says so: a
      // focus stop that looks live and does nothing is worse than no stop.
      expect(_isFocusable(tester, const ValueKey<String>('dv-studio-undo')),
          isFalse);

      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, '/x');
      await tester.pumpAndSettle();

      expect(_isFocusable(tester, const ValueKey<String>('dv-studio-undo')),
          isTrue,
          reason: 'with a change to undo it is a button, so it is a focus stop');
    });
  });
}

/// Tab until [key] holds the focus, or give up. Walking rather than counting
/// keeps the test about reachability, which is the thing that was broken.
Future<void> _tabTo(WidgetTester tester, Key key, {int limit = 40}) async {
  for (int i = 0; i < limit; i++) {
    await _tab(tester);
    if (_focusRing(find.byKey(key))) return;
  }
  fail('$key was not reachable in $limit Tabs');
}

/// Whether the keyed control can take the focus at all, which is the
/// difference between "a button that is off" and "a button that is missing".
bool _isFocusable(WidgetTester tester, Key key) =>
    tester.widgetList<Focus>(
      find.descendant(of: find.byKey(key), matching: find.byType(Focus)),
    ).any((Focus focus) => focus.canRequestFocus);
