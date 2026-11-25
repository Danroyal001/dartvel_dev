// The pixel's own script, in a real browser.
//
// Meta's fbevents.js sends a PageView of its own, with no event id, on every
// history.pushState: a single page application's route change. The module
// sends its own PageView for that route, with an event id its Conversions API
// twin shares, so with the pixel's automatic one also going out every route
// change would count twice. And fbevents.js drops any PageView after the
// first one of a page load unless told duplicates are allowed, so the
// module's own views of the second and later routes would never leave the
// browser at all. Both are switches on fbq that must be set before `init`.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_meta_pixel/src/browser.dart';
import 'package:test/test.dart';

/// Stands in for Meta's base code: defines an `fbq` that records each call
/// with the two switches as they were at the time.
const String fakeBaseCode = '''
window.__fbqCalls = [];
window.fbq = function() {
  window.__fbqCalls.push({
    args: Array.prototype.slice.call(arguments),
    disablePushState: window.fbq.disablePushState === true,
    allowDuplicatePageViews: window.fbq.allowDuplicatePageViews === true,
  });
};
''';

Future<List<JSObject>> callsWhenThere(int count) async {
  for (int attempt = 0; attempt < 200; attempt++) {
    final JSArray<JSObject>? calls =
        globalContext['__fbqCalls'] as JSArray<JSObject>?;
    if (calls != null && calls.length >= count) return calls.toDart;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('fbq was called fewer than $count times');
}

void main() {
  test('the automatic SPA PageView is off and duplicates are allowed '
      'before init', () async {
    final MetaPixelBrowser browser = createMetaPixelBrowser();
    browser.load('1234567890',
        scriptUrl:
            'data:text/javascript,${Uri.encodeComponent(fakeBaseCode)}');
    browser.track('PageView', const <String, Object?>{},
        eventId: 'id-1', custom: false);
    browser.track('PageView', const <String, Object?>{},
        eventId: 'id-2', custom: false);

    final List<JSObject> calls = await callsWhenThere(3);
    final JSObject init = calls.first;
    expect((init['args'] as JSArray<JSAny?>).toDart.first.dartify(), 'init');
    expect((init['disablePushState'] as JSBoolean).toDart, isTrue,
        reason: 'fbevents.js sends its own PageView, without an event id, on '
            'every pushState unless fbq.disablePushState is set before init');
    expect((init['allowDuplicatePageViews'] as JSBoolean).toDart, isTrue,
        reason: 'fbevents.js drops every PageView after the first of a page '
            'load unless fbq.allowDuplicatePageViews is set');

    // Each route's view goes out with its own id, the one its server twin
    // carries.
    final List<Object?> ids = <Object?>[
      for (final JSObject call in calls.skip(1))
        ((call['args'] as JSArray<JSAny?>).toDart[3].dartify()
            as Map<Object?, Object?>)['eventID'],
    ];
    expect(ids, <String>['id-1', 'id-2']);
  });
}
