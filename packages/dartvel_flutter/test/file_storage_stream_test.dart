// DV.FileStorage.putStream and getStream: the calls the File Storage section
// shows, on the app default, on an active host's storage, and on the device
// disk through DV.Platform.fileStorage.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVLocalFileStorageAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _DiskHost extends DVPlatformHost {
  _DiskHost(this.storage);

  final DVFileStorageAdapter storage;

  @override
  String get id => 'disk';

  @override
  bool get isActive => true;

  @override
  DVFileStorageAdapter? get fileStorage => storage;
}

Stream<List<int>> _chunks() async* {
  yield <int>[1, 2];
  yield <int>[3];
}

Future<List<int>> _collect(Stream<List<int>> stream) async =>
    <int>[for (final List<int> chunk in await stream.toList()) ...chunk];

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv-file-storage-stream-');
  });

  tearDown(() {
    DV.FileStorage.configure(DVMemoryFileStorageAdapter());
    DVDeviceStorage.reset();
    DVPlatformHosts.reset();
    root.deleteSync(recursive: true);
  });

  test('the configured adapter takes a stream and gives one back', () async {
    final DVMemoryFileStorageAdapter bucket = DVMemoryFileStorageAdapter();
    DV.FileStorage.configure(bucket);

    await DV.FileStorage.putStream('avatar.png', _chunks());

    expect(await bucket.get('avatar.png'), <int>[1, 2, 3]);
    expect(await _collect(await DV.FileStorage.getStream('avatar.png')),
        <int>[1, 2, 3]);
  });

  test('an active host storage takes the stream, as it takes put', () async {
    final DVMemoryFileStorageAdapter hostDisk = DVMemoryFileStorageAdapter();
    final DVMemoryFileStorageAdapter bucket = DVMemoryFileStorageAdapter();
    DV.FileStorage.configure(bucket);
    DV.Platform.registerHost(_DiskHost(hostDisk));

    await DV.FileStorage.putStream('k', _chunks());

    expect(await hostDisk.get('k'), <int>[1, 2, 3]);
    expect(await bucket.exists('k'), isFalse);
    expect(await _collect(await DV.FileStorage.getStream('k')), <int>[1, 2, 3]);
  });

  test('DV.Platform.fileStorage streams onto the device disk', () async {
    DVDeviceStorage.useAdapters(
      DVLocalFileStorageAdapter(root: p.join(root.path, 'files')),
      cache: DVLocalFileStorageAdapter(root: p.join(root.path, 'cache')),
    );

    await DV.Platform.fileStorage.putStream('clips/a.bin', _chunks());

    expect(File(p.join(root.path, 'files', 'clips', 'a.bin')).readAsBytesSync(),
        <int>[1, 2, 3]);
    expect(
      await _collect(await DV.Platform.fileStorage.getStream('clips/a.bin')),
      <int>[1, 2, 3],
    );
  });

  test('a missing object fails getStream with a 404', () async {
    await expectLater(
      DV.FileStorage.getStream('nothing'),
      throwsA(isA<DVFileStorageException>()
          .having((DVFileStorageException e) => e.isNotFound, 'isNotFound',
              isTrue)),
    );
  });
}
