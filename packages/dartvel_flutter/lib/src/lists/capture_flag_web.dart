import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the build's page capture marked this page (window.__dvCapture).
bool dvCaptureRequested() {
  try {
    return globalContext.has('__dvCapture') && globalContext['__dvCapture'].dartify() == true;
  } catch (_) {
    return false;
  }
}
