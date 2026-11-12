/// Whether a scrollable DVBox list builds only the rows on screen.
///
/// It does, by default and everywhere: an application never writes
/// ListView.builder to get it (owner, 12 Nov 2026). A page of a few hundred
/// rows built whole is a slow first frame and, on a phone, a crash.
///
/// The one exception is the build's page capture (`dartvel build web` and
/// `web-server`), which reads each page whole from the semantics tree for
/// the HTML that crawlers, link previews and readers with scripting off get.
/// A row a lazy list has not built is not in that tree, so while the capture
/// runs every list is built whole. The capture marks the page with
/// `window.__dvCapture` before the app starts.
library;

import 'capture_flag_stub.dart' if (dart.library.js_interop) 'capture_flag_web.dart';

abstract final class DVLazyLists {
  /// True while the build's capture reads the page: every list is built
  /// whole. Tests set it to check both shapes.
  static bool buildWhole = dvCaptureRequested();
}
