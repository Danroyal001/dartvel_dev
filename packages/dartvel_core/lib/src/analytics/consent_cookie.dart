/// One consent choice shared by every host of a site.
///
/// Each host of an application keeps consent in its own storage, and a
/// browser never shares that between origins: a visitor who accepted on
/// `example.com` is asked again on `tools.example.com`, and on each
/// `<tool>.tools.example.com` after it. With `dartvel.analytics.consent.domain`
/// set, the latest choice also travels in a first-party cookie for that
/// domain, which every host under it reads as it loads consent.
///
/// The cookie is a copy, never the evidence: a host that adopts it writes the
/// choice into its own consent records, under its own install, so the record
/// is where the data it allows is collected.
library dartvel_core.analytics.consent_cookie;

import 'dart:convert';

import 'consent.dart';
import 'consent_cookie_none.dart'
    if (dart.library.js_interop) 'consent_cookie_web.dart'
    as platform;

/// The browser's cookies as one host sees them. In a browser, `document.cookie`
/// and the page's own address; nowhere else is there one.
abstract interface class DVConsentCookieJar {
  /// The host the page was loaded from, such as `qr.tools.example.com`.
  String get host;

  /// Whether the page was loaded over https. A `Secure` cookie set from a
  /// plain http page is dropped by the browser without a word.
  bool get secure;

  String? read(String name);

  void write(
    String name,
    String value, {
    String? domain,
    required bool secure,
    required Duration maxAge,
    required String sameSite,
  });
}

/// The page's cookie jar in a browser, or null anywhere else.
DVConsentCookieJar? dvConsentCookieJar() => platform.dvConsentCookieJar();

/// A choice as the cookie carries it.
final class DVConsentSharedChoice {
  const DVConsentSharedChoice({
    required this.version,
    required this.answers,
    required this.recordedAt,
    required this.prompt,
  });

  final String version;
  final Map<String, bool> answers;
  final DateTime recordedAt;
  final DVConsentPrompt prompt;
}

/// The cookie's name, and its value written and read.
abstract final class DVConsentCookie {
  static const String name = 'dv_consent';

  /// How long a shared choice lasts: a year, as the stored answer is asked
  /// for again under a new policy version anyway.
  static const Duration maxAge = Duration(days: 365);

  static const String _format = 'v1';

  /// `v1.<base64url JSON>`: a cookie token, with no character a browser
  /// would quote or split on.
  static String encode({
    required String version,
    required Map<String, bool> answers,
    required DateTime recordedAt,
    required DVConsentPrompt prompt,
  }) =>
      '$_format.${base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{'v': version, 'a': answers, 't': recordedAt.toUtc().toIso8601String(), 'p': prompt.name}))).replaceAll('=', '')}';

  /// The choice in [value], or null for anything that is not one written by
  /// [encode]: a cookie is input from outside and is never trusted to parse.
  static DVConsentSharedChoice? decode(String? value) {
    if (value == null || !value.startsWith('$_format.')) return null;
    try {
      String body = value.substring(_format.length + 1);
      body = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      final Object? json = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (json is! Map) return null;
      final Object? version = json['v'];
      final Object? answers = json['a'];
      final Object? at = json['t'];
      final Object? prompt = json['p'];
      if (version is! String || answers is! Map || at is! String) return null;
      final Map<String, bool> read = <String, bool>{
        for (final MapEntry<Object?, Object?> e in answers.entries)
          if (e.key is String && e.value is bool)
            e.key! as String: e.value! as bool,
      };
      final DVConsentPrompt how =
          DVConsentPrompt.values
              .where((DVConsentPrompt p) => p.name == prompt)
              .firstOrNull ??
          DVConsentPrompt.banner;
      return DVConsentSharedChoice(
        version: version,
        answers: read,
        recordedAt: DateTime.parse(at).toUtc(),
        prompt: how,
      );
    } on Object {
      return null;
    }
  }

  /// The domain to set the cookie for from [host]: [domain] when the host is
  /// it or under it, and null (a host-only cookie) otherwise -- a browser
  /// refuses a cookie for a domain the page is not under.
  static String? domainFor(String host, String domain) {
    final String name = host.toLowerCase();
    return name == domain || name.endsWith('.$domain') ? domain : null;
  }
}
