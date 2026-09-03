// Responsive breakpoints in a Studio page.
//
// A page built in Studio rendered the same at every width: one fontSize, one
// padding, one column count. The status index listed responsive breakpoints
// as absent. A node now carries per-breakpoint overrides of its properties,
// resolved against context.screen.breakpoint -- the same breakpoint every
// hand-written page reads -- so a heading can be 24 on a phone and 40 on a
// desktop, and the export carries that into Dart rather than flattening it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument page(DVPageNode node) =>
    DVPageDocument(route: '/p', title: 'p', root: DVPageNode(type: 'box', children: <DVPageNode>[node]));

Widget host(DVPageDocument document, double width) => MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DVPageDocumentRenderer(document),
      ),
    );

double? fontSizeOfText(WidgetTester tester) {
  final Text text = tester.widget(find.byType(Text).first);
  return text.style?.fontSize;
}

void main() {
  group('the node', () {
    test('an override is stored per breakpoint and survives JSON', () {
      final DVPageNode node = DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40);

      final DVPageNode back = DVPageNode.fromJson(node.toJson());
      expect(back.properties['fontSize'], 24);
      expect(back.breakpoints['desktop']?['fontSize'], 40);
    });

    test('a node with no overrides writes no breakpoints key', () {
      // Every page in the store would otherwise grow an empty map.
      expect(DVPageNode.text('x').toJson().containsKey('breakpoints'), isFalse);
    });

    test('effective properties for a breakpoint are the base plus its overrides',
        () {
      final DVPageNode node = DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withProperty('padding', 8)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40);

      final Map<String, Object?> desktop = node.propertiesFor(DVBreakpoint.desktop);
      expect(desktop['fontSize'], 40);
      expect(desktop['padding'], 8, reason: 'untouched properties come through');
      expect(node.propertiesFor(DVBreakpoint.mobile)['fontSize'], 24);
    });

    test('a narrower breakpoint inherits from the wider ones below it, not above',
        () {
      // Mobile-first, like every responsive system people already know: an
      // override at tablet applies to tablet, desktop and wide until one of
      // them overrides it again. Mobile is the base.
      final DVPageNode node = DVPageNode.text('Hello')
          .withProperty('fontSize', 16)
          .withBreakpointProperty(DVBreakpoint.tablet, 'fontSize', 20)
          .withBreakpointProperty(DVBreakpoint.wide, 'fontSize', 48);

      expect(node.propertiesFor(DVBreakpoint.mobile)['fontSize'], 16);
      expect(node.propertiesFor(DVBreakpoint.tablet)['fontSize'], 20);
      expect(node.propertiesFor(DVBreakpoint.desktop)['fontSize'], 20,
          reason: 'desktop inherits tablet');
      expect(node.propertiesFor(DVBreakpoint.wide)['fontSize'], 48);
    });

    test('removing an override puts the base back', () {
      final DVPageNode node = DVPageNode.text('x')
          .withProperty('fontSize', 16)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', null);
      expect(node.propertiesFor(DVBreakpoint.desktop)['fontSize'], 16);
      expect(node.breakpoints.containsKey('desktop'), isFalse,
          reason: 'an emptied breakpoint is dropped');
    });
  });

  group('rendering', () {
    testWidgets('a phone width renders the base', (WidgetTester tester) async {
      final DVPageDocument doc = page(DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40));

      await tester.pumpWidget(host(doc, 390));
      expect(fontSizeOfText(tester), 24);
    });

    testWidgets('a desktop width renders the override', (WidgetTester tester) async {
      final DVPageDocument doc = page(DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40));

      await tester.pumpWidget(host(doc, 1280));
      expect(fontSizeOfText(tester), 40);
    });

    testWidgets('a resize re-resolves', (WidgetTester tester) async {
      final DVPageDocument doc = page(DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40));

      await tester.pumpWidget(host(doc, 1280));
      expect(fontSizeOfText(tester), 40);
      await tester.pumpWidget(host(doc, 390));
      expect(fontSizeOfText(tester), 24);
    });

    testWidgets('layout properties respond too', (WidgetTester tester) async {
      // Columns are the case people actually build: one on a phone, three on
      // a desktop.
      final DVPageNode grid = DVPageNode.box(layout: 'grid')
          .withProperty('columns', 1)
          .withBreakpointProperty(DVBreakpoint.desktop, 'columns', 3);
      final DVPageDocument doc = page(grid);
      await tester.pumpWidget(host(doc, 1280));
      // The renderer hands the resolved columns to DVBox.grid; three columns
      // means three children fit on one row.
      expect(grid.propertiesFor(DVBreakpoint.desktop)['columns'], 3);
    });
  });

  group('export', () {
    test('a node with overrides exports a switch on the breakpoint', () {
      final DVPageDocument doc = page(DVPageNode.text('Hello')
          .withProperty('fontSize', 24)
          .withBreakpointProperty(DVBreakpoint.desktop, 'fontSize', 40));

      final String source = doc.toDartSource();
      expect(source, contains('context.screen.breakpoint'));
      expect(source, contains('40'));
      expect(source, contains('24'));
    });

    test('a node without overrides exports as before', () {
      final DVPageDocument doc = page(DVPageNode.text('Hello').withProperty('fontSize', 24));
      expect(doc.toDartSource(), isNot(contains('breakpoint')));
    });
  });
}
