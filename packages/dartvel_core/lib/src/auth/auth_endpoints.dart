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

import '../../dartvel.dart'
    show DVMailAddress, DVMailMessage, DVNotificationMail, DVNotificationsService;
import '../analytics/analytics_runtime.dart' show DVPrivacyRuntime;
import '../edge/bot_protection.dart';
import '../edge/credentials.dart';
import '../http/client_address.dart';
import '../http/wintercg.dart';
import '../middleware/body_limit.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart' show DVErasureResult, DVPrivacy;
import '../tenancy/tenants.dart';
import 'account_mail.dart';
import 'api_scopes.dart' show DVApiPrincipal;
import 'auth.dart';
import 'second_factor.dart';
import 'session_authentication.dart';
import 'sessions.dart';
import 'tokens.dart'
    show DVAuthTokenFailure, DVAuthTokenRecord, DVAuthTokenResult, DVAuthTokens;

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
  static const String factorsPath = '/auth/factors';
  static const String totpPath = '/auth/factors/totp';
  static const String totpConfirmPath = '/auth/factors/totp/confirm';
  static const String recoveryCodesPath = '/auth/factors/recovery-codes';
  static const String removeFactorPath = '/auth/factors/remove';
  static const String accountPath = '/auth/account';
  static const String emailChangePath = '/auth/account/email';
  static const String emailVerifyPath = '/auth/account/email/verify';
  static const String deleteAccountPath = '/auth/account/delete';

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
    factorsPath,
    totpPath,
    totpConfirmPath,
    recoveryCodesPath,
    removeFactorPath,
    accountPath,
    emailChangePath,
    emailVerifyPath,
    deleteAccountPath,
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
  static Duration _stepUpWindow = const Duration(minutes: 10);
  static Future<void> Function(String email, String code)? _sendEmailVerification;
  static DVPrivacy? _privacy;
  static DVEmailVerificationMail? _emailVerificationMail;
  static DVEmailVerificationMail? _generatedEmailVerificationMail;
  static DVAuthTokens _verificationTokens =
      DVAuthTokens(lifetime: const Duration(minutes: 30));

  /// Makes these endpoints sign people in through [credentials], with
  /// [secondFactors] when accounts may have one.
  ///
  /// [secondFactorWindow] is how long a session issued by a password alone
  /// may wait for its second factor before it is revoked. [stepUpWindow] is
  /// how recently a second factor must have been presented for a session to
  /// generate recovery codes -- what a stolen session would do first, to
  /// keep the account after the session is revoked.
  ///
  /// [sendEmailVerification] delivers the code that proves a new address
  /// receives mail. Without it the code goes through `DV.Notifications.mail`
  /// from `DV.Notifications.useMailSender`, as [emailVerificationMail] builds
  /// it -- or the template the generated server installs -- and an address
  /// change is refused, naming what to configure, while mail has nowhere to
  /// go. [privacy] is the project's Data Compliance erasure, which deleting
  /// an account runs before the account is removed; without it the
  /// `DV.Privacy` the generated server configures from `DARTVEL_PRIVACY_KEY`
  /// runs, and deletion is refused while neither exists.
  /// [verificationTokens] keeps the codes, hashed.
  static void install({
    required DVCredentialGuard credentials,
    DVSecondFactors? secondFactors,
    Duration secondFactorWindow = const Duration(minutes: 10),
    Duration stepUpWindow = const Duration(minutes: 10),
    Future<void> Function(String email, String code)? sendEmailVerification,
    DVPrivacy? privacy,
    DVAuthTokens? verificationTokens,
    DVEmailVerificationMail? emailVerificationMail,
  }) {
    _credentials = credentials;
    _secondFactors = secondFactors;
    _secondFactorWindow = secondFactorWindow;
    _stepUpWindow = stepUpWindow;
    _sendEmailVerification = sendEmailVerification;
    _privacy = privacy;
    _emailVerificationMail = emailVerificationMail;
    _verificationTokens =
        verificationTokens ?? DVAuthTokens(lifetime: const Duration(minutes: 30));
  }

  /// Takes the installed provider away, for a test.
  static void uninstall() {
    _credentials = null;
    _secondFactors = null;
    _secondFactorWindow = const Duration(minutes: 10);
    _stepUpWindow = const Duration(minutes: 10);
    _sendEmailVerification = null;
    _privacy = null;
    _emailVerificationMail = null;
    _generatedEmailVerificationMail = null;
    _verificationTokens = DVAuthTokens(lifetime: const Duration(minutes: 30));
  }

  /// The verification mail the generated server builds from the project --
  /// its name in the subject. Called by the generated server; an
  /// `emailVerificationMail` passed to [install] wins over it, and it
  /// survives [install] because the application installs its provider
  /// without knowing the server did this.
  static void useGeneratedEmailVerificationMail(DVEmailVerificationMail template) {
    _generatedEmailVerificationMail = template;
  }

  /// The mail a verification code goes out in when nothing more specific is
  /// installed.
  static DVMailMessage defaultEmailVerificationMail(DVEmailVerification v) =>
      DVMailMessage(
        from: v.from,
        to: <DVMailAddress>[DVMailAddress(v.to)],
        subject: 'Confirm your new e-mail address',
        text: 'Enter this code to confirm this address for your account:\n\n'
            '${v.code}\n\n'
            'It works once, for ${v.validFor.inMinutes} minutes. If you did not '
            'ask to change your address, ignore this message: nothing changes '
            'until the code is entered.',
      );

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

  /// Who a velocity limit counts [request] against: its client address, as
  /// [DVClientAddress] resolves it -- the connection's peer, or the client a
  /// trusted proxy reports.
  ///
  /// This read the first `X-Forwarded-For` entry, which the client writes: a
  /// new one per attempt escaped the per-source limit, and every request
  /// sending none shared one source.
  static String sourceOf(Request request) => DVClientAddress.sourceOf(request);

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

  // --- the signed-in person's second factors ---------------------------------

  /// `GET /auth/factors`: whether the signed-in person has an authenticator
  /// and how many unspent recovery codes. A count, never a code.
  static Future<Response> factors(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        return _json(200, await _factorStatus(factors, principal.userId));
      });

  /// `POST /auth/factors/totp`: starts enrolling an authenticator app and
  /// answers its secret and the `otpauth://` URI a QR code encodes.
  ///
  /// Nothing is active afterwards. Sign-in asks for no code until
  /// [confirmTotp] proves the app holds the secret, so an enrollment
  /// abandoned half way does not lock the account behind an app nobody set
  /// up. Refused while an authenticator is active: replacing one is removing
  /// it, which needs a second factor.
  static Future<Response> beginTotp(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        if (await factors.hasTotp(principal.userId)) return _factorExists();
        final DVTotpEnrollment enrollment = await factors.beginTotp(
          principal.userId,
          account: await _accountName(principal),
        );
        return _json(200, <String, Object?>{
          'secret': enrollment.secret,
          'uri': enrollment.uri.toString(),
        });
      });

  /// `POST /auth/factors/totp/confirm`: `code` from the app being enrolled.
  /// Activates the authenticator and rotates the session with the factor
  /// recorded, since the code just proved it.
  static Future<Response> confirmTotp(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? code = body.string('code');
        if (code == null) {
          return _error(400, 'invalid_request', 'A code is required.');
        }
        final Response? failed = await _presentFactor(
          guard,
          request,
          principal.userId,
          () => factors.confirmTotp(principal.userId, code),
        );
        if (failed != null) return failed;
        final _Rotated? rotated =
            await _rotate(request, factorPresented: true);
        if (rotated == null) return _unauthenticated();
        return _deliver(request, rotated.stage, rotated.issued, <String, Object?>{
          'factors': await _factorStatus(factors, principal.userId),
        }, bearer: rotated.bearer);
      });

  /// `POST /auth/factors/recovery-codes`: a new set of recovery codes,
  /// replacing every earlier one, answered this once. Stored only as salted
  /// HMACs, so no endpoint can show them again.
  ///
  /// Needs an active authenticator -- a recovery code recovers a second
  /// factor -- and one presented within the step-up window: a stolen session
  /// that could print itself recovery codes would keep the account after the
  /// session was revoked.
  static Future<Response> recoveryCodes(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        if (!await factors.hasTotp(principal.userId)) return _noSecondFactor();
        final DVMfa fresh = DVMfa.recent(_stepUpWindow);
        if (!fresh.isSatisfiedBy(principal.session, DateTime.now().toUtc())) {
          return stepUpRequired(fresh);
        }
        // Rotated first: a rotation that failed after the codes were replaced
        // would have spent the old set and delivered nothing.
        final _Rotated? rotated =
            await _rotate(request, factorPresented: false);
        if (rotated == null) return _unauthenticated();
        final DVRecoveryCodes codes =
            await factors.regenerateRecoveryCodes(principal.userId);
        return _deliver(request, rotated.stage, rotated.issued, <String, Object?>{
          'recoveryCodes': codes.codes,
          'generatedAt': codes.generatedAt.toUtc().toIso8601String(),
        }, bearer: rotated.bearer);
      });

  /// `POST /auth/factors/remove`: `code` from the authenticator, or one
  /// `recoveryCode`, presented in this request. Removes the authenticator
  /// and every recovery code, and rotates the session.
  ///
  /// A recent factor on the session is not enough: removing the second
  /// factor is the one change that makes a stolen password sufficient again,
  /// so it takes the factor itself.
  static Future<Response> removeFactor(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final DVSecondFactors? factors = _secondFactors;
        if (factors == null) return _text(404, 'Not Found');
        if (!await factors.hasTotp(principal.userId)) return _noSecondFactor();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? code = body.string('code');
        final String? recoveryCode = body.string('recoveryCode');
        if (code == null && recoveryCode == null) {
          return _error(400, 'invalid_request',
              'A code from the authenticator or a recovery code is required.');
        }
        final Response? failed = await _presentFactor(
          guard,
          request,
          principal.userId,
          () => code != null
              ? factors.verifyTotp(principal.userId, code)
              : factors.redeemRecoveryCode(principal.userId, recoveryCode!),
        );
        if (failed != null) return failed;
        await factors.removeTotp(principal.userId);
        await factors.removeRecoveryCodes(principal.userId);
        final _Rotated? rotated =
            await _rotate(request, factorPresented: true);
        if (rotated == null) return _unauthenticated();
        return _deliver(request, rotated.stage, rotated.issued, <String, Object?>{
          'factors': await _factorStatus(factors, principal.userId),
        }, bearer: rotated.bearer);
      });

  /// The gate a generated route declaring `mfa:` runs: null when the request's
  /// session meets [policy], otherwise the refusal to answer with.
  ///
  /// Nobody signed in is a plain 401 -- signing in comes first. A caller
  /// authenticated with an API key or an OAuth token is 403: it has no second
  /// factor to present, and a step-up challenge would send it looking for
  /// one. A session without the factor, or with one older than the policy's
  /// window, is [stepUpRequired]. A session still waiting for its second
  /// factor never gets here: the authentication stage refused it.
  static Response? requireMfa(DVMfa policy) {
    final DVSessionPrincipal? principal = DVSessionPrincipal.current;
    if (principal == null) {
      if (DVApiPrincipal.current != null) {
        return _error(403, 'mfa_unavailable',
            'This needs a signed-in person\'s second factor.');
      }
      return _unauthenticated();
    }
    if (policy.isSatisfiedBy(principal.session, DateTime.now().toUtc())) {
      return null;
    }
    return stepUpRequired(policy);
  }

  /// The refusal for a session whose second factor is missing or older than
  /// [policy] allows (`DV-SESSION-001`): RFC 9470's
  /// `insufficient_user_authentication`, with `max_age` when the policy has a
  /// window, so a client asks for a code rather than for a sign-in.
  static Response stepUpRequired(DVMfa policy) {
    final Duration? within = policy.within;
    DVObservability.logger
        .info('DV-SESSION-001: a second factor is required and was not recent.');
    return _json(
      401,
      <String, Object?>{
        'error': 'mfa_required',
        'code': 'DV-SESSION-001',
        'message': 'A second factor is required.',
        if (within != null) 'maxAge': within.inSeconds,
      },
      headers: <String, String>{
        'www-authenticate': within == null
            ? DVSessionAuthentication.mfaChallenge
            : '${DVSessionAuthentication.mfaChallenge}, '
                'max_age=${within.inSeconds}',
      },
    );
  }

  static Future<Map<String, Object?>> _factorStatus(
    DVSecondFactors factors,
    String userId,
  ) async =>
      <String, Object?>{
        'totp': await factors.hasTotp(userId),
        'recoveryCodes': await factors.remainingRecoveryCodes(userId),
      };

  /// What an authenticator app lists the account under: the address, when
  /// the application's user or its provider can say what it is.
  static Future<String> _accountName(DVSessionPrincipal principal) async {
    final Object? user = principal.user;
    if (user is AuthUser) return user.email;
    final Object? provider = _credentials?.provider;
    if (provider is DVAccountDirectory) {
      final AuthUser? found = await provider.userById(principal.userId);
      if (found != null) return found.email;
    }
    return principal.userId;
  }

  /// Checks a presented factor against the account's velocity limit, the
  /// one guessing codes at sign-in counts against. Null when it verified.
  static Future<Response?> _presentFactor(
    DVCredentialGuard guard,
    Request request,
    String userId,
    Future<bool> Function() verify,
  ) async {
    final String account = 'second-factor:$userId';
    final String source = sourceOf(request);
    final DVVelocityRefusal? locked =
        await guard.velocity.check(account: account, source: source);
    if (locked != null) return _velocity(locked);
    if (!await verify()) {
      await guard.velocity.recordFailure(account: account, source: source);
      return _error(400, 'invalid_code', 'That code is not valid.');
    }
    await guard.velocity.recordSuccess(account: account);
    return null;
  }

  /// Rotates the session [request] presented, recording a second factor
  /// when [factorPresented]. Null when it no longer names a live session.
  static Future<_Rotated?> _rotate(
    Request request, {
    required bool factorPresented,
  }) async {
    final DVSessionAuthentication stage = _stage();
    final _Presented? presented = _presented(request, stage);
    if (presented == null) return null;
    final DVSessions sessions = DVSessionAuthentication.sessions;
    final DVIssuedSession issued = factorPresented
        ? await sessions.completeMfa(presented.token)
        : await sessions.rotate(presented.token);
    return _Rotated(stage, issued, bearer: !presented.fromCookie);
  }

  static Response _factorExists() => _error(409, 'factor_exists',
      'This account already has an authenticator. Remove it first.');

  static Response _noSecondFactor() => _error(
      409, 'no_second_factor', 'This account has no second factor.');

  // --- the signed-in person's account ----------------------------------------

  /// `GET /auth/account`: the signed-in person's account, with an address
  /// change still waiting for its code.
  static Future<Response> account(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        return _json(200, <String, Object?>{
          'account': await _accountJson(principal),
        });
      });

  /// `POST /auth/account/email`: `email`, the address the account should
  /// move to. Sends a code to that address and changes nothing.
  ///
  /// The answer is the same whether or not another account has the address:
  /// the session holder learns that only by proving they receive its mail.
  /// Requests count against the account's and the source's velocity limits,
  /// so this is not a way to mail codes to strangers.
  static Future<Response> requestEmailChange(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final Object? provider = guard.provider;
        if (provider is! DVAccountProvider) return _accountChangesNotConfigured();
        // Before anything is minted or recorded: a change that answered 202
        // with no mail able to leave would show the person a pending address
        // and a code that never arrives.
        final Object sender = _verificationSender();
        if (sender is Response) return sender;
        final Future<void> Function(String, String) send =
            sender as Future<void> Function(String, String);
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? email = body.string('email')?.trim().toLowerCase();
        if (email == null || !_address.hasMatch(email)) {
          return _error(400, 'invalid_email', 'That e-mail address is not valid.');
        }
        final String userId = principal.userId;
        final AuthUser? user = await provider.userById(userId);
        if (user == null) return _unauthenticated();
        if (user.email.toLowerCase() == email) {
          return _error(
              400, 'invalid_request', 'That is already the account\'s address.');
        }
        final String account = _emailChangeKey(userId);
        final String source = sourceOf(request);
        final DVVelocityRefusal? locked =
            await guard.velocity.check(account: account, source: source);
        if (locked != null) return _velocity(locked);
        await guard.velocity.recordFailure(account: account, source: source);
        final String code = await _verificationTokens.issueOtp(account);
        await _verificationTokens.store.put(
          _emailTargetKey(userId),
          DVAuthTokenRecord(
            identifier: email,
            hash: '',
            expiresAt: DateTime.now().add(_verificationTokens.lifetime),
          ),
        );
        try {
          await send(email, code);
        } on Object {
          // Nothing went out, so nothing is pending: the code is unusable
          // without its target, and the account does not show an address the
          // person was never sent anything at.
          await _verificationTokens.store.delete(_emailTargetKey(userId));
          rethrow;
        }
        return _json(202, <String, Object?>{'pendingEmail': email});
      });

  /// How a verification code is delivered: the installed
  /// `sendEmailVerification`, or `DV.Notifications.mail` from its configured
  /// sender. A [Response] refusing the change when neither can send.
  static Object _verificationSender() {
    final Future<void> Function(String, String)? installed = _sendEmailVerification;
    if (installed != null) return installed;
    if (!const DVNotificationMail().isConfigured) {
      return _mailNotConfigured(
          'no mail provider is registered. Register one with '
          'DV.Notifications.mail.useProvider(...)');
    }
    final DVMailAddress? from = const DVNotificationsService().mailSender;
    if (from == null) {
      return _mailNotConfigured(
          'no sender is configured. Call DV.Notifications.useMailSender(...) '
          'with an address the application is authorised to send from');
    }
    final DVEmailVerificationMail template = _emailVerificationMail ??
        _generatedEmailVerificationMail ??
        defaultEmailVerificationMail;
    return (String email, String code) => const DVNotificationMail().send(
          template(DVEmailVerification(
            from: from,
            to: email,
            code: code,
            validFor: _verificationTokens.lifetime,
          )),
        );
  }

  static Response _mailNotConfigured(String why) => _error(
        503,
        'mail_not_configured',
        'Changing an address sends a code to the new address through '
            'DV.Notifications.mail, and $why, or pass sendEmailVerification to '
            'DVAuthEndpoints.install. Nothing was changed.',
      );

  /// `POST /auth/account/email/verify`: `code`, as the new address received
  /// it. The address changes now, and the session rotates.
  static Future<Response> verifyEmailChange(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final Object? provider = guard.provider;
        if (provider is! DVAccountProvider) return _accountChangesNotConfigured();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final String? code = body.string('code');
        if (code == null) {
          return _error(400, 'invalid_request', 'A code is required.');
        }
        final String userId = principal.userId;
        final String? target = await _pendingEmail(userId);
        if (target == null) return _invalidCode();
        final DVAuthTokenResult result =
            await _verificationTokens.redeemOtp(_emailChangeKey(userId), code.trim());
        if (!result.isSuccess) {
          return result.failure == DVAuthTokenFailure.throttled
              ? _error(429, 'too_many_attempts', 'Too many attempts. Request a new code.')
              : _invalidCode();
        }
        await _verificationTokens.store.delete(_emailTargetKey(userId));
        try {
          await provider.changeEmail(userId, target);
        } on AuthException catch (error) {
          return switch (error.failure) {
            AuthFailure.accountExists => _error(409, 'account_exists',
                'An account already exists for that e-mail address.'),
            AuthFailure.invalidEmail =>
              _error(400, 'invalid_email', 'That e-mail address is not valid.'),
            _ => throw error,
          };
        }
        final _Rotated? rotated =
            await _rotate(request, factorPresented: false);
        if (rotated == null) return _unauthenticated();
        return _deliver(request, rotated.stage, rotated.issued, <String, Object?>{
          'account': await _accountJson(principal),
        }, bearer: rotated.bearer);
      });

  /// `POST /auth/account/delete`: `confirm: true`, the account's `password`,
  /// and a `code` or `recoveryCode` when it has a second factor.
  ///
  /// Not a row deletion: the project's Data Compliance erasure runs first
  /// where one is installed, and a failure there answers 503 with the account
  /// intact so it can be tried again. Then the second factors, the account and
  /// every session go, and the cookie is cleared.
  static Future<Response> deleteAccount(Request request) => _guard(() async {
        final DVSessionPrincipal? principal = DVSessionPrincipal.current;
        if (principal == null) return _unauthenticated();
        final DVCredentialGuard? guard = _credentials;
        if (guard == null) return _notConfigured();
        final Object? provider = guard.provider;
        if (provider is! DVAccountProvider) return _accountChangesNotConfigured();
        // Checked before the password or a code is spent. Deleting the
        // account without the erasure removes the row a person signs in with
        // and keeps everything else about them -- the deletion Data Compliance
        // says an account deletion must not be -- and answers as if it worked.
        final DVPrivacy? privacy = _privacy ??
            (DVPrivacyRuntime.isConfigured ? DVPrivacyRuntime.current : null);
        if (privacy == null) return _erasureNotConfigured();
        final _Body body = await _body(request);
        final Response? refused = body.refused;
        if (refused != null) return refused;
        final Object? confirm = body.fields['confirm'];
        if (confirm != true && confirm != 'true') {
          return _error(400, 'confirmation_required',
              'Deleting an account needs explicit confirmation.');
        }
        final String? password = body.string('password');
        if (password == null) {
          return _error(
              400, 'invalid_request', 'The account\'s password is required.');
        }
        final String userId = principal.userId;
        final AuthUser? user = await provider.userById(userId);
        if (user == null) return _unauthenticated();
        // Re-authentication through the guard, so a wrong password here counts
        // against the account exactly as one at sign-in does.
        try {
          final AuthUser? again = await guard.signIn(user.email, password,
              source: sourceOf(request));
          if (again == null || again.id != userId) {
            return _credentialError(AuthException.invalidCredentials);
          }
        } on Object catch (error) {
          return _credentialError(error);
        }
        final DVSecondFactors? factors = _secondFactors;
        if (factors != null && await factors.hasTotp(userId)) {
          final String? code = body.string('code');
          final String? recoveryCode = body.string('recoveryCode');
          if (code == null && recoveryCode == null) {
            return stepUpRequired(DVMfa.required);
          }
          final Response? failed = await _presentFactor(
            guard,
            request,
            userId,
            () => code != null
                ? factors.verifyTotp(userId, code)
                : factors.redeemRecoveryCode(userId, recoveryCode!),
          );
          if (failed != null) return failed;
        }
        final DVErasureResult erasure = await privacy.erase(
          subject: userId,
          reason: 'The account holder deleted their account.',
          requestedBy: userId,
          runBy: 'DVAuthEndpoints.deleteAccount',
        );
        if (!erasure.complete) {
          // DV-PRIVACY-009: the person's data is still wherever the walk could
          // not reach. The account stays, so the deletion can be asked for
          // again and the walk -- which is repeatable -- finishes the job.
          return _json(503, <String, Object?>{
            'error': 'erasure_incomplete',
            'message': 'The account was not deleted: the erasure could not '
                'reach ${erasure.unreached.join(', ')}. Try again later.',
            'unreached': erasure.unreached,
          });
        }
        if (factors != null) {
          await factors.removeTotp(userId);
          await factors.removeRecoveryCodes(userId);
        }
        await _verificationTokens.store.delete(_emailTargetKey(userId));
        await provider.deleteAccount(userId);
        final DVSessions sessions = DVSessionAuthentication.sessions;
        for (final DVSession session in await sessions.list(userId)) {
          await sessions.revoke(session.id);
        }
        final DVSessionAuthentication stage = _stage();
        return _json(
          200,
          <String, Object?>{
            'deleted': true,
            'erasure': <String, Object?>{
              'complete': erasure.complete,
              'unreached': erasure.unreached,
              'codes': erasure.codes,
            },
          },
          headers: <String, String>{
            'set-cookie': stage.cookie.clearHeader(development: stage.development),
          },
        );
      });

  static Future<Map<String, Object?>> _accountJson(
      DVSessionPrincipal principal) async {
    AuthUser? user;
    final Object? provider = _credentials?.provider;
    if (provider is DVAccountDirectory) {
      user = await provider.userById(principal.userId);
    }
    final Object? resolved = principal.user;
    if (user == null && resolved is AuthUser) user = resolved;
    final String? pending = await _pendingEmail(principal.userId);
    return <String, Object?>{
      'id': principal.userId,
      if (user != null) 'email': user.email,
      if (user?.name != null) 'name': user!.name,
      if (pending != null) 'pendingEmail': pending,
    };
  }

  /// The address an account is moving to, while its code is still good.
  static Future<String?> _pendingEmail(String userId) async {
    final DVAuthTokenRecord? record =
        await _verificationTokens.store.get(_emailTargetKey(userId));
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      await _verificationTokens.store.delete(_emailTargetKey(userId));
      return null;
    }
    return record.identifier;
  }

  static String _emailChangeKey(String userId) => 'email-change:$userId';

  static String _emailTargetKey(String userId) => 'email-change-target:$userId';

  static final RegExp _address = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static Response _invalidCode() =>
      _error(400, 'invalid_code', 'That code is not valid.');

  static Response _accountChangesNotConfigured() => _error(
        503,
        'account_changes_not_configured',
        'Changing or deleting an account needs a provider that is a '
            'DVAccountProvider, passed to DVAuthEndpoints.install.',
      );

  static Response _erasureNotConfigured() => _error(
        503,
        'erasure_not_configured',
        'The account was not deleted. Deleting an account runs the Data '
            'Compliance erasure, and DV.Privacy is not configured in this '
            'process: set DARTVEL_PRIVACY_KEY in the server environment, or '
            'pass privacy to DVAuthEndpoints.install.',
      );

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

  /// [bearer] is whether the session being replaced was presented as a
  /// bearer token by something other than a browser: that client holds the
  /// token itself, and a rotated one in a cookie would sign it out.
  static Response _deliver(
    Request request,
    DVSessionAuthentication stage,
    DVIssuedSession issued,
    Map<String, Object?> fields, {
    bool bearer = false,
  }) {
    final bool inBody =
        deliversToken(request) || (bearer && !isBrowser(request));
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

class _Rotated {
  const _Rotated(this.stage, this.issued, {required this.bearer});

  final DVSessionAuthentication stage;
  final DVIssuedSession issued;
  final bool bearer;

  @override
  String toString() => '_Rotated(${issued.session.id})';
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
