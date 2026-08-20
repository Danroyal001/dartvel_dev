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
class DVWindowSharedStore {
  DVWindowSharedStore({
    DVSharedStoreBackend? backend,
    DVSharedStoreCipher cipher = const DVNullSharedStoreCipher(),
    this.debounce = const Duration(milliseconds: 50),
    this.spillThresholdBytes = 32 * 1024,
    DVFileStorageAdapter? spillStorage,
  })  : _backend = backend ?? DVMemorySharedStoreBackend(),
        _cipher = cipher,
        _spill = spillStorage {
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

  /// A signal changing per frame must not produce a write per frame.
  final Duration debounce;

  StreamSubscription<String>? _subscription;
  final Map<String, StreamController<DVJsonValue?>> _watchers =
      <String, StreamController<DVJsonValue?>>{};
  final Map<String, ValueNotifier<DVJsonValue?>> _signals =
      <String, ValueNotifier<DVJsonValue?>>{};
  final Map<String, Timer> _pending = <String, Timer>{};
  final Map<String, DVJsonValue?> _latest = <String, DVJsonValue?>{};

  Future<DVJsonValue?> get(String key) async {
    if (_latest.containsKey(key)) return _latest[key];
    return _resolve(await _backend.read(key));
  }

  /// Reads a stored entry, following a spill pointer when it is one.
  Future<DVJsonValue?> _resolve(String? stored) async {
    if (stored == null) return null;
    final plaintext = _cipher.decrypt(stored);
    if (plaintext == null) return null;
    if (!plaintext.startsWith(_spillPrefix)) return _parse(plaintext);

    final storage = _spill;
    if (storage == null) return null;
    try {
      final bytes = await storage.get(plaintext.substring(_spillPrefix.length));
      final body = _cipher.decrypt(utf8.decode(bytes));
      return body == null ? null : _parse(body);
    } catch (_) {
      // A pointer whose object is gone is an unreadable value like any other.
      return null;
    }
  }

  /// Writes [value], coalescing rapid writes to the same key.
  ///
  /// Last write wins, per key. Keys are the conflict unit, so unrelated state
  /// in the same window never contends; state that needs merge semantics is
  /// model state.
  Future<void> set(String key, DVJsonValue? value) async {
    _latest[key] = value;
    _publish(key, value);

    _pending[key]?.cancel();
    final completer = Completer<void>();
    _pending[key] = Timer(debounce, () async {
      _pending.remove(key);
      await _flush(key, value);
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Writes now, bypassing the debounce. Tear-out uses this: the window is
  /// about to open and the state has to be there when it reads.
  Future<void> flush(String key) async {
    _pending.remove(key)?.cancel();
    await _flush(key, _latest[key]);
  }

  Future<void> _flush(String key, DVJsonValue? value) async {
    if (value == null) {
      await _backend.write(key, null);
      return;
    }
    final encoded = jsonEncode(DVJsonCodec.toJson(value));
    final storage = _spill;
    if (storage != null && encoded.length > spillThresholdBytes) {
      // The pointer write is what triggers the notification, and the reader
      // follows it — so spilling needs no watcher of its own.
      final objectKey = 'dartvel/window-shared/${_objectName(key)}';
      await storage.put(
        objectKey,
        utf8.encode(_cipher.encrypt(encoded)),
        contentType: 'application/octet-stream',
      );
      await _backend.write(key, _cipher.encrypt('$_spillPrefix$objectKey'));
      return;
    }
    await _backend.write(key, _cipher.encrypt(encoded));
  }

  /// A file-safe name for [key]. Deterministic, so a rewrite replaces the
  /// object rather than leaving the previous one behind.
  static String _objectName(String key) =>
      key.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');

  Stream<DVJsonValue?> watch(String key) => _watchers
      .putIfAbsent(key, () => StreamController<DVJsonValue?>.broadcast())
      .stream;

  /// A live signal for [key], updated by this window and by any other.
  ValueListenable<DVJsonValue?> signal(String key) {
    final existing = _signals[key];
    if (existing != null) return existing;
    final notifier = ValueNotifier<DVJsonValue?>(_latest[key]);
    _signals[key] = notifier;
    // A late joiner reads current state rather than waiting for a change it
    // has already missed — the whole reason this is a store.
    unawaited(get(key).then((DVJsonValue? value) {
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
    final value = await _resolve(await _backend.read(key));
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
