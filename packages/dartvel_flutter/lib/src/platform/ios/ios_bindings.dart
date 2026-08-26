/// iOS native bindings, behind a conditional import so the web build never
/// sees `dart:ffi`.
library dartvel_flutter.platform.ios;

export 'ios_bindings_unsupported.dart'
    if (dart.library.ffi) 'ios_bindings_ffi.dart';

// Shared by both branches, and a plain value rather than a binding, so it is
// exported directly. The haptic identifiers are worth asserting off-device.
export 'ios_capabilities.dart' show dvIosHapticSoundId;
