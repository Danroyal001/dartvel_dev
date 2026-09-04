/// Kiosk enforcement on Android: lock task mode, held from Dart.
///
/// Lock task is an `Activity`'s, and an Activity is the one thing a JNI
/// binding cannot reach from the application `Context` that package:jni's
/// `GetApplicationContext()` hands back. That is why this went unbuilt long
/// enough to be recorded as blocked, and it was the wrong conclusion:
/// `Application.registerActivityLifecycleCallbacks` is the public route to
/// the running Activity, the callback is a Java interface, and jnigen
/// generates an `implement` for it. No platform channel, which is what the
/// native integration rule asks for.
///
/// What lock task does and does not do is worth stating, because a kiosk that
/// reports more than it holds is worse than one that reports nothing. Pinned
/// without a device owner, Android shows a confirmation dialog and the
/// application is only pinned once somebody answers it -- which on a device
/// in a lobby is never. With the application as device owner, which is what
/// `dartvel build android` prepares by writing the device-admin receiver, it
/// is silent and immediate. Either way the home and recents buttons stop
/// leaving and the notification shade stops opening: those are lock task's,
/// not this code's.
library dartvel_flutter.platform.android.kiosk;

import 'package:jni/jni.dart';

import 'generated/android/app/Activity.dart';
import 'generated/android/app/Application.dart';
import 'generated/android/os/Bundle.dart';

/// The Activity in front of the person, as the application's own lifecycle
/// callbacks report it.
///
/// Held as a field rather than looked up on demand, because there is no
/// lookup: Android tells you when an Activity resumes and never answers the
/// question afterwards.
class DVAndroidActivities {
  const DVAndroidActivities._();

  static Activity? _current;
  static bool _watching = false;

  /// The resumed Activity, or null before the first one resumes.
  static Activity? get current => _current;

  /// Whether the application is reporting its Activities.
  static bool get watching => _watching;

  /// Starts watching [application]. Safe to call twice; the second does
  /// nothing, because two registrations mean two callbacks and the second
  /// would overwrite what the first recorded.
  static void watch(Application application) {
    if (_watching) return;
    application.registerActivityLifecycleCallbacks(
      Application$ActivityLifecycleCallbacks.implement(
        // Every callback the interface declares, because it declares them
        // all. Three of them do something; the rest are here so a future
        // Android that calls one does not find a hole.
        $Application$ActivityLifecycleCallbacks(
          onActivityResumed: (Activity? activity) => _current = activity,
          onActivityPaused: (Activity? activity) {},
          onActivityDestroyed: (Activity? activity) {
            // Only when it is the one being held. An Activity destroyed
            // behind the one in front is an ordinary rotation, and
            // forgetting the current one for it would leave the kiosk
            // unable to enforce.
            if (identical(_current, activity)) _current = null;
          },
          onActivityPreCreated: (Activity? a, Bundle? b) {},
          onActivityCreated: (Activity? a, Bundle? b) {},
          onActivityPostCreated: (Activity? a, Bundle? b) {},
          onActivityPreStarted: (Activity? a) {},
          onActivityStarted: (Activity? a) {},
          onActivityPostStarted: (Activity? a) {},
          onActivityPreResumed: (Activity? a) {},
          onActivityPostResumed: (Activity? a) {},
          onActivityPrePaused: (Activity? a) {},
          onActivityPostPaused: (Activity? a) {},
          onActivityPreStopped: (Activity? a) {},
          onActivityStopped: (Activity? a) {},
          onActivityPostStopped: (Activity? a) {},
          onActivityPreSaveInstanceState: (Activity? a, Bundle? b) {},
          onActivitySaveInstanceState: (Activity? a, Bundle? b) {},
          onActivityPostSaveInstanceState: (Activity? a, Bundle? b) {},
          onActivityPreDestroyed: (Activity? a) {},
          onActivityPostDestroyed: (Activity? a) {},
        ),
      ),
    );
    _watching = true;
  }

  /// Test-only: forgets what it saw.
  static void reset() {
    _current = null;
    _watching = false;
  }
}

class DVAndroidKiosk {
  const DVAndroidKiosk._();

  static const Set<String> implemented = <String>{
    'kiosk.enforce',
    'kiosk.release',
  };

  static bool _held = false;

  /// Whether lock task is being held.
  static bool get held => _held;

  /// Why the last enforce did not take. Null when it did.
  static String? lastError;

  static void register(
    void Function(String, Object? Function(Object?)) bind,
  ) {
    bind('kiosk.enforce', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return _enforce(map);
    });
    bind('kiosk.release', (Object? _) {
      release();
      return true;
    });
  }

  static Map<String, Object?> _enforce(Map<Object?, Object?> map) {
    release();
    final List<Object?> combos =
        map['combos'] is List ? map['combos']! as List<Object?> : const <Object?>[];

    final Activity? activity = DVAndroidActivities.current;
    if (activity == null) {
      lastError = DVAndroidActivities.watching
          ? 'no Activity has resumed yet, so there is nothing to lock'
          : 'the Android bindings are not registered, so no Activity is '
              'being watched';
    } else {
      try {
        activity.startLockTask();
        _held = true;
        lastError = null;
      } on JThrowable catch (error) {
        // Reported rather than thrown: DV-KIOSK-001 is the operator's
        // finding to read, and a kiosk that crashed on the way in is a
        // device showing a stack trace in a lobby.
        lastError = 'startLockTask was refused: ${error.message}';
      }
    }

    return <String, Object?>{
      // Android does not hold individual key combinations. Lock task takes
      // the home and recents buttons wholesale, which covers what the combos
      // are for and is not the same thing -- so each is reported unenforced
      // with the reason rather than claimed.
      'blocked': const <String>[],
      'unenforced': <String, String>{
        for (final Object? combo in combos)
          '$combo': _held
              ? 'lock task mode blocks the home and recents buttons wholesale; '
                  'Android holds no individual key combinations'
              : lastError ?? 'lock task mode is not held',
      },
      // The bars the buttons are drawn on are the window's, and the window
      // belongs to Flutter's own embedding, which puts the application
      // fullscreen already when the policy asks for it.
      'fullscreen': map['fullscreen'] == true && _held,
      // No pointer to confine on a touch device. Claiming it would be a
      // kiosk that reports a guarantee the hardware has no way to break.
      'confined': false,
      // Lock task closes the notification shade, and this is the one
      // platform where that is not a separate promise.
      'notificationsSuppressed': _held,
      'lockTask': _held,
      if (lastError != null) 'error': lastError,
    };
  }

  /// Lets go of lock task. Safe when nothing is held.
  static void release() {
    if (!_held) return;
    _held = false;
    final Activity? activity = DVAndroidActivities.current;
    if (activity == null) return;
    try {
      activity.stopLockTask();
    } on JThrowable {
      // The Activity is going away, which is the usual reason. Nothing to
      // report: releasing something that has already gone is release.
    }
  }
}
