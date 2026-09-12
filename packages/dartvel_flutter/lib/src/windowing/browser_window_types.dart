/// What the browser answers when an application asks it for a window.
///
/// Pure Dart, so both the web implementation and the stub can speak it and no
/// other target carries `package:web` to read it.
library dartvel_flutter.windowing.browser_window_types;

/// What the browser did with a window request.
enum DVBrowserWindowOutcome {
  /// Not a browser: nothing was attempted, and the caller goes on down the
  /// native path it always used.
  notWeb,

  /// The browser opened the window.
  opened,

  /// The browser refused it. On every current browser that means the call was
  /// not attributed to a user gesture, or popups are blocked for the site --
  /// one refusal, reported as itself rather than as a missing binding.
  blocked,
}

/// The result of asking the browser for a window.
class DVBrowserWindowResult {
  const DVBrowserWindowResult(this.outcome, {this.id});

  final DVBrowserWindowOutcome outcome;

  /// What the window was registered under, so it can be closed later. Null
  /// unless [outcome] is [DVBrowserWindowOutcome.opened].
  final String? id;
}

/// Opens [url] as a browser window.
///
/// Replaceable on `DVWindowManager.browserWindowOpener`, so a test can give
/// both of the browser's answers without a browser.
typedef DVBrowserWindowOpener = DVBrowserWindowResult Function(
  String url, {
  String? title,
  double? width,
  double? height,
});
