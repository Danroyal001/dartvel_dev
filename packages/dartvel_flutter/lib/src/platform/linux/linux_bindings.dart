/// Linux desktop native bindings, behind a conditional import so the web
/// build never sees dart:ffi.
library dartvel_flutter.platform.linux;

export 'linux_bindings_unsupported.dart'
    if (dart.library.ffi) 'linux_bindings_ffi.dart';
