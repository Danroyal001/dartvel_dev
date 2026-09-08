// What a page document says about how its children sit together.
//
// A box's layout was its direction and nothing else: every list and every row
// rendered with the framework's default eight-point gap, its children packed
// to the start and stretched across. A design with twenty-four points between
// cards and a row spread across the width could be described in a document
// and could not be rendered from one, so the page came out looking like a
// different design.
//
// DVBox has taken spacing, align and crossAlign since it was written. The
// renderer simply never passed them on.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties, {String layout = 'list'}) {
  final DVPageDocument document = DVPageDocument(route: '/laid-out');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box(layout: layout);
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('one'), parent: box.id);
  editor.insert(DVPageNode.text('two'), parent: box.id);
  return document;
}

/// The gap the built column actually leaves between its two children.
double gapIn(WidgetTester tester) {
  final Iterable<Element> texts = find.text('one').evaluate();
  expect(texts, isNotEmpty);
  final Rect first = tester.getRect(find.text('one'));
  final Rect second = tester.getRect(find.text('two'));
  return second.top - first.bottom;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a box with no spacing keeps the framework default', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{}));

    expect(gapIn(tester), 8);
  });

  testWidgets('a box that names its spacing gets it', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'spacing': 24}));

    expect(gapIn(tester), 24);
  });

  testWidgets('spacing of zero is zero, not the default', (WidgetTester tester) async {
    // The case a fallback swallows: `properties['spacing'] ?? 8` reads a
    // deliberate zero as "unset" only if the code is written carelessly, and
    // a design with no gaps is a real design.
    await pump(tester, pageWith(const <String, Object?>{'spacing': 0}));

    expect(gapIn(tester), 0);
  });

  testWidgets('a row spread across the width spreads', (WidgetTester tester) async {
    await pump(tester, pageWith(
      const <String, Object?>{'mainAxis': 'spaceBetween'},
      layout: 'row',
    ));

    final Rect first = tester.getRect(find.text('one'));
    final Rect second = tester.getRect(find.text('two'));
    expect(second.left - first.right, greaterThan(100),
        reason: 'space between should push them apart');
  });

  testWidgets('a cross-axis alignment is honoured', (WidgetTester tester) async {
    await pump(tester, pageWith(
      const <String, Object?>{'crossAxis': 'center'},
      layout: 'list',
    ));

    final Rect first = tester.getRect(find.text('one'));
    // Centred rather than stretched: a stretched child fills the width.
    expect(first.left, greaterThan(0));
  });

  testWidgets('a name that is not an alignment is ignored, not a crash', (WidgetTester tester) async {
    // Documents are data and can be edited by hand or arrive from an import.
    await pump(tester, pageWith(const <String, Object?>{'mainAxis': 'sideways'}));

    expect(find.text('one'), findsOneWidget);
  });

  test('the exported source carries the layout too', () {
    // An exported page that lost its spacing would compile and look wrong,
    // which is the worst of the two ways to be wrong.
    final String source = pageWith(
      const <String, Object?>{'spacing': 24, 'mainAxis': 'spaceBetween'},
      layout: 'row',
    ).toDartSource();

    expect(source, contains('spacing: 24'));
    expect(source, contains('DVAlign.spaceBetween'));
  });

  test('the inspector offers every layout property the renderer honours', () {
    // The same rule the modifier list keeps: a property the page honours and
    // the inspector cannot set is a control the builder does not have.
    expect(
      dvStudioLayoutProperties.map((DVStudioLayoutProperty p) => p.name),
      containsAll(<String>['spacing', 'mainAxis', 'crossAxis', 'columns']),
    );
    for (final DVStudioLayoutProperty property in dvStudioLayoutProperties) {
      if (property.kind == DVStudioPropertyKind.choice) {
        expect(property.choices, isNotEmpty,
            reason: '${property.name} offers no values to choose from');
      }
    }
  });

  test('every alignment name the inspector offers is one the renderer knows', () {
    // Offered and unrecognised is a control that silently does nothing.
    for (final String name in dvStudioAlignNames) {
      expect(dvStudioAlignOf(name).name, name);
    }
    for (final String name in dvStudioCrossAlignNames) {
      expect(dvStudioCrossAlignOf(name).name, name);
    }
  });

  group('how many columns a grid has', () {
    // The renderer reads it, the exporter writes it, a document can even
    // override it per breakpoint -- and the inspector offered no control for
    // it, so a grid built in the builder was permanently two columns wide.
    // That is the drift the layout list exists to prevent, in the layout list.
    // Three children, because a grid never draws more columns than it has
    // cards: two cards in a three-column grid occupy the row rather than two
    // thirds of it, which is the grid being sensible and would make a test
    // of the column count measure the child count instead.
    DVPageDocument gridWith(Map<String, Object?> properties) {
      final DVPageDocument document = DVPageDocument(route: '/grid');
      final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
      DVPageNode grid = DVPageNode.box(layout: 'grid');
      properties.forEach((String name, Object? value) {
        grid = grid.withProperty(name, value);
      });
      editor.insert(grid, parent: document.root.id);
      for (final String label in <String>['one', 'two', 'three']) {
        editor.insert(DVPageNode.text(label), parent: grid.id);
      }
      return document;
    }

    test('the inspector offers it', () {
      expect(
        dvStudioLayoutProperties.map((DVStudioLayoutProperty p) => p.name),
        contains('columns'),
      );
    });

    test('and only where it means something', () {
      // A control that does nothing is worse than one that is not there: the
      // person who sets it has decided something, and a row has no columns.
      final DVStudioLayoutProperty columns = dvStudioLayoutProperties
          .firstWhere((DVStudioLayoutProperty p) => p.name == 'columns');

      expect(columns.appliesTo('grid'), isTrue);
      expect(columns.appliesTo('row'), isFalse);

      // Spacing belongs to every layout, and saying so is what keeps the
      // rule from being a special case for one property.
      final DVStudioLayoutProperty spacing = dvStudioLayoutProperties
          .firstWhere((DVStudioLayoutProperty p) => p.name == 'spacing');
      expect(spacing.appliesTo('row'), isTrue);
      expect(spacing.appliesTo('grid'), isTrue);
    });

    testWidgets('the number reaches the grid', (WidgetTester tester) async {
      // A desktop-width surface, because the column count is a ceiling that
      // steps down on a narrow one: three columns on a phone would be three
      // cards the width of a thumbnail, so the grid asks for one. The number
      // under test is the ceiling, and it only means anything where the
      // screen allows it.
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: DVPageDocumentRenderer(
            gridWith(const <String, Object?>{'columns': 3}),
          ),
        ),
      );

      final SliverGridDelegateWithFixedCrossAxisCount delegate =
          tester.widget<GridView>(find.byType(GridView)).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
    });

    test('and the exported source carries it', () {
      expect(
        gridWith(const <String, Object?>{'columns': 3}).toDartSource(),
        contains('columns: 3'),
      );
    });
  });
}
