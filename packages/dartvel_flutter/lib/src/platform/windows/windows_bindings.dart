/// Windows desktop native bindings, behind a conditional import so the web
/// build never sees `dart:ffi`.
library dartvel_flutter.platform.windows;

export 'windows_bindings_unsupported.dart'
    if (dart.library.ffi) 'windows_bindings_ffi.dart';
