// The application key on the web: sealed at rest by a non-extractable
// WebCrypto key in IndexedDB.
//
// The CryptoKey cannot be read back even by the application's own
// JavaScript, so it survives an XSS that would lift a string from
// localStorage. It seals the 32-byte application key at rest; the key
// itself is unwrapped into memory at start, as on every other platform.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show DVAppKey, DVAppKeyStore;
import 'package:web/web.dart' as web;

class DVWebCryptoAppKeyStore implements DVAppKeyStore {
  final String app;
  final String database;

  const DVWebCryptoAppKeyStore({required this.app, this.database = 'dartvel-keys'});

  static bool get isAvailable => true;

  static const String _store = 'keys';
  static const String _wrapKey = 'wrap';
  String get _record => 'app:$app';

  // --- IndexedDB ---------------------------------------------------------------

  Future<web.IDBDatabase> _open() {
    final Completer<web.IDBDatabase> done = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(database, 1);
    request.onupgradeneeded = ((web.IDBVersionChangeEvent _) {
      final web.IDBDatabase db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }).toJS;
    request.onsuccess = ((web.Event _) => done.complete(request.result as web.IDBDatabase)).toJS;
    request.onerror = ((web.Event _) => done.completeError(StateError('IndexedDB would not open: ${request.error?.message}'))).toJS;
    return done.future;
  }

  Future<JSAny?> _get(String key) async {
    final web.IDBDatabase db = await _open();
    try {
      final web.IDBRequest request = db.transaction(_store.toJS, 'readonly').objectStore(_store).get(key.toJS);
      return await _result(request);
    } finally {
      db.close();
    }
  }

  Future<void> _put(String key, JSAny value) async {
    final web.IDBDatabase db = await _open();
    try {
      await _result(db.transaction(_store.toJS, 'readwrite').objectStore(_store).put(value, key.toJS));
    } finally {
      db.close();
    }
  }

  Future<void> _delete(String key) async {
    final web.IDBDatabase db = await _open();
    try {
      await _result(db.transaction(_store.toJS, 'readwrite').objectStore(_store).delete(key.toJS));
    } finally {
      db.close();
    }
  }

  static Future<JSAny?> _result(web.IDBRequest request) {
    final Completer<JSAny?> done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => done.completeError(StateError('IndexedDB request failed: ${request.error?.message}'))).toJS;
    return done.future;
  }

  // --- WebCrypto ---------------------------------------------------------------

  /// The sealing key: made once, non-extractable, kept in IndexedDB as the
  /// structured-cloneable object it is.
  /// `{name: 'AES-GCM', ...}` as the plain object WebCrypto takes; the
  /// typed dictionaries are not in package:web 1.1.
  static JSObject _aesGcm({Uint8List? iv, int? length}) {
    final JSObject params = JSObject();
    params.setProperty('name'.toJS, 'AES-GCM'.toJS);
    if (iv != null) params.setProperty('iv'.toJS, iv.toJS);
    if (length != null) params.setProperty('length'.toJS, length.toJS);
    return params;
  }

  Future<web.CryptoKey> _wrappingKey() async {
    final JSAny? existing = await _get(_wrapKey);
    if (existing != null && existing.isA<web.CryptoKey>()) return existing as web.CryptoKey;
    final web.CryptoKey made = (await web.window.crypto.subtle
        .generateKey(
          _aesGcm(length: 256),
          false,
          <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart)! as web.CryptoKey;
    await _put(_wrapKey, made);
    return made;
  }

  @override
  Future<Uint8List?> read() async {
    final JSAny? sealed = await _get(_record);
    if (sealed == null) return null;
    final JSObject record = sealed as JSObject;
    final Uint8List iv = (record.getProperty('iv'.toJS) as JSUint8Array).toDart;
    final Uint8List data = (record.getProperty('data'.toJS) as JSUint8Array).toDart;
    try {
      final JSAny? plain = await web.window.crypto.subtle
          .decrypt(_aesGcm(iv: iv), await _wrappingKey(), data.toJS)
          .toDart;
      final Uint8List key = (plain as JSArrayBuffer).toDart.asUint8List();
      return key.length == DVAppKey.lengthBytes ? Uint8List.fromList(key) : null;
    } catch (_) {
      // Sealed by a key this profile no longer has: not this key.
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    final Uint8List iv = Uint8List(12);
    web.window.crypto.getRandomValues(iv.toJS);
    final JSAny? sealed = await web.window.crypto.subtle
        .encrypt(_aesGcm(iv: iv), await _wrappingKey(), key.toJS)
        .toDart;
    final Uint8List data = (sealed as JSArrayBuffer).toDart.asUint8List();
    final JSObject record = JSObject();
    record.setProperty('iv'.toJS, iv.toJS);
    record.setProperty('data'.toJS, Uint8List.fromList(data).toJS);
    await _put(_record, record);
  }

  @override
  Future<void> clear() => _delete(_record);

  /// For tests: what IndexedDB holds for this app, sealed.
  Future<Uint8List?> debugStoredBytes() async {
    final JSAny? sealed = await _get(_record);
    if (sealed == null) return null;
    return ((sealed as JSObject).getProperty('data'.toJS) as JSUint8Array).toDart;
  }

  /// For tests: whether the sealing key could be exported. It must not be.
  Future<bool> debugWrappingKeyExtractable() async => (await _wrappingKey()).extractable;
}

/// The key store for [app] on the web: the WebCrypto-sealed one.
Future<DVAppKeyStore> dvAppKeyStoreFor(String app) async => DVWebCryptoAppKeyStore(app: app);
