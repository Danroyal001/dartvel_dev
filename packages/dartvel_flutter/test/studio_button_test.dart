// A button element looks and behaves like a button.
//
// The palette's Button was a text node announcing itself as a button and
// nothing else, so on the artboard and on the published page it was the word
// "Button" in body text: nobody could tell it from a label. And the semantics
// it did carry were a modifier the first style replaced, so a button somebody
// gave a colour stopped being a button to a screen reader.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument _page(DVPageNode node) {
  final DVPageDocument document = DVPageDocument(route: '/b', title: 'B');
  DVPageDocumentEditor(document).insert(node, parent: document.root.id);
  return document;
}

DVPageNode _paletteButton() =>
    dvStudioLeafTypes.firstWhere((DVStudioLeafType t) => t.type == 'button')
        .create();

Future<void> _pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 600, child: DVPageDocumentRenderer(document)),
        ),
      ),
    ));

/// The filled box drawn behind [text], if there is one.
BoxDecoration? _fillBehind(WidgetTester tester, Finder text) {
  for (final Element element in find
      .ancestor(of: text, matching: find.byType(DecoratedBox))
      .evaluate()) {
    final Decoration decoration = (element.widget as DecoratedBox).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration;
    }
  }
  for (final Element element in find
      .ancestor(of: text, matching: find.byType(Container))
      .evaluate()) {
    final Decoration? decoration = (element.widget as Container).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration;
    }
    final Color? color = (element.widget as Container).color;
    if (color != null) return BoxDecoration(color: color);
  }
  return null;
}

void main() {
  testWidgets('a button from the palette is drawn filled, padded and rounded',
      (WidgetTester tester) async {
    await _pump(tester, _page(_paletteButton()));

    final Finder label = find.text('Button');
    expect(label, findsOneWidget);
    final BoxDecoration? fill = _fillBehind(tester, label);
    expect(fill, isNotNull, reason: 'the button has no fill behind its label');
    expect(fill!.borderRadius, isNotNull);
    // Padded: the tap target is larger than the word on it.
    final Size text = tester.getSize(label);
    final Finder box = find
        .ancestor(of: label, matching: find.byType(DecoratedBox))
        .first;
    expect(tester.getSize(box).height, greaterThan(text.height + 8));
  });

  testWidgets('a stored button with no styling is still drawn as a button',
      (WidgetTester tester) async {
    // A page published before the palette styled its buttons.
    await _pump(tester, _page(DVPageNode.text('Order').withType('button')));

    expect(_fillBehind(tester, find.text('Order')), isNotNull);
  });

  testWidgets('a styled button is still a button to assistive technology',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _page(DVPageNode.text('Pay')
          .withType('button')
          .withProperty('backgroundColor', '#0A7A3D')),
    );

    expect(
      tester.getSemantics(find.text('Pay')),
      matchesSemantics(isButton: true, label: 'Pay'),
    );
    semantics.dispose();
  });

  test('an exported button carries its semantics in the one modifier it has',
      () {
    // Two .modifier() calls is the second replacing the first.
    final String source = _page(DVPageNode.text('Pay')
            .withType('button')
            .withProperty('backgroundColor', '#0A7A3D'))
        .toDartSource();
    final int at = source.indexOf("DVText('Pay')");
    expect(at, isNot(-1));
    final String node = source.substring(at, source.indexOf('\n', at));
    expect('.modifier('.allMatches(node).length, 1, reason: node);
    expect(node, contains('semanticButton()'));
    expect(node, contains('backgroundColor('));
  });
}
