import 'dart:typed_data';
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

  test('existing dropped-file constructor and byte maps remain readable', () async {
    final file = DVDroppedFile(name: 'before.txt', bytes: Uint8List.fromList([1, 2]));
    final event = DVDropEvent(files: <DVDroppedFile>[file]);
    final DVDroppedFile legacy = event.files.single;
    expect(legacy.bytes, [1, 2]);
    expect(legacy.mimeType.isEmpty, isTrue);
    expect(await event.files.single.readBytes(), [1, 2]);
    final decoded = DVDropEvent.fromMap({
      'files': [{'name': 'map.txt', 'mimeType': 'text/plain', 'bytes': [3, 4]}],
    });
    expect(decoded.files.single.bytes, [3, 4]);
    expect(await decoded.files.single.readBytes(), [3, 4]);
  });

  test('window drag-over stream still reports enter and leave', () async {
    final over = <bool>[];
    final subscription = const DVDragDrop().draggingOver.listen(over.add);
    await const DVDragDrop().accept();
    DVDragDrop.dispatchHover(12, 12);
    DVDragDrop.dispatchLeave();
    await Future<void>.delayed(.zero);
    expect(over, [true, false]);
    await const DVDragDrop().stop();
    DVDragDrop.dispatchDragOver(true);
    await Future<void>.delayed(.zero);
    expect(over, [true, false]);
    await subscription.cancel();
  });
}
