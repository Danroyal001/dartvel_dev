/// The origins a browser client sends its credentials to on a request that
/// leaves its own origin.
///
/// A fetch carries cookies to the page's own origin and, unless it asks for
/// `credentials: 'include'`, to nowhere else. The session cookie lives on the
/// API's origin, so a web build served from one origin calling an API on
/// another was signed out on every call. Including credentials on every
/// request would fix that and hand the person's session to any third party a
/// call reaches, so they go only to origins named here, exactly.
///
/// The generated client names its own backend's origin. The server's half is
/// `dartvel.server.cors`: `allowCredentials: true` with the web build's
/// origins listed, never `origins: any`, which the build refuses. The
/// session cookie stays `SameSite=Lax`, so the API and the web build have to
/// be the same site -- app.example.com and api.example.com, not two domains.
library dartvel_core.http.credentialed_origins;

class DVCredentialedOrigins {
  const DVCredentialedOrigins._();

  static final Set<String> _origins = <String>{};

  /// The origins named so far, as scheme://host:port.
  static Set<String> get origins => Set<String>.unmodifiable(_origins);

  /// Sends credentials to [origin] -- `https://api.example.com` -- from now
  /// on.
  ///
  /// Throws [ArgumentError] for anything that is not one exact origin: a
  /// wildcard, `null`, a path or trailing slash, a query, user information,
  /// or plain `http` anywhere but the loopback, where a network attacker who
  /// can rewrite the page can also spend the session.
  static void allow(String origin) {
    _origins.add(_normalise(origin));
  }

  /// Names the origin of the generated client's backend, [baseUrl], and
  /// answers null -- or, when it cannot be named, why.
  ///
  /// A relative or empty URL is the page's own origin, where the browser
  /// sends the cookie unasked, so nothing is named. Only the origin is named:
  /// a path on the backend URL does not widen or narrow it.
  static String? allowBackend(String baseUrl) {
    final Uri? uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final String origin = '${uri.scheme}://${uri.authority}';
    try {
      allow(origin);
      return null;
    } on ArgumentError catch (error) {
      return 'The backend $origin is not sent credentials from a browser: '
          '${error.message}';
    }
  }

  /// Whether a request to [url] carries credentials.
  static bool includes(Uri url) {
    if (_origins.isEmpty) return false;
    if (url.scheme != 'https' && url.scheme != 'http') return false;
    if (url.host.isEmpty) return false;
    return _origins.contains(_key(url));
  }

  /// Forgets every origin. For a test.
  static void clear() => _origins.clear();

  static String _normalise(String origin) {
    Never refuse(String why) => throw ArgumentError.value(
        origin, 'origin', '$why Name one origin exactly, such as https://api.example.com.');
    final String text = origin.trim();
    if (text.isEmpty || text == '*' || text == 'null' || text == 'any') {
      refuse('Credentials are never sent to a wildcard or opaque origin.');
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
      refuse('It is not an origin.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      refuse('Only http and https origins carry credentials.');
    }
    if (uri.host.contains('*')) {
      refuse('A wildcard host would send the session to every subdomain.');
    }
    if (uri.path.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      refuse('An origin is scheme, host and port, with no path or trailing slash.');
    }
    if (uri.userInfo.isNotEmpty) refuse('An origin carries no user information.');
    if (uri.scheme == 'http' && !_loopback(uri.host)) {
      refuse('Plain http is refused outside the loopback.');
    }
    return _key(uri);
  }

  static bool _loopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '[::1]';

  static String _key(Uri uri) =>
      '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
}
