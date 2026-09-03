// Drag and drop's Dart side: what the desktop dropped reaches the
// application, and nothing reaches it after the window stops accepting.
//
// The desktop capability list names drag and drop and nothing implemented
// it: a file dragged onto a Dartvel window landed nowhere. A binding
// reports a drop as the paths, the text and where it landed; deciding what
// to do with them is the application's.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<Object?> accepted = <Object?>[];
  var stopped = 0;

  setUp(() {
    accepted.clear();
    stopped = 0;
    DVNativeBridge.register('dragDrop.accept', (Object? args) {
      accepted.add(args);
      return true;
    });
    DVNativeBridge.register('dragDrop.stop', (Object? _) {
      stopped++;
      return true;
    });
  });
  tearDown(() {
    DVNativeBridge.unregister('dragDrop.accept');
    DVNativeBridge.unregister('dragDrop.stop');
    DVDragDrop.reset();
  });

  test('a drop reaches the handler and the stream, with what was dropped', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);
    final Future<DVDropEvent> streamed = const DVDragDrop().dropped.first;

    DVDragDrop.dispatch(const DVDropEvent(paths: <String>['/tmp/a.txt', '/tmp/b.png'], x: 12, y: 34));

    expect(got.single.paths, <String>['/tmp/a.txt', '/tmp/b.png']);
    expect(got.single.x, 12);
    expect(got.single.y, 34);
    expect((await streamed).paths.length, 2);
  });

  test('dropped text arrives as text, not as a path', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);

    DVDragDrop.dispatch(const DVDropEvent(text: 'https://dartvel.dev'));

    expect(got.single.text, 'https://dartvel.dev');
    expect(got.single.paths, isEmpty);
  });

  test('the accepted types are what the binding is told to take', () async {
    await const DVDragDrop().accept(types: const <DVDropType>[DVDropType.files]);
    expect((accepted.single! as Map)['types'], <String>['files']);

    await const DVDragDrop().accept();
    expect((accepted.last! as Map)['types'], <String>['files', 'text']);
  });

  test('after stop, a late drop reaches nobody', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);
    await const DVDragDrop().stop();

    DVDragDrop.dispatch(const DVDropEvent(paths: <String>['/tmp/late.txt']));

    expect(got, isEmpty);
    expect(stopped, 1);
  });

  test('a drop with nothing in it is not delivered', () async {
    final List<DVDropEvent> got = <DVDropEvent>[];
    await const DVDragDrop().accept(onDrop: got.add);

    DVDragDrop.dispatch(const DVDropEvent());

    expect(got, isEmpty, reason: 'an empty drop is the desktop offering nothing, not a drop');
  });

  test('with no binding, accepting fails naming what is missing', () async {
    DVNativeBridge.unregister('dragDrop.accept');
    await expectLater(
      const DVDragDrop().accept(),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('dragDrop.accept'))),
    );
  });
}
