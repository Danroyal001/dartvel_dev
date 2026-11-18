import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'attribution.dart';

/// `localStorage`: first-party, read synchronously as the page starts, and a
/// few hundred bytes is all the touches take.
DVAttributionStorage dvAttributionStorage() => _LocalStorage();

/// The address the page was loaded at, before the router changes it.
Uri? dvLandingAddress() {
  try {
    final JSObject? location = globalContext['location'] as JSObject?;
    final String? href = (location?['href'] as JSString?)?.toDart;
    return href == null ? null : Uri.tryParse(href);
  } on Object {
    return null;
  }
}

/// `document.referrer`: the page that linked here, or empty.
String? dvLandingReferrer() {
  try {
    final JSObject? document = globalContext['document'] as JSObject?;
    final String? referrer = (document?['referrer'] as JSString?)?.toDart;
    return referrer == null || referrer.isEmpty ? null : referrer;
  } on Object {
    return null;
  }
}

final class _LocalStorage implements DVAttributionStorage {
  JSObject? get _storage => globalContext['localStorage'] as JSObject?;

  @override
  String? read(String key) {
    final JSAny? value =
        _storage?.callMethod<JSAny?>('getItem'.toJS, key.toJS);
    return (value as JSString?)?.toDart;
  }

  @override
  void write(String key, String value) {
    _storage?.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
  }
}
