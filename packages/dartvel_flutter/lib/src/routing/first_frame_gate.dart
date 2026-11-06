import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'first_frame_platform_stub.dart'
    if (dart.library.js_interop) 'first_frame_platform_web.dart'
    as platform;

bool _watching = false;

/// Flutter's DOM callback runs even when frames are deferred. Publish the
/// framework handshake only when the engine has actually rendered its frame.
void dvWatchWebFirstFrame() {
  if (!kIsWeb || _watching) return;
  _watching = true;
  unawaited(
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      platform.dvPublishFirstFrame();
    }),
  );
}

/// Test the web engine handover with a deterministic widget-test binding.
/// Kept inside the framework; it is not exported to applications.
@visibleForTesting
bool? dvDebugWebFirstFrame;

bool get dvHoldWebFirstFrame {
  bool web = kIsWeb;
  assert(() {
    web = dvDebugWebFirstFrame ?? web;
    return true;
  }());
  return web;
}
