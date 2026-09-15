// Refused because nobody signed in, or refused because the caller may not.
//
// A route's policy answered a bare yes or no, so a request with no session on
// a route whose policy needs a signed-in user got the same 403 as a person the
// policy refused. A client cannot act on that: 401 says sign in and try again,
// 403 says signing in again will not help. The silent failure is the one that
// still looks right -- a 403 where a 401 belongs sends a signed-out person to
// a "not allowed" screen, and a 401 where a 403 belongs loops a signed-in one
// back through sign-in forever.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Account {
  const _Account(this.role);

  final String role;
}

class _Receipt {
  const _Receipt();
}

DVSessionPrincipal _signedIn(Object? user) => DVSessionPrincipal(
      session: DVSession(
        id: 'ses_test',
        userId: 'u-1',
        tenant: 'acme',
        createdAt: DateTime.utc(2026, 9, 15),
        lastSeenAt: DateTime.utc(2026, 9, 15),
      ),
      user: user,
    );

void main() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();
  bool open = false;

  setUpAll(() {
    authorization.registerDeclared<_Account, _Receipt?>(
        'view', (_Account user, _Receipt? receipt) => true);
    authorization.registerDeclared<_Account, _Receipt?>(
        'delete', (_Account user, _Receipt? receipt) => user.role == 'admin');
    authorization.registerDeclared<Object?, _Receipt?>(
        'viewAny', (Object? user, _Receipt? receipt) => open);
  });

  setUp(() {
    open = false;
    DVBackendPolicy.decide = null;
  });

  Future<DVPolicyDecision> deciding(Object? caller, String action) {
    Future<DVPolicyDecision> ask() =>
        DVBackendPolicy.checkAction(action, '/api/receipts');
    return switch (caller) {
      final DVSessionPrincipal session =>
        DVSessionPrincipal.actingAs(session, ask),
      final DVApiPrincipal key => DVApiPrincipal.actingAs(key, ask),
      _ => ask(),
    };
  }

  test('no caller, and a policy that needs one, is unauthenticated', () async {
    expect(await deciding(null, '_Receipt.view'), DVPolicyDecision.unauthenticated);
    expect(await deciding(null, '_Receipt.delete'),
        DVPolicyDecision.unauthenticated);
  });

  test('a policy that can answer without a caller answers', () async {
    expect(await deciding(null, '_Receipt.viewAny'), DVPolicyDecision.forbidden,
        reason: 'it took no caller and said no: signing in is not the answer');
    open = true;
    expect(await deciding(null, '_Receipt.viewAny'), DVPolicyDecision.allowed);
  });

  test('a signed-in person the policy refuses is forbidden', () async {
    expect(await deciding(_signedIn(const _Account('viewer')), '_Receipt.delete'),
        DVPolicyDecision.forbidden);
    expect(await deciding(_signedIn(const _Account('admin')), '_Receipt.delete'),
        DVPolicyDecision.allowed);
  });

  test('a session with no user the policy can take is forbidden, not asked to '
      'sign in again', () async {
    expect(await deciding(_signedIn(null), '_Receipt.view'),
        DVPolicyDecision.forbidden);
  });

  test('an API key the policy cannot take is forbidden', () async {
    final DVApiPrincipal key = DVApiPrincipal(
      kind: DVApiPrincipalKind.apiKey,
      subject: 'key-1',
      tenant: 'acme',
      scopes: <String>{'receipts:read'},
      actions: <String>{'_Receipt.view'},
    );
    expect(await deciding(key, '_Receipt.view'), DVPolicyDecision.forbidden);
  });

  test('an action nothing registered is forbidden whoever asks', () async {
    expect(await deciding(null, '_Receipt.export'), DVPolicyDecision.forbidden);
  });

  test('decide answers for the route, and its no is a 403', () async {
    DVBackendPolicy.decide = (String policy, String path) async => false;
    expect(await deciding(null, '_Receipt.view'), DVPolicyDecision.forbidden);
    DVBackendPolicy.decide = (String policy, String path) async => true;
    expect(await deciding(null, '_Receipt.view'), DVPolicyDecision.allowed);
  });

  test('allowsAction is checkAction answering allowed', () async {
    expect(await DVBackendPolicy.allowsAction('_Receipt.view', '/api/receipts'),
        isFalse);
    open = true;
    expect(
        await DVBackendPolicy.allowsAction('_Receipt.viewAny', '/api/receipts'),
        isTrue);
  });
}
