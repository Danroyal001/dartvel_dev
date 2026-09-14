/// The worker side of `DV.Workers` in a browser.
library dartvel.compute.web_worker_entry;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_worker_protocol.dart';

/// Answers requests from the page. Call it from the worker script's `main`
/// after registering the same tasks the page registered.
///
/// ```dart
/// void main() {
///   DVWorkerTasks.register('parseLedger', parseLedger);
///   dvWebWorkerMain();
/// }
/// ```
void dvWebWorkerMain() {
  final JSObject scope = globalContext;
  void post(Map<String, Object?> message) =>
      scope.callMethod<JSAny?>('postMessage'.toJS, message.jsify());

  scope['onmessage'] = ((JSObject event) {
    final Object? data = event['data'].dartify();
    if (data is Map) {
      // dvWorkerHandle always posts a final answer, so nothing is awaited.
      dvWorkerHandle(data, post).ignore();
    } else {
      post(<String, Object?>{
        'id': -1,
        'kind': 'failed',
        'failure': 'crashed',
        'error': 'the worker was sent something that is not a request',
      });
    }
  }).toJS;
}
