/// The transport to the Swift shim `dartvel build ios` compiles into the
/// application: three C symbols looked up in the running process, and one
/// `NativeCallable` every answer comes back through.
///
/// No platform channel: Dart calls `dartvel_ios_call` directly, and the Swift
/// calls the completion function pointer from whichever thread its framework
/// answered on. `NativeCallable.listener` is what makes that safe -- the call
/// is posted to this isolate rather than run on a foreign thread.
library dartvel_flutter.platform.ios.shim_ffi;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:dartvel_core/dartvel.dart'
    show
        dvIosShimCallSymbol,
        dvIosShimCompletionSymbol,
        dvIosShimDiskFreeSymbol,
        dvIosShimNetworkEventId,
        dvIosShimVersion,
        dvIosShimVersionSymbol;
import 'package:ffi/ffi.dart';

typedef _CompletionNative = Void Function(Int64 id, Pointer<Utf8> json);
typedef _SetCompletionNative = Void Function(Pointer<NativeFunction<_CompletionNative>>);
typedef _SetCompletionDart = void Function(Pointer<NativeFunction<_CompletionNative>>);
typedef _CallNative = Void Function(Int64 id, Pointer<Utf8> op, Pointer<Utf8> json);
typedef _CallDart = void Function(int id, Pointer<Utf8> op, Pointer<Utf8> json);
typedef _VersionNative = Int32 Function();
typedef _VersionDart = int Function();
typedef _DiskFreeNative = Int64 Function(Pointer<Utf8> path);
typedef _DiskFreeDart = int Function(Pointer<Utf8> path);

/// The shim, once it has been found and its version matches.
class DVIosShim {
  DVIosShim._(this._call, this._diskFree);

  final _CallDart _call;
  final _DiskFreeDart? _diskFree;
  final Map<int, Completer<Map<String, Object?>>> _pending = <int, Completer<Map<String, Object?>>>{};
  int _next = 1;

  /// Connectivity changes, once `network.watch` has been sent.
  void Function(Map<String, Object?> event)? onNetwork;

  static DVIosShim? _instance;

  /// Why [open] answered null, for `DVIosBindings.lastFailure`.
  static String? failure;

  /// The shim in this process, or null when the application has none.
  ///
  /// None is the ordinary answer for an application built with plain
  /// `flutter build`, which compiles no Swift of Dartvel's.
  static DVIosShim? open() {
    if (_instance != null) return _instance;
    final DynamicLibrary process = DynamicLibrary.process();
    final int version;
    try {
      version = process.lookupFunction<_VersionNative, _VersionDart>(dvIosShimVersionSymbol)();
    } on ArgumentError {
      failure = 'this application has no Dartvel platform shim. It is compiled in by '
          '`dartvel build ios`; an app built with plain `flutter build ios` has '
          'none, and the bindings it backs stay unregistered.';
      return null;
    }
    if (version != dvIosShimVersion) {
      failure = 'the platform shim in this application speaks version $version and this '
          'runtime speaks $dvIosShimVersion. Rebuild with `dartvel build ios`.';
      return null;
    }
    final _CallDart call = process.lookupFunction<_CallNative, _CallDart>(dvIosShimCallSymbol);
    _DiskFreeDart? diskFree;
    try {
      diskFree = process.lookupFunction<_DiskFreeNative, _DiskFreeDart>(dvIosShimDiskFreeSymbol);
    } on ArgumentError {
      diskFree = null;
    }
    final DVIosShim shim = DVIosShim._(call, diskFree);
    // Never closed: the shim may answer for as long as the process lives.
    final NativeCallable<_CompletionNative> completion =
        NativeCallable<_CompletionNative>.listener(shim._complete)..keepIsolateAlive = false;
    process.lookupFunction<_SetCompletionNative, _SetCompletionDart>(dvIosShimCompletionSymbol)(
        completion.nativeFunction);
    failure = null;
    return _instance = shim;
  }

  void _complete(int id, Pointer<Utf8> json) {
    Map<String, Object?> answer;
    try {
      final Object? decoded = jsonDecode(json.toDartString());
      answer = decoded is Map
          ? decoded.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v))
          : <String, Object?>{'error': 'the shim answered $decoded'};
    } on FormatException catch (error) {
      answer = <String, Object?>{'error': 'the shim answered with something that is not JSON: $error'};
    } finally {
      // strdup'd by the Swift; this side owns it once it arrives.
      malloc.free(json);
    }
    if (id == dvIosShimNetworkEventId) {
      onNetwork?.call(answer);
      return;
    }
    _pending.remove(id)?.complete(answer);
  }

  /// Sends [op] and waits for its answer.
  Future<Map<String, Object?>> call(String op, Map<String, Object?> args) {
    final int id = _next++;
    final Completer<Map<String, Object?>> answered = Completer<Map<String, Object?>>();
    _pending[id] = answered;
    final Pointer<Utf8> opPointer = op.toNativeUtf8();
    final Pointer<Utf8> jsonPointer = jsonEncode(args).toNativeUtf8();
    try {
      // The Swift copies both strings before it returns.
      _call(id, opPointer, jsonPointer);
    } finally {
      calloc.free(opPointer);
      calloc.free(jsonPointer);
    }
    return answered.future;
  }

  /// Free bytes on the volume holding [path], or 0 when unknown.
  int diskFreeBytes(String path) {
    final _DiskFreeDart? diskFree = _diskFree;
    if (diskFree == null) return 0;
    final Pointer<Utf8> pointer = path.toNativeUtf8();
    try {
      final int free = diskFree(pointer);
      return free < 0 ? 0 : free;
    } finally {
      calloc.free(pointer);
    }
  }
}
