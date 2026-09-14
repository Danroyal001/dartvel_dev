// Key custody on phones: the application key is in the platform's keyring or
// it is refused, never in a file.
//
// What these hold to, off a device:
//   - Android and iOS are never handed the file store, and describe() never
//     says "not keyring-protected" for them;
//   - a keyring that cannot answer refuses with DVAppKeyStoreUnavailable, and
//     nothing is written anywhere else instead;
//   - a key an earlier version left in the file is moved into the keyring
//     once, and the file is removed only after the keyring copy reads back.
//
// The keyrings themselves -- the Android Keystore and the iOS Keychain -- are
// exercised on an emulator and a simulator by .github/workflows/key-custody.yml.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

Uint8List key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (int i) => (i * 11 + seed) & 0xff));

/// A keyring held in memory that records what was asked of it, and when.
///
/// [fileAtReadBack] is where the ordering guarantee is observed: whether the
/// legacy file still existed at the moment the keyring was read after a
/// write. A migration that deletes first and reads back after passes every
/// check that only looks at the end state.
class FakeKeyring implements DVAppKeyStore {
  Uint8List? held;
  final List<String> calls = <String>[];
  final String? watchFile;
  final List<bool> fileAtReadBack = <bool>[];

  /// What read-back returns instead of the stored key, to model a keyring
  /// that accepted a write and kept nothing (or something else).
  bool dropWrites = false;
  Object? readError;
  Object? writeError;
  bool _written = false;

  FakeKeyring({this.held, this.watchFile});

  @override
  Future<Uint8List?> read() async {
    calls.add('read');
    if (readError != null) throw readError!;
    if (_written && watchFile != null) {
      fileAtReadBack.add(File(watchFile!).existsSync());
    }
    return held;
  }

  @override
  Future<void> write(Uint8List value) async {
    calls.add('write');
    if (writeError != null) throw writeError!;
    _written = true;
    if (!dropWrites) held = Uint8List.fromList(value);
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    held = null;
  }
}

DVAppKeyStoreUnavailable locked() => const DVAppKeyStoreUnavailable(
      'the Keychain',
      'the device has not been unlocked since it started',
    );

/// Every file under [dir], recursively.
List<String> filesUnder(Directory dir) => dir.existsSync()
    ? dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((File f) => f.path)
        .toList()
    : <String>[];

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('dv_custody_'));
  tearDown(() => home.deleteSync(recursive: true));

  String legacyPath(String app) => '${home.path}/.dartvel/keys/$app.key';

  group('choosing a store on a phone', () {
    test('iOS is the Keychain, with the old file only as a migration source',
        () {
      final DVAppKeyStore store = DVAppKeyStores.choose(
          app: 'shop', home: home.path, platform: 'ios', secretService: false);
      expect(store, isNot(isA<DVFileAppKeyStore>()));
      expect(store, isA<DVMigratingAppKeyStore>());
      final DVMigratingAppKeyStore migrating = store as DVMigratingAppKeyStore;
      expect(migrating.keyring, isA<DVKeychainAppKeyStore>());
      expect((migrating.keyring as DVKeychainAppKeyStore).account, 'shop');
      expect((migrating.legacy as DVFileAppKeyStore).path, legacyPath('shop'));
      final String said = DVAppKeyStores.describe(store);
      expect(said, contains('Keychain'));
      expect(said, isNot(contains('not keyring-protected')));
    });

    test('Android is the Keystore it is handed, for this application', () {
      final List<String> asked = <String>[];
      final FakeKeyring keystore = FakeKeyring();
      final DVAppKeyStore store = DVAppKeyStores.choose(
        app: 'shop',
        home: home.path,
        platform: 'android',
        secretService: false,
        androidKeystore: (String app) {
          asked.add(app);
          return keystore;
        },
      );
      expect(store, isNot(isA<DVFileAppKeyStore>()));
      expect((store as DVMigratingAppKeyStore).keyring, same(keystore));
      expect(asked, <String>['shop']);
      expect(DVAppKeyStores.describe(store),
          isNot(contains('not keyring-protected')));
    });

    test('a key made on Android goes into the Keystore and nowhere on disk',
        () async {
      final FakeKeyring keystore = FakeKeyring();
      final DVAppKeyStore store = DVAppKeyStores.choose(
        app: 'shop',
        home: home.path,
        platform: 'android',
        secretService: false,
        androidKeystore: (_) => keystore,
      );
      final Uint8List made = await DVAppKey.ensure(store);
      expect(keystore.held, made);
      expect(filesUnder(home), isEmpty,
          reason: 'no key material in a plain file, and no key directory');
      expect(await store.read(), made, reason: 'and it is read back');
    });

    test('Android with no Keystore binding refuses, and writes no file',
        () async {
      final DVAppKeyStore store = DVAppKeyStores.choose(
          app: 'shop', home: home.path, platform: 'android', secretService: false);
      expect(store, isNot(isA<DVFileAppKeyStore>()));
      await expectLater(
          DVAppKey.ensure(store), throwsA(isA<DVAppKeyStoreUnavailable>()));
      await expectLater(store.write(key(1)),
          throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(filesUnder(home), isEmpty);
      expect(DVAppKeyStores.describe(store), contains('refused'));
    });

    test('desktop choices are unchanged', () {
      expect(
          DVAppKeyStores.choose(
              app: 'shop', home: '/Users/ada', platform: 'macos', secretService: false),
          isA<DVKeychainAppKeyStore>());
      expect(
          DVAppKeyStores.choose(
              app: 'shop', home: '/home/ada', platform: 'linux', secretService: false),
          isA<DVFileAppKeyStore>());
    });
  });

  group('a keyring that cannot answer', () {
    test('refuses a read with the typed error and leaves the file alone',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(2));
      final FakeKeyring keyring = FakeKeyring()..readError = locked();
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      await expectLater(store.read(), throwsA(isA<DVAppKeyStoreUnavailable>()));
      await expectLater(
          DVAppKey.ensure(store), throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(await legacy.read(), key(2), reason: 'the old key is not lost');
      expect(keyring.calls, isNot(contains('write')));
    });

    test('refuses a write with the typed error and writes no file', () async {
      final FakeKeyring keyring = FakeKeyring()..writeError = locked();
      final DVMigratingAppKeyStore store = DVMigratingAppKeyStore(
          keyring: keyring, legacy: DVFileAppKeyStore(legacyPath('shop')));
      await expectLater(
          DVAppKey.ensure(store), throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(filesUnder(home), isEmpty);
    });

    test('the error says which store and why', () {
      final String said = locked().toString();
      expect(said, contains('DVAppKeyStoreUnavailable'));
      expect(said, contains('the Keychain'));
      expect(said, contains('unlocked'));
    });
  });

  group('moving a key out of the old file', () {
    test('moves it once, and removes the file after the copy reads back',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(3));
      final FakeKeyring keyring = FakeKeyring(watchFile: legacyPath('shop'));
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);

      expect(await DVAppKey.ensure(store), key(3),
          reason: 'the existing key, not a new one: data sealed under it stays readable');
      expect(keyring.held, key(3));
      expect(File(legacyPath('shop')).existsSync(), isFalse);
      expect(keyring.fileAtReadBack, <bool>[true],
          reason: 'the file still existed when the keyring copy was read back');
      expect(keyring.calls, <String>['read', 'write', 'read']);

      // Once: a later read is the keyring's alone.
      keyring.calls.clear();
      expect(await store.read(), key(3));
      expect(keyring.calls, <String>['read']);
    });

    test('keeps the file when the keyring accepts the write and keeps nothing',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(4));
      final FakeKeyring keyring = FakeKeyring()..dropWrites = true;
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      await expectLater(store.read(), throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(await legacy.read(), key(4));
    });

    test('keeps the file when the keyring reads back a different key',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(5));
      final _Substituting keyring = _Substituting(key(6));
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      await expectLater(store.read(), throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(await legacy.read(), key(5));
    });

    test('keeps the file when the keyring refuses the write', () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(7));
      final FakeKeyring keyring = FakeKeyring()..writeError = locked();
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      await expectLater(store.read(), throwsA(isA<DVAppKeyStoreUnavailable>()));
      expect(await legacy.read(), key(7));
    });

    test('finishes a move interrupted after the copy and before the delete',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(8));
      final FakeKeyring keyring = FakeKeyring(held: key(8));
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      expect(await store.read(), key(8));
      expect(File(legacyPath('shop')).existsSync(), isFalse);
      expect(keyring.calls, isNot(contains('write')));
    });

    test('leaves a file whose key the keyring does not hold, and uses the keyring',
        () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(9));
      final FakeKeyring keyring = FakeKeyring(held: key(10));
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      expect(await store.read(), key(10));
      expect(await legacy.read(), key(9),
          reason: 'the only copy of a key something may still be sealed under');
      expect(keyring.calls, isNot(contains('write')));
    });

    test('writes go to the keyring only', () async {
      final FakeKeyring keyring = FakeKeyring();
      final DVMigratingAppKeyStore store = DVMigratingAppKeyStore(
          keyring: keyring, legacy: DVFileAppKeyStore(legacyPath('shop')));
      await store.write(key(11));
      expect(keyring.held, key(11));
      expect(filesUnder(home), isEmpty);
    });

    test('clear removes the key from both', () async {
      final DVFileAppKeyStore legacy = DVFileAppKeyStore(legacyPath('shop'));
      await legacy.write(key(12));
      final FakeKeyring keyring = FakeKeyring(held: key(13));
      final DVMigratingAppKeyStore store =
          DVMigratingAppKeyStore(keyring: keyring, legacy: legacy);
      await store.clear();
      expect(keyring.held, isNull);
      expect(File(legacyPath('shop')).existsSync(), isFalse);
    });
  });

  group('what the Keychain answers', () {
    test('a device not unlocked since it started is a refusal that says so', () {
      final DVAppKeyStoreUnavailable refusal =
          dvKeychainRefusal(-25308, 'SecItemCopyMatching');
      expect(refusal.status, -25308);
      expect(refusal.reason, contains('unlocked'));
    });

    test('a Keychain store off Apple refuses with the typed error', () async {
      const DVKeychainAppKeyStore store =
          DVKeychainAppKeyStore(service: 'dartvel-test', account: 'shop');
      await expectLater(store.read(), throwsA(isA<DVAppKeyStoreUnavailable>()));
      await expectLater(
          store.write(key(14)), throwsA(isA<DVAppKeyStoreUnavailable>()));
    }, testOn: 'linux || windows');

    test('a missing entitlement and an absent keychain are named', () {
      expect(dvKeychainRefusal(-34018, 'SecItemAdd').reason,
          contains('entitlement'));
      expect(dvKeychainRefusal(-25291, 'SecItemAdd').reason,
          contains('no keychain'));
      expect(dvKeychainRefusal(-50, 'SecItemAdd').reason, contains('-50'));
    });
  });
}

/// Accepts a write and reads back a key other than the one written.
class _Substituting implements DVAppKeyStore {
  final Uint8List other;
  bool written = false;
  _Substituting(this.other);

  @override
  Future<Uint8List?> read() async => written ? other : null;

  @override
  Future<void> write(Uint8List key) async => written = true;

  @override
  Future<void> clear() async => written = false;
}
