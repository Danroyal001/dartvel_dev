// Key custody from the Flutter side: `dvAppKeyStoreFor`, which the generated
// runtime calls as `dvAppKeyStoreFor('<package>')`, hands a phone its keyring
// -- the Android Keystore or the iOS Keychain -- with no change to the
// application, and never the file store.
//
// Off a device the Keystore cannot be reached, so what is held to here is the
// choice, the refusal (typed, and with no file written in its place), and the
// shape of what the Android store puts on disk: a nonce and a sealed key,
// never the key. The Keystore itself is exercised on an emulator by
// .github/workflows/key-custody.yml.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart'
    show
        DVAppKey,
        DVAppKeyStore,
        DVAppKeyStoreUnavailable,
        DVAppKeyStores,
        DVFileAppKeyStore,
        DVKeychainAppKeyStore,
        DVMigratingAppKeyStore;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (int i) => (i * 13 + seed) & 0xff));

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('dv_android_custody_'));
  tearDown(() => home.deleteSync(recursive: true));

  group('the store the generated runtime asks for', () {
    test('on Android is the Keystore, with the old file only to move a key from', () async {
      final DVAppKeyStore store = await dvAppKeyStoreFor('shop', platform: 'android', home: home.path);
      expect(store, isNot(isA<DVFileAppKeyStore>()));
      expect(store, isA<DVMigratingAppKeyStore>());
      final DVAppKeyStore keyring = (store as DVMigratingAppKeyStore).keyring;
      expect(keyring, isA<DVAndroidKeystoreAppKeyStore>());
      expect((keyring as DVAndroidKeystoreAppKeyStore).app, 'shop');
      final String said = DVAppKeyStores.describe(store);
      expect(said, contains('Android Keystore'));
      expect(said, isNot(contains('not keyring-protected')));
    });

    test('on iOS is the Keychain', () async {
      final DVAppKeyStore store = await dvAppKeyStoreFor('shop', platform: 'ios', home: home.path);
      expect(store, isNot(isA<DVFileAppKeyStore>()));
      expect((store as DVMigratingAppKeyStore).keyring, isA<DVKeychainAppKeyStore>());
    });

    test('off a device the Keystore refuses, and no file is written in its place', () async {
      final DVAppKeyStore store = await dvAppKeyStoreFor('shop', platform: 'android', home: home.path);
      await expectLater(DVAppKey.ensure(store), throwsA(isA<DVAppKeyStoreUnavailable>()));
      await expectLater(
        const DVAndroidKeystoreAppKeyStore(app: 'shop').write(bytes(32, 1)),
        throwsA(isA<DVAppKeyStoreUnavailable>()),
      );
      expect(home.listSync(recursive: true), isEmpty);
    });

    test('this machine keeps the custody it had', () async {
      final DVAppKeyStore store = await dvAppKeyStoreFor('shop', home: home.path);
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(store, isNot(isA<DVMigratingAppKeyStore>()));
      }
    });
  });

  group('what the Android store keeps on disk', () {
    test('a nonce and a sealed key, which open back to the same two', () {
      final Uint8List nonce = bytes(12, 1);
      final Uint8List sealed = bytes(48, 2);
      final String blob = dvAndroidSealKeyBlob(nonce, sealed);
      expect(blob, startsWith('dvks1:'));
      final ({Uint8List nonce, Uint8List sealed})? opened = dvAndroidOpenKeyBlob(blob);
      expect(opened, isNotNull);
      expect(opened!.nonce, nonce);
      expect(opened.sealed, sealed);
    });

    test('never a bare key: sealing refuses anything that is not a sealed key', () {
      // 32 bytes is an application key with no GCM tag on it -- the key
      // itself, which is exactly what must not reach a file.
      expect(() => dvAndroidSealKeyBlob(bytes(12, 1), bytes(32, 2)), throwsArgumentError);
      expect(() => dvAndroidSealKeyBlob(bytes(8, 1), bytes(48, 2)), throwsArgumentError);
    });

    test('a damaged or wrong-sized blob opens to nothing', () {
      expect(dvAndroidOpenKeyBlob('not a blob'), isNull);
      expect(dvAndroidOpenKeyBlob('dvks1:!!!'), isNull);
      expect(dvAndroidOpenKeyBlob('dvks1:AAAA'), isNull);
      expect(dvAndroidOpenKeyBlob(''), isNull);
    });

    test('in the no-backup directory, one per application', () {
      expect(dvAndroidSealedKeyPath('/data/user/0/com.shop/no_backup', 'shop'),
          '/data/user/0/com.shop/no_backup/dartvel-keys/shop.sealed');
      expect(dvAndroidSealedKeyPath('/data/user/0/com.shop/no_backup/', 'shop'),
          '/data/user/0/com.shop/no_backup/dartvel-keys/shop.sealed');
      expect(dvAndroidSealedKeyPath('/x', 'a/../b'), '/x/dartvel-keys/a_.._b.sealed',
          reason: 'an application name is not a path');
      expect(dvAndroidSealedKeyPath(null, 'shop'), isNull);
      expect(dvAndroidSealedKeyPath('', 'shop'), isNull);
    });

    test('the Keystore alias is per application', () {
      expect(dvAndroidKeystoreAlias('shop'), isNot(dvAndroidKeystoreAlias('till')));
      expect(dvAndroidKeystoreAlias('shop'), contains('shop'));
    });
  });
}
