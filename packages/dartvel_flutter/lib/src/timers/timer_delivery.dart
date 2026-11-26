/// How a timer reaches a person when it rings: the platform's half of
/// `DV.Timers`.
library dartvel_flutter.timers.timer_delivery;

import 'timer.dart';

/// Whether this platform can still ring a timer when the app is not running.
///
/// Said plainly to the person by the application, so nobody trusts a timer
/// to wake them that cannot.
enum DVTimerReach {
  /// Rings while the app is open, in a background tab or window included;
  /// not once it is closed. Browsers, and the desktop.
  whileOpen,

  /// Rings from the operating system, with the app closed and the screen
  /// off. Android with `dartvel.timers` on.
  appClosed,
}

/// Whether notifications may be shown.
enum DVTimerPermission { granted, denied, notAsked, unsupported }

/// The platform's part: making a sound, showing a notification, and, where
/// the operating system can, ringing at a time with the app gone.
///
/// The service decides when a timer rings; a delivery only carries it out.
/// Implemented for browsers, for Android (a broadcast receiver the build
/// writes) and, everywhere else, as the platform's plain notification.
abstract interface class DVTimerDelivery {
  DVTimerReach get reach;

  /// Actions taken outside the page: a notification's snooze, a dismissal.
  Stream<DVTimerAction> get actions;

  Future<DVTimerPermission> permission();

  /// Asks, from the gesture that started a timer.
  Future<DVTimerPermission> requestPermission();

  /// Called from the gesture that starts a timer: a browser plays sound later
  /// only from an audio context a gesture opened.
  void prime();

  /// Has the operating system ring [timer] at its end even if the app is not
  /// running then. Nothing where the platform cannot.
  Future<void> schedule(DVTimer timer);

  /// Undoes [schedule] for [id].
  Future<void> cancel(String id);

  /// [timer] is due and the app is running: sound and a notification.
  Future<void> ring(DVTimer timer);

  /// Stops the sound for [id] and takes its notification away.
  Future<void> silence(String id);
}

/// Where the timers are kept between visits: one string.
abstract interface class DVTimerStore {
  String? read();
  void write(String value);
}
