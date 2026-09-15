/// The application's own sign-in, as HTTP endpoints the generated backend
/// serves: sign-up, sign-in, a second factor, sign-out, and the signed-in
/// person's sessions.
///
/// The server authenticated a session on every route and nothing it generated
/// ever issued one. What goes wrong here still answers 200, so each guard says
/// where it is:
///
/// * credentials go through [DVCredentialGuard] -- one refusal and one floor
///   of time whether or not the account exists, velocity limits per account
///   and per source, and the breach check at sign-up;
/// * a browser gets the session in an `HttpOnly` `__Host-` cookie and never
///   in the body, where a script could read it. Only a request carrying none
///   of the headers a browser sends and a script cannot suppress, and asking
///   for the token with [deliveryHeader], gets it in the body -- and then no
///   cookie;
/// * an account with a second factor gets a session that authenticates
///   nothing until the factor is presented, and the token it rotates to is the
///   first with the person's privilege;
/// * sign-in replaces a session the request already carried, and sign-out
///   revokes on the server, then clears the cookie;
/// * the sessions endpoints answer for the signed-in person's own sessions on
///   the request's tenant: another person's session is not found, and
///   revoking the others never revokes this one;
/// * nothing presented -- a password, a token, a code -- is logged or echoed,
///   and every answer is `no-store`.
library dartvel_core.auth.auth_endpoints;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../edge/bot_protection.dart';
import '../edge/credentials.dart';
import '../http/wintercg.dart';
import '../middleware/body_limit.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import 'auth.dart';
import 'second_factor.dart';
import 'session_authentication.dart';
import 'sessions.dart';

/// Handlers for the generated auth routes.
///
/// Each runs inside the request's tenant scope. [session], [sessions],
/// [revoke] and [revokeOthers] also run behind the authentication stage and
/// read [DVSessionPrincipal.current]; the others judge the session they are
/// given themselves, because a session waiting for its second factor -- which
/// the stage refuses -- is the one those endpoints exist to finish or end.
/// CSRF is the generated route's to check, as on every other POST.
class DVAuthEndpoints {
  const DVAuthEndpoints._();

  static const String signUpPath = '/auth/sign-up';
  static const String signInPath = '/auth/sign-in';
  static const String secondFactorPath = '/auth/second-factor';
  static const String signOutPath = '/auth/sign-out';
  static const String sessionPath = '/auth/session';
  static const String sessionsPath = '/auth/sessions';
  static const String revokePath = '/auth/sessions/revoke';
  static const String revokeOthersPath = '/auth/sessions/revoke-others';

  /// Every path these endpoints are served under, below the API base path.
  static const List<String> paths = <String>[
    signUpPath,
    signInPath,
    secondFactorPath,
    signOutPath,
    sessionPath,
    sessionsPath,
    revokePath,
    revokeOthersPath,
  ];

  /// Sent as `token` by a native client that keeps the session token itself.
  /// A browser never gets the token in a body, whatever this says.
  static const String deliveryHeader = 'x-dartvel-session-delivery';

  /// What the platform reports the device as, recorded on the session.
  static const String deviceHeader = 'x-dartvel-device';

  /// The most a body to these endpoints may be.
  static const int maxBodyBytes = 16 * 1024;

  /// Headers a browser attaches to a script's request and the script cannot
  /// remove: their presence means a page is asking.
  static const List<String> _browserHeaders = <String>[
    'origin',
    'sec-fetch-mode',
    'sec-fetch-site',
    'sec-fetch-dest',
  ];

  static DVCredentialGuard? _credentials;
  static DVSecondFactors? _secondFactors;
  static Duration _secondFactorWindow = const Duration(minutes: 10);

  /// Makes these endpoints sign people in through [credentials], with
  /// [secondFactors] when accounts may have one.
  ///
  /// [secondFactorWindow] is how long a session issued by a password alone
  /// may wait for its second factor before it is revoked.
  static void install({
    required DVCredentialGuard credentials,
    DVSecondFactors? secondFactors,
    Duration secondFactorWindow = const Duration(minutes: 10),
  }) {
    _credentials = credentials;
    _secondFactors = secondFactors;
    _secondFactorWindow = secondFactorWindow;
  }

  /// Takes the installed provider away, for a test.
  static void uninstall() {
    _credentials = null;
    _secondFactors = null;
    _secondFactorWindow = const Duration(minutes: 10);
  }

  /// Whether a provider is installed in this process.
  static bool get installed => _credentials != null;

  /// Whether [request] came from a page in a browser.
  static bool isBrowser(Request request) =>
      _browserHeaders.any(request.headers.has);

  /// Whether the session issued to [request] goes in the response body
  /// rather than a cookie: a client that asked, and is not a browser.
  static bool deliversToken(Request request) =>
      !isBrowser(request) &&
      request.headers.get(deliveryHeader)?.trim().toLowerCase() == 'token';

  /// Who a velocity limit counts [request] against: the client address the
  /// proxy in front of the server reports. The server layer does not expose
  /// the peer address, so a request that reaches it directly shares one
  /// source with every other such request.
  static String sourceOf(Request request) {
    final String? forwarded = request.headers.get('x-forwarded-for');
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final String? real = request.headers.get('x-real-ip');
    if (real != null && real.trim().isNotEmpty) return real.trim();
    return 'direct';
  }

  // --- credentials -----------------------------------------------------------

  /// `POST /auth/sign-up`: `email`, `password`, optionally `name` and a bot
  /// `challenge` token.
  static Future<Response> signUp(Request request) => _guard(() async {
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? email = body.string('email');
        final String? password = body.string('password');
        if (email == null || password == null) return _missingCredentials();
        final AuthUser? user;
        try {
          user = await guard.signUp(
            email,
            password,
            name: body.string('name'),
            source: sourceOf(request),
            challengeToken: body.string('challenge'),
          );
        } on Object catch (error) {
          return _credentialError(error);
        }
        if (user == null) return _credentialError(AuthException.invalidCredentials);
        return _issue(request, user);
      });

  /// `POST /auth/sign-in`: `email` and `password`.
  static Future<Response> signIn(Request request) => _guard(() async {
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? email = body.string('email');
        final String? password = body.string('password');
        if (email == null || password == null) return _missingCredentials();
        final AuthUser? user;
        try {
          user = await guard.signIn(email, password, source: sourceOf(request));
        } on Object catch (error) {
          return _credentialError(error);
        }
        if (user == null) return _credentialError(AuthException.invalidCredentials);
        return _issue(request, user);
      });

  /// `POST /auth/second-factor`: `code` from the account's authenticator, or
  /// one `recoveryCode`, presented with the session the sign-in issued.
  ///
  /// Also step-up for a live session: presenting a factor again records it
  /// again. Either way the session rotates.
  static Future<Response> secondFactor(Request request) => _guard(() async {
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        final DVSessionAuthentication stage = _stage();
        final _Presented? presented = _presented(request, stage);
        if (presented == null) return _unauthenticated();
        final DVSessions sessions = DVSessionAuthentication.sessions;
        final DVSessionCheck check = await sessions.check(
          presented.token,
          tenant: const DVTenants().currentTenant,
        );
        final DVSession? session = check.session;
        if (session == null) return _invalidSession(stage, presented);
        if (session.mfaPending &&
            DateTime.now().toUtc().difference(session.createdAt) >
                _secondFactorWindow) {
          await sessions.revoke(session.id);
          return _invalidSession(stage, presented);
        }
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? code = body.string('code');
        final String? recoveryCode = body.string('recoveryCode');
        if (code == null && recoveryCode == null) {
          return _error(400, 'invalid_request',
              'A code or a recovery code is required.');
        }
        // Counted against the account the session belongs to, so guessing
        // codes is limited however many sign-ins it is spread across.
        final String account = 'second-factor:${session.userId}';
        final String source = sourceOf(request);
        final DVVelocityRefusal? locked =
            await guard.velocity.check(account: account, source: source);
        if (locked != null) return _velocity(locked);
        final bool verified = code != null
            ? await factors.verifyTotp(session.userId, code)
            : await factors.redeemRecoveryCode(session.userId, recoveryCode!);
        if (!verified) {
          await guard.velocity.recordFailure(account: account, source: source);
          return _error(400, 'invalid_code', 'That code is not valid.');
        }
        await guard.velocity.recordSuccess(account: account);
        final DVIssuedSession completed =
            await sessions.completeMfa(presented.token);
        return _deliver(request, stage, completed, <String, Object?>{
          'mfaRequired': false,
        });
      });

  /// `POST /auth/sign-out`: revokes the session the request carries, on the
  /// server, and clears the cookie. Answers 204 whether or not there was a
  /// live session, so a client can always finish signing out.
  static Future<Response> signOut(Request request) => _guard(() async {
        final DVSessionAuthentication? stage = DVSessionAuthentication.installed;
        final DVSessionCookie cookie = stage?.cookie ?? const DVSessionCookie();
        final bool development = stage?.development ?? false;
        if (stage != null) {
          final _Presented? presented = _presented(request, stage);
          if (presented != null) {
            final DVSessions sessions = DVSessionAuthentication.sessions;
            final DVSession? session = (await sessions.check(
              presented.token,
              tenant: const DVTenants().currentTenant,
            ))
                .session;
            if (session != null) await sessions.revoke(session.id);
          }
        }
        return Response(
          204,
          headers: Headers(<String, Object?>{
            ..._noStore,
            'set-cookie': cookie.clearHeader(development: development),
          }),
        );
      });

  // --- the signed-in person's sessions ---------------------------------------

  /// `GET /auth/session`: the session this request authenticated with.
  static Future<Response> session(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        return _json(200, <String, Object?>{
          'session': <String, Object?>{
            ...principal.session.toJson(),
            'isCurrent': true,
          },
        });
      });

  /// `GET /auth/sessions`: every live session of the signed-in person on
  /// this tenant, newest sign-in first, with this one marked current.
  static Future<Response> sessions(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        return _json(200, <String, Object?>{
          'sessions': <Object?>[
            for (final DVSession s in await _own(principal))
              <String, Object?>{
                ...s.toJson(),
                'isCurrent': s.id == principal.session.id,
              },
          ],
        });
      });

  /// `POST /auth/sessions/revoke`: `id`, one of the signed-in person's own
  /// sessions. Anything else is 404, so a guessed id says nothing about
  /// whether it belongs to somebody.
  static Future<Response> revoke(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? id = body.string('id');
        if (id == null) {
          return _error(400, 'invalid_request', 'A session id is required.');
        }
        DVSession? target;
        for (final DVSession s in await _own(principal)) {
          if (s.id == id) target = s;
        }
        if (target == null) return _text(404, 'Not Found');
        await DVSessionAuthentication.sessions.revoke(target.id);
        final DVSessionAuthentication stage = _stage();
        return Response(
          204,
          headers: Headers(<String, Object?>{
            ..._noStore,
            // Revoking this session is signing this device out.
            if (target.id == principal.session.id)
              'set-cookie': stage.cookie.clearHeader(development: stage.development),
          }),
        );
      });

  /// `POST /auth/sessions/revoke-others`: every other live session of the
  /// signed-in person on this tenant. Answers how many.
  static Future<Response> revokeOthers(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        int revoked = 0;
        for (final DVSession s in await _own(principal)) {
          if (s.id == principal.session.id) continue;
          await DVSessionAuthentication.sessions.revoke(s.id);
          revoked++;
        }
        return _json(200, <String, Object?>{'revoked': revoked});
      });

  // --- issuing ---------------------------------------------------------------

  static Future<Response> _issue(Request request, AuthUser user) async {
    final DVSessionAuthentication stage = _stage();
    final DVSessions sessions = DVSessionAuthentication.sessions;
    final DVSecondFactors? factors = _secondFactors;
    final bool mfaRequired = factors != null && await factors.hasTotp(user.id);

    // A session this device already carried is replaced, not left live
    // beside the new one.
    final _Presented? presented = _presented(request, stage);
    if (presented != null) {
      final DVSession? previous = (await sessions.check(
        presented.token,
        tenant: const DVTenants().currentTenant,
      ))
          .session;
      if (previous != null) await sessions.revoke(previous.id);
    }

    final DVIssuedSession issued = await sessions.create(
      user.id,
      device: _device(request),
      claims: mfaRequired
          ? const <String, Object?>{DVSession.mfaPendingClaim: true}
          : const <String, Object?>{},
    );
    return _deliver(request, stage, issued, <String, Object?>{
      'user': <String, Object?>{
        'id': user.id,
        'email': user.email,
        if (user.name != null) 'name': user.name,
      },
      'mfaRequired': mfaRequired,
    });
  }

  static Response _deliver(
    Request request,
    DVSessionAuthentication stage,
    DVIssuedSession issued,
    Map<String, Object?> fields,
  ) {
    final bool inBody = deliversToken(request);
    return _json(
      200,
      <String, Object?>{
        ...fields,
        'session': issued.session.toJson(),
        if (inBody) 'token': issued.token,
      },
      headers: <String, String>{
        if (!inBody)
          'set-cookie':
              stage.cookie.header(issued.token, development: stage.development),
      },
    );
  }

  static Future<List<DVSession>> _own(DVSessionPrincipal principal) async => <DVSession>[
        for (final DVSession s
            in await DVSessionAuthentication.sessions.list(principal.userId))
          if (s.tenant == principal.tenant) s,
      ];

  static DVSessionAuthentication _stage() =>
      DVSessionAuthentication.installed ??
      (throw StateError('No session authentication is installed.'));

  static _Presented? _presented(Request request, DVSessionAuthentication stage) {
    final String? bearer =
        DVSessionAuthentication.credentialOf(request.headers.get('authorization'));
    if (bearer != null) return _Presented(bearer, fromCookie: false);
    final String? carried = stage.cookie
        .read(request.headers.get('cookie'), development: stage.development);
    return carried == null ? null : _Presented(carried, fromCookie: true);
  }

  static final RegExp _printable = RegExp(r'^[\x20-\x7E]{1,120}$');

  static String? _device(Request request) {
    final String? device = request.headers.get(deviceHeader)?.trim();
    return device != null && _printable.hasMatch(device) ? device : null;
  }

  // --- answers ---------------------------------------------------------------

  static const Map<String, Object?> _noStore = <String, Object?>{
    'cache-control': 'no-store',
    'pragma': 'no-cache',
  };

  /// Runs [body], answering 503 with nothing of the failure in it when it
  /// throws: a provider's or a store's message can quote what it was given.
  static Future<Response> _guard(Future<Response> Function() body) async {
    try {
      return await body();
    } on Object catch (error) {
      DVObservability.logger.error(
        'An auth endpoint failed (${error.runtimeType}); the request was '
        'refused.',
      );
      return _text(503, 'Service Unavailable');
    }
  }

  /// Fixed text for each refusal. A provider's own message is not sent: it
  /// may quote the address it was given, or word a missing account
  /// differently from a wrong password.
  static Response _credentialError(Object error) {
    if (error is DVVelocityRefusal) return _velocity(error);
    if (error is DVBreachedPasswordRefusal) {
      return _json(400, <String, Object?>{
        'error': 'breached_password',
        'code': error.code,
        'message': error.message,
      });
    }
    if (error is DVBotRefusal) {
      return _error(403, 'challenge_failed', error.message);
    }
    if (error is AuthException) {
      return switch (error.failure) {
        AuthFailure.accountExists => _error(409, 'account_exists',
            'An account already exists for that e-mail address.'),
        AuthFailure.weakPassword =>
          _error(400, 'weak_password', 'That password is too weak.'),
        AuthFailure.invalidEmail =>
          _error(400, 'invalid_email', 'That e-mail address is not valid.'),
        _ => _error(400, 'invalid_credentials',
            DVCredentialGuard.credentialsRefused.message),
      };
    }
    // The breach corpus could not be asked and the guard fails closed, or
    // anything else the provider threw.
    throw error;
  }

  static Response _velocity(DVVelocityRefusal refusal) =>
      _error(429, 'too_many_attempts', refusal.message);

  static Response _missingCredentials() => _error(
      400, 'invalid_request', 'An e-mail address and a password are required.');

  static Response _notConfigured() => _error(
        503,
        'auth_not_configured',
        'No auth provider is installed in this process. Install one with '
            'DVAuthEndpoints.install(credentials: DVCredentialGuard(provider: '
            '...)) before startBackend.',
      );

  static Response _unauthenticated() => Response(
        401,
        headers: Headers(<String, Object?>{
          'content-type': 'text/plain; charset=utf-8',
          'www-authenticate': 'Bearer',
          ..._noStore,
        }),
        body: Stream<List<int>>.value(utf8.encode('Unauthorized')),
      );

  static Response _invalidSession(
    DVSessionAuthentication stage,
    _Presented presented,
  ) =>
      Response(
        401,
        headers: Headers(<String, Object?>{
          'content-type': 'text/plain; charset=utf-8',
          'www-authenticate': 'Bearer error="invalid_token"',
          ..._noStore,
          if (presented.fromCookie)
            'set-cookie': stage.cookie.clearHeader(development: stage.development),
        }),
        body: Stream<List<int>>.value(utf8.encode('Unauthorized')),
      );

  static Response _error(int status, String error, String message) =>
      _json(status, <String, Object?>{'error': error, 'message': message});

  static Response _json(
    int status,
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  }) =>
      Response(
        status,
        headers: Headers(<String, Object?>{
          'content-type': 'application/json; charset=utf-8',
          ..._noStore,
          ...headers,
        }),
        body: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      );

  static Response _text(int status, String message) => Response(
        status,
        headers: Headers(<String, Object?>{
          'content-type': 'text/plain; charset=utf-8',
          ..._noStore,
        }),
        body: Stream<List<int>>.value(utf8.encode(message)),
      );

  /// A JSON object or a urlencoded form, capped at [maxBodyBytes].
  static Future<_Body> _body(Request request) async {
    if (dvDeclaredTooLarge(
      contentLength: request.headers.get('content-length'),
      limit: maxBodyBytes,
    )) {
      return _Body.refused(_text(413, dvTooLargeMessage(maxBodyBytes)));
    }
    final Uint8List? bytes = await dvReadCapped(request.body.stream, maxBodyBytes);
    if (bytes == null) {
      return _Body.refused(_text(413, dvTooLargeMessage(maxBodyBytes)));
    }
    final String raw = utf8.decode(bytes, allowMalformed: true);
    final String type = (request.headers.get('content-type') ?? '').toLowerCase();
    try {
      if (type.contains('application/x-www-form-urlencoded')) {
        return _Body(Uri.splitQueryString(raw));
      }
      if (raw.trim().isEmpty) return const _Body(<String, Object?>{});
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return _Body(Map<String, Object?>.from(decoded));
    } on FormatException {
      // Refused below, without quoting it.
    }
    return _Body.refused(
        _error(400, 'invalid_request', 'The body is not a JSON object or a form.'));
  }
}

class _Presented {
  const _Presented(this.token, {required this.fromCookie});

  final String token;
  final bool fromCookie;

  @override
  String toString() => '_Presented(fromCookie: $fromCookie)';
}

class _Body {
  const _Body(this.fields) : refused = null;

  const _Body.refused(Response this.refused) : fields = const <String, Object?>{};

  final Map<String, Object?> fields;
  final Response? refused;

  String? string(String name) {
    final Object? value = fields[name];
    return value is String && value.isNotEmpty ? value : null;
  }
}
