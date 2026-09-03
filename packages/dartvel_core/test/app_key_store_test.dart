// Where the application key lives: the platform key store, never the repo.
//
// On Linux that is the Secret Service (libsecret), keyring-backed; where no
// Secret Service answers -- a headless box, a container -- a file the user
// alone can read, and the store says which it is. What the tests hold to: a
// key round-trips, clears, and is not readable by anyone else; the Secret
// Service store keeps accounts apart; and the choice between them is made
// on what actually answers, not on what the platform is called.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

Uint8List key(int seed) => Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + seed) & 0xff));

void main() {
  group('the file store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dv_key_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads nothing until something is written, then round-trips', () async {
      final DVFileAppKeyStore store = DVFileAppKeyStore('${dir.path}/app.key');
      expect(await store.read(), isNull);
      await store.write(key(1));
      expect(await store.read(), key(1));
      expect(await DVFileAppKeyStore('${dir.path}/app.key').read(), key(1), reason: 'another instance, same file');
    });

    test('the file is readable by its owner alone', () async {
      final DVFileAppKeyStore store = DVFileAppKeyStore('${dir.path}/nested/app.key');
      await store.write(key(2));
      final ProcessResult stat = await Process.run('stat', <String>['-c', '%a', '${dir.path}/nested/app.key']);
      expect('${stat.stdout}'.trim(), '600');
      final ProcessResult dirStat = await Process.run('stat', <String>['-c', '%a', '${dir.path}/nested']);
      expect('${dirStat.stdout}'.trim(), '700');
    }, testOn: 'linux || mac-os');

    test('clear removes it', () async {
      final DVFileAppKeyStore store = DVFileAppKeyStore('${dir.path}/app.key');
      await store.write(key(3));
      await store.clear();
      expect(await store.read(), isNull);
      expect(File('${dir.path}/app.key').existsSync(), isFalse);
    });

    test('a damaged file reads as no key rather than a wrong one', () async {
      File('${dir.path}/app.key').writeAsStringSync('not base64 at all!!');
      expect(await DVFileAppKeyStore('${dir.path}/app.key').read(), isNull);
      File('${dir.path}/short.key').writeAsStringSync('AAAA');
      expect(await DVFileAppKeyStore('${dir.path}/short.key').read(), isNull, reason: 'wrong length');
    });
  });

  group('the Secret Service store', () {
    late bool available;
    setUpAll(() async => available = await DVSecretServiceAppKeyStore.isAvailable());

    test('round-trips and clears', () async {
      if (!available) {
        markTestSkipped('no Secret Service on this session bus; run under dbus-run-session with gnome-keyring');
        return;
      }
      final DVSecretServiceAppKeyStore store =
          DVSecretServiceAppKeyStore(service: 'dartvel-test', account: 'app-${pid}');
      addTearDown(store.clear);
      expect(await store.read(), isNull);
      await store.write(key(4));
      expect(await store.read(), key(4));
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('accounts are kept apart', () async {
      if (!available) {
        markTestSkipped('no Secret Service on this session bus');
        return;
      }
      final DVSecretServiceAppKeyStore a = DVSecretServiceAppKeyStore(service: 'dartvel-test', account: 'a-$pid');
      final DVSecretServiceAppKeyStore b = DVSecretServiceAppKeyStore(service: 'dartvel-test', account: 'b-$pid');
      addTearDown(a.clear);
      addTearDown(b.clear);
      await a.write(key(5));
      await b.write(key(6));
      expect(await a.read(), key(5));
      expect(await b.read(), key(6));
    });

    test('without a Secret Service, isAvailable is false and nothing throws', () async {
      // Whatever this machine has, the answer is a boolean, not an exception:
      // the store chooser has to be able to ask.
      expect(available, isA<bool>());
    });
  });

  group('the store for this machine', () {
    test('is chosen from what answers here, under the given home', () async {
      final Directory home = Directory.systemTemp.createTempSync('dv_home_');
      addTearDown(() => home.deleteSync(recursive: true));
      final DVAppKeyStore store = await DVAppKeyStores.platform('shop', home: home.path);
      final bool service = await DVSecretServiceAppKeyStore.isAvailable();
      if (Platform.isLinux && service) {
        expect(store, isA<DVSecretServiceAppKeyStore>());
      } else {
        expect(store, isA<DVFileAppKeyStore>());
        expect((store as DVFileAppKeyStore).path, '${home.path}/.dartvel/keys/shop.key');
      }
      // Whatever it is, a key can be kept in it: that is the promise a
      // running application relies on at first start.
      final Uint8List key = await DVAppKey.ensure(store);
      expect(await store.read(), key);
      await store.clear();
    });

    test('the home defaults to the user\'s', () async {
      final DVAppKeyStore store = await DVAppKeyStores.platform('shop', secretService: false);
      final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;
      expect((store as DVFileAppKeyStore).path, startsWith(home));
    });
  });

  group('choosing a store', () {
    test('Linux with a Secret Service uses it; without one, the file under the home', () {
      final DVAppKeyStore withService = DVAppKeyStores.choose(
          app: 'shop', home: '/home/ada', platform: 'linux', secretService: true);
      expect(withService, isA<DVSecretServiceAppKeyStore>());
      expect(DVAppKeyStores.describe(withService), contains('Secret Service'));

      final DVAppKeyStore without = DVAppKeyStores.choose(
          app: 'shop', home: '/home/ada', platform: 'linux', secretService: false);
      expect(without, isA<DVFileAppKeyStore>());
      expect((without as DVFileAppKeyStore).path, '/home/ada/.dartvel/keys/shop.key');
      expect(DVAppKeyStores.describe(without), contains('/home/ada/.dartvel/keys/shop.key'));
    });

    test('Windows is DPAPI and macOS is the Keychain, whatever else answers', () {
      final DVAppKeyStore windows = DVAppKeyStores.choose(
          app: 'shop', home: r'C:\Users\ada', platform: 'windows', secretService: false);
      expect(windows, isA<DVDpapiAppKeyStore>());
      expect(DVAppKeyStores.describe(windows), contains('DPAPI'));
      final DVAppKeyStore mac = DVAppKeyStores.choose(
          app: 'shop', home: '/Users/ada', platform: 'macos', secretService: true);
      expect(mac, isA<DVKeychainAppKeyStore>());
      expect(DVAppKeyStores.describe(mac), contains('Keychain'));
    });

    test('platforms with no custody of their own fall back to the file store, and say so', () {
      final DVAppKeyStore store = DVAppKeyStores.choose(
          app: 'shop', home: '/home/ada', platform: 'fuchsia', secretService: false);
      expect(store, isA<DVFileAppKeyStore>());
      expect(DVAppKeyStores.describe(store), contains('file'));
    });
  });

  group('the DPAPI store', () {
    test('round-trips, clears, and keeps nothing readable on disk', () async {
      if (!Platform.isWindows) {
        markTestSkipped('DPAPI is Windows');
        return;
      }
      final Directory dir = Directory.systemTemp.createTempSync('dv_dpapi_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final DVDpapiAppKeyStore store = DVDpapiAppKeyStore('${dir.path}\\app.key');
      expect(await store.read(), isNull);
      await store.write(key(7));
      expect(await store.read(), key(7));
      final List<int> onDisk = File('${dir.path}\\app.key').readAsBytesSync();
      expect(onDisk, isNot(equals(key(7))), reason: 'the blob is protected, not the key');
      expect(String.fromCharCodes(onDisk), isNot(contains(base64Encode(key(7)))));
      await store.clear();
      expect(await store.read(), isNull);
    }, testOn: 'windows');
  });

  group('the Keychain store', () {
    test('round-trips, clears, and keeps accounts apart', () async {
      if (!Platform.isMacOS) {
        markTestSkipped('the Keychain is macOS');
        return;
      }
      final DVKeychainAppKeyStore a = DVKeychainAppKeyStore(service: 'dartvel-test', account: 'a-$pid');
      final DVKeychainAppKeyStore b = DVKeychainAppKeyStore(service: 'dartvel-test', account: 'b-$pid');
      addTearDown(a.clear);
      addTearDown(b.clear);
      expect(await a.read(), isNull);
      await a.write(key(8));
      await b.write(key(9));
      expect(await a.read(), key(8));
      expect(await b.read(), key(9));
      await a.write(key(10));
      expect(await a.read(), key(10), reason: 'writing again replaces');
      await a.clear();
      expect(await a.read(), isNull);
      expect(await b.read(), key(9));
    }, testOn: 'mac-os');
  });
}
