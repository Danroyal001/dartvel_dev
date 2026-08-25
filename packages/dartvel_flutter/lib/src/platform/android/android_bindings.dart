/// Android native bindings, behind a conditional import so the web build never
/// sees `dart:ffi` or JNI.
library dartvel_flutter.platform.android;

export 'android_bindings_unsupported.dart'
    if (dart.library.ffi) 'android_bindings_jni.dart';
