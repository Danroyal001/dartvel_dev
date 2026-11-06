import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'first_frame_platform_stub.dart'
    if (dart.library.js_interop) 'first_frame_platform_web.dart'
    as platform;

bool _watching = false;

/// Waits for the rendered frame after initial layout notifications.
Future<void> dvWaitForPostLayoutRaster(WidgetsBinding binding) async {
  // Scroll metrics notifications run after layout. Let those listeners finish
  // before accepting a later frame, including when timings arrive in a batch.
  await binding.endOfFrame;
  final int layoutFrame = binding.currentSystemFrameTimeStamp.inMicroseconds;
  final ready = Completer<void>();
  void onTimings(List<FrameTiming> timings) {
    if (timings.any(
      (frame) =>
          frame.timestampInMicroseconds(.vsyncStart) > layoutFrame,
    )) {
      binding.removeTimingsCallback(onTimings);
      ready.complete();
    }
  }

  void requestFrame(Duration _) {
    if (ready.isCompleted) return;
    binding.addPostFrameCallback(requestFrame);
    binding.scheduleFrame();
  }

  binding.addTimingsCallback(onTimings);
  requestFrame(.zero);
  await ready.future;
}

/// Flutter's DOM callback runs even when frames are deferred. Publish the
/// framework handshake only when the engine has actually rendered its frame.
void dvWatchWebFirstFrame() {
  if (!kIsWeb || _watching) return;
  _watching = true;
  unawaited(
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) async {
      await dvWaitForPostLayoutRaster(WidgetsBinding.instance);
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
