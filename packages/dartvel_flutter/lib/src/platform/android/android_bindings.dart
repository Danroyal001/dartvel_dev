/// Android native bindings, behind a conditional import so the web build never
/// sees `dart:ffi` or JNI.
library dartvel_flutter.platform.android;

export 'android_bindings_unsupported.dart'
    if (dart.library.ffi) 'android_bindings_jni.dart';

// Shared by both branches of the conditional export: plain values describing
// how the share intent is built, so they can be asserted without a device.
export 'android_capabilities.dart'
    show
        dvAndroidFullscreenBlocker,
        dvAndroidGeometry,
        dvAndroidShareIntentFlags,
        dvAndroidShareMimeType,
        dvAndroidShareUsesChooser,
        dvAndroidLaunchRoute;

// The answers the NFC and Bluetooth bindings hand back, apart from the JNI
// calls that fetch them. Shared by both branches for the same reason: a bond
// state read one value too wide produces a well-formed wrong answer, and that
// is worth asserting on a machine with no device attached.
export 'android_radio_shapes.dart';
