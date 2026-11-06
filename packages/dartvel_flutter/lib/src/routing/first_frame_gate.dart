import 'package:flutter/foundation.dart';

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
