// Authentication system
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'password.dart';

/// A password nobody knows, for a dummy hash that no guess should match.
String _dummySecret() {
  final random = Random.secure();
  return base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
}

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

/// A provider that can describe an account by its id, for the account
/// endpoints that act on the signed-in person rather than on credentials.
///
/// Separate from [AuthProvider] so a provider that cannot answer is still a
/// provider: what depends on it degrades to the user id rather than failing.
abstract interface class DVAccountDirectory {
  /// The account with [id], or null when there is none.
  Future<AuthUser?> userById(String id);
}

/// A provider that can find an account by its address, for the places an
/// operator names a person the way people are named -- Studio granting
/// access to `sam@example.com` rather than to `acct_...`.
abstract interface class DVAccountLookup {
  /// The account whose address is [email], compared as the provider stores
  /// addresses, or null when there is none.
  Future<AuthUser?> userByEmail(String email);
}

/// A provider that can change an account's address and delete an account,
/// for the generated account endpoints.
///
/// The endpoints decide when: an address changes only after a code sent to
/// it comes back, and an account is deleted only after its password -- and
/// its second factor, when it has one -- and explicit confirmation. The
/// provider only does what it is told.
abstract interface class DVAccountProvider implements DVAccountDirectory {
  /// Moves the account with [id] to [email]. Throws [AuthException] with
  /// [AuthFailure.accountExists] when another account has that address and
  /// [AuthFailure.invalidEmail] when it is not one.
  Future<AuthUser> changeEmail(String id, String email);

  /// Removes the account with [id]. Its credentials no longer sign in.
  Future<void> deleteAccount(String id);
}

/// A provider that can set an account's password, for the generated
/// password-change endpoint.
///
/// The endpoint decides when: only after the current password is checked
/// through the credential guard, a second factor where the account has one,
/// and the breach check. The provider only stores what it is told, refusing
/// a password its own rules call weak.
abstract interface class DVPasswordProvider implements DVAccountDirectory {
  /// Sets the password of the account with [id]. Throws [AuthException] with
  /// [AuthFailure.weakPassword] for a password the provider will not keep.
  Future<void> changePassword(String id, String password);
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
  /// Never thrown by a Dartvel provider: an unknown account is
  /// [invalidCredentials], because telling it apart from a wrong password
  /// tells anyone which e-mail addresses have accounts.
  @Deprecated('An unknown account is AuthFailure.invalidCredentials. Kept so '
      'existing switches compile, and so DVCredentialGuard can collapse a '
      'provider that still throws it.')
  unknownAccount,

  /// Never thrown by a Dartvel provider: a wrong password is
  /// [invalidCredentials], for the same reason as [unknownAccount].
  @Deprecated('A wrong password is AuthFailure.invalidCredentials. Kept so '
      'existing switches compile, and so DVCredentialGuard can collapse a '
      'provider that still throws it.')
  invalidPassword,
  accountExists,
  weakPassword,
  invalidEmail,

  /// The e-mail address and password do not match an account: either there
  /// is no such account or the password is wrong, and the caller is not told
  /// which.
  invalidCredentials,
}

class AuthException implements Exception {
  final AuthFailure failure;
  final String message;

  const AuthException(this.failure, this.message);

  /// The one refusal a sign-in gets, whether or not the account exists.
  ///
  /// Why a sign-in failed is known on the server and belongs in its logs and
  /// its velocity counts, never in the answer.
  static const AuthException invalidCredentials = AuthException(
    AuthFailure.invalidCredentials,
    'That e-mail address and password do not match an account.',
  );

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
class LocalAuthProvider implements AuthProvider, DVAccountProvider, DVPasswordProvider {
  static const int minimumPasswordLength = 8;

  final _controller = StreamController<AuthUser?>.broadcast();
  final Map<String, _StoredCredential> _accounts =
      <String, _StoredCredential>{};
  final DVPasswordHasher _hasher;

  /// What a password is checked against when no account matches, so a miss
  /// does one verification like a wrong password does. Made once, by the same
  /// hasher, so it costs what a stored hash costs; hashing on every miss would
  /// make a miss do twice the work and answer measurably slower. Made at
  /// construction rather than on the first miss, which would otherwise be the
  /// one sign-in slower than a wrong password.
  final String _dummyHash;

  AuthUser? _currentUser;
  int _nextId = 1;

  LocalAuthProvider({DVPasswordHasher? hasher})
      : this._(hasher ??
            DVPasswordHasher(
              // Development default: strong enough to exercise the real code
              // path without making every test sign-in slow.
              iterations: 10000,
            ));

  LocalAuthProvider._(this._hasher)
      : _dummyHash = _hasher.hash(_dummySecret());

  /// Registered account e-mails, for test assertions and dev tooling.
  List<String> get accounts => List<String>.unmodifiable(_accounts.keys);

  /// Signs in, or throws [AuthException.invalidCredentials] whether the
  /// account is missing or the password is wrong, after the same work.
  @override
  Future<AuthUser?> signIn(String email, String password) async {
    final key = _normalize(email);
    final stored = _accounts[key];
    final matched =
        _hasher.verify(password, stored?.passwordHash ?? _dummyHash);
    if (stored == null || !matched) {
      throw AuthException.invalidCredentials;
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
    // Hashed before the address is looked up, so a taken address does not
    // answer sooner than a free one.
    final passwordHash = _hasher.hash(password);
    if (_accounts.containsKey(key)) {
      throw const AuthException(
        AuthFailure.accountExists,
        'An account already exists for that e-mail address.',
      );
    }

    final user = AuthUser(id: 'local_${_nextId++}', email: key, name: name);
    _accounts[key] = _StoredCredential(user, passwordHash);

    _currentUser = user;
    _controller.add(_currentUser);
    return _currentUser;
  }

  @override
  Future<AuthUser?> userById(String id) async {
    for (final _StoredCredential stored in _accounts.values) {
      if (stored.user.id == id) return stored.user;
    }
    return null;
  }

  @override
  Future<AuthUser> changeEmail(String id, String email) async {
    final String key = _normalize(email);
    if (!key.contains('@') || key.startsWith('@') || key.endsWith('@')) {
      throw const AuthException(
        AuthFailure.invalidEmail,
        'That e-mail address is not valid.',
      );
    }
    final MapEntry<String, _StoredCredential> current = _accounts.entries
        .firstWhere((MapEntry<String, _StoredCredential> e) => e.value.user.id == id,
            orElse: () => throw StateError('No account has that id.'));
    if (current.key == key) return current.value.user;
    if (_accounts.containsKey(key)) {
      throw const AuthException(
        AuthFailure.accountExists,
        'An account already exists for that e-mail address.',
      );
    }
    final AuthUser moved = AuthUser(
      id: id,
      email: key,
      name: current.value.user.name,
      metadata: current.value.user.metadata,
    );
    _accounts.remove(current.key);
    _accounts[key] = _StoredCredential(moved, current.value.passwordHash);
    if (_currentUser?.id == id) _currentUser = moved;
    return moved;
  }

  @override
  Future<void> changePassword(String id, String password) async {
    if (password.length < minimumPasswordLength) {
      throw const AuthException(
        AuthFailure.weakPassword,
        'Passwords must be at least $minimumPasswordLength characters.',
      );
    }
    final String passwordHash = _hasher.hash(password);
    final MapEntry<String, _StoredCredential> current = _accounts.entries
        .firstWhere((MapEntry<String, _StoredCredential> e) => e.value.user.id == id,
            orElse: () => throw StateError('No account has that id.'));
    _accounts[current.key] = _StoredCredential(current.value.user, passwordHash);
  }

  @override
  Future<void> deleteAccount(String id) async {
    _accounts.removeWhere(
        (String _, _StoredCredential stored) => stored.user.id == id);
    if (_currentUser?.id == id) _currentUser = null;
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
