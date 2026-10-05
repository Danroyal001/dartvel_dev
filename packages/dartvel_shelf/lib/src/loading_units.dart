/// Code a web-server binary loads when it is first used.
///
/// Dart's AOT compiler splits a program into loading units: the root, which
/// the runtime maps at start, and one unit per group of libraries reached
/// only through `import ... deferred as`, loaded when the program first
/// calls that import's `loadLibrary()`. A web-server binary carries its units
/// as payload sections (`unit.<id>`, each on a 64 KiB boundary of the file)
/// and this points the VM at them: the native server library's
/// `aw_units_load` maps a unit straight from the executable with the
/// runtime's own ELF loader the first time any isolate asks for it. Nothing
/// is written out, and a unit no request needs is never mapped.
library;

import 'dart:ffi' as ffi;
import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart' show DVBinaryPayload;
import 'package:ffi/ffi.dart' as pkgffi;

import 'native_library.dart';

typedef _HandlerN = ffi.Handle Function(ffi.IntPtr);
typedef _SetN = ffi.Handle Function(ffi.Pointer<ffi.NativeFunction<_HandlerN>>);
typedef _SetD = Object Function(ffi.Pointer<ffi.NativeFunction<_HandlerN>>);

ffi.DynamicLibrary? _library;

/// The payload section a loading unit is carried in.
String dvLoadingUnitSection(int id) => 'unit.$id';

/// Makes the deferred code units [payload] carries loadable from where they
/// lie, and returns how many it carries: zero for a program compiled as one
/// unit, which needs nothing.
///
/// Throws [UnsupportedError] when the payload carries units that this
/// process cannot load -- a native library without the loader, or a runtime
/// that does not export the embedding API -- so the binary fails at start
/// rather than at the first request that needs one.
Future<int> dvInstallLoadingUnits(DVBinaryPayload payload) async {
  final Map<int, int> units = <int, int>{};
  for (final String name in payload.names) {
    if (!name.startsWith('unit.')) continue;
    final int? id = int.tryParse(name.substring(5));
    final ({int offset, int length})? at = payload.locate(name);
    if (id != null && at != null) units[id] = at.offset;
  }
  if (units.isEmpty) return 0;
  final ffi.DynamicLibrary library = (await openNativeServerLibrary()).library;
  if (!library.providesSymbol('aw_units_load') ||
      library.lookupFunction<ffi.Int32 Function(), int Function()>('aw_units_supported')() == 0) {
    throw UnsupportedError('dartvel: this binary carries deferred code that its '
        'native server library or runtime cannot load');
  }
  final int Function(int, ffi.Pointer<ffi.Uint8>, int, int) register = library.lookupFunction<
      ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Uint64),
      int Function(int, ffi.Pointer<ffi.Uint8>, int, int)>('aw_units_register');
  final Uint8List path = utf8.encode(payload.path);
  final ffi.Pointer<ffi.Uint8> native = pkgffi.calloc<ffi.Uint8>(path.length);
  try {
    native.asTypedList(path.length).setAll(0, path);
    for (final MapEntry<int, int> unit in units.entries) {
      if (register(unit.key, native, path.length, unit.value) != 0) {
        throw UnsupportedError('dartvel: code unit ${unit.key} could not be registered');
      }
    }
  } finally {
    pkgffi.calloc.free(native);
  }
  ffi.DynamicLibrary.executable().lookupFunction<_SetN, _SetD>('Dart_SetDeferredLoadHandler')(
      library.lookup<ffi.NativeFunction<_HandlerN>>('aw_units_load'));
  _library = library;
  return units.length;
}

/// How many code units this process has mapped so far.
int dvLoadedUnitCount() =>
    _library?.lookupFunction<ffi.Int32 Function(), int Function()>('aw_units_loaded')() ?? 0;
