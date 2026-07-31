// Authentication system
import 'dart:async';

import 'password.dart';

/// User model
class AuthUser {
  final String id;
  final String email;
  final String? name;
  final Map<String, Object?>? metadata;

  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.metadata,
  });

  factory AuthUser.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      metadata: metadata is Map<Object?, Object?>
          ? Map<String, Object?>.from(metadata)
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'email': email,
      if (name != null) 'name': name,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Auth state
enum AuthState {
  unknown,
  authenticated,
  unauthenticated,
}

/// Authentication provider
abstract class AuthProvider {
  Future<AuthUser?> signIn(String email, String password);
  Future<AuthUser?> signUp(String email, String password, {String? name});
  Future<void> signOut();
  Future<AuthUser?> currentUser();
  Stream<AuthUser?> get authStateChanges;
}

/// Auth manager
class Auth {
  static Auth? _instance;
  final AuthProvider provider;

  Auth._(this.provider);

  static void initialize(AuthProvider provider) {
    _instance = Auth._(provider);
  }

  static Auth get instance {
    if (_instance == null) {
      throw StateError('Auth not initialized');
    }
    return _instance!;
  }

  Future<AuthUser?> signIn(String email, String password) {
    return provider.signIn(email, password);
  }

  Future<AuthUser?> signUp(String email, String password, {String? name}) {
    return provider.signUp(email, password, name: name);
  }

  Future<void> signOut() {
    return provider.signOut();
  }

  Future<AuthUser?> currentUser() {
    return provider.currentUser();
  }

  Stream<AuthUser?> get authStateChanges => provider.authStateChanges;
}

/// Why an authentication attempt failed.
enum AuthFailure {
  unknownAccount,
  invalidPassword,
  accountExists,
  weakPassword,
  invalidEmail,
}

class AuthException implements Exception {
  final AuthFailure failure;
  final String message;

  const AuthException(this.failure, this.message);

  @override
  String toString() => 'AuthException(${failure.name}): $message';
}

class _StoredCredential {
  final AuthUser user;
  final String passwordHash;

  const _StoredCredential(this.user, this.passwordHash);
}

/// In-memory auth provider for local development and tests.
///
/// Credentials are really stored and really verified: passwords are salted and
/// hashed with [DVPasswordHasher], an unknown account or a wrong password is
/// rejected, and accounts cannot be silently overwritten. It holds everything
/// in memory and has no account recovery, e-mail verification, or session
/// expiry, so it remains a development and test adapter — configure a real
/// [AuthProvider] for production.
class LocalAuthProvider implements AuthProvider {
  static const int minimumPasswordLength = 8;

  final _controller = StreamController<AuthUser?>.broadcast();
  final Map<String, _StoredCredential> _accounts =
      <String, _StoredCredential>{};
  final DVPasswordHasher _hasher;

  AuthUser? _currentUser;
  int _nextId = 1;

  LocalAuthProvider({DVPasswordHasher? hasher})
      : _hasher = hasher ??
            DVPasswordHasher(
              // Development default: strong enough to exercise the real code
              // path without making every test sign-in slow.
              iterations: 10000,
            );

  /// Registered account e-mails, for test assertions and dev tooling.
  List<String> get accounts => List<String>.unmodifiable(_accounts.keys);

  @override
  Future<AuthUser?> signIn(String email, String password) async {
    final key = _normalize(email);
    final stored = _accounts[key];
    if (stored == null) {
      // Hash anyway so a missing account and a wrong password take comparable
      // time, rather than leaking which e-mails are registered.
      _hasher.verify(password, _hasher.hash(password));
      throw const AuthException(
        AuthFailure.unknownAccount,
        'No account exists for that e-mail address.',
      );
    }
    if (!_hasher.verify(password, stored.passwordHash)) {
      throw const AuthException(
        AuthFailure.invalidPassword,
        'That password is incorrect.',
      );
    }

    _currentUser = stored.user;
    _controller.add(_currentUser);
    return _currentUser;
  }

  @override
  Future<AuthUser?> signUp(String email, String password,
      {String? name}) async {
    final key = _normalize(email);
    if (!key.contains('@') || key.startsWith('@') || key.endsWith('@')) {
      throw const AuthException(
        AuthFailure.invalidEmail,
        'That e-mail address is not valid.',
      );
    }
    if (password.length < minimumPasswordLength) {
      throw const AuthException(
        AuthFailure.weakPassword,
        'Passwords must be at least $minimumPasswordLength characters.',
      );
    }
    if (_accounts.containsKey(key)) {
      throw const AuthException(
        AuthFailure.accountExists,
        'An account already exists for that e-mail address.',
      );
    }

    final user = AuthUser(id: 'local_${_nextId++}', email: key, name: name);
    _accounts[key] = _StoredCredential(user, _hasher.hash(password));

    _currentUser = user;
    _controller.add(_currentUser);
    return _currentUser;
  }

  /// Removes every account and signs out. Intended for test teardown.
  void reset() {
    _accounts.clear();
    _nextId = 1;
    _currentUser = null;
  }

  static String _normalize(String email) => email.trim().toLowerCase();

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<AuthUser?> currentUser() async {
    return _currentUser;
  }

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;
}

@Deprecated('Use LocalAuthProvider instead.')
typedef DebugAuthProvider = LocalAuthProvider;

/// JWT token manager
class JwtTokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  void setTokens({
    required String accessToken,
    String? refreshToken,
    Duration? expiresIn,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    if (expiresIn != null) {
      _expiresAt = DateTime.now().add(expiresIn);
    }
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  bool get isExpired {
    if (_expiresAt == null) return false;
    return DateTime.now().isAfter(_expiresAt!);
  }

  bool get hasToken => _accessToken != null;

  void clear() {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
  }
}
