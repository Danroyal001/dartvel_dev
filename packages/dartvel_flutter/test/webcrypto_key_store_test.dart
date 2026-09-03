// The application key on the web: sealed at rest by a non-extractable
// WebCrypto key in IndexedDB.
//
// The spec's table: a non-extractable CryptoKey in IndexedDB, which cannot
// be read back even by the application's own JavaScript, so it survives an
// XSS that would lift a string from localStorage. What that key does here
// is seal the 32-byte application key at rest; the application key itself
// is unwrapped into memory at start, as on every other platform. What the
// tests hold to: a key round-trips across store instances (the same
// IndexedDB), clears, and what sits in IndexedDB is not the key.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List key(int seed) => Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + seed) & 0xff));

void main() {
  final String db = 'dartvel-test-${DateTime.now().microsecondsSinceEpoch}';

  test('reads nothing until something is written, then round-trips across instances', () async {
    final DVWebCryptoAppKeyStore store = DVWebCryptoAppKeyStore(app: 'shop', database: db);
    expect(await store.read(), isNull);
    await store.write(key(1));
    expect(await store.read(), key(1));
    expect(await DVWebCryptoAppKeyStore(app: 'shop', database: db).read(), key(1), reason: 'another instance, the same IndexedDB');
  });

  test('what sits in IndexedDB is not the key', () async {
    final DVWebCryptoAppKeyStore store = DVWebCryptoAppKeyStore(app: 'sealed', database: db);
    await store.write(key(2));
    final Uint8List? stored = await store.debugStoredBytes();
    expect(stored, isNotNull);
    expect(stored, isNot(equals(key(2))));
    expect(base64Encode(stored!), isNot(contains(base64Encode(key(2)))));
    expect(await store.debugWrappingKeyExtractable(), isFalse, reason: 'the CryptoKey that seals it cannot be exported');
  });

  test('apps are kept apart, and clear removes one', () async {
    final DVWebCryptoAppKeyStore a = DVWebCryptoAppKeyStore(app: 'a', database: db);
    final DVWebCryptoAppKeyStore b = DVWebCryptoAppKeyStore(app: 'b', database: db);
    await a.write(key(3));
    await b.write(key(4));
    expect(await a.read(), key(3));
    expect(await b.read(), key(4));
    await a.clear();
    expect(await a.read(), isNull);
    expect(await b.read(), key(4));
  });

  test('DVAppKey.ensure works on it, which is what a running app calls', () async {
    final DVWebCryptoAppKeyStore store = DVWebCryptoAppKeyStore(app: 'ensure', database: db);
    final Uint8List first = await DVAppKey.ensure(store);
    expect(first, hasLength(32));
    expect(await DVAppKey.ensure(DVWebCryptoAppKeyStore(app: 'ensure', database: db)), first);
  });

  test('the store for an app on the web is this one', () async {
    expect(await dvAppKeyStoreFor('shop'), isA<DVWebCryptoAppKeyStore>());
  });
}
