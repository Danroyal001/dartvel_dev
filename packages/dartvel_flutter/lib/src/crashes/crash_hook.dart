/// The places an error can reach the crash reporter from.
library;

/// Where an error arrived. One error can arrive at more than one, and is
/// recorded once; the same place seeing it again is a second occurrence.
enum DVCrashHook {
  /// `FlutterError.onError`: errors the framework caught and reported.
  flutterError,

  /// `PlatformDispatcher.instance.onError`: uncaught errors in the root zone.
  platformDispatcher,

  /// The isolate's error listener, which carries only text.
  isolate,

  /// A browser window's `error` event.
  windowError,

  /// A browser window's `unhandledrejection` event.
  unhandledRejection,

  /// `DV.Crashes.runGuarded`.
  guardedZone,

  /// `DV.Crashes.record`, called by the application.
  application,
}

/// Receives an error that arrived only as its description and stack text.
typedef DVCrashTextReceiver = void Function(
  String error,
  String stack,
  DVCrashHook hook,
);
