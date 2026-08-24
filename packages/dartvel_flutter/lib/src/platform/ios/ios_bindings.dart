/// iOS native bindings, behind a conditional import so the web build never
/// sees `dart:ffi`.
library dartvel_flutter.platform.ios;

export 'ios_bindings_unsupported.dart'
    if (dart.library.ffi) 'ios_bindings_ffi.dart';
