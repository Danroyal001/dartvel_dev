import 'consent_cookie.dart';

/// Outside a browser there are no cookies to share a choice through.
DVConsentCookieJar? dvConsentCookieJar() => null;
