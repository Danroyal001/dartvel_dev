/// Names the Android push bridge is reached by, shared by the build that
/// writes it and the Dart client that calls it.
///
/// One constant each, because the two halves live in packages that cannot
/// import each other, and a name spelled twice is a lookup that fails for
/// ever -- the same way an APK built with plain `flutter build` fails, so
/// nothing could tell the two apart.
library;

/// The generated Java class Dart calls, in JNI's slash form.
const String dvAndroidPushBridgeClass = 'dev/dartvel/jni/DartvelPush';

/// The Firebase service the manifest declares, in Java's dotted form.
const String dvAndroidPushServiceClass =
    'dev.dartvel.jni.DartvelMessagingService';

/// The Firebase Cloud Messaging client library the generated project depends
/// on. 26.0.0 is the newest on Google Maven as of 2026-10-11. Used without the
/// google-services Gradle plugin: the four values the plugin would read from
/// `google-services.json` are written as the string resources
/// `FirebaseOptions.fromResource` reads, so there is no JSON file to commit
/// and nothing for the plugin to rewrite.
const String dvAndroidFirebaseMessagingLibrary =
    'com.google.firebase:firebase-messaging:26.0.0';
