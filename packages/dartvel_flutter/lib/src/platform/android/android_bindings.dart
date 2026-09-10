/// Android native bindings, behind a conditional import so the web build never
/// sees `dart:ffi` or JNI.
library dartvel_flutter.platform.android;

export 'android_bindings_unsupported.dart'
    if (dart.library.ffi) 'android_bindings_jni.dart';

// Shared by both branches of the conditional export: plain values describing
// how the share intent is built, so they can be asserted without a device.
export 'android_capabilities.dart'
    show
        dvAndroidShareIntentFlags,
        dvAndroidShareMimeType,
        dvAndroidShareUsesChooser,
        dvAndroidLaunchRoute,
        // The decisions the sensor, biometric, notification and device
        // bindings make before they reach Java. Exported because they are
        // the half that can be tested off a device, and the half where a
        // wrong answer still looks like an answer.
        dvAndroidSensorSample,
        dvAndroidBiometricSuccess,
        dvAndroidBiometricAvailable,
        dvAndroidNotificationChannelId,
        dvAndroidNotificationChannelName,
        dvAndroidNotificationNeedsChannel,
        dvAndroidNotificationId,
        dvAndroidStateDirectory,
        dvAndroidFilesRoot;
