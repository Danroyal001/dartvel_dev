import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drag and drop beyond the desktop window: the shared event, routing a drop
/// to the widget under it, the picker fallback, and dragging inside the
/// application on a target with no system drag and drop.
void main() {
  setUp(() {
    DVDragDrop.reset();
    for (final String name in <String>[
      'dragDrop.accept', 'dragDrop.stop', 'dragDrop.startDrag', 'dragDrop.setPending',
      'dialogs.openFile', 'media.pick',
    ]) {
      DVNativeBridge.unregister(name);
    }
  });

  group('the shared drop event', () {
    test('reads files a platform gave without a path, through its reader', () async {
      final DVDropEvent event = DVDropEvent.fromMap(<String, Object?>{
        'files': <Object?>[
          <String, Object?>{'name': 'photo.jpg', 'uri': 'content://media/external/images/1', 'size': 3},
          <String, Object?>{'name': 'notes', 'mimeType': 'text/plain'},
        ],
        'urls': <Object?>['https://dartvel.dev/docs', 'not a url'],
        'text': 'hello',
        'x': 10,
        'y': 20,
      }, readers: (int index) async => <int>[index, index, index]);
      expect(event.files.map((DVIncomingFile file) => file.name), <String>['photo.jpg', 'notes']);
      expect(event.files.first.mimeType, 'image/jpeg', reason: 'guessed from the extension');
      expect(event.files.first.uri.toString(), 'content://media/external/images/1');
      expect(event.files.last.mimeType, 'text/plain', reason: 'the platform said');
      expect(await event.files.last.readBytes(), Uint8List.fromList(<int>[1, 1, 1]));
      expect(event.urls, <Uri>[Uri.parse('https://dartvel.dev/docs')]);
      expect(event.text, 'hello');
      expect(event.position, const Offset(10, 20));
    });

    test('desktop paths still arrive as paths, and as files', () {
      final DVDropEvent event = DVDropEvent.fromMap(<String, Object?>{
        'paths': <Object?>['/home/me/report.pdf'],
      });
      expect(event.paths, <String>['/home/me/report.pdf']);
      expect(event.files.single.name, 'report.pdf');
      expect(event.files.single.mimeType, 'application/pdf');
    });

    test('a drop carrying only a link is not empty', () {
      expect(DVDropEvent(urls: <Uri>[Uri.parse('https://a.b')]).isEmpty, isFalse);
      expect(const DVDropEvent().isEmpty, isTrue);
    });
  });

  group('routing a drop', () {
    DVDropTargetRegistration target(Rect rect, List<DVDropEvent> into,
            {Set<DVDropType> types = const <DVDropType>{DVDropType.files, DVDropType.text, DVDropType.urls}}) =>
        DVDropTargetRegistration(bounds: () => rect, types: types, onDrop: into.add);

    test('the smallest target under the drop takes it, and nobody else', () async {
      final List<DVDropEvent> page = <DVDropEvent>[];
      final List<DVDropEvent> card = <DVDropEvent>[];
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(0, 0, 800, 600), page));
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(100, 100, 200, 100), card));
      DVDragDrop.dispatch(const DVDropEvent(text: 'in the card', x: 150, y: 150));
      DVDragDrop.dispatch(const DVDropEvent(text: 'on the page', x: 500, y: 500));
      expect(card.single.text, 'in the card');
      expect(page.single.text, 'on the page');
    });

    test('a target that does not admit what was dropped is passed over', () async {
      final List<DVDropEvent> textOnly = <DVDropEvent>[];
      final List<DVDropEvent> anything = <DVDropEvent>[];
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(0, 0, 400, 400), anything));
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(0, 0, 100, 100), textOnly,
          types: const <DVDropType>{DVDropType.text}));
      DVDragDrop.dispatch(const DVDropEvent(paths: <String>['/tmp/a.png'], x: 50, y: 50));
      expect(textOnly, isEmpty);
      expect(anything.single.files.single.name, 'a.png');
    });

    test('a target gets only the kinds it admits', () async {
      final List<DVDropEvent> textOnly = <DVDropEvent>[];
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(0, 0, 100, 100), textOnly,
          types: const <DVDropType>{DVDropType.text}));
      DVDragDrop.dispatch(const DVDropEvent(paths: <String>['/tmp/a.png'], text: 'caption', x: 5, y: 5));
      expect(textOnly.single.text, 'caption');
      expect(textOnly.single.files, isEmpty);
    });

    test('hover is reported to the target under the drag and taken back on leave', () async {
      final List<bool> hovers = <bool>[];
      await DVDragDrop.addTarget(DVDropTargetRegistration(
        bounds: () => const Rect.fromLTWH(0, 0, 100, 100),
        types: DVDropType.values.toSet(),
        onDrop: (_) {},
        onHover: hovers.add,
      ));
      DVDragDrop.dispatchHover(50, 50);
      DVDragDrop.dispatchHover(60, 60);
      DVDragDrop.dispatchHover(500, 500);
      DVDragDrop.dispatchHover(50, 50);
      DVDragDrop.dispatchLeave();
      expect(hovers, <bool>[true, false, true, false]);
    });

    test('a widget target turns on the platform drop handling it needs', () async {
      final List<Object?> accepted = <Object?>[];
      DVNativeBridge.register('dragDrop.accept', (Object? arguments) {
        accepted.add(arguments);
        return true;
      });
      await DVDragDrop.addTarget(target(const Rect.fromLTWH(0, 0, 10, 10), <DVDropEvent>[]));
      expect(accepted, hasLength(1));
    });
  });

  group('drag out', () {
    test('a drag carries its payload to the platform, with where it started', () async {
      final List<Object?> started = <Object?>[];
      DVNativeBridge.register('dragDrop.startDrag', (Object? arguments) {
        started.add(arguments);
        return true;
      });
      final bool ok = await const DVDragDrop().startDrag(
        DVDragPayload(text: 'hi', urls: <Uri>[Uri.parse('https://dartvel.dev')],
            files: const <DVOutgoingFile>[DVOutgoingFile(name: 'a.csv', bytes: <int>[1, 2])]),
        x: 3,
        y: 4,
      );
      expect(ok, isTrue);
      final Map<Object?, Object?> sent = started.single! as Map<Object?, Object?>;
      expect(sent['text'], 'hi');
      expect(sent['urls'], <String>['https://dartvel.dev']);
      expect((sent['files']! as List<Object?>).single, <String, Object?>{
        'name': 'a.csv', 'mimeType': 'text/csv', 'bytes': <int>[1, 2],
      });
      expect(sent['x'], 3);
    });

    test('an empty payload starts nothing', () async {
      expect(await const DVDragDrop().startDrag(const DVDragPayload()), isFalse);
    });

    test('a platform that starts its own drag is told the payload on pointer down', () {
      final List<Object?> pending = <Object?>[];
      DVNativeBridge.register('dragDrop.setPending', (Object? arguments) {
        pending.add(arguments);
        return true;
      });
      expect(const DVDragDrop().canDragOut, isTrue);
      DVDragDrop.pendingPayload = const DVDragPayload(text: 'x');
      expect((pending.single! as Map<Object?, Object?>)['text'], 'x');
    });
  });

  group('where there is no drag and drop', () {
    test('choosing files instead delivers them as a drop to the same handler', () async {
      DVNativeBridge.register('dialogs.openFile', (Object? _) => <Object?>['/tmp/one.txt', '/tmp/two.txt']);
      final List<DVDropEvent> seen = <DVDropEvent>[];
      final Future<void> listening = const DVDragDrop().dropped.first.then(seen.add);
      final DVDropEvent? event = await const DVDragDrop().chooseInstead();
      await listening;
      expect(event!.paths, <String>['/tmp/one.txt', '/tmp/two.txt']);
      expect(seen.single.files.map((DVIncomingFile f) => f.name), <String>['one.txt', 'two.txt']);
    });

    test('a phone without a file dialog uses its picker', () async {
      DVNativeBridge.register('media.pick', (Object? _) => <Object?>[
            <String, Object?>{'name': 'scan.pdf', 'uri': 'content://docs/1'},
          ]);
      final DVDropEvent? event = await const DVDragDrop().chooseInstead();
      expect(event!.files.single.name, 'scan.pdf');
    });

    testWidgets('widgets still drag to widgets inside the application', (WidgetTester tester) async {
      final List<DVDropEvent> dropped = <DVDropEvent>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            DVBox(const SizedBox(width: 80, height: 80, child: Text('drag me')))
                .modifier(DVModifier().draggable(const DVDragPayload(text: 'moved'))),
            const SizedBox(height: 100),
            DVBox(const SizedBox(width: 200, height: 120, child: Text('drop here')))
                .modifier(DVModifier().dropTarget(onDrop: dropped.add)),
          ]),
        ),
      ));
      expect(const DVDragDrop().canDragOut, isFalse);
      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.text('drag me')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.text('drop here')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dropped.single.text, 'moved');
    });

    testWidgets('a system drop lands on the widget it is over', (WidgetTester tester) async {
      final List<DVDropEvent> dropped = <DVDropEvent>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DVBox(const SizedBox(width: 100, height: 100))
                .modifier(DVModifier().dropTarget(onDrop: dropped.add)),
          ),
        ),
      ));
      final Offset center = tester.getCenter(find.byType(DVDropTarget));
      DVDragDrop.dispatch(DVDropEvent(text: 'from Files', x: center.dx, y: center.dy));
      DVDragDrop.dispatch(const DVDropEvent(text: 'outside', x: 1, y: 1));
      expect(dropped.map((DVDropEvent e) => e.text), <String?>['from Files']);
    });
  });
}
