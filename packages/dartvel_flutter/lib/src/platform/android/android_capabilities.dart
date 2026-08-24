/// The names the Android bindings would cover, and why none of them do yet.
library dartvel_flutter.platform.android.capabilities;

/// Empty, and the emptiness is a finding rather than a gap in effort.
///
/// The route is fixed by the native integration rule: JNI through
/// `package:jni`, never a platform channel. Everything worth binding —
/// `ClipboardManager`, `Vibrator` — is reached through
/// `Context.getSystemService`, so a `Context` is the prerequisite for all of
/// it.
///
/// **`package:jni` 1.0.0 does not expose one.** `GetApplicationContext` exists
/// in its internal generated bindings and is not part of the public API.
/// Reaching into another package's internals to get it would be a binding that
/// compiles today and breaks on a patch release, and the failure would land in
/// somebody's shipped application rather than here.
///
/// The two ways out, neither taken yet:
///
///   * Have `package:jni` expose the application context, which is an upstream
///     change and the right one.
///   * Ship a small Android archive with Dartvel that caches the context at
///     startup and hands it to Dart — which is what plugins do, minus the
///     platform channel.
///
/// Until one of those, every Android binding stays unregistered and throws
/// `DVNativeBridge`'s "not registered" error. That is a true statement about
/// what Dartvel can do on Android; a registered no-op would not be.
const Set<String> dvAndroidImplementedBindings = <String>{};
