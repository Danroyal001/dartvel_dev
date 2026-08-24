/// Android native bindings.
///
/// There is no implementation branch yet, deliberately — see
/// `android_capabilities.dart` for the specific blocker. Both sides of this
/// export resolve to the stub, so `register()` reports false and every binding
/// keeps throwing rather than appearing to work.
library dartvel_flutter.platform.android;

export 'android_bindings_unsupported.dart';
