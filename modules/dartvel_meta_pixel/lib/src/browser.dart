import 'browser_none.dart' if (dart.library.js_interop) 'browser_web.dart'
    as platform;

/// The pixel's own script, in the one place it runs: a browser.
///
/// Everything else the module does is the same on every target; this is the
/// part that is not, kept behind an interface so the rest can be tested
/// without a browser and compiled without one.
abstract interface class MetaPixelBrowser {
  /// Whether there is a page to load the pixel into. False on a device and
  /// on the backend.
  bool get available;

  /// Loads the pixel's script from [scriptUrl] and initialises [pixelId].
  /// Called once.
  void load(String pixelId, {required String scriptUrl});

  /// `fbq('track', ...)`, or `fbq('trackCustom', ...)` for a [custom] event,
  /// with [eventId] as its `eventID`.
  void track(
    String name,
    Map<String, Object?> data, {
    required String eventId,
    required bool custom,
  });

  /// `fbq('consent', 'grant')` or `fbq('consent', 'revoke')`.
  void consent({required bool granted});

  /// The value of the cookie [name], or null.
  String? cookie(String name);

  /// The value of [name] in the page's address, or null.
  String? queryParameter(String name);

  /// The page's address.
  String? get pageUrl;

  String? get userAgent;
}

/// The browser of the environment this was compiled for.
MetaPixelBrowser createMetaPixelBrowser() => platform.createBrowser();
