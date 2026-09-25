/// IndexedDB, the one store a browser keeps across a closed tab that holds
/// more than localStorage's few megabytes and does not block the page.
library;

import 'dart:async';
import 'dart:js_interop';

import '../database/adapter.dart';
import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'offline_database.dart';

Future<DVDatabaseAdapter> dvOpenLocalOfflineDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) async {
  try {
    return await DVSnapshotDatabaseAdapter.open(
      await DVIndexedDbSnapshots.open('$appId.offline'),
    );
  } catch (error) {
    // A private window in some browsers, or storage the person turned off.
    // Memory, which the store reports as DV-OFFLINE-001, rather than an
    // application that cannot start.
    DVObservability.log(
      'IndexedDB could not be opened ($error); offline data models keep '
      'their writes in memory for this session.',
      level: DVLogLevel.warn,
      code: 'DV-OFFLINE-001',
    );
    return MemoryDVDatabaseAdapter();
  }
}

/// One IndexedDB database, one object store, a snapshot per table.
class DVIndexedDbSnapshots implements DVTableSnapshots {
  DVIndexedDbSnapshots._(this._db);

  static const String _store = 'tables';

  final _IDBDatabase _db;

  /// Opens (creating when needed) the IndexedDB database called [name].
  static Future<DVIndexedDbSnapshots> open(String name) async {
    final _IDBFactory? factory = _indexedDB;
    if (factory == null) {
      throw StateError('this browser has no IndexedDB');
    }
    final _IDBOpenDBRequest request = factory.open(name, 1);
    request.onupgradeneeded = ((JSAny? _) {
      final _IDBDatabase db = request.result as _IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }).toJS;
    final JSAny? db = await _completion(request);
    return DVIndexedDbSnapshots._(db! as _IDBDatabase);
  }

  @override
  Future<Map<String, String>> readAll() async {
    final _IDBObjectStore store =
        _db.transaction(_store.toJS, 'readonly').objectStore(_store);
    final _IDBRequest keysRequest = store.getAllKeys();
    final _IDBRequest valuesRequest = store.getAll();
    final List<JSAny?> keys =
        ((await _completion(keysRequest))! as JSArray<JSAny?>).toDart;
    final List<JSAny?> values =
        ((await _completion(valuesRequest))! as JSArray<JSAny?>).toDart;
    return <String, String>{
      for (int i = 0; i < keys.length; i++)
        (keys[i]! as JSString).toDart: (values[i]! as JSString).toDart,
    };
  }

  @override
  Future<void> write(String table, String snapshot) async {
    final _IDBTransaction transaction =
        _db.transaction(_store.toJS, 'readwrite');
    transaction.objectStore(_store).put(snapshot.toJS, table.toJS);
    await _committed(transaction);
  }

  @override
  Future<void> remove(String table) async {
    final _IDBTransaction transaction =
        _db.transaction(_store.toJS, 'readwrite');
    transaction.objectStore(_store).delete(table.toJS);
    await _committed(transaction);
  }

  static Future<JSAny?> _completion(_IDBRequest request) {
    final Completer<JSAny?> done = Completer<JSAny?>();
    request.onsuccess = ((JSAny? _) {
      if (!done.isCompleted) done.complete(request.result);
    }).toJS;
    request.onerror = ((JSAny? _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${request.error}'));
      }
    }).toJS;
    return done.future;
  }

  /// Resolves when [transaction] has committed, which is when a write is
  /// kept -- a request's success is only that it was accepted.
  static Future<void> _committed(_IDBTransaction transaction) {
    final Completer<void> done = Completer<void>();
    transaction.oncomplete = ((JSAny? _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    void failed(JSAny? _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${transaction.error}'));
      }
    }

    transaction.onerror = failed.toJS;
    transaction.onabort = failed.toJS;
    return done.future;
  }
}

@JS('indexedDB')
external _IDBFactory? get _indexedDB;

extension type _IDBFactory._(JSObject _) implements JSObject {
  external _IDBOpenDBRequest open(String name, int version);
}

extension type _IDBRequest._(JSObject _) implements JSObject {
  external JSAny? get result;
  external JSAny? get error;
  external set onsuccess(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

extension type _IDBOpenDBRequest._(JSObject _) implements _IDBRequest {
  external set onupgradeneeded(JSFunction? handler);
}

extension type _DOMStringList._(JSObject _) implements JSObject {
  external bool contains(String name);
}

extension type _IDBDatabase._(JSObject _) implements JSObject {
  external _DOMStringList get objectStoreNames;
  external _IDBObjectStore createObjectStore(String name);
  external _IDBTransaction transaction(JSAny storeNames, String mode);
}

extension type _IDBTransaction._(JSObject _) implements JSObject {
  external _IDBObjectStore objectStore(String name);
  external JSAny? get error;
  external set oncomplete(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external set onabort(JSFunction? handler);
}

extension type _IDBObjectStore._(JSObject _) implements JSObject {
  external _IDBRequest put(JSAny value, JSAny key);
  external _IDBRequest delete(JSAny key);
  external _IDBRequest getAll();
  external _IDBRequest getAllKeys();
}
