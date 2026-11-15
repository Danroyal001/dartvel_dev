import 'browser_none.dart' if (dart.library.js_interop) 'browser_web.dart'
    as platform;

/// Google's tag, in the one place it runs: a browser.
///
/// Kept behind an interface so the rest of the module can be tested without
/// a browser and compiled without one.
abstract interface class GoogleAnalyticsBrowser {
  /// Whether there is a page to load the tag into. False on a device and on
  /// the backend.
  bool get available;

  /// Loads the tag for [measurementId]: the script at [scriptUrl] that
  /// defines `gtag`, then `gtag('config', ...)` with `send_page_view` set to
  /// [sendPageView], then Google's own script. Called once.
  void load(
    String measurementId, {
    required String scriptUrl,
    required bool sendPageView,
  });

  /// `gtag('event', name, params)`.
  void event(String name, Map<String, Object?> params);

  /// `gtag('consent', 'update', ...)` for analytics storage.
  void consent({required bool granted});

  /// The client id Google's tag gave this browser, or null before it has.
  String? get clientId;

  /// The tag's current session id, or null before it has one.
  String? get sessionId;

  /// The page's address.
  String? get pageUrl;

  /// The page's title.
  String? get pageTitle;
}

/// The browser of the environment this was compiled for.
GoogleAnalyticsBrowser createGoogleAnalyticsBrowser() =>
    platform.createBrowser();

/// The client id in a `_ga` cookie: its last two numbers, joined by a
/// period, which is the form Google recommends sending. A cookie that does
/// not have that shape is returned whole, which Google also accepts.
String? dvGoogleAnalyticsClientIdFromCookie(String? cookie) {
  if (cookie == null || cookie.trim().isEmpty) return null;
  final RegExpMatch? match =
      RegExp(r'(\d+\.\d+)$').firstMatch(cookie.trim());
  return match?.group(1) ?? cookie.trim();
}
