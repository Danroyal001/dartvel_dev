// Accounts kept in the application's database.
//
// The generated server's sign-in endpoints authenticate through an
// AuthProvider, and the only one Dartvel had kept its accounts in a map. A
// web-server binary installed nothing, so signing up answered 503, and one
// that installed LocalAuthProvider forgot every account on restart -- which
// looks like a working sign-in right up to the first deploy. The silent
// failures worth a test:
//  * an account that does not outlive the process that created it;
//  * a password stored so that reading the table reveals it;
//  * a sign-in that says whether the address has an account;
//  * two accounts for one address, from differently written or concurrent
//    sign-ups, where sign-in then picks one of them;
//  * a changed password or a deleted account that still signs in.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

const String _password = 'correct horse battery staple';

DVDatabaseAuthProvider _provider(DVDatabaseAdapter adapter) =>
    DVDatabaseAuthProvider(adapter, hasher: DVPasswordHasher(iterations: 1000));

Matcher _failsWith(AuthFailure failure) => throwsA(
    isA<AuthException>().having((AuthException e) => e.failure, 'failure', failure));

void main() {
  late Directory dir;
  late String file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dv_db_auth_');
    file = '${dir.path}/data.db';
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('an account outlives the process that created it', () async {
    final SqliteDVDatabaseAdapter first = SqliteDVDatabaseAdapter.file(file);
    final AuthUser created = (await _provider(first)
        .signUp('Owner@Example.com ', _password, name: 'Owner'))!;
    first.close();

    // A new adapter and a new provider: what a restarted binary has.
    final SqliteDVDatabaseAdapter second = SqliteDVDatabaseAdapter.file(file);
    addTearDown(second.close);
    final DVDatabaseAuthProvider restarted = _provider(second);
    final AuthUser? signedIn =
        await restarted.signIn('owner@example.com', _password);

    expect(signedIn?.id, created.id);
    expect(signedIn?.email, 'owner@example.com');
    expect(signedIn?.name, 'Owner');
    expect((await restarted.userById(created.id))?.email, 'owner@example.com');
  });

  test('the table holds a hash, never the password', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    await _provider(db).signUp('a@example.com', _password);

    final List<Map<String, Object?>> rows =
        await db.query('SELECT * FROM dv_accounts');
    expect(rows, hasLength(1));
    for (final Object? value in rows.single.values) {
      expect('$value', isNot(contains(_password)));
    }
    expect('${rows.single['password_hash']}', startsWith('pbkdf2-sha256\$'));
  });

  test('a wrong password and an unknown address are the same refusal',
      () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    await provider.signUp('a@example.com', _password);

    await expectLater(provider.signIn('a@example.com', 'not the password'),
        _failsWith(AuthFailure.invalidCredentials));
    await expectLater(provider.signIn('nobody@example.com', _password),
        _failsWith(AuthFailure.invalidCredentials));
  });

  test('one address is one account, however it is written', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    await provider.signUp('a@example.com', _password);

    await expectLater(provider.signUp(' A@EXAMPLE.com', 'another password 1'),
        _failsWith(AuthFailure.accountExists));
    expect(await db.query('SELECT id FROM dv_accounts'), hasLength(1));
    // And the first password is still the one that signs in.
    expect(await provider.signIn('a@example.com', _password), isNotNull);
  });

  test('two sign-ups for one address at once leave one account', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(file);
    addTearDown(db.close);
    // Two providers, as two web processes over one database would have.
    final List<Object?> outcomes = await Future.wait(<Future<Object?>>[
      for (final DVDatabaseAuthProvider p in <DVDatabaseAuthProvider>[
        _provider(db),
        _provider(db),
      ])
        p
            .signUp('race@example.com', _password)
            .then<Object?>((AuthUser? u) => u)
            .catchError((Object e) => e),
    ]);

    expect(outcomes.whereType<AuthUser>(), hasLength(1), reason: '$outcomes');
    expect(
        outcomes.whereType<AuthException>().map((AuthException e) => e.failure),
        <AuthFailure>[AuthFailure.accountExists]);
    expect(
        await db.query('SELECT id FROM dv_accounts WHERE email = ?',
            <Object?>['race@example.com']),
        hasLength(1));
  });

  test('an address or a password that is not one is refused', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);

    await expectLater(
        provider.signUp('no-at-sign', _password), _failsWith(AuthFailure.invalidEmail));
    await expectLater(
        provider.signUp('a@example.com', 'short'), _failsWith(AuthFailure.weakPassword));
    // Nothing was kept: the address is still free.
    expect(await provider.signUp('a@example.com', _password), isNotNull);
  });

  test('ids are distinct and do not count accounts', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    final AuthUser a = (await provider.signUp('a@example.com', _password))!;
    final AuthUser b = (await provider.signUp('b@example.com', _password))!;

    expect(a.id, isNot(b.id));
    expect(a.id, isNot(anyOf('1', 'local_1', 'acct_1')));
    expect(a.id.length, greaterThanOrEqualTo(16));
  });

  test('a changed password replaces the old one', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    final AuthUser a = (await provider.signUp('a@example.com', _password))!;

    await provider.changePassword(a.id, 'a brand new passphrase');

    await expectLater(provider.signIn('a@example.com', _password),
        _failsWith(AuthFailure.invalidCredentials));
    expect((await provider.signIn('a@example.com', 'a brand new passphrase'))?.id,
        a.id);
    await expectLater(
        provider.changePassword(a.id, 'short'), _failsWith(AuthFailure.weakPassword));
  });

  test('a changed address signs in, and cannot take another account\'s',
      () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    final AuthUser a = (await provider.signUp('a@example.com', _password))!;
    await provider.signUp('b@example.com', _password);

    await expectLater(provider.changeEmail(a.id, 'B@example.com'),
        _failsWith(AuthFailure.accountExists));
    final AuthUser moved = await provider.changeEmail(a.id, 'c@example.com');

    expect(moved.id, a.id);
    expect((await provider.signIn('c@example.com', _password))?.id, a.id);
    await expectLater(provider.signIn('a@example.com', _password),
        _failsWith(AuthFailure.invalidCredentials));
  });

  test('a deleted account no longer signs in', () async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.memory();
    addTearDown(db.close);
    final DVDatabaseAuthProvider provider = _provider(db);
    final AuthUser a = (await provider.signUp('a@example.com', _password))!;

    await provider.deleteAccount(a.id);

    expect(await provider.userById(a.id), isNull);
    await expectLater(provider.signIn('a@example.com', _password),
        _failsWith(AuthFailure.invalidCredentials));
    // The address is free again.
    expect(await provider.signUp('a@example.com', _password), isNotNull);
  });
}
