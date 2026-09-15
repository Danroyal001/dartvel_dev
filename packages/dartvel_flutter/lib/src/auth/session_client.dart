/// `DV.Auth` signing in through the application's own generated backend.
///
/// The generated server issues a session at `/auth/sign-in`; this is the half
/// on the device. What goes wrong here still looks signed in, so each guard
/// says where it is:
///
/// * a native client asks for the `dvs_` token and keeps it sealed under the
///   application key -- the key `dartvel key` manages, in the platform's
///   keyring -- before it reaches a file. With no key custody it is used for
///   this process and never written down;
/// * a browser never asks for the token: the server's `HttpOnly` cookie is the
///   session, and nothing on the page can read it;
/// * sign-out forgets the session only once the server has revoked it. One
///   the server did not confirm leaves the device signed in and throws, rather
///   than looking signed out while the token still works;
/// * a session waiting for its second factor is held in memory, never stored
///   or handed to the generated client, and only the rotated token is kept;
/// * a stored session the server no longer honours is forgotten at launch
///   (`DV-SESSION-002`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../dartvel_flutter.dart' show DVAuthProvider, DVAuthUser;

/// A request to the generated auth endpoints that the server did not answer
/// as asked. Carries the status and the path, never the body.
class DVSessionRequestFailed implements Exception {
  const DVSessionRequestFailed(this.statusCode, this.path);

  final int statusCode;
  final String path;

  @override
  String toString() => 'DVSessionRequestFailed($statusCode at $path)';
}

/// A second-factor code the server refused.
class DVSecondFactorRefused implements Exception {
  const DVSecondFactorRefused();

  String get message => 'That code is not valid.';

  @override
  String toString() => 'DVSecondFactorRefused: $message';
}

/// What second factors the signed-in person has.
class DVSecondFactorStatus {
  const DVSecondFactorStatus({required this.totp, required this.recoveryCodes});

  /// Whether an authenticator app is active on the account.
  final bool totp;

  /// How many unspent recovery codes the account has.
  final int recoveryCodes;

  factory DVSecondFactorStatus.fromJson(Map<String, Object?> json, String path) {
    final Object? totp = json['totp'];
    final Object? codes = json['recoveryCodes'];
    if (totp is! bool || codes is! int) throw DVSessionRequestFailed(200, path);
    return DVSecondFactorStatus(totp: totp, recoveryCodes: codes);
  }

  @override
  String toString() =>
      'DVSecondFactorStatus(totp: $totp, recoveryCodes: $recoveryCodes)';
}

/// The signed-in person's account, as the server describes it.
class DVAccount {
  const DVAccount({required this.id, this.email, this.name, this.pendingEmail});

  final String id;

  /// The address the account signs in with. It changes only once a new
  /// address is verified.
  final String? email;
  final String? name;

  /// A new address waiting for its code, or null.
  final String? pendingEmail;

  factory DVAccount.fromJson(Object? json, String path) {
    if (json is! Map || json['id'] is! String) {
      throw DVSessionRequestFailed(200, path);
    }
    return DVAccount(
      id: json['id'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      pendingEmail: json['pendingEmail'] as String?,
    );
  }

  @override
  String toString() => 'DVAccount($id)';
}

/// Where a native client keeps its session token.
abstract interface class DVSessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

/// A token held for the life of the process only.
class DVMemorySessionTokenStore implements DVSessionTokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// Where a sealed token's bytes go: a dumb sink, because the sealing happens
/// before anything reaches it.
abstract interface class DVSessionTokenSink {
  Future<String?> read();

  /// Stores [value], or removes what is stored when it is null.
  Future<void> write(String? value);
}

/// A session token sealed with AES-256-GCM under the application key before
/// it reaches [sink].
///
/// The sink holds ciphertext only, so a copy of it -- a backup, another
/// user's process, a lost laptop's disk -- is not a working session. When the
/// key store cannot answer, the token is not written at all: an unsealed
/// token on disk is exactly what this exists to prevent.
class DVSealedSessionTokenStore implements DVSessionTokenStore {
  DVSealedSessionTokenStore({required this.sink, required this.keys});

  final DVSessionTokenSink sink;

  /// The application key store, asked only once there is something to seal
  /// or unseal: a keyring can prompt, and a launch with nothing stored should
  /// not.
  final Future<DVAppKeyStore> Function() keys;

  Future<DVAppKeyCipher?> _cipher() async {
    try {
      return DVAppKeyCipher(await DVAppKey.ensure(await keys()));
    } on Object catch (error) {
      DVObservability.log(
        'The application key store could not be used '
        '(${error.runtimeType}); the session token is not written down.',
        level: DVLogLevel.warn,
      );
      return null;
    }
  }

  @override
  Future<String?> read() async {
    final String? sealed = await sink.read();
    if (sealed == null) return null;
    final DVAppKeyCipher? cipher = await _cipher();
    if (cipher == null) return null;
    final String? token = cipher.decrypt(sealed);
    if (token == null || !token.startsWith(DVSessions.tokenPrefix)) {
      // Unreadable -- a rotated key, a reset keyring, or something that was
      // never sealed. Discarded rather than sent anywhere.
      await sink.write(null);
      return null;
    }
    return token;
  }

  @override
  Future<void> write(String token) async {
    final DVAppKeyCipher? cipher = await _cipher();
    if (cipher == null) {
      if (await sink.read() != null) await sink.write(null);
      return;
    }
    await sink.write(cipher.encrypt(token));
  }

  /// Removes the stored token, touching the sink only when it holds one.
  @override
  Future<void> clear() async {
    if (await sink.read() != null) await sink.write(null);
  }
}

/// The generated backend's sessions, from the device.
///
/// The generated runtime installs one over the application's backend, hands
/// its token to `DartvelClient.setAuthToken` through [onToken], and makes it
/// `DV.Auth`'s provider unless the application configures its own.
class DVSessionClient {
  DVSessionClient({
    required this.api,
    this.onToken,
    DVSessionTokenStore? tokens,
    bool? web,
    this.device,
    Future<DVHttpResponse> Function(DVHttpRequest request)? send,
  })  : _tokens = tokens,
        web = web ?? kIsWeb,
        _send = send ?? dvSendHttpRequest;

  static DVSessionClient? _installed;

  /// The client the generated runtime installed, or null.
  static DVSessionClient? get installed => _installed;

  static void install(DVSessionClient client) => _installed = client;

  /// Takes the installed client away, for a test.
  static void uninstall() => _installed = null;

  /// The backend URL for an API path, such as `DartvelRuntime.api`.
  final Uri Function(String path) api;

  /// Called with the live token when there is one and with null when there
  /// no longer is -- never with a token waiting for its second factor, and
  /// never in a browser.
  final void Function(String? token)? onToken;

  final DVSessionTokenStore? _tokens;

  /// Whether this runs in a browser, where the cookie is the session.
  final bool web;

  /// What the platform reports the device as, recorded on the session.
  final String? device;

  final Future<DVHttpResponse> Function(DVHttpRequest request) _send;

  String? _token;
  String? _pendingToken;
  DVAuthUser? _pendingUser;
  final DVMutableLifecycleSignal<DVSession?> _session =
      DVMutableLifecycleSignal<DVSession?>(null);

  /// This device's session as a read-only signal. Only the server's answers
  /// change it.
  DVLifecycleSignal<DVSession?> get session => _session;

  /// This device's session, or null when nobody is signed in here.
  DVSession? get current => _session.value;

  /// Whether a sign-in is waiting for its second factor.
  bool get awaitingSecondFactor => _pendingUser != null;

  /// Signs in. Throws [DVMfaRequired] when the account has a second factor,
  /// which [completeSecondFactor] then presents.
  Future<DVAuthUser> signIn({required String email, required String password}) =>
      _credentials(DVAuthEndpoints.signInPath,
          <String, Object?>{'email': email, 'password': password});

  /// Creates an account and signs in.
  Future<DVAuthUser> signUp({
    required String email,
    required String password,
    String? name,
  }) =>
      _credentials(DVAuthEndpoints.signUpPath, <String, Object?>{
        'email': email,
        'password': password,
        if (name != null) 'name': name,
      });

  /// Presents a code from the account's authenticator, or one recovery code,
  /// for the sign-in waiting on it -- or again, as step-up, for this session.
  Future<DVAuthUser> completeSecondFactor({String? code, String? recoveryCode}) async {
    if (code == null && recoveryCode == null) {
      throw ArgumentError('A code or a recovery code is required.');
    }
    const String path = DVAuthEndpoints.secondFactorPath;
    final DVHttpResponse response = await _request('POST', path,
        body: <String, Object?>{
          if (code != null) 'code': code,
          if (recoveryCode != null) 'recoveryCode': recoveryCode,
        },
        bearer: _pendingToken ?? _token);
    final Map<String, Object?> json = _decode(response, path);
    final DVSession session = _sessionOf(json, path);
    final DVAuthUser user = _pendingUser ??
        DVAuthUser(
            id: session.userId, provider: 'email', createdAt: session.createdAt);
    await _adopt(web ? null : json['token'] as String?, session, path);
    _pendingUser = null;
    return user;
  }

  /// Revokes this session on the server, then forgets it here.
  ///
  /// Throws, and leaves the device signed in, when the server did not
  /// confirm: forgetting a token the server still honours is not signing out.
  Future<void> signOut() async {
    final String? bearer = _pendingToken ?? _token;
    if (!web && bearer == null) {
      _pendingUser = null;
      _session.set(null);
      return;
    }
    const String path = DVAuthEndpoints.signOutPath;
    final DVHttpResponse response = await _request('POST', path, bearer: bearer);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw DVSessionRequestFailed(response.statusCode, path);
    }
    _pendingToken = null;
    _pendingUser = null;
    await _forget();
  }

  /// At launch: the stored session, if the server still honours it.
  ///
  /// A stored token is handed to [onToken] before the server is asked, so a
  /// launch without a network still sends it. One the server refuses is
  /// forgotten.
  Future<DVSession?> restore() async {
    if (web) return refresh();
    String? token;
    try {
      token = await _tokens?.read();
    } on Object {
      token = null;
    }
    if (token == null) return null;
    _token = token;
    onToken?.call(token);
    return refresh();
  }

  /// Asks the server which session this device is on.
  Future<DVSession?> refresh() async {
    if (!web && _token == null) return null;
    const String path = DVAuthEndpoints.sessionPath;
    final DVHttpResponse response = await _request('GET', path, bearer: _token);
    if (response.statusCode == 401) {
      DVObservability.log(
        'DV-SESSION-002: this device\'s session is no longer live; it was '
        'signed out.',
        code: 'DV-SESSION-002',
      );
      await _forget();
      return null;
    }
    final DVSession session = _sessionOf(_decode(response, path), path);
    _session.set(session);
    return session;
  }

  // --- this person's sessions ------------------------------------------------

  /// Every live session of the signed-in person on this tenant, newest
  /// sign-in first, with this device's marked current. The server answers
  /// for the person this session belongs to and nobody else.
  Future<List<DVSession>> sessions() async {
    const String path = DVAuthEndpoints.sessionsPath;
    final Map<String, Object?> json =
        _decode(await _request('GET', path, bearer: _token), path);
    final Object? listed = json['sessions'];
    if (listed is! List) throw const DVSessionRequestFailed(200, path);
    return <DVSession>[
      for (final Object? s in listed)
        if (s is Map) DVSession.fromJson(Map<String, Object?>.from(s)),
    ];
  }

  /// Revokes one of the signed-in person's sessions by its listed id. The
  /// server refuses another person's as not found, which throws here.
  /// Revoking this device's own session signs this device out.
  Future<void> revoke(String sessionId) async {
    const String path = DVAuthEndpoints.revokePath;
    final DVHttpResponse response = await _request('POST', path,
        body: <String, Object?>{'id': sessionId}, bearer: _token);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw DVSessionRequestFailed(response.statusCode, path);
    }
    if (current?.id == sessionId) {
      _pendingUser = null;
      await _forget();
    }
  }

  /// Revokes every other session of the signed-in person on this tenant and
  /// answers how many. This device's session is the one the server keeps.
  Future<int> revokeOthers() async {
    const String path = DVAuthEndpoints.revokeOthersPath;
    final Map<String, Object?> json =
        _decode(await _request('POST', path, bearer: _token), path);
    final Object? revoked = json['revoked'];
    if (revoked is! int) throw const DVSessionRequestFailed(200, path);
    return revoked;
  }

  // --- this person's second factors -----------------------------------------

  /// Whether the signed-in person has an authenticator, and how many unspent
  /// recovery codes. A count: no endpoint answers a code twice.
  Future<DVSecondFactorStatus> secondFactors() async {
    const String path = DVAuthEndpoints.factorsPath;
    return DVSecondFactorStatus.fromJson(
        _decode(await _request('GET', path, bearer: _token), path), path);
  }

  /// Starts enrolling an authenticator app: the secret to show as a QR code
  /// and as text. Nothing is active, and this device keeps none of it, until
  /// [confirmTotpEnrollment] presents a code from the app.
  Future<DVTotpEnrollment> beginTotpEnrollment() async {
    const String path = DVAuthEndpoints.totpPath;
    final Map<String, Object?> json =
        _decode(await _request('POST', path, bearer: _token), path);
    final Object? secret = json['secret'];
    final Object? uri = json['uri'];
    final Uri? parsed = uri is String ? Uri.tryParse(uri) : null;
    if (secret is! String || parsed == null) {
      throw const DVSessionRequestFailed(200, path);
    }
    return DVTotpEnrollment(secret: secret, uri: parsed);
  }

  /// Activates the authenticator being enrolled with a [code] from it. The
  /// server rotates the session, and this device keeps the rotated one.
  Future<void> confirmTotpEnrollment(String code) async {
    const String path = DVAuthEndpoints.totpConfirmPath;
    await _rotated(path, <String, Object?>{'code': code});
  }

  /// A new set of recovery codes, replacing every earlier one. The returned
  /// codes are the only copy anywhere: they are not stored on this device.
  ///
  /// Throws [DVMfaRequired] when the session's second factor is not recent;
  /// present one with [completeSecondFactor] and ask again.
  Future<DVRecoveryCodes> regenerateRecoveryCodes() async {
    const String path = DVAuthEndpoints.recoveryCodesPath;
    final Map<String, Object?> json = await _rotated(path, null);
    final Object? codes = json['recoveryCodes'];
    if (codes is! List) throw const DVSessionRequestFailed(200, path);
    return DVRecoveryCodes(
      codes: List<String>.unmodifiable(<String>[
        for (final Object? c in codes) '$c',
      ]),
      generatedAt: DateTime.tryParse('${json['generatedAt']}')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  /// Removes the authenticator and every recovery code, presenting a [code]
  /// from the authenticator or one [recoveryCode] with the request.
  Future<void> removeSecondFactor({String? code, String? recoveryCode}) async {
    if (code == null && recoveryCode == null) {
      throw ArgumentError(
          'Removing a second factor takes a code or a recovery code.');
    }
    const String path = DVAuthEndpoints.removeFactorPath;
    await _rotated(path, <String, Object?>{
      if (code != null) 'code': code,
      if (recoveryCode != null) 'recoveryCode': recoveryCode,
    });
  }

  // --- this person's account ------------------------------------------------

  /// The signed-in person's account, including an address change still
  /// waiting for its code.
  Future<DVAccount> account() async {
    const String path = DVAuthEndpoints.accountPath;
    final Map<String, Object?> json =
        _decode(await _request('GET', path, bearer: _token), path);
    return DVAccount.fromJson(json['account'], path);
  }

  /// Asks for the account's address to become [email]. The server sends a
  /// code to that address; nothing changes until [confirmEmailChange]
  /// presents it.
  Future<void> requestEmailChange(String email) async {
    const String path = DVAuthEndpoints.emailChangePath;
    _decode(
        await _request('POST', path,
            body: <String, Object?>{'email': email}, bearer: _token),
        path);
  }

  /// Presents the code sent to the new address. The address changes, the
  /// server rotates the session, and this device keeps the rotated one.
  Future<DVAccount> confirmEmailChange(String code) async {
    const String path = DVAuthEndpoints.emailVerifyPath;
    final Map<String, Object?> json =
        await _rotated(path, <String, Object?>{'code': code});
    return DVAccount.fromJson(json['account'], path);
  }

  /// Deletes the account, presenting its [password] -- and a [code] or
  /// [recoveryCode] when it has a second factor. Only once the server
  /// confirms is the session forgotten here; a refusal throws and leaves
  /// the device signed in.
  Future<void> deleteAccount({
    required String password,
    String? code,
    String? recoveryCode,
  }) async {
    const String path = DVAuthEndpoints.deleteAccountPath;
    _decode(
        await _request('POST', path,
            body: <String, Object?>{
              'password': password,
              'confirm': true,
              if (code != null) 'code': code,
              if (recoveryCode != null) 'recoveryCode': recoveryCode,
            },
            bearer: _token),
        path);
    _pendingToken = null;
    _pendingUser = null;
    await _forget();
  }

  /// A POST whose answer carries the rotated session, which is adopted
  /// before the rest of the answer is handed back.
  Future<Map<String, Object?>> _rotated(
      String path, Map<String, Object?>? body) async {
    final Map<String, Object?> json = _decode(
        await _request('POST', path, body: body, bearer: _token), path);
    await _adopt(web ? null : json['token'] as String?, _sessionOf(json, path), path);
    return json;
  }

  // --- the wire --------------------------------------------------------------

  Future<DVAuthUser> _credentials(String path, Map<String, Object?> body) async {
    final DVHttpResponse response =
        await _request('POST', path, body: body, bearer: _token);
    final Map<String, Object?> json = _decode(response, path);
    final DVSession session = _sessionOf(json, path);
    final Object? described = json['user'];
    final DVAuthUser user = DVAuthUser(
      id: described is Map ? '${described['id']}' : session.userId,
      email: described is Map ? described['email'] as String? : null,
      provider: 'email',
      createdAt: session.createdAt,
    );
    final String? token = web ? null : json['token'] as String?;
    // The server replaced whatever session this device presented.
    await _forget();
    if (json['mfaRequired'] == true) {
      _pendingToken = token;
      _pendingUser = user;
      throw DVMfaRequired(DVMfa.required, session.id);
    }
    await _adopt(token, session, path);
    return user;
  }

  Future<void> _adopt(String? token, DVSession session, String path) async {
    _pendingToken = null;
    if (!web) {
      if (token == null || !token.startsWith(DVSessions.tokenPrefix)) {
        throw DVSessionRequestFailed(200, path);
      }
      _token = token;
      try {
        await _tokens?.write(token);
      } on Object catch (error) {
        DVObservability.log(
          'The session token could not be stored (${error.runtimeType}); it '
          'lasts for this process.',
          level: DVLogLevel.warn,
        );
      }
      onToken?.call(token);
    }
    _session.set(session);
  }

  Future<void> _forget() async {
    final bool held = _token != null;
    _token = null;
    try {
      await _tokens?.clear();
    } on Object {
      // Nothing stored, or nowhere to store it.
    }
    if (held) onToken?.call(null);
    // A signal set to what it holds emits nothing, so a listener sees only
    // the transitions.
    _session.set(null);
  }

  Future<DVHttpResponse> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? bearer,
  }) {
    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      if (const DVCSRF().requiresValidation(method))
        DVCSRF.headerName: const DVCSRF().token(),
      if (body != null) 'content-type': 'application/json; charset=utf-8',
      if (!web) DVAuthEndpoints.deliveryHeader: 'token',
      if (!web && device != null) DVAuthEndpoints.deviceHeader: device!,
      if (!web && bearer != null) 'authorization': 'Bearer $bearer',
    };
    return _send(DVHttpRequest(
      url: api(path),
      method: method,
      headers: headers,
      body: body == null ? const <int>[] : utf8.encode(jsonEncode(body)),
    ));
  }

  DVSession _sessionOf(Map<String, Object?> json, String path) {
    final Object? session = json['session'];
    if (session is! Map) throw DVSessionRequestFailed(200, path);
    return DVSession.fromJson(Map<String, Object?>.from(session));
  }

  /// The body of a 200, or the refusal it stands for. A refusal is rebuilt
  /// from its code with the client's own wording, never from the server's
  /// text.
  Map<String, Object?> _decode(DVHttpResponse response, String path) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map) return Map<String, Object?>.from(decoded);
      throw DVSessionRequestFailed(response.statusCode, path);
    }
    final Object? error = decoded is Map ? decoded['error'] : null;
    throw switch (error) {
      'invalid_credentials' => AuthException.invalidCredentials,
      'account_exists' => const AuthException(AuthFailure.accountExists,
          'An account already exists for that e-mail address.'),
      'weak_password' =>
        const AuthException(AuthFailure.weakPassword, 'That password is too weak.'),
      'invalid_email' => const AuthException(
          AuthFailure.invalidEmail, 'That e-mail address is not valid.'),
      'breached_password' => const DVBreachedPasswordRefusal(),
      'too_many_attempts' =>
        const DVVelocityRefusal(scope: 'server', retryAfter: Duration.zero),
      'challenge_failed' => const DVBotRefusal('the server refused the challenge'),
      'invalid_code' => const DVSecondFactorRefused(),
      // Not a revoked session: the session is live and wants a code. It is
      // kept, and the caller asks for one.
      'mfa_required' => DVMfaRequired(DVMfa.required, current?.id ?? ''),
      _ => DVSessionRequestFailed(response.statusCode, path),
    };
  }
}

/// `DV.Session`: this device's session, as a read-only signal.
///
/// There is no setter anywhere on it. The session is what the server issued
/// and last confirmed, so only the installed [DVSessionClient] changes it --
/// on sign-in, a completed second factor, a launch's check, sign-out and a
/// revocation of this device. Empty until the generated runtime installs a
/// client.
class DVSessionSignal implements DVLifecycleSignal<DVSession?> {
  const DVSessionSignal();

  static final DVMutableLifecycleSignal<DVSession?> _none =
      DVMutableLifecycleSignal<DVSession?>(null);

  DVLifecycleSignal<DVSession?> get _source =>
      DVSessionClient.installed?.session ?? _none;

  /// This device's session, or null when nobody is signed in here.
  DVSession? get current => _source.value;

  /// The session's opaque id: rotated with its token, never a user id.
  String? get id => current?.id;

  /// The session's server-issued claims.
  Map<String, Object?> get claims => current?.claims ?? const <String, Object?>{};

  @override
  DVSession? get value => _source.value;

  @override
  DVSession? read() => _source.read();

  @override
  Stream<DVSession?> get changes => _source.changes;

  @override
  StreamSubscription<DVSession?> listen(
    FutureOr<void> Function(DVSession? state) onState,
  ) =>
      _source.listen(onState);
}

/// `DV.Auth`'s provider over [DVSessionClient]: e-mail and password against
/// the generated backend.
class DVSessionAuthProvider implements DVAuthProvider {
  DVSessionAuthProvider(this.client);

  final DVSessionClient client;

  @override
  Future<DVAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) =>
      client.signIn(email: email, password: password);

  @override
  Future<DVAuthUser> signUp({
    String? email,
    String? password,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (email == null || password == null) {
      throw ArgumentError(
          'The generated backend signs up with an e-mail address and a password.');
    }
    final Object? name = metadata['name'];
    return client.signUp(
        email: email, password: password, name: name is String ? name : null);
  }

  @override
  Future<void> signOut() => client.signOut();

  Never _unsupported(String method) => throw UnsupportedError(
        'The generated backend signs in with an e-mail address and a password; '
        '$method needs a provider configured with DV.Auth.configure.',
      );

  @override
  Future<DVAuthUser> signInAnonymously() async => _unsupported('signInAnonymously');

  @override
  Future<DVAuthUser> signInWithProvider(String provider) async =>
      _unsupported('signInWithProvider');

  @override
  Future<DVAuthUser> signInWithRawOAuth(Map<String, Object?> oauth) async =>
      _unsupported('signInWithRawOAuth');

  @override
  Future<DVAuthUser> signInWithPasskey() async => _unsupported('signInWithPasskey');

  @override
  Future<DVAuthUser> signInWithBiometrics() async =>
      _unsupported('signInWithBiometrics');

  @override
  Future<DVAuthUser> signInWithWeb3() async => _unsupported('signInWithWeb3');
}
