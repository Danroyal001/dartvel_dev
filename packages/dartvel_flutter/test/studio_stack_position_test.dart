// Where a child sits inside a free-positioned frame.
//
// A design that does not use auto-layout places everything by coordinate: a
// badge on a card, a label over a photograph, a floating button. Imported,
// the frame becomes a stack -- and a stack with no positions piles every
// child into the top-left corner, so a screen full of carefully placed
// elements comes through as a heap.
//
// The sizes already survive. The positions had nowhere to go.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(List<Map<String, Object?>> children) {
  final DVPageDocument document = DVPageDocument(route: '/placed');
  final DVPageNode stack = DVPageNode.box(layout: 'stack');
  document.root = stack;
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  for (final Map<String, Object?> properties in children) {
    DVPageNode child = DVPageNode.text('${properties['text']}');
    properties.forEach((String name, Object? value) {
      if (name != 'text') child = child.withProperty(name, value);
    });
    editor.insert(child, parent: stack.id);
  }
  return document;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a child that names a position is drawn there',
      (WidgetTester tester) async {
    await pump(tester, pageWith(<Map<String, Object?>>[
      <String, Object?>{'text': 'badge', 'left': 24, 'top': 48},
    ]));

    expect(tester.getTopLeft(find.text('badge')), const Offset(24, 48));
  });

  testWidgets('two children keep their own places', (WidgetTester tester) async {
    // The failure being fixed: without positions both are drawn at the same
    // corner and the design reads as a heap.
    await pump(tester, pageWith(<Map<String, Object?>>[
      <String, Object?>{'text': 'one', 'left': 0, 'top': 0},
      <String, Object?>{'text': 'two', 'left': 100, 'top': 200},
    ]));

    expect(tester.getTopLeft(find.text('one')), const Offset(0, 0));
    expect(tester.getTopLeft(find.text('two')), const Offset(100, 200));
  });

  testWidgets('one edge alone is enough', (WidgetTester tester) async {
    // A child pinned to the right of its parent names right and nothing
    // else. Filling the other edge in with a zero would move it.
    await pump(tester, pageWith(<Map<String, Object?>>[
      <String, Object?>{'text': 'pinned', 'right': 0},
    ]));

    expect(tester.getTopRight(find.text('pinned')).dx,
        tester.getSize(find.byType(MaterialApp)).width);
  });

  testWidgets('a child with no position is left where the stack puts it',
      (WidgetTester tester) async {
    await pump(tester, pageWith(<Map<String, Object?>>[
      <String, Object?>{'text': 'plain'},
    ]));

    expect(tester.takeException(), isNull);
    expect(find.text('plain'), findsOneWidget);
  });

  test('the position is in the exported source', () {
    final String source = pageWith(<Map<String, Object?>>[
      <String, Object?>{'text': 'badge', 'left': 24, 'top': 48},
    ]).toDartSource();

    expect(source, contains('Positioned(left: 24.0, top: 48.0'));
  });
}
