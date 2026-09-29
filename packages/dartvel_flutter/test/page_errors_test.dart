// The two routes every app gets for a page that cannot be shown.
//
// These were a widget in the Studio page route and a document the build wrote
// by hand. The not-found page had no heading, so the accessibility gate that
// demands an h1 on every captured route would have failed the build the moment
// these became routes, and neither page said what it was for a reader of the
// captured text -- which is all a search engine and a crawler ever see.
//
// Both answer in the app's own theme, both are reachable by a keyboard, a
// remote and a switch, and both are links a crawler follows rather than text
// that looks like one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      home: Builder(builder: (BuildContext context) => child),
    );

/// The semantics node of the page, with its children.
SemanticsNode _semanticsRoot(WidgetTester tester) =>
    tester.getSemantics(find.byType(MaterialApp).first);

/// Every label in the tree, as one string: what a screen reader reads and
/// what a crawler sees in the captured document.
String _labels(WidgetTester tester) {
  final SemanticsNode root = _semanticsRoot(tester);
  final StringBuffer buffer = StringBuffer();
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) buffer.write('${node.label} ');
    node.visitChildren((SemanticsNode child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return buffer.toString();
}

/// The labels carried by nodes marked as headings. A heading is what the
/// capture turns into an `<h1>`, and the accessibility gate fails a build
/// whose captured route has none, so this is what these pages are tested on.
List<String> _headings(WidgetTester tester) {
  final SemanticsNode root = _semanticsRoot(tester);
  final List<String> headings = <String>[];
  void walk(SemanticsNode node) {
    if (node.flagsCollection.isHeader && node.label.isNotEmpty) {
      headings.add(node.label);
    }
    node.visitChildren((SemanticsNode child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return headings;
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_app(page));
  await tester.pumpAndSettle();
}

void main() {
  group('the not-found page', () {
    testWidgets('has a heading, because every captured route must', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpPage(tester, const DVNotFoundPage(route: '/nowhere'));
      expect(_headings(tester), contains('Page not found'));
      handle.dispose();
    });

    testWidgets('names the path that was asked for, so a wrong link is '
        'fixable', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpPage(tester, const DVNotFoundPage(route: '/artickles/2'));
      expect(_labels(tester), contains('/artickles/2'));
      handle.dispose();
    });

    testWidgets('offers the way back as a link', (WidgetTester tester) async {
      await _pumpPage(tester, const DVNotFoundPage(route: '/nowhere'));
      expect(find.text('Go to the home page'), findsOneWidget);
      expect(
        tester.widget<DVNavLink>(find.byType(DVNavLink)).to.path,
        '/',
      );
    });

    testWidgets('carries the app theme, so a bare error page is not the '
        'fallback red on yellow', (WidgetTester tester) async {
      const Color canvas = Color(0xFF102030);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(surface: canvas),
          ),
          home: Builder(
            builder: (BuildContext context) =>
                const DVNotFoundPage(route: '/nowhere'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A router's error page has no Scaffold above it, so bare text there
      // takes Flutter's error style. A Material supplies the theme's canvas
      // and the theme's text styles; neither is there by accident.
      final Material material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(DVNotFoundPage),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, isNull, reason: 'the theme supplies the colour');
      final BuildContext context = tester.element(find.text('Page not found'));
      expect(
        Theme.of(context).canvasColor,
        canvas,
        reason: 'the page was handed the app theme, not the fallback',
      );
      expect(
        tester.widget<Text>(find.text('Page not found')).style,
        Theme.of(context).textTheme.headlineMedium,
      );
    });
  });

  group('the offline page', () {
    testWidgets('says it is on the device, since the network is what is '
        'missing', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpPage(tester, const DVOfflinePage());
      expect(_labels(tester), contains('on this device'));
      handle.dispose();
    });

    testWidgets('has a heading too', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpPage(tester, const DVOfflinePage());
      expect(_headings(tester), contains('You are offline'));
      handle.dispose();
    });

    testWidgets('takes a person back to where they were once the network is '
        'back', (WidgetTester tester) async {
      await _pumpPage(
        tester,
        const DVOfflinePage(from: '/articles/one'),
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(
        tester.widget<DVNavLink>(find.byType(DVNavLink)).to.path,
        '/articles/one',
      );
    });

    testWidgets('offers the home page when there was nowhere to go back to',
        (WidgetTester tester) async {
      await _pumpPage(tester, const DVOfflinePage());
      expect(
        tester.widget<DVNavLink>(find.byType(DVNavLink)).to.path,
        '/',
      );
    });

    testWidgets('refuses a `from` that would leave the site, and refuses its '
        'own route', (WidgetTester tester) async {
      for (final String from in <String>[
        '//evil.example',
        'https://evil.example/x',
        r'/\evil.example',
        '/offline?from=%2F',
      ]) {
        await _pumpPage(tester, DVOfflinePage(from: from));
        expect(
          tester.widget<DVNavLink>(find.byType(DVNavLink)).to.path,
          '/',
          reason: 'for $from',
        );
      }
    });

    testWidgets('names the path it failed to open, so a person can tell a '
        'dead link from a dead network', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpPage(tester, const DVOfflinePage(from: '/articles/one'));
      expect(_labels(tester), contains('/articles/one'));
      handle.dispose();
    });
  });
}
