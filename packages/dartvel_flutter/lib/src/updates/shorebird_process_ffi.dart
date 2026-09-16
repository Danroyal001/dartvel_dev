/// The Shorebird updater's symbols in the running process.
///
/// The same names and signatures `package:shorebird_code_push` binds, from
/// the updater's `updater_dart.h`.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'shorebird_updates.dart';

final class _UpdateResult extends Struct {
  @Int32()
  external int status;

  external Pointer<Utf8> message;
}

DVShorebirdNative dvShorebirdProcessUpdater() => _ProcessUpdater();

class _ProcessUpdater implements DVShorebirdNative {
  _ProcessUpdater() {
    final DynamicLibrary process = DynamicLibrary.process();
    try {
      _current = process
          .lookupFunction<UintPtr Function(), int Function()>(
            'shorebird_current_boot_patch_number',
          );
      _next = process.lookupFunction<UintPtr Function(), int Function()>(
        'shorebird_next_boot_patch_number',
      );
      _check = process
          .lookupFunction<Bool Function(Pointer<Char>), bool Function(Pointer<Char>)>(
            'shorebird_check_for_downloadable_update',
          );
      _update = process.lookupFunction<
        Pointer<_UpdateResult> Function(Pointer<Char>),
        Pointer<_UpdateResult> Function(Pointer<Char>)
      >('shorebird_update_with_result');
      _free = process.lookupFunction<
        Void Function(Pointer<_UpdateResult>),
        void Function(Pointer<_UpdateResult>)
      >('shorebird_free_update_result');
      linked = true;
    } on ArgumentError {
      linked = false;
    }
  }

  @override
  late final bool linked;

  late final int Function() _current;
  late final int Function() _next;
  late final bool Function(Pointer<Char>) _check;
  late final Pointer<_UpdateResult> Function(Pointer<Char>) _update;
  late final void Function(Pointer<_UpdateResult>) _free;

  @override
  int currentPatch() => _current();

  @override
  int nextPatch() => _next();

  @override
  bool checkForUpdate(String? channel) =>
      _withChannel(channel, (Pointer<Char> c) => _check(c));

  @override
  (int, String?) update(String? channel) =>
      _withChannel(channel, (Pointer<Char> c) {
        final Pointer<_UpdateResult> result = _update(c);
        if (result == nullptr) return (DVShorebirdNative.error, null);
        try {
          final Pointer<Utf8> message = result.ref.message;
          return (
            result.ref.status,
            message == nullptr ? null : message.toDartString(),
          );
        } finally {
          _free(result);
        }
      });

  T _withChannel<T>(String? channel, T Function(Pointer<Char>) call) {
    if (channel == null) return call(nullptr);
    final Pointer<Utf8> native = channel.toNativeUtf8();
    try {
      return call(native.cast<Char>());
    } finally {
      malloc.free(native);
    }
  }
}
