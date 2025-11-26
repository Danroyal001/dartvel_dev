// Authentication system
import 'dart:async';

/// User model
class AuthUser {
  final String id;
  final String email;
  final String? name;
  final Map<String, dynamic>? metadata;

  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.metadata,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
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

/// Mock auth provider
class DebugAuthProvider implements AuthProvider {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Future<AuthUser?> signIn(String email, String password) async {
    // Mock sign in
    await Future.delayed(const Duration(milliseconds: 500));

    if (password.length < 6) {
      throw Exception('Password too short');
    }

    _currentUser = AuthUser(
      id: '123',
      email: email,
      name: 'Demo User',
    );

    _controller.add(_currentUser);
    return _currentUser;
  }

  @override
  Future<AuthUser?> signUp(String email, String password,
      {String? name}) async {
    await Future.delayed(const Duration(milliseconds: 500));

    _currentUser = AuthUser(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: email,
      name: name,
    );

    _controller.add(_currentUser);
    return _currentUser;
  }

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
