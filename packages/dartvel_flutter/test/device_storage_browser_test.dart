@TestOn('browser')
library;

// DV.Platform.fileStorage in a browser: the origin private file system,
// through the same calls as DV.FileStorage. Run with
// `flutter test --platform chrome`, which starts its own headless Chrome.
//
// The pickers open a modal and are not called here (a headless run would
// hang on them); they go through `media.pick`, which the web bindings suite
// covers, and showDirectoryPicker, which needs a person.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/storage/device_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVOriginPrivateFileStorageAdapter.available, isTrue,
        reason: 'headless Chrome has the origin private file system');
    DVDeviceStorage.reset();
  });

  tearDown(() async {
    for (final String key in await DV.Platform.fileStorage.list()) {
      await DV.Platform.fileStorage.delete(key);
    }
    for (final String key in await DV.Platform.fileStorage.cache.list()) {
      await DV.Platform.fileStorage.cache.delete(key);
    }
  });

  test('put, get, exists, list and delete round-trip in OPFS', () async {
    await DV.Platform.fileStorage.put('notes/today.txt', <int>[1, 2, 3]);
    await DV.Platform.fileStorage.put('top.bin', <int>[9]);
    expect(await DV.Platform.fileStorage.get('notes/today.txt'), <int>[1, 2, 3]);
    expect(await DV.Platform.fileStorage.exists('notes/today.txt'), isTrue);
    expect(await DV.Platform.fileStorage.list(), <String>['notes/today.txt', 'top.bin']);
    expect(await DV.Platform.fileStorage.list(prefix: 'notes/'), <String>['notes/today.txt']);
    await DV.Platform.fileStorage.delete('notes/today.txt');
    expect(await DV.Platform.fileStorage.exists('notes/today.txt'), isFalse);
  });

  test('a shorter write leaves no old tail', () async {
    await DV.Platform.fileStorage.put('a.bin', <int>[1, 2, 3, 4]);
    await DV.Platform.fileStorage.put('a.bin', <int>[5]);
    expect(await DV.Platform.fileStorage.get('a.bin'), <int>[5]);
  });

  test('a missing key is a 404, as on a bucket', () async {
    await expectLater(
      DV.Platform.fileStorage.get('nothing-here.bin'),
      throwsA(isA<DVFileStorageException>().having((DVFileStorageException e) => e.statusCode, 'status', 404)),
    );
  });

  test('a key that climbs out is refused', () async {
    await expectLater(DV.Platform.fileStorage.put('../x', <int>[1]), throwsA(isA<DVFileStorageException>()));
  });

  test('the cache is apart from the app files and hidden from their list', () async {
    await DV.Platform.fileStorage.cache.put('thumb.png', <int>[4]);
    await DV.Platform.fileStorage.put('kept.txt', <int>[1]);
    expect(await DV.Platform.fileStorage.cache.list(), <String>['thumb.png']);
    expect(await DV.Platform.fileStorage.list(), <String>['kept.txt']);
  });

  test('what DV.Platform.files wrote is where fileStorage reads it', () async {
    // ignore: deprecated_member_use_from_same_package
    DVWebBindings.register();
    await DVNativeBridge.require<bool>('files.writeBytes', <String, Object?>{'path': 'legacy.bin', 'bytes': <int>[7, 7]});
    expect(await DV.Platform.fileStorage.get('legacy.bin'), <int>[7, 7]);
    DVWebBindings.unregister();
  });

  test('a folder read in by the fallback input is read-only', () async {
    final DVReadOnlyFolderFileStorageAdapter folder =
        DVReadOnlyFolderFileStorageAdapter(<String, List<int>>{'plan.md': <int>[1], 'img/a.png': <int>[2]});
    final DVStorage storage = DVStorage.bound(folder);
    expect(await storage.list(prefix: 'img/'), <String>['img/a.png']);
    await expectLater(
      storage.put('new.txt', <int>[1]),
      throwsA(isA<DVFileStorageException>().having((DVFileStorageException e) => e.statusCode, 'status', 405)),
    );
  });
}
