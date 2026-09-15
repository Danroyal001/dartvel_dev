// A route's Resource.action, asked with the signed-in person as the caller.
//
// DVBackendPolicy.allowsAction handed the registered policy the API key
// principal or nothing, so a request authenticated with the application's own
// session reached the policy with no caller: a policy written against the
// application's user type refused everybody, and one taking Object? could not
// tell a signed-in person from an anonymous request.
//
// The silent failures:
//  * a policy typed on the application's user handed the session principal,
//    or nothing, and refusing a person it would have allowed;
//  * a policy taking Object? handed the principal where the application
//    resolved a user, so `user is Account` is false for everybody;
//  * the API key path handed the session, or its scopes skipped.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Account {
  const _Account(this.id, this.role);

  final String id;
  final String role;
}

class _Invoice {
  const _Invoice();
}

DVSessionPrincipal _signedIn(Object? user, {String tenant = 'acme'}) =>
    DVSessionPrincipal(
      session: DVSession(
        id: 'ses_test',
        userId: user is _Account ? user.id : 'u-1',
        tenant: tenant,
        createdAt: DateTime.utc(2026, 9, 15),
        lastSeenAt: DateTime.utc(2026, 9, 15),
      ),
      user: user,
    );

void main() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();
  final List<Object?> seen = <Object?>[];

  setUpAll(() {
    authorization.registerDeclared<_Account, _Invoice?>(
        'view', (_Account user, _Invoice? invoice) => true);
    authorization.registerDeclared<_Account, _Invoice?>(
        'delete', (_Account user, _Invoice? invoice) => user.role == 'admin');
    authorization.registerDeclared<DVSessionPrincipal, _Invoice?>(
        'restore',
        (DVSessionPrincipal caller, _Invoice? invoice) =>
            caller.tenant == 'acme');
    authorization.registerDeclared<Object?, _Invoice?>('create',
        (Object? user, _Invoice? invoice) {
      seen.add(user);
      return user != null;
    });
  });

  setUp(() {
    seen.clear();
    DVBackendPolicy.decide = null;
  });

  Future<bool> asking(Object? caller, String action) {
    Future<bool> ask() => DVBackendPolicy.allowsAction(action, '/api/invoices');
    return switch (caller) {
      final DVSessionPrincipal session =>
        DVSessionPrincipal.actingAs(session, ask),
      final DVApiPrincipal key => DVApiPrincipal.actingAs(key, ask),
      _ => ask(),
    };
  }

  test('a policy on the application\'s user is handed the signed-in account',
      () async {
    expect(await asking(_signedIn(const _Account('u-1', 'viewer')), '_Invoice.view'),
        isTrue);
    expect(await asking(_signedIn(const _Account('u-1', 'viewer')), '_Invoice.delete'),
        isFalse);
    expect(await asking(_signedIn(const _Account('u-2', 'admin')), '_Invoice.delete'),
        isTrue);
  });

  test('a policy on the session principal is handed the principal', () async {
    expect(await asking(_signedIn(const _Account('u-1', 'viewer')), '_Invoice.restore'),
        isTrue);
    expect(
        await asking(_signedIn(const _Account('u-1', 'viewer'), tenant: 'globex'),
            '_Invoice.restore'),
        isFalse);
  });

  test('a policy taking Object? is handed the application\'s user when there is '
      'one, and the principal when there is not', () async {
    const _Account account = _Account('u-1', 'viewer');
    expect(await asking(_signedIn(account), '_Invoice.create'), isTrue);
    expect(seen.single, same(account));

    seen.clear();
    final DVSessionPrincipal bare = _signedIn(null);
    expect(await asking(bare, '_Invoice.create'), isTrue);
    expect(seen.single, same(bare));
  });

  test('a session with no resolved user cannot pass a policy on the user type',
      () async {
    expect(await asking(_signedIn(null), '_Invoice.view'), isFalse);
  });

  test('an API key is still the caller its request authenticated as', () async {
    final DVApiPrincipal key = DVApiPrincipal(
      kind: DVApiPrincipalKind.apiKey,
      subject: 'key-1',
      tenant: 'acme',
      scopes: <String>{'invoices:write'},
      actions: <String>{'_Invoice.create'},
    );
    expect(await asking(key, '_Invoice.create'), isTrue);
    expect(seen.single, same(key));
    expect(await asking(key, '_Invoice.view'), isFalse,
        reason: 'outside the key\'s scopes');
  });

  test('decide still answers for the route, and sees the signed-in person',
      () async {
    final List<String?> asked = <String?>[];
    DVBackendPolicy.decide = (String policy, String path) async {
      asked.add(DVSessionPrincipal.current?.userId);
      return true;
    };
    expect(await asking(_signedIn(const _Account('u-1', 'viewer')), '_Invoice.delete'),
        isTrue);
    expect(asked, <String?>['u-1']);
  });
}
