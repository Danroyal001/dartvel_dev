/// The application's own sessions as the authentication stage of a request.
///
/// `DVSessions` could issue, rotate and revoke a session and no served request
/// asked it, so a request carrying the application's session reached a route
/// policy with no caller: the server had no user to hand it, and only an API
/// key or OAuth token became a principal. The generated backend installs this
/// where it starts and asks it on every route, beside the platform API's
/// stage, so a signed-in person is a [DVSessionPrincipal] for the rest of the
/// request -- the caller a route policy is asked about and what an injected
/// `DVContext` carries.
///
/// What goes wrong here goes wrong silently, so each guard says where it is:
///
/// * only a bearer token shaped like a session (`dvs_`) and the session
///   cookie are this stage's to judge -- an API key, an OAuth token and any
///   other bearer token pass through to whoever owns them;
/// * a presented session that does not authenticate -- unknown, rotated away,
///   revoked, expired, issued on another tenant, or whose user is gone -- is
///   one 401 with no reason in it, on every route, because a revoked session
///   fails its next request rather than being read as an anonymous one;
/// * the user and the membership are read on every request rather than kept
///   from sign-in, so a role changed mid-session applies to the next request;
/// * nothing presented is ever logged or echoed.
library dartvel_core.auth.session_authentication;

import 'dart:async';

import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import 'organizations.dart';
import 'sessions.dart';

/// Who a request authenticated with the application's own session is.
///
/// Resolved at the authentication stage and current for the rest of the
/// request. A route policy written against the application's user type is
/// handed [user]; one written against this type is handed the principal.
class DVSessionPrincipal {
  DVSessionPrincipal({required this.session, this.user, this.membership});

  /// The session, as it was checked for this request.
  final DVSession session;

  /// What the application's `resolveUser` made of the session on this
  /// request, or null when it set none. Its server-safe user: a generated
  /// model reaches Flutter and cannot load in the server.
  final Object? user;

  /// The person's membership in the organization on the request's tenant,
  /// read on this request, or null when there is no such organization, they
  /// are not a member, or no organizations were configured.
  final DVMembership? membership;

  String get userId => session.userId;

  /// The tenant the session was issued on, which is the request's.
  String get tenant => session.tenant;

  /// Server-issued claims. There is no way for a client to write one.
  Map<String, Object?> get claims => session.claims;

  static const Symbol _zoneKey = #dartvelSessionPrincipal;

  /// The signed-in person the current request authenticated as, or null for
  /// a request that presented no session.
  ///
  /// A zone value rather than a field, for the reason `DVApiPrincipal.current`
  /// is one: a server hands the isolate between requests at every await.
  static DVSessionPrincipal? get current {
    final Object? principal = Zone.current[_zoneKey];
    return principal is DVSessionPrincipal ? principal : null;
  }

  /// Runs [body] with [principal] as [current].
  static Future<T> actingAs<T>(
    DVSessionPrincipal principal,
    Future<T> Function() body,
  ) =>
      runZoned(body, zoneValues: <Object?, Object?>{_zoneKey: principal});

  // The session id rather than the token, which is never written anywhere.
  @override
  String toString() =>
      'DVSessionPrincipal(${session.id}, user: $userId on $tenant)';
}

/// What the session stage made of a request.
class DVSessionAuthenticationResult {
  const DVSessionAuthenticationResult._({
    this.principal,
    this.status,
    this.message,
    this.challenge,
    this.clearCookie,
  });

  /// The request presented no session: it is someone else's to judge.
  static const DVSessionAuthenticationResult none =
      DVSessionAuthenticationResult._();

  const DVSessionAuthenticationResult.authenticated(
      DVSessionPrincipal principal)
      : this._(principal: principal);

  const DVSessionAuthenticationResult.refused(
    int status,
    String message, {
    String? challenge,
    String? clearCookie,
  }) : this._(
          status: status,
          message: message,
          challenge: challenge,
          clearCookie: clearCookie,
        );

  final DVSessionPrincipal? principal;

  /// The status to answer with, when the request is refused.
  final int? status;

  /// The fixed text of the refusal. Nothing from the request is in it.
  final String? message;

  /// The `WWW-Authenticate` value, for a 401.
  final String? challenge;

  /// A `Set-Cookie` value removing the session cookie, when the refused
  /// session came from it -- an `HttpOnly` cookie is one the page cannot
  /// clear, so without this a browser would present it, and be refused, on
  /// every request including the sign-in that would replace it.
  final String? clearCookie;

  bool get refused => status != null;
}

/// The session stage a backend process runs.
class DVSessionAuthentication {
  DVSessionAuthentication({
    DVSessions? sessions,
    this.resolveUser,
    this.organizations,
    this.cookie = const DVSessionCookie(),
    this.development = false,
  }) : _sessions = sessions ?? DVSessions();

  final DVSessions _sessions;

  /// The application's user for a live session, read on every request: its
  /// server-safe representation, which is what a policy written against the
  /// application's user type is handed. Null from it refuses the session --
  /// the person it belonged to no longer exists.
  final FutureOr<Object?> Function(DVSession session)? resolveUser;

  /// Where memberships are read from, when the application uses
  /// organizations.
  final FutureOr<DVOrganizations?> Function()? organizations;

  /// The cookie a browser carries the session in.
  final DVSessionCookie cookie;

  /// Whether the cookie is read under its development name. Outside
  /// development only the `__Host-` name is the session: a cookie under the
  /// bare name is one a sibling subdomain could have set.
  final bool development;

  static const String _challenge = 'Bearer error="invalid_token"';

  static DVSessionAuthentication? _installed;

  /// The session stage this process runs, or null before one is installed.
  static DVSessionAuthentication? get installed => _installed;

  /// Makes a session stage this process's. The generated `startBackend`
  /// installs one over the application's database unless the application
  /// installed its own first -- which is where it passes [resolveUser].
  static DVSessionAuthentication install({
    DVSessions? sessions,
    FutureOr<Object?> Function(DVSession session)? resolveUser,
    FutureOr<DVOrganizations?> Function()? organizations,
    DVSessionCookie cookie = const DVSessionCookie(),
    bool development = false,
  }) =>
      _installed = DVSessionAuthentication(
        sessions: sessions,
        resolveUser: resolveUser,
        organizations: organizations,
        cookie: cookie,
        development: development,
      );

  /// Takes the installed stage away, for a test.
  static void uninstall() => _installed = null;

  /// The sessions the installed stage checks: where a sign-in creates one,
  /// and a sign-out revokes it.
  static DVSessions get sessions {
    final DVSessionAuthentication? stage = _installed;
    if (stage == null) {
      throw StateError(
        'No session authentication is installed in this process. The '
        'generated startBackend installs one; install your own with '
        'DVSessionAuthentication.install before it starts to set resolveUser.',
      );
    }
    return stage._sessions;
  }

  /// The session token in an `Authorization` header, or null when it carries
  /// none -- which includes an API key, an OAuth token and the application's
  /// other bearer tokens.
  static String? credentialOf(String? authorization) {
    if (authorization == null) return null;
    final String value = authorization.trim();
    if (value.length < 7 || value.substring(0, 7).toLowerCase() != 'bearer ') {
      return null;
    }
    final String credential = value.substring(7).trim();
    return credential.startsWith(DVSessions.tokenPrefix) ? credential : null;
  }

  /// The stage for a request whose `Authorization` header is [authorization]
  /// and whose `Cookie` header is [cookie], on the current tenant.
  ///
  /// Without an installed stage a presented session is refused with 503
  /// rather than ignored: ignoring it would hand the route a request its
  /// caller believes is authenticated and nothing checked.
  static Future<DVSessionAuthenticationResult> authenticateRequest({
    String? authorization,
    String? cookie,
  }) async {
    final DVSessionAuthentication? stage = _installed;
    if (stage != null) {
      return stage.authenticate(authorization: authorization, cookie: cookie);
    }
    const DVSessionCookie defaults = DVSessionCookie();
    final bool presented = credentialOf(authorization) != null ||
        defaults.read(cookie, development: false) != null ||
        defaults.read(cookie, development: true) != null;
    return presented
        ? const DVSessionAuthenticationResult.refused(
            503, 'Service Unavailable')
        : DVSessionAuthenticationResult.none;
  }

  /// Resolves the session a request presents on [tenant], or the current
  /// tenant when none is given.
  Future<DVSessionAuthenticationResult> authenticate({
    String? authorization,
    String? cookie,
    String? tenant,
  }) async {
    final String? bearer = credentialOf(authorization);
    final String? carried =
        bearer == null ? this.cookie.read(cookie, development: development) : null;
    final String? token = bearer ?? carried;
    if (token == null) return DVSessionAuthenticationResult.none;
    final bool fromCookie = bearer == null;
    final String requested = tenant ?? const DVTenants().currentTenant;
    try {
      final DVSessionCheck check =
          await _sessions.check(token, tenant: requested);
      final DVSession? session = check.session;
      if (session == null) {
        if (check.code case final String code) {
          DVObservability.logger
              .info('$code: a revoked session was presented and refused.');
        }
        return _refused(fromCookie);
      }
      Object? user;
      final FutureOr<Object?> Function(DVSession)? resolve = resolveUser;
      if (resolve != null) {
        user = await resolve(session);
        if (user == null) return _refused(fromCookie);
      }
      DVMembership? membership;
      final DVOrganizations? orgs = await organizations?.call();
      if (orgs != null) {
        final DVOrganization? organization = await orgs.forTenant(requested);
        if (organization != null) {
          membership = await orgs.membership(organization.id, session.userId);
        }
      }
      return DVSessionAuthenticationResult.authenticated(DVSessionPrincipal(
        session: session,
        user: user,
        membership: membership,
      ));
    } on Object catch (error) {
      // The type only. A store's or a resolver's message can quote what it
      // was given.
      DVObservability.logger.error(
        'Session authentication failed (${error.runtimeType}); the request '
        'was refused.',
      );
      return const DVSessionAuthenticationResult.refused(
          503, 'Service Unavailable');
    }
  }

  DVSessionAuthenticationResult _refused(bool fromCookie) =>
      DVSessionAuthenticationResult.refused(
        401,
        'Unauthorized',
        challenge: _challenge,
        clearCookie:
            fromCookie ? cookie.clearHeader(development: development) : null,
      );
}
