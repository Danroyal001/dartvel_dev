/// macOS native bindings, behind a conditional import so the web build never
/// sees `dart:ffi`.
library dartvel_flutter.platform.macos;

export 'macos_bindings_unsupported.dart'
    if (dart.library.ffi) 'macos_bindings_ffi.dart';
