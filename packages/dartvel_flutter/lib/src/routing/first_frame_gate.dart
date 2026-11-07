import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'first_frame_platform_stub.dart'
    if (dart.library.js_interop) 'first_frame_platform_web.dart'
    as platform;

bool _watching = false;

bool _scrollbarsFadingIn(WidgetsBinding binding) {
  bool fading = false;
  void visit(Element element) {
    if (fading) return;
    final widget = element.widget;
    if (widget is CustomPaint) {
      final painter = widget.foregroundPainter;
      if (painter is ScrollbarPainter &&
          painter.fadeoutOpacityAnimation.status == .forward) {
        fading = true;
        return;
      }
    }
    element.visitChildElements(visit);
  }

  binding.rootElement?.visitChildElements(visit);
  return fading;
}

/// Waits for the rendered frame after initial layout notifications.
Future<void> dvWaitForPostLayoutRaster(WidgetsBinding binding) async {
  // Scroll metrics notifications run after layout. Let those listeners finish
  // before accepting a later frame, including when timings arrive in a batch.
  await binding.endOfFrame;
  int settledFrame = binding.currentSystemFrameTimeStamp.inMicroseconds;
  final ready = Completer<void>();
  void onTimings(List<FrameTiming> timings) {
    if (_scrollbarsFadingIn(binding)) return;
    if (timings.any(
      (frame) =>
          frame.timestampInMicroseconds(.vsyncStart) > settledFrame,
    )) {
      binding.removeTimingsCallback(onTimings);
      ready.complete();
    }
  }

  void requestFrame(Duration _) {
    if (ready.isCompleted) return;
    if (_scrollbarsFadingIn(binding)) {
      settledFrame = binding.currentSystemFrameTimeStamp.inMicroseconds;
    }
    binding.addPostFrameCallback(requestFrame);
    binding.scheduleFrame();
  }

  binding.addTimingsCallback(onTimings);
  requestFrame(.zero);
  await ready.future;
}

/// Keeps frames coming until [binding] reports its first frame rasterized.
///
/// The web engine hands frame timings over in batches, and only when a frame
/// finishes more than 100 ms after the previous batch; the first-frame
/// future completes from those timings. An app whose first frames all finish
/// inside one such window and then go idle -- multi-threaded skwasm, which
/// rasterizes on a worker -- would never be told, and the splash would
/// stay over it. A frame every 100 ms until then
/// releases the batch; it stops the moment the first frame is reported.
///
/// [rasterized] is the first-frame future, [WidgetsBinding.waitUntilFirstFrameRasterized]
/// unless a test supplies its own.
Future<void> dvFlushFirstFrameTimings(
  WidgetsBinding binding, {
  Future<void>? rasterized,
}) async {
  final Future<void> reported =
      rasterized ?? binding.waitUntilFirstFrameRasterized;
  bool done = false;
  final Timer ticker = Timer.periodic(
    const Duration(milliseconds: 100),
    (_) {
      if (!done) binding.scheduleFrame();
    },
  );
  try {
    await reported;
  } finally {
    done = true;
    ticker.cancel();
  }
}

/// Flutter's DOM callback runs even when frames are deferred. Publish the
/// framework handshake only when the engine has actually rendered its frame.
void dvWatchWebFirstFrame() {
  if (!kIsWeb || _watching) return;
  _watching = true;
  unawaited(
    dvFlushFirstFrameTimings(WidgetsBinding.instance).then((_) async {
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
