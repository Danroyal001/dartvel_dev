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
          'letterSpacing',
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
      };
      for (final property in dvStudioProperties) {
        expect(
          property.apply(const DVModifier(), sample[property.name]),
          isNotNull,
          reason: '${property.name} is offered but applies nothing',
        );
      }
    });

    test('a value it cannot use is ignored rather than guessed at', () {
      for (final property in dvStudioProperties) {
        expect(
          property.apply(const DVModifier(), 'not-a-valid-value-for-anything'),
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
