import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modifier routes a drop after styling is chained', (
    tester,
  ) async {
    DVDragDrop.reset();
    final received = <DVDropEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: const DVBox(Text('Drop here')).modifier(
            const DVModifier()
                .dropTarget(onDrop: received.add, types: {.text})
                .width(160)
                .height(80),
          ),
        ),
      ),
    );
    final at = tester.getCenter(find.text('Drop here'));
    DVDragDrop.dispatch(DVDropEvent(text: 'delivered', x: at.dx, y: at.dy));
    expect(received.single.text, 'delivered');
    await tester.pumpWidget(const SizedBox());
    DVDragDrop.dispatch(DVDropEvent(text: 'disposed', x: at.dx, y: at.dy));
    expect(received, hasLength(1));
  });

  testWidgets('draggable modifier survives styling and uses local fallback', (
    tester,
  ) async {
    DVNativeBridge.unregister('dragDrop.startDrag');
    DVNativeBridge.unregister('dragDrop.setPending');
    await tester.pumpWidget(
      MaterialApp(
        home: const DVBox(Text('Drag me')).modifier(
          const DVModifier()
              .draggable(const DVDragPayload(text: 'payload'))
              .padding(8),
        ),
      ),
    );
    expect(find.byType(LongPressDraggable<DVDragPayload>), findsOneWidget);
  });
}
