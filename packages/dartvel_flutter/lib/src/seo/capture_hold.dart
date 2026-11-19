/// Work an app tells the prerender to wait for.
///
/// A build reads each page once its text has held still for a moment. Some
/// work changes what a page shows without changing its text first: the
/// consent banner waits on the visitor's stored answer, and until that has
/// been read the page looks finished. Under load the read took longer than
/// the text took to look settled, so one build of sigmadev.digital wrote the
/// banner into some pages and left it out of others (19 Nov 2026). Work like
/// that holds the capture until it is done.
library dartvel_flutter.seo.capture_hold;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'capture_hold_stub.dart'
    if (dart.library.js_interop) 'capture_hold_web.dart';

/// One piece of work the capture waits for. [release] it when the work is
/// done, or when it will never finish (it failed, or its widget went away);
/// releasing twice is harmless.
class DVCaptureHold {
  DVCaptureHold._();

  static int _active = 0;

  /// How many holds are unreleased.
  static int get active => _active;

  /// Holds the capture until the returned hold is released.
  static DVCaptureHold begin() {
    _active++;
    dvPublishCaptureHolds(_active);
    return DVCaptureHold._();
  }

  bool _released = false;

  /// Lets the capture go on, as far as this work is concerned.
  void release() {
    if (_released) return;
    _released = true;
    _active--;
    dvPublishCaptureHolds(_active);
  }

  /// Forgets every hold, between tests.
  @visibleForTesting
  static void resetForTest() {
    _active = 0;
    dvPublishCaptureHolds(0);
  }
}
