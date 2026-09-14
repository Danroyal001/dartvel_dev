import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../dartvel_flutter.dart';

/// Where a shared value is actually kept, and how a change reaches another
/// window.
///
/// Every target needs persistence — tab order and drafts must survive a
/// relaunch on a desktop as much as on a phone. Only cross-engine targets need
/// the OS to deliver notifications, because windows that share an isolate are
/// already reached by the signal write itself.
abstract class DVSharedStoreBackend {
  /// The raw stored string for [key], or null.
  Future<String?> read(String key);

  /// Stores [value], or removes the key when null.
  Future<void> write(String key, String? value);

  /// Every key currently held.
  Future<List<String>> keys();

  /// Changes made by *another* window. In-process backends may return an
  /// empty stream: a same-engine write already reaches every window.
  Stream<String> get changed => const Stream<String>.empty();
}

/// The default backend: in memory, with no cross-engine notification.
///
/// Correct for desktop, where windows share an isolate, and for tests. A
/// target whose windows are separate engines registers a backend that reads
/// and writes the platform preference store instead.
class DVMemorySharedStoreBackend extends DVSharedStoreBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<List<String>> keys() async => _values.keys.toList(growable: false);
}

/// Encrypts values before they reach the backend.
///
/// Encryption is Dartvel's job rather than the store's, so the backing store
/// is a dumb byte sink on every target — one code path and one threat model,
/// rather than depending on encrypted preferences here and `localStorage`,
/// which has no encryption story at all, there.
abstract class DVSharedStoreCipher {
  String encrypt(String plaintext);

  /// Returns null when the value cannot be read — a rotated key, a reset
  /// keychain, a profile moved between machines. The store discards it rather
  /// than failing: it holds view state, so losing it costs a tab order.
  String? decrypt(String ciphertext);
}

/// The default when no application key has been provided.
///
/// Deliberately not encryption, and it says so: a cipher that pretends would
/// be worse than one that is honest about doing nothing, because the first
/// gets trusted.
///
/// It governs view state only. The sealed namespaces
/// ([DVWindowSharedStore.sealedPrefixes]) are encrypted under the application
/// key whichever cipher a store has.
class DVNullSharedStoreCipher implements DVSharedStoreCipher {
  const DVNullSharedStoreCipher();

  @override
  String encrypt(String plaintext) => plaintext;

  @override
  String? decrypt(String ciphertext) => ciphertext;
}

/// AES-256-GCM under the application key.
///
/// Encryption is on for the whole store rather than per key: a per-key opt-in
/// means the one key someone forgot is the one that mattered, and encrypting
/// view state costs nothing at these sizes.
class DVAppKeySharedStoreCipher implements DVSharedStoreCipher {
  final DVAppKeyCipher _cipher;

  DVAppKeySharedStoreCipher(Uint8List key) : _cipher = DVAppKeyCipher(key);

  /// Resolves the key from [store], generating one on first use.
  static Future<DVAppKeySharedStoreCipher> forStore(
    DVAppKeyStore store,
  ) async =>
      DVAppKeySharedStoreCipher(await DVAppKey.ensure(store));

  @override
  String encrypt(String plaintext) => _cipher.encrypt(plaintext);

  @override
  String? decrypt(String ciphertext) => _cipher.decrypt(ciphertext);
}

/// Cross-window view state: which tab is active, tab order, layout, scroll
/// offsets, drafts.
///
/// Not for model data. Models already converge through model sync, which
/// applies auth, tenant filters and policy checks before delivery; copying
/// rows in here would bypass all three.
///
/// A watched store rather than message passing, because a message has a
/// delivery moment: a window opened five seconds later gets nothing, and crash
/// recovery has nothing to read. A store has no delivery moment — late joiners
/// read current state on open.
/// Thrown when application code touches a reserved key namespace.
///
/// Typed rather than a bare ArgumentError so an application can catch this one
/// case -- a plugin composing keys from user input, say -- without swallowing
/// every other argument fault.
class DVSharedStoreKeyError extends ArgumentError {
  DVSharedStoreKeyError(this.key, this.prefix)
      : super.value(
          key,
          'key',
          'starts with the reserved prefix "$prefix". Keys beginning "dv." or '
              '"workspace." belong to Dartvel; an application writing one '
              'would overwrite framework state, and the failure would arrive '
              'later as a workspace that restores wrong',
        );

  /// The rejected key.
  final String key;

  /// The reserved prefix it started with.
  final String prefix;
}

/// Where a store finds the application key store, or null when this platform
/// has none.
///
/// A function rather than a store, so nothing asks the platform for a key
/// until a sealed value is first written or read: a keyring probe at startup
/// would be paid by every application, whether it keeps anything sealed or
/// not.
typedef DVAppKeyStoreSource = Future<DVAppKeyStore?> Function();

/// A value under a sealed namespace that was not written, because no
/// application key could be had to encrypt it under.
///
/// Thrown rather than falling back: a sealed value written in plaintext
/// because the keyring was locked is exactly the write the seal exists to
/// stop.
class DVSharedStoreSealUnavailable implements Exception {
  DVSharedStoreSealUnavailable(this.key, [this.cause]);

  /// The key that was not written.
  final String key;

  /// What resolving the application key failed with; null when no key store
  /// answered at all.
  final Object? cause;

  /// Why, in words that name neither the value nor anything read from the
  /// key store.
  String get reason => cause == null
      ? 'no application key store is available on this platform to encrypt '
          'it under, and it is never stored in plaintext'
      : 'the application key could not be read or created '
          '(${cause.runtimeType}), and it is never stored in plaintext';

  @override
  String toString() => 'DVSharedStoreSealUnavailable: $key was not written: $reason';
}

class DVWindowSharedStore {
  DVWindowSharedStore({
    DVSharedStoreBackend? backend,
    DVSharedStoreCipher cipher = const DVNullSharedStoreCipher(),
    this.debounce = const Duration(milliseconds: 50),
    this.spillThresholdBytes = 32 * 1024,
    DVFileStorageAdapter? spillStorage,
    DVAppKeyStoreSource? appKeys,
  })  : _backend = backend ?? DVMemorySharedStoreBackend(),
        _cipher = cipher,
        _spill = spillStorage,
        _appKeys = appKeys {
    _subscription = _backend.changed.listen(_onExternalChange);
  }

  /// Values larger than this go to file storage, leaving a pointer behind.
  ///
  /// Preference stores are built for small values — they load wholesale into
  /// memory, and browsers cap an origin at a few megabytes. Workspace state is
  /// bytes; a rich-text draft is not.
  final int spillThresholdBytes;

  final DVFileStorageAdapter? _spill;

  /// Marks a stored value as a pointer to spilled bytes rather than the bytes.
  static const String _spillPrefix = 'dv-spill:';

  final DVSharedStoreBackend _backend;
  final DVSharedStoreCipher _cipher;

  /// Where this store finds the application key; [defaultAppKeys] when null.
  final DVAppKeyStoreSource? _appKeys;

  /// The application key cipher, once one has been had.
  DVAppKeyCipher? _seal;

  /// A signal changing per frame must not produce a write per frame.
  final Duration debounce;

  StreamSubscription<String>? _subscription;
  final Map<String, StreamController<DVJsonValue?>> _watchers =
      <String, StreamController<DVJsonValue?>>{};
  final Map<String, ValueNotifier<DVJsonValue?>> _signals =
      <String, ValueNotifier<DVJsonValue?>>{};
  final Map<String, Timer> _pending = <String, Timer>{};
  final Map<String, DVJsonValue?> _latest = <String, DVJsonValue?>{};

  /// Namespaces an application may not touch.
  ///
  /// `workspace.` is DVTabWorkspace's layout state; `xr.` holds world anchor
  /// tokens (`xr.anchors.*`); `dv.` is everything else the framework keeps
  /// here. A prefix rule, not a substring one: `myapp.workspace.name`
  /// collides with nothing and stays legal.
  static const List<String> reservedPrefixes = <String>['dv.', 'workspace.', 'xr.'];

  /// Namespaces written only encrypted under the application key, whatever
  /// cipher the store was given, and refused when no key can be had.
  ///
  /// `xr.anchors.` holds world anchor tokens, and a token re-localizes a
  /// physical place -- often a room in somebody's home. The store's cipher
  /// is a choice about view state, where the default of none costs a tab
  /// order; it is not a choice anybody made about that.
  static const List<String> sealedPrefixes = <String>['xr.anchors.'];

  /// A source with no key store: what a store has until one is configured.
  static Future<DVAppKeyStore?> noAppKeys() async => null;

  /// Where a store made without `appKeys` finds the application key store.
  ///
  /// None by default. A store has no application id to name a platform key
  /// store by, and guessing one would share a key between applications; so
  /// until the application sets this, a sealed value is refused rather than
  /// written. Read when a key is first needed, so a store made before this
  /// was set still uses it.
  static DVAppKeyStoreSource defaultAppKeys = noAppKeys;

  static bool _isSealed(String key) => sealedPrefixes.any(key.startsWith);

  /// The application key cipher, resolved on first use, or
  /// [DVSharedStoreSealUnavailable] naming [key].
  Future<DVAppKeyCipher> _sealFor(String key) async {
    final DVAppKeyCipher? known = _seal;
    if (known != null) return known;
    final DVAppKeyStore? keys;
    try {
      keys = await (_appKeys ?? defaultAppKeys)();
    } on Object catch (error) {
      throw DVSharedStoreSealUnavailable(key, error);
    }
    if (keys == null) throw DVSharedStoreSealUnavailable(key);
    try {
      return _seal = DVAppKeyCipher(await DVAppKey.ensure(keys));
    } on Object catch (error) {
      throw DVSharedStoreSealUnavailable(key, error);
    }
  }

  /// Throws if [key] is in a reserved namespace.
  static void _reject(String key) {
    for (final String prefix in reservedPrefixes) {
      if (key.startsWith(prefix)) throw DVSharedStoreKeyError(key, prefix);
    }
  }

  Future<DVJsonValue?> get(String key) {
    _reject(key);
    return getReserved(key);
  }

  /// [get] without the namespace check, for the framework's own state.
  @internal
  Future<DVJsonValue?> getReserved(String key) async {
    if (_latest.containsKey(key)) return _latest[key];
    return _resolve(key, await _backend.read(key));
  }

  /// Reads a stored entry, following a spill pointer when it is one.
  Future<DVJsonValue?> _resolve(String key, String? stored) async {
    if (stored == null) return null;
    final plaintext = _cipher.decrypt(stored);
    if (plaintext == null) return null;
    if (!plaintext.startsWith(_spillPrefix)) return _open(key, plaintext);

    final storage = _spill;
    if (storage == null) return null;
    try {
      final bytes = await storage.get(plaintext.substring(_spillPrefix.length));
      final body = _cipher.decrypt(utf8.decode(bytes));
      return body == null ? null : _open(key, body);
    } catch (_) {
      // A pointer whose object is gone is an unreadable value like any other.
      return null;
    }
  }

  /// Parses [body], opening the application key seal first when [key] is in
  /// a sealed namespace.
  ///
  /// A sealed value that does not open is unreadable like any other --
  /// including one an earlier version wrote in plaintext, which is not read
  /// as a value.
  Future<DVJsonValue?> _open(String key, String body) async {
    if (!_isSealed(key)) return _parse(body);
    final DVAppKeyCipher seal;
    try {
      seal = await _sealFor(key);
    } on DVSharedStoreSealUnavailable {
      return null;
    }
    final String? opened = seal.decrypt(body);
    return opened == null ? null : _parse(opened);
  }

  /// Writes [value], coalescing rapid writes to the same key.
  ///
  /// Last write wins, per key. Keys are the conflict unit, so unrelated state
  /// in the same window never contends; state that needs merge semantics is
  /// model state.
  Future<void> set(String key, DVJsonValue? value) {
    _reject(key);
    return setReserved(key, value);
  }

  /// [set] without the namespace check, for the framework's own state.
  ///
  /// A value under a sealed namespace throws [DVSharedStoreSealUnavailable]
  /// when no application key can be had, and nothing is kept -- not even in
  /// memory, where it would read back as though it had been stored.
  @internal
  Future<void> setReserved(String key, DVJsonValue? value) async {
    if (value != null && _isSealed(key)) await _sealFor(key);
    DVWindowPerformance.current.recordStoreWrite(key);
    _latest[key] = value;
    _publish(key, value);

    _pending[key]?.cancel();
    final completer = Completer<void>();
    _pending[key] = Timer(debounce, () async {
      _pending.remove(key);
      try {
        await _flush(key, value);
        if (!completer.isCompleted) completer.complete();
      } catch (error, stackTrace) {
        // To the caller that asked for the write. Thrown inside the timer,
        // it reached nobody and the future never completed.
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Writes now, bypassing the debounce. Tear-out uses this: the window is
  /// about to open and the state has to be there when it reads.
  Future<void> flush(String key) {
    _reject(key);
    return flushReserved(key);
  }

  /// [flush] without the namespace check, for the framework's own state.
  @internal
  Future<void> flushReserved(String key) async {
    _pending.remove(key)?.cancel();
    await _flush(key, _latest[key]);
  }

  Future<void> _flush(String key, DVJsonValue? value) async {
    if (value == null) {
      // The object first, then the pointer. A crash between the two leaves an
      // object nothing points at, which the next write of this key replaces;
      // the other order leaves a pointer to an object that is gone, and a
      // reader following it gets an error instead of a missing value.
      await _dropSpill(key);
      await _backend.write(key, null);
      DVWindowPerformance.current.recordStoreFlush(key, bytes: null);
      return;
    }
    final encoded = jsonEncode(DVJsonCodec.toJson(value));
    // Sealed before the store's own cipher sees it, so what reaches the
    // backend -- or spills to file storage -- is ciphertext under the
    // application key whichever cipher this store was given.
    final payload =
        _isSealed(key) ? (await _sealFor(key)).encrypt(encoded) : encoded;
    final storage = _spill;
    if (storage != null && payload.length > spillThresholdBytes) {
      DVWindowPerformance.current
          .recordStoreFlush(key, bytes: payload.length, spilled: true);
      // The pointer write is what triggers the notification, and the reader
      // follows it — so spilling needs no watcher of its own.
      final objectKey = 'dartvel/window-shared/${_objectName(key)}';
      await storage.put(
        objectKey,
        utf8.encode(_cipher.encrypt(payload)),
        contentType: 'application/octet-stream',
      );
      await _backend.write(key, _cipher.encrypt('$_spillPrefix$objectKey'));
      return;
    }
    // Small enough to live in the preference store. If this key spilled
    // before, the object it left is now unreferenced -- the pointer is about
    // to be overwritten with the value itself.
    await _dropSpill(key);
    await _backend.write(key, _cipher.encrypt(payload));
    DVWindowPerformance.current.recordStoreFlush(key, bytes: payload.length);
  }

  /// Deletes the spilled object for [key], if this key spilled one.
  ///
  /// Nothing deleted them. A removed key cleared its pointer and left the
  /// object, and a value that shrank below the threshold was written inline
  /// over the pointer and left the object -- so the bytes stayed on disk, or
  /// in a bucket, for the life of the installation with nothing referring to
  /// them.
  ///
  /// `sweepAfter` is the setting the specification names for cleaning these
  /// up later and it still cannot be honoured: DVFileStorageAdapter has list
  /// and delete and no notion of when an object was written, so "older than
  /// 24 hours" is not a question this interface can answer. Deleting on
  /// removal needs no age, and is the half that is correct rather than a
  /// tidy-up after the fact.
  ///
  /// A rewrite that spills again is unaffected: the object name is derived
  /// from the key, so the new write replaces the old object at the same name.
  Future<void> _dropSpill(String key) async {
    final storage = _spill;
    if (storage == null) return;
    final objectKey = 'dartvel/window-shared/${_objectName(key)}';
    // Asked rather than assumed. A delete on a key that was never written is
    // an error on some adapters and a no-op on others, and a store should not
    // depend on which.
    if (await storage.exists(objectKey)) await storage.delete(objectKey);
  }

  /// A file-safe name for [key]. Deterministic, so a rewrite replaces the
  /// object rather than leaving the previous one behind.
  static String _objectName(String key) =>
      key.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');

  Stream<DVJsonValue?> watch(String key) {
    _reject(key);
    return _watchStream(key);
  }

  Stream<DVJsonValue?> _watchStream(String key) => _watchers
      .putIfAbsent(key, () => StreamController<DVJsonValue?>.broadcast())
      .stream;

  /// A live signal for [key], updated by this window and by any other.
  ValueListenable<DVJsonValue?> signal(String key) {
    _reject(key);
    return signalReserved(key);
  }

  /// [signal] without the namespace check, for the framework's own state.
  @internal
  ValueListenable<DVJsonValue?> signalReserved(String key) {
    final existing = _signals[key];
    if (existing != null) return existing;
    final notifier = ValueNotifier<DVJsonValue?>(_latest[key]);
    _signals[key] = notifier;
    // A late joiner reads current state rather than waiting for a change it
    // has already missed — the whole reason this is a store.
    unawaited(getReserved(key).then((DVJsonValue? value) {
      if (_signals[key] == notifier) notifier.value = value;
    }));
    return notifier;
  }

  Future<List<String>> keys() => _backend.keys();

  /// Drops the in-memory copy so the next read goes to the backend.
  ///
  /// Exists for tests that need to prove a value survived the wire format
  /// rather than being served from the cache that made the write fast.
  @visibleForTesting
  void evictCache() => _latest.clear();

  Future<void> remove(String key) => set(key, null);

  void _publish(String key, DVJsonValue? value) {
    _watchers[key]?.add(value);
    _signals[key]?.value = value;
  }

  Future<void> _onExternalChange(String key) async {
    final value = await _resolve(key, await _backend.read(key));
    _latest[key] = value;
    _publish(key, value);
  }

  DVJsonValue? _parse(String plaintext) {
    try {
      return DVJsonCodec.fromJson(jsonDecode(plaintext));
    } catch (_) {
      // A value that cannot be read is discarded rather than fatal: it holds
      // view state, so losing it costs a tab order.
      return null;
    }
  }

  Future<void> dispose() async {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    await _subscription?.cancel();
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();
    for (final notifier in _signals.values) {
      notifier.dispose();
    }
    _signals.clear();
    _latest.clear();
  }
}
