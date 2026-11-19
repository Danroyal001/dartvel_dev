/// The browser half of a capture hold: the count, where the build's capture
/// reads it (`globalThis.__dvCaptureHolds`, dartvel_cli page_shots.dart).
library dartvel_flutter.seo.capture_hold.web;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Writes how many holds are unreleased where the capture looks.
void dvPublishCaptureHolds(int active) {
  globalContext['__dvCaptureHolds'] = active.toJS;
}
