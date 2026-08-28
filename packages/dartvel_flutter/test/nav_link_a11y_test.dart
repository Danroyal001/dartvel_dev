// Tab traversal and screen readers.
//
// An earlier test pressed Tab, found nothing focused, and was rewritten to
// focus the link's node directly. That made the suite pass and left the
// question unanswered: a link nobody can reach with the keyboard is not
// reachable, whatever a test that skips the keyboard says.
//
// These press the key.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              // The real page wrapper, not an approximation of it. The shell
              // is where the SelectionArea lives, and the SelectionArea is
              // what was taking the first tab stop.
              DVPageShell(
                spec: const DVPageScaffoldSpec(title: 'Links'),
                child: subject,
              ),
        ),
        for (final String p in const <String>['/one', '/two', '/three'])
          GoRoute(
            path: p,
            builder: (BuildContext context, GoRouterState state) =>
                Scaffold(body: Text('at $p')),
          ),
      ],
    );

Future<void> pump(WidgetTester tester, Widget subject) async {
  final router = routerWith(subject);
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

/// The path of the link that currently has focus, or null.
String? focusedLinkPath(WidgetTester tester) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return null;
  final context = focused.context;
  if (context == null) return null;
  DVNavLink? link;
  context.visitAncestorElements((Element element) {
    if (element.widget is DVNavLink) {
      link = element.widget as DVNavLink;
      return false;
    }
    return true;
  });
  return link?.to.path;
}

Widget threeLinks() => const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DVNavLink(to: DVRouteTarget('/one'), child: DVText('One')),
        DVNavLink(to: DVRouteTarget('/two'), child: DVText('Two')),
        DVNavLink(to: DVRouteTarget('/three'), child: DVText('Three')),
      ],
    );

void main() {
  group('keyboard traversal', () {
    testWidgets('Tab reaches a link', (WidgetTester tester) async {
      await pump(tester, threeLinks());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(focusedLinkPath(tester), '/one',
          reason: 'the first Tab should land on the first link');
    });

    testWidgets('Tab moves through them in order',
        (WidgetTester tester) async {
      await pump(tester, threeLinks());

      final visited = <String?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        visited.add(focusedLinkPath(tester));
      }

      expect(visited, <String>['/one', '/two', '/three']);
    });

    testWidgets('Shift+Tab goes back', (WidgetTester tester) async {
      await pump(tester, threeLinks());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedLinkPath(tester), '/two');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(focusedLinkPath(tester), '/one');
    });

    testWidgets('Enter activates whichever link has focus',
        (WidgetTester tester) async {
      await pump(tester, threeLinks());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(DV.Navigation.currentPath, '/two');
    });

    testWidgets('Space activates it too', (WidgetTester tester) async {
      // A link takes Enter; a button takes Space. Taking both is what people
      // expect and costs nothing.
      await pump(tester, threeLinks());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(DV.Navigation.currentPath, '/one');
    });

    testWidgets('a disabled link is skipped rather than focused',
        (WidgetTester tester) async {
      // Tabbing onto something that does nothing is worse than not reaching
      // it: the keyboard user cannot tell it is disabled.
      await pump(tester, const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DVNavLink(
            to: DVRouteTarget('/one'),
            enabled: false,
            child: DVText('One'),
          ),
          DVNavLink(to: DVRouteTarget('/two'), child: DVText('Two')),
        ],
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(focusedLinkPath(tester), '/two');
    });

    testWidgets('focus is visible when it arrives by keyboard',
        (WidgetTester tester) async {
      // Focus nobody can see is focus nobody can follow.
      await pump(tester, threeLinks());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Asserted as a change in what is painted, not as a property on
      // whatever widget happens to be inside. The previous version of this
      // read InkWell.focusColor, which stayed non-null even when the link
      // could not build at all on a page without a Scaffold.
      Color? highlightOf(int index) => tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(DVNavLink).at(index),
            matching: find.byType(DecoratedBox),
          ))
          .map((DecoratedBox box) => (box.decoration as BoxDecoration).color)
          .firstWhere((Color? color) => color != null, orElse: () => null);

      expect(highlightOf(0), isNotNull,
          reason: 'a focused link should look focused');
      expect(highlightOf(1), isNull,
          reason: 'an unfocused link should not');
    });
  });

  group('screen readers', () {
    testWidgets('it reads as a link, with its label and destination',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/one'),
        child: DVText('Read me'),
      ));

      final node = tester.getSemantics(find.byType(DVNavLink));
      expect(node, isSemantics(isLink: true, hasTapAction: true));
      expect(node.label, contains('Read me'),
          reason: 'a link with no label announces nothing useful');
      handle.dispose();
    });

    testWidgets('an explicit label replaces the child text',
        (WidgetTester tester) async {
      // "Read more" three times on a page is three links a screen-reader user
      // cannot tell apart. The label is how you fix that.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/one'),
        semanticLabel: 'Read more about pricing',
        child: DVText('Read more'),
      ));

      expect(
        tester.getSemantics(find.byType(DVNavLink)).label,
        'Read more about pricing',
      );
      handle.dispose();
    });

    testWidgets('a disabled link does not offer a tap it will not honour',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/one'),
        enabled: false,
        child: DVText('One'),
      ));

      expect(
        tester.getSemantics(find.byType(DVNavLink)),
        isNot(isSemantics(hasTapAction: true)),
      );
      handle.dispose();
    });

    testWidgets('the preview card is not announced',
        (WidgetTester tester) async {
      // It is a picture of somewhere else. Reading a whole page into the
      // middle of this one would be worse than silence.
      DVRoutePreviews.register(
        '/one',
        (BuildContext context) => const Text('a whole other page'),
      );
      addTearDown(DVRoutePreviews.clear);

      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/one'),
        child: DVText('One'),
      ));

      await tester.longPress(find.text('One'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('a whole other page'), findsOneWidget);
      expect(
        find.bySemanticsLabel('a whole other page'),
        findsNothing,
        reason: 'the preview should be visible, not announced',
      );
      handle.dispose();
    });
  });

  group('requesting and accepting focus', () {
    testWidgets('a link accepts focus when asked', (WidgetTester tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/one'),
        focusNode: node,
        child: const DVText('One'),
      ));

      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isTrue);
      expect(focusedLinkPath(tester), '/one');
    });

    testWidgets('a disabled link refuses it', (WidgetTester tester) async {
      // Refuses rather than takes-and-does-nothing: focus sitting on
      // something inert is a dead end a keyboard user has to escape.
      final node = FocusNode();
      addTearDown(node.dispose);

      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/one'),
        focusNode: node,
        enabled: false,
        child: const DVText('One'),
      ));

      node.requestFocus();
      await tester.pump();

      expect(node.hasFocus, isFalse);
    });

    testWidgets('autofocus takes it on arrival', (WidgetTester tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/one'),
        focusNode: node,
        autofocus: true,
        child: const DVText('One'),
      ));
      await tester.pump();

      expect(node.hasFocus, isTrue);
    });

    testWidgets('a link gives focus up when it goes away',
        (WidgetTester tester) async {
      // A node still holding focus after its widget is gone strands the
      // keyboard: Tab starts from nowhere.
      final node = FocusNode();
      addTearDown(node.dispose);

      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/one'),
        focusNode: node,
        child: const DVText('One'),
      ));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await pump(tester, const SizedBox.shrink());
      await tester.pump();

      expect(node.hasFocus, isFalse);
    });
  });
}
