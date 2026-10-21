// What a drop delivered before widget targets and links existed still
// arrives the same way: a binding that hands over a file's bytes in the map
// (the browser binding did, and a custom binding may) gives a readable file,
// and the window's drag-over stream still says when a drag is over it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DVDragDrop.reset();
    DVNativeBridge.register('dragDrop.accept', (_) => true);
    DVNativeBridge.register('dragDrop.stop', (_) => true);
  });
  tearDown(() {
    DVDragDrop.reset();
    DVNativeBridge.unregister('dragDrop.accept');
    DVNativeBridge.unregister('dragDrop.stop');
  });

  test('a file map carrying bytes is read from those bytes', () async {
    final DVDropEvent decoded = DVDropEvent.fromMap(<Object?, Object?>{
      'files': <Object?>[
        <Object?, Object?>{'name': 'map.txt', 'mimeType': 'text/plain', 'bytes': <int>[3, 4]},
      ],
    });
    expect(decoded.files.single.name, 'map.txt');
    expect(await decoded.files.single.readBytes(), <int>[3, 4]);
  });

  test('a file map without a type takes one from its name', () {
    final DVDropEvent decoded = DVDropEvent.fromMap(<Object?, Object?>{
      'files': <Object?>[
        <Object?, Object?>{'name': 'photo.png', 'bytes': <int>[1]},
      ],
    });
    expect(decoded.files.single.mimeType, 'image/png');
  });

  test('a drop ends the drag-over, and nothing is reported after stop', () async {
    final List<bool> over = <bool>[];
    final subscription = const DVDragDrop().draggingOver.listen(over.add);
    await const DVDragDrop().accept();
    DVDragDrop.dispatchHover(12, 12);
    DVDragDrop.dispatch(const DVDropEvent(text: 'dropped', x: 12, y: 12));
    await Future<void>.delayed(Duration.zero);
    expect(over, <bool>[true, false]);
    await const DVDragDrop().stop();
    DVDragDrop.dispatchHover(12, 12);
    DVDragDrop.dispatchLeave();
    await Future<void>.delayed(Duration.zero);
    expect(over, <bool>[true, false]);
    await subscription.cancel();
  });
}
