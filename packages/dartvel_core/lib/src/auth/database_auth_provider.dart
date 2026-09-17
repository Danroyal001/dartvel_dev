/// Accounts kept in the application's database.
///
/// The generated server's sign-up and sign-in endpoints authenticate through
/// an [AuthProvider], and a deployment needs one whose accounts outlive the
/// process: [LocalAuthProvider] keeps them in memory, so a server using it
/// forgets every account on restart. This one keeps them in a framework table
/// over any [DVDatabaseAdapter], which is what the generated server installs
/// when the application installed nothing of its own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/adapter.dart';
import '../database/framework_tables.dart';
import 'auth.dart';
import 'password.dart';

/// Accounts in a `dv_accounts` table: an id, the address, a name and a salted
/// PBKDF2 hash of the password. The password itself is never stored.
///
/// One address is one account. The address is kept trimmed and in lower case,
/// and the table's unique key decides between two sign-ups for the same
/// address at once, so two web processes over one database cannot both create
/// it.
class DVDatabaseAuthProvider
    implements
        AuthProvider,
        DVAccountProvider,
        DVAccountLookup,
        DVPasswordProvider {
  DVDatabaseAuthProvider(
    this.adapter, {
    this.table = 'dv_accounts',
    DVPasswordHasher? hasher,
    DateTime Function()? clock,
  })  : _hasher = hasher ?? DVPasswordHasher(),
        _clock = clock ?? DateTime.now {
    _dummyHash = _hasher.hash(_randomString(32));
  }

  static const int minimumPasswordLength = LocalAuthProvider.minimumPasswordLength;

  /// The longest address kept. Longer than any address a mail server
  /// delivers to (RFC 5321), and short enough to be a unique key everywhere.
  static const int maximumEmailLength = 254;

  final DVDatabaseAdapter adapter;
  final String table;
  final DVPasswordHasher _hasher;
  final DateTime Function() _clock;
  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();

  /// What a password is checked against when no account matches, so a miss
  /// costs what a wrong password costs.
  late final String _dummyHash;

  Future<void>? _ready;

  Future<void> _ensure() => _ready ??= dvEnsureFrameworkTable(
        adapter,
        'CREATE TABLE IF NOT EXISTS $table ('
        'id VARCHAR(64) PRIMARY KEY, '
        // 254 is [maximumEmailLength], written out so the column's type can be
        // read from the source like every other framework table's.
        'email VARCHAR(254) NOT NULL UNIQUE, '
        'name TEXT, password_hash TEXT NOT NULL, created_at BIGINT)',
      );

  @override
  Future<AuthUser?> signUp(String email, String password, {String? name}) async {
    final String address = _address(email);
    _checkPassword(password);
    // Hashed before the address is looked up, so a taken address does not
    // answer sooner than a free one.
    final String passwordHash = _hasher.hash(password);
    await _ensure();
    if (await _byEmail(address) != null) throw _exists;
    final AuthUser user =
        AuthUser(id: 'acct_${_randomString(24)}', email: address, name: name);
    try {
      await adapter.execute(
        'INSERT INTO $table (id, email, name, password_hash, created_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          user.id,
          address,
          name,
          passwordHash,
          _clock().toUtc().millisecondsSinceEpoch,
        ],
      );
    } on Object {
      // Another sign-up for this address got there between the lookup and
      // the insert, and the unique key refused this one.
      if (await _byEmail(address) != null) throw _exists;
      rethrow;
    }
    _changes.add(user);
    return user;
  }

  @override
  Future<AuthUser?> signIn(String email, String password) async {
    await _ensure();
    final Map<String, Object?>? row = await _byEmail(_normalize(email));
    final String? stored = row?['password_hash'] as String?;
    final bool matched = _hasher.verify(password, stored ?? _dummyHash);
    if (row == null || !matched) throw AuthException.invalidCredentials;
    final AuthUser user = _user(row);
    _changes.add(user);
    return user;
  }

  @override
  Future<AuthUser?> userById(String id) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT id, email, name FROM $table WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _user(rows.first);
  }

  @override
  Future<AuthUser?> userByEmail(String email) async {
    await _ensure();
    final Map<String, Object?>? row = await _byEmail(_normalize(email));
    return row == null ? null : _user(row);
  }

  @override
  Future<AuthUser> changeEmail(String id, String email) async {
    final String address = _address(email);
    final AuthUser current = await _existing(id);
    if (current.email == address) return current;
    if (await _byEmail(address) != null) throw _exists;
    try {
      await adapter.execute(
        'UPDATE $table SET email = ? WHERE id = ?',
        <Object?>[address, id],
      );
    } on Object {
      if (await _byEmail(address) != null) throw _exists;
      rethrow;
    }
    return AuthUser(id: id, email: address, name: current.name);
  }

  @override
  Future<void> changePassword(String id, String password) async {
    _checkPassword(password);
    await _existing(id);
    await adapter.execute(
      'UPDATE $table SET password_hash = ? WHERE id = ?',
      <Object?>[_hasher.hash(password), id],
    );
  }

  @override
  Future<void> deleteAccount(String id) async {
    await _ensure();
    await adapter.execute('DELETE FROM $table WHERE id = ?', <Object?>[id]);
  }

  /// The server keeps no signed-in person of its own: who is signed in is the
  /// session a request carries.
  @override
  Future<void> signOut() async => _changes.add(null);

  @override
  Future<AuthUser?> currentUser() async => null;

  @override
  Stream<AuthUser?> get authStateChanges => _changes.stream;

  Future<AuthUser> _existing(String id) async {
    final AuthUser? user = await userById(id);
    if (user == null) throw StateError('No account has that id.');
    return user;
  }

  Future<Map<String, Object?>?> _byEmail(String address) async {
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT id, email, name, password_hash FROM $table WHERE email = ?',
      <Object?>[address],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static AuthUser _user(Map<String, Object?> row) => AuthUser(
        id: '${row['id']}',
        email: '${row['email']}',
        name: row['name'] as String?,
      );

  static const AuthException _exists = AuthException(
    AuthFailure.accountExists,
    'An account already exists for that e-mail address.',
  );

  static String _normalize(String email) => email.trim().toLowerCase();

  static String _address(String email) {
    final String address = _normalize(email);
    final int at = address.indexOf('@');
    if (at <= 0 ||
        at != address.lastIndexOf('@') ||
        at == address.length - 1 ||
        address.length > maximumEmailLength ||
        address.contains(RegExp(r'\s'))) {
      throw const AuthException(
        AuthFailure.invalidEmail,
        'That e-mail address is not valid.',
      );
    }
    return address;
  }

  static void _checkPassword(String password) {
    if (password.length < minimumPasswordLength) {
      throw const AuthException(
        AuthFailure.weakPassword,
        'Passwords must be at least $minimumPasswordLength characters.',
      );
    }
  }

  static String _randomString(int bytes) {
    final Random random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
