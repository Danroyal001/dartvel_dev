import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVLocalFileStorageAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/desktop_permissions.dart';
import 'package:dartvel_flutter/src/platform/storage/device_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv-device-storage-');
    DVDeviceStorage.useAdapters(
      DVLocalFileStorageAdapter(root: p.join(root.path, 'files')),
      cache: DVLocalFileStorageAdapter(root: p.join(root.path, 'cache')),
    );
  });

  tearDown(() {
    DVDeviceStorage.reset();
    DVDeviceStorage.declare();
    DV.Test.resetNativeBindings();
    DV.FileStorage.configure(DVMemoryFileStorageAdapter());
    root.deleteSync(recursive: true);
  });

  test('DV.Platform.fileStorage has DV.FileStorage calls, on the device disk', () async {
    await DV.Platform.fileStorage.put('notes/today.txt', <int>[1, 2, 3]);
    expect(File(p.join(root.path, 'files', 'notes', 'today.txt')).readAsBytesSync(), <int>[1, 2, 3]);
    expect(await DV.Platform.fileStorage.get('notes/today.txt'), <int>[1, 2, 3]);
    expect(await DV.Platform.fileStorage.exists('notes/today.txt'), isTrue);
    expect(await DV.Platform.fileStorage.list(prefix: 'notes/'), <String>['notes/today.txt']);
    await DV.Platform.fileStorage.delete('notes/today.txt');
    expect(await DV.Platform.fileStorage.exists('notes/today.txt'), isFalse);
  });

  test("the app's default adapter does not move it", () async {
    final DVMemoryFileStorageAdapter bucket = DVMemoryFileStorageAdapter();
    DV.FileStorage.configure(bucket);
    await DV.Platform.fileStorage.put('local.bin', <int>[9]);
    await DV.FileStorage.put('remote.bin', <int>[8]);
    expect(await bucket.exists('local.bin'), isFalse);
    expect(await DV.Platform.fileStorage.exists('remote.bin'), isFalse);
    expect(File(p.join(root.path, 'files', 'local.bin')).existsSync(), isTrue);
  });

  test('a bound storage refuses to be reconfigured, and says which to use', () {
    expect(
      () => DV.Platform.fileStorage.configure(DVMemoryFileStorageAdapter()),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('DV.FileStorage.configure'))),
    );
  });

  test('the cache is its own directory with the same calls', () async {
    await DV.Platform.fileStorage.cache.put('thumb.png', <int>[4]);
    expect(File(p.join(root.path, 'cache', 'thumb.png')).existsSync(), isTrue);
    expect(await DV.Platform.fileStorage.exists('thumb.png'), isFalse);
  });

  test('keys cannot climb out of the app directory', () {
    expect(DV.Platform.fileStorage.put('../escape.txt', <int>[1]), throwsA(isA<DVFileStorageException>()));
  });

  test('pick answers what the platform picker chose, with readable bytes', () async {
    final File picked = File(p.join(root.path, 'receipt.pdf'))..writeAsBytesSync(<int>[5, 6]);
    DV.Test.fakeNativeBinding('media.pick', (Object? arguments) {
      expect((arguments! as Map)['type'], 'any');
      return <Object?>[<String, Object?>{'path': picked.path, 'type': 'file'}];
    });
    final List<DVPickedFile> files = await DV.Platform.fileStorage.pick();
    expect(files.single.name, 'receipt.pdf');
    expect(await files.single.readBytes(), <int>[5, 6]);
  });

  test('a cancelled pick is empty, not an error', () async {
    DV.Test.fakeNativeBinding('media.pick', (_) => <Object?>[]);
    expect(await DV.Platform.fileStorage.pick(), isEmpty);
  });

  test('a browser-style pick carries bytes and no path', () async {
    DV.Test.fakeNativeBinding('media.pick', (_) => <Object?>[
          <String, Object?>{'name': 'a.png', 'bytes': <int>[7], 'type': 'image'},
        ]);
    final DVPickedFile file = (await DV.Platform.fileStorage.pick(type: 'image')).single;
    expect(file.path, isNull);
    expect(await file.readBytes(), <int>[7]);
  });

  test('pickDirectory answers the folder as a storage with the same calls', () async {
    final Directory folder = Directory(p.join(root.path, 'Projects'))..createSync();
    DV.Test.fakeNativeBinding('dialogs.chooseDirectory', (_) => <String, Object?>{'path': folder.path});
    final DVStorage? picked = await DV.Platform.fileStorage.pickDirectory();
    await picked!.put('plan.md', <int>[1]);
    expect(File(p.join(folder.path, 'plan.md')).existsSync(), isTrue);
    expect(await picked.list(), <String>['plan.md']);
  });

  test('pickDirectory where there is no folder picker says so', () {
    expect(DV.Platform.fileStorage.pickDirectory(), throwsA(isA<UnsupportedError>()));
  });

  test('a cancelled folder pick is null', () async {
    DV.Test.fakeNativeBinding('dialogs.chooseDirectory', (_) => <String, Object?>{'path': null});
    expect(await DV.Platform.fileStorage.pickDirectory(), isNull);
  });

  group('requestAccess', () {
    test('access the project never declared is a StateError naming the fix', () {
      expect(
        DV.Platform.fileStorage.requestAccess(DVDeviceFileAccess.photos),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('dartvel.fileStorage.access'))),
      );
    });

    test('a refusal is DVFileAccessDenied, through DV.Platform.permissions', () async {
      DVDeviceStorage.declare(config: DVFileStorageConfig.parse(<String, Object?>{'access': <String>['photos'], 'reason': 'x'}));
      final List<Object?> asked = <Object?>[];
      DV.Test.fakeNativeBinding('permissions.request', (Object? arguments) {
        asked.add((arguments! as Map)['permission']);
        return false;
      });
      await expectLater(DV.Platform.fileStorage.requestAccess(DVDeviceFileAccess.photos), throwsA(isA<DVFileAccessDenied>()));
      expect(asked, <Object?>['photos']);
    });

    test('a grant answers', () async {
      DVDeviceStorage.declare(config: DVFileStorageConfig.parse(<String, Object?>{'access': <String>['media'], 'reason': 'x'}));
      DV.Test.fakeNativeBinding('permissions.request', (_) => true);
      await DV.Platform.fileStorage.requestAccess(DVDeviceFileAccess.media);
    });

    test('documents need no permission: picking is the grant', () async {
      DVDeviceStorage.declare(config: DVFileStorageConfig.parse(<String, Object?>{'access': <String>['documents']}));
      await DV.Platform.fileStorage.requestAccess(DVDeviceFileAccess.documents);
    });

    test('all files that are not switched on say where to switch them on', () async {
      DVDeviceStorage.declare(config: DVFileStorageConfig.parse(<String, Object?>{'access': <String>['allFiles']}));
      DV.Test.fakeNativeBinding('permissions.request', (_) => false);
      await expectLater(
        DV.Platform.fileStorage.requestAccess(DVDeviceFileAccess.allFiles),
        throwsA(isA<DVFileAccessDenied>().having((DVFileAccessDenied e) => e.reason, 'reason', contains('Settings'))),
      );
    });
  });

  group('the device directory per OS', () {
    String? where(String os, Map<String, String> env, {String area = 'files', String? android}) =>
        dvDeviceStorageDirectory(area, 'shop', operatingSystem: os, environment: env, androidFilesDirectory: android);

    test('Android: the files and cache directories the app was given', () {
      expect(where('android', const <String, String>{}, android: '/data/user/0/dev.shop/files'),
          '/data/user/0/dev.shop/files/dartvel-files');
      expect(where('android', const <String, String>{}, area: 'cache', android: '/data/user/0/dev.shop/files'),
          '/data/user/0/dev.shop/cache/dartvel');
    });

    test('iOS: Documents and Library/Caches in the container', () {
      const Map<String, String> env = <String, String>{'HOME': '/var/mobile/Containers/Data/Application/X'};
      expect(where('ios', env), '/var/mobile/Containers/Data/Application/X/Documents');
      expect(where('ios', env, area: 'cache'), '/var/mobile/Containers/Data/Application/X/Library/Caches/dartvel');
    });

    test('macOS: Application Support and Caches under the app id', () {
      expect(where('macos', const <String, String>{'HOME': '/Users/ada'}), '/Users/ada/Library/Application Support/shop');
      expect(where('macos', const <String, String>{'HOME': '/Users/ada'}, area: 'cache'), '/Users/ada/Library/Caches/shop');
    });

    test('Windows: LOCALAPPDATA, then APPDATA', () {
      expect(where('windows', const <String, String>{'LOCALAPPDATA': r'C:\Users\ada\AppData\Local'}),
          r'C:\Users\ada\AppData\Local\shop\Files');
      expect(where('windows', const <String, String>{'APPDATA': r'C:\Users\ada\AppData\Roaming'}, area: 'cache'),
          r'C:\Users\ada\AppData\Roaming\shop\Cache');
    });

    test('Linux and embedded Linux: XDG, with its defaults', () {
      expect(where('linux', const <String, String>{'HOME': '/home/ada'}), '/home/ada/.local/share/shop');
      expect(where('linux', const <String, String>{'HOME': '/home/ada'}, area: 'cache'), '/home/ada/.cache/shop');
      expect(where('linux', const <String, String>{'XDG_DATA_HOME': '/data/apps'}), '/data/apps/shop');
    });

    test('no usable directory is null, never the filesystem root', () {
      expect(where('linux', const <String, String>{'HOME': '/'}), isNull);
      expect(where('ios', const <String, String>{}), isNull);
      expect(where('android', const <String, String>{}), isNull);
    });
  });

  test('a desktop answers every fileStorage kind as held, as it does photos', () {
    for (final DVDeviceFileAccess kind in DVDeviceFileAccess.values) {
      if (kind == DVDeviceFileAccess.documents) continue;
      expect(DVDesktopPermissions.granted(kind.key), isTrue, reason: kind.key);
    }
  });
}
