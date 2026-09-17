/// Studio in development, for the person running the development server.
///
/// A deployment opens Studio to accounts granted `Studio.access`. `dartvel
/// dev` and `dartvel preview` have no accounts to speak of, and bind to
/// 0.0.0.0 so a phone on the network can reach the app -- which would hand
/// Studio, with the project's records and its page builder, to anybody on
/// the same network. So a development server makes a grant token and prints
/// a link carrying it, the way a notebook server does. Opening the link sets
/// a cookie scoped to the mount, and the mount serves only a browser that
/// holds it.
library;

import 'dart:math';

import '../http/wintercg.dart';
import 'admin_server.dart' show DVAdminMount;

/// The development grant for one run of a development server.
class DVStudioDevGrant {
  const DVStudioDevGrant(this.token);

  /// A new grant with a random 32-character token.
  factory DVStudioDevGrant.generate() {
    final Random random = Random.secure();
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return DVStudioDevGrant(String.fromCharCodes(<int>[
      for (int i = 0; i < 32; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]));
  }

  /// The grant `dartvel dev` handed its backend in [environmentVariable], or
  /// null when it handed none. A backend restarted on a change keeps the
  /// grant, so the link printed once goes on working.
  static DVStudioDevGrant? fromEnvironment(Map<String, String> environment) {
    final String? token = environment[environmentVariable];
    return token == null || token.length < 16 ? null : DVStudioDevGrant(token);
  }

  /// Where a development server hands its grant to the backend it starts.
  static const String environmentVariable = 'DARTVEL_STUDIO_DEV_GRANT';

  /// The query parameter the printed link carries the token in.
  static const String queryParameter = 'dev_grant';

  /// The cookie a browser holds the grant in.
  static const String cookieName = 'dartvel_studio_dev';

  final String token;

  /// The link to print: Studio at [mount] on [origin], carrying the token.
  String link(String origin, DVAdminMount mount) =>
      '$origin${mount.path}/?$queryParameter=$token';

  /// The redirect that sets the cookie, for a request carrying the token in
  /// its address; null for any other request.
  ///
  /// Redirected rather than served, so the token leaves the address bar and
  /// the browser history, and a Referer never carries it anywhere.
  Response? claim(Request request, DVAdminMount mount) {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    if (!mount.owns(path)) return null;
    final String? offered = request.url.queryParameters[queryParameter];
    if (offered == null || !_same(offered, token)) return null;
    return Response(
      303,
      headers: Headers(<String, String>{
        'location': '${mount.path}/',
        'set-cookie': '$cookieName=$token; Path=${mount.path}; HttpOnly; '
            'SameSite=Strict',
        'cache-control': 'no-store',
      }),
    );
  }

  /// Whether [request] comes from the browser the link was opened in.
  Future<bool> check(Request request) async {
    final String? cookies = request.headers.get('cookie');
    if (cookies == null) return false;
    for (final String part in cookies.split(';')) {
      final int eq = part.indexOf('=');
      if (eq < 0) continue;
      if (part.substring(0, eq).trim() != cookieName) continue;
      if (_same(part.substring(eq + 1).trim(), token)) return true;
    }
    return false;
  }

  /// Compared in time that does not depend on where the strings differ.
  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
