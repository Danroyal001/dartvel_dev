/// A second window on the web, which is a browser window and nothing else.
///
/// Every other target opens a window through the `window.open` native
/// binding. The web has no such binding and cannot have one: what a browser
/// gives a page is `window.open`, a popup it opens inside a user gesture and
/// refuses outside one. That refusal is a rule of the platform, which the
/// specification names (`DV-WINDOW-003`) and Dartvel reports rather than
/// attempts to bypass -- where before it read as a missing native binding,
/// an `error` blaming the integration for the browser doing its job.
///
/// Behind a conditional export for the same reason the URL strategy is: no
/// other target carries `package:web`, and off the web the stub answers
/// [DVBrowserWindowOutcome.notWeb] so the caller continues down the native
/// path unchanged.
library dartvel_flutter.windowing.browser_window;

export 'browser_window_stub.dart'
    if (dart.library.js_interop) 'browser_window_web.dart';
export 'browser_window_types.dart';
