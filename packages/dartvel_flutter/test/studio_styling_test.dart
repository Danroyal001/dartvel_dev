// The page builder's styling vocabulary.
//
// The renderer and the inspector used to keep separate lists, and they had
// already drifted: `padding` rendered while the inspector offered no control
// for it, so a property the platform honoured could not be set by the person
// using the builder. Both now read dvStudioProperties, and the first test here
// is what keeps that true.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentWith(Map<String, Object?> properties) {
  final document = DVPageDocument(route: '/styled', title: 'Styled');
  final editor = DVPageDocumentEditor(document);
  var node = DVPageNode.text('Hello');
  properties.forEach((String name, Object? value) {
    node = node.withProperty(name, value);
  });
  editor.insert(node, parent: document.root.id);
  return document;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DVPageDocumentRenderer(document))),
    );

void main() {
  group('property table', () {
    test('covers the modifiers a builder needs, not just two', () {
      final names = dvStudioProperties.map((p) => p.name).toSet();
      expect(
        names,
        containsAll(<String>[
          'fontSize', 'padding', 'margin', 'width', 'height', 'rounded',
          'color', 'backgroundColor', 'fontWeight', 'align', 'card',
          'letterSpacing', 'borderColor', 'borderWidth', 'opacity',
          'fontFamily', 'lineHeight',
          'gradientFrom', 'gradientTo', 'gradientAngle',
          'maxLines', 'overflow',
          'paddingLeft', 'paddingTop', 'paddingRight', 'paddingBottom',
          'shadowColor', 'shadowX', 'shadowY', 'shadowBlur', 'shadowSpread',
        ]),
      );
    });

    test('every property applies something for a valid value', () {
      // A property listed but inert would appear in the inspector and do
      // nothing, which is worse than not offering it.
      const sample = <String, Object?>{
        'fontSize': 18, 'letterSpacing': 1, 'padding': 8, 'margin': 4,
        'width': 100, 'height': 50, 'rounded': 6, 'color': 0xFF112233,
        'backgroundColor': '#445566', 'fontWeight': 'bold',
        'align': 'center', 'card': true,
        // A border is one decision made of two values, so the width is only
        // usable with the colour it belongs to; opacity is a fraction.
        'borderColor': '#112233', 'borderWidth': 2, 'opacity': 0.5,
        // A shadow is one decision made of five, so its parts are only
        // usable with the colour they belong to; padding has four sides and
        // each applies the whole inset.
        'shadowColor': '#33000000', 'shadowX': 0, 'shadowY': 4,
        'shadowBlur': 12, 'shadowSpread': 0,
        'paddingLeft': 8, 'paddingTop': 8, 'paddingRight': 8,
        'paddingBottom': 8,
        'fontFamily': 'Inter', 'lineHeight': 1.5,
        // A gradient is two colours and a direction, so the second colour
        // and the angle are only usable with the first.
        'gradientFrom': '#FF112233', 'gradientTo': '#FF445566',
        'gradientAngle': 90,
        // A line limit is a count, so zero lines is not a limit; the
        // overflow is one of the words a design uses.
        'maxLines': 2, 'overflow': 'ellipsis',
      };
      for (final property in dvStudioProperties) {
        expect(
          property.apply(const DVModifier(), sample[property.name], sample),
          isNotNull,
          reason: '${property.name} is offered but applies nothing',
        );
      }
    });

    test('a value it cannot use is ignored rather than guessed at', () {
      for (final property in dvStudioProperties) {
        // A free-text property has no nonsense: every non-empty string is a
        // font family somewhere, and refusing one would refuse a real
        // typeface for looking unusual.
        if (property.kind == DVStudioPropertyKind.text) continue;
        expect(
          property.apply(const DVModifier(), 'not-a-valid-value-for-anything',
              const <String, Object?>{}),
          isNull,
          reason: '${property.name} accepted nonsense',
        );
      }
    });

    test('choices are declared for the properties that have them', () {
      final byName = <String, DVStudioProperty>{
        for (final p in dvStudioProperties) p.name: p,
      };
      expect(byName['fontWeight']!.choices, contains('bold'));
      expect(byName['align']!.choices, contains('center'));
      expect(byName['padding']!.choices, isEmpty);
    });
  });

  group('colour parsing', () {
    test('accepts the integer form the @DVPage annotation uses', () {
      expect(parseDocumentColor(0xFF112233), const Color(0xFF112233));
    });

    test('accepts the #RRGGBB a web colour input produces', () {
      expect(parseDocumentColor('#112233'), const Color(0xFF112233));
      expect(parseDocumentColor('#FF112233'), const Color(0xFF112233));
    });

    test('rejects what it cannot read instead of rendering black', () {
      for (final value in <Object?>[null, 'teal', '#12', true, '#GGHHII']) {
        expect(parseDocumentColor(value), isNull, reason: '$value');
      }
    });
  });

  nodeCatalogue();

  group('rendering', () {
    testWidgets('a styled node renders', (WidgetTester tester) async {
      await pump(
        tester,
        documentWith(const <String, Object?>{
          'fontSize': 24,
          'color': 0xFF112233,
          'backgroundColor': '#EEEEEE',
          'padding': 12,
          'rounded': 8,
          'card': true,
        }),
      );

      expect(find.text('Hello'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Hello'));
      expect(text.style?.fontSize, 24,
          reason: 'fontSize must reach the rendered text');
      expect(text.style?.color, const Color(0xFF112233),
          reason: 'color must reach the rendered text');
    });

    testWidgets('an unstyled node still renders', (WidgetTester tester) async {
      await pump(tester, documentWith(const <String, Object?>{}));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('a bad colour does not break the page',
        (WidgetTester tester) async {
      await pump(
        tester,
        documentWith(const <String, Object?>{'color': 'chartreuse'}),
      );
      expect(find.text('Hello'), findsOneWidget);
    });
  });
}

// Appended: the node catalogue. Same lesson as the property table — a type has
// to be handled in the renderer, the Dart exporter and the palette, and one
// handled in only two of the three produces a page that previews correctly and
// exports to code that does not compile.
void nodeCatalogue() {
  group('leaf types', () {
    test('the catalogue covers more than text and image', () {
      final types = dvStudioLeafTypes.map((t) => t.type).toSet();
      expect(types,
          containsAll(<String>['text', 'image', 'button', 'spacer', 'divider']));
    });

    test('every type builds a widget and exports Dart source', () {
      for (final leaf in dvStudioLeafTypes) {
        final node = leaf.create();
        expect(node.type, leaf.type,
            reason: '${leaf.label} creates a node of another type');
        expect(leaf.build(node), isNotNull);
        final source = leaf.source(node, (String v) => v);
        expect(source, isNotEmpty,
            reason: '${leaf.label} exports no source');
      }
    });

    test('the palette offers exactly the types the renderer knows', () {
      final palette =
          DVStudioPaletteItem.defaults.map((i) => i.create().type).toSet();
      for (final leaf in dvStudioLeafTypes) {
        expect(palette, contains(leaf.type),
            reason: '${leaf.type} renders but is not in the palette');
      }
    });

    testWidgets('a document of every type renders', (WidgetTester tester) async {
      final document = DVPageDocument(route: '/all', title: 'All');
      final editor = DVPageDocumentEditor(document);
      for (final leaf in dvStudioLeafTypes) {
        editor.insert(leaf.create(), parent: document.root.id);
      }

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DVPageDocumentRenderer(document))),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Button'), findsOneWidget);
    });

    test('exported source mentions every node in the document', () {
      final document = DVPageDocument(route: '/all', title: 'All');
      final editor = DVPageDocumentEditor(document);
      for (final leaf in dvStudioLeafTypes) {
        editor.insert(leaf.create(), parent: document.root.id);
      }

      final source = document.toDartSource();
      expect(source, contains('DVText'));
      expect(source, contains('DVImageView'));
      expect(source, contains('semanticButton'));
      expect(source, contains('SizedBox'));
      expect(source, contains('ColoredBox'));
    });
  });
}
