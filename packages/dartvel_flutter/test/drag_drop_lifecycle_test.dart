import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';

void main() {
  var starts = 0;
  var stops = 0;
  setUp(() {
    DVDragDrop.reset();
    starts = stops = 0;
    DVNativeBridge.register('dragDrop.accept', (_) {
      starts++;
      return true;
    });
    DVNativeBridge.register('dragDrop.stop', (_) {
      stops++;
      return true;
    });
  });
  tearDown(() {
    DVDragDrop.reset();
    DVNativeBridge.unregister('dragDrop.accept');
    DVNativeBridge.unregister('dragDrop.stop');
  });
  DVDropTargetRegistration target(List<DVDropEvent> into) =>
      DVDropTargetRegistration(
        bounds: () => const Rect.fromLTWH(0, 0, 100, 100),
        types: {.text},
        onDrop: into.add,
      );

  test(
    'window filters payloads even when native binding accepts everything',
    () async {
      final received = <DVDropEvent>[];
      await const DVDragDrop().accept(types: [.text], onDrop: received.add);
      DVDragDrop.dispatch(const DVDropEvent(paths: ['/tmp/a']));
      DVDragDrop.dispatch(const DVDropEvent(text: 'yes', paths: ['/tmp/b']));
      expect(received, hasLength(1));
      expect(received.single.paths, isEmpty);
      expect(received.single.text, 'yes');
    },
  );

  test('stopping the window keeps widget targets live', () async {
    final received = <DVDropEvent>[];
    final registration = target(received);
    await const DVDragDrop().accept();
    await DVDragDrop.addTarget(registration);
    await const DVDragDrop().stop();
    expect(
      stops,
      0,
      reason: 'native listener must remain while a widget needs it',
    );
    DVDragDrop.dispatch(const DVDropEvent(text: 'widget', x: 20, y: 20));
    expect(received.single.text, 'widget');
    DVDragDrop.removeTarget(registration);
    await Future<void>.delayed(.zero);
    expect(stops, 1);
  });

  test(
    'multiple widgets share one native listener until last disposal',
    () async {
      final a = target([]), b = target([]);
      await DVDragDrop.addTarget(a);
      await DVDragDrop.addTarget(b);
      expect(starts, 1);
      DVDragDrop.removeTarget(a);
      await Future<void>.delayed(.zero);
      expect(stops, 0);
      DVDragDrop.removeTarget(b);
      await Future<void>.delayed(.zero);
      expect(stops, 1);
    },
  );
  testWidgets('native pending-only drags never call unsupported startDrag', (
    tester,
  ) async {
    DVNativeBridge.unregister('dragDrop.startDrag');
    final pending = <Object?>[];
    DVNativeBridge.register('dragDrop.setPending', (value) {
      pending.add(value);
      return true;
    });
    addTearDown(() => DVNativeBridge.unregister('dragDrop.setPending'));
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Center(
          child: DVDraggable(
            payload: const DVDragPayload(text: 'link'),
            child: const ColoredBox(
              color: Color(0xff000000),
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DVDraggable)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(pending.first, isA<Map>());
    expect(pending.last, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('rebuilding a drop target updates its accepted types', (
    tester,
  ) async {
    final received = <DVDropEvent>[];
    Widget build(Set<DVDropType> types) => Directionality(
      textDirection: .ltr,
      child: Center(
        child: DVDropTarget(
          spec: DVDropTargetSpec(onDrop: received.add, types: types),
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    await tester.pumpWidget(build({.text}));
    await tester.pumpWidget(build({.files}));
    final at = tester.getCenter(find.byType(DVDropTarget));
    DVDragDrop.dispatch(DVDropEvent(text: 'stale', x: at.dx, y: at.dy));
    DVDragDrop.dispatch(
      DVDropEvent(paths: ['/tmp/new.txt'], x: at.dx, y: at.dy),
    );
    expect(received, hasLength(1));
    expect(received.single.paths, ['/tmp/new.txt']);
    await tester.pumpWidget(const SizedBox());
  });
}
