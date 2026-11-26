import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'consent_cookie.dart';

/// `document.cookie`, and the page's host and scheme.
DVConsentCookieJar? dvConsentCookieJar() {
  try {
    final JSObject? location = globalContext['location'] as JSObject?;
    final String? host = (location?['hostname'] as JSString?)?.toDart;
    final String? protocol = (location?['protocol'] as JSString?)?.toDart;
    if (host == null || host.isEmpty) return null;
    return _DocumentCookies(host, protocol == 'https:');
  } on Object {
    return null;
  }
}

final class _DocumentCookies implements DVConsentCookieJar {
  _DocumentCookies(this.host, this.secure);

  @override
  final String host;

  @override
  final bool secure;

  JSObject? get _document => globalContext['document'] as JSObject?;

  @override
  String? read(String name) {
    try {
      final String all = (_document?['cookie'] as JSString?)?.toDart ?? '';
      for (final String part in all.split(';')) {
        final String pair = part.trim();
        if (pair.startsWith('$name=')) return pair.substring(name.length + 1);
      }
    } on Object {
      // Cookies blocked: no shared choice.
    }
    return null;
  }

  @override
  void write(
    String name,
    String value, {
    String? domain,
    required bool secure,
    required Duration maxAge,
    required String sameSite,
  }) {
    final String cookie = <String>[
      '$name=$value',
      'Path=/',
      'Max-Age=${maxAge.inSeconds}',
      'SameSite=$sameSite',
      if (domain != null) 'Domain=$domain',
      if (secure) 'Secure',
    ].join('; ');
    try {
      _document?['cookie'] = cookie.toJS;
    } on Object {
      // Cookies blocked: the choice still stands on this host.
    }
  }
}
