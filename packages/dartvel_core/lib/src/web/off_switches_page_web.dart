/// The browser half of the off switches: the meta tag the server wrote.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'off_switches.dart' show dvOffMetaName;

/// The `content` of the page's `dartvel-off` meta tag, or null without one.
String? dvOffSwitchesFromPage() {
  try {
    final JSObject? document = globalContext['document'] as JSObject?;
    final JSObject? tag = document?.callMethod<JSObject?>('querySelector'.toJS, 'meta[name="$dvOffMetaName"]'.toJS);
    return (tag?['content'] as JSString?)?.toDart;
  } on Object {
    return null;
  }
}
