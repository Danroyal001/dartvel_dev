// The OAuth 2.1 provider core, against the in-memory adapter and SQLite.
//
// Every guard here fails silently when it is missing: the exchange still
// returns tokens, the token still introspects as active. An authorization
// code that redeems twice, a refresh token that keeps working after rotation,
// PKCE that is optional for a public client, a redirect URI matched by prefix,
// a revoked client whose tokens still work, a token from one tenant accepted
// by another -- each has a test below that fails if its guard is removed.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

final DVApiScopes _scopes = DVApiScopes(
  const <String, List<String>>{
    'orders:read': <String>['Order.view', 'Order.list'],
    'orders:write': <String>['Order.create', 'Order.update'],
    'profile': <String>['User.viewSelf'],
  },
  descriptions: const <String, String>{
    'orders:read': 'See your orders',
    'profile': 'See your name and e-mail address',
  },
);

const String _verifier =
    'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk0123456789abcdefgh';

String _challenge(String verifier) => base64Url
    .encode(crypto.sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

TypeMatcher<DVOAuthError> _oauthError(String error) =>
    isA<DVOAuthError>().having((DVOAuthError e) => e.error, 'error', error);

void main() {
  for (final (String name, DVDatabaseAdapter Function() create) in _adapters) {
    group('OAuth provider on $name', () {
      late DateTime now;
      late DVDatabaseAdapter database;
      late DVOAuthProvider oauth;
      late DVRegisteredOAuthClient web;
      late DVRegisteredOAuthClient mobile;

      const String webRedirect = 'https://partner.example/callback';
      const String mobileRedirect = 'com.partner.app:/oauth';

      setUp(() async {
        now = DateTime.utc(2026, 9, 14, 9);
        database = create();
        oauth = DVOAuthProvider(
          database: database,
          scopes: _scopes,
          clock: () => now,
        );
        await oauth.ensureSchema();
        web = await oauth.registerClient(
          name: 'Partner web',
          redirectUris: const <String>[webRedirect],
          scopes: const <String>['orders:read', 'orders:write', 'profile'],
          actor: 'ops',
        );
        mobile = await oauth.registerClient(
          name: 'Partner app',
          redirectUris: const <String>[mobileRedirect],
          scopes: const <String>['orders:read'],
          public: true,
        );
      });

      Future<DVIssuedAuthorizationCode> authorize({
        DVRegisteredOAuthClient? client,
        String redirectUri = webRedirect,
        List<String> scopes = const <String>['orders:read'],
        String userId = 'ada',
        String tenant = 'acme',
        String verifier = _verifier,
      }) async {
        final DVAuthorizationRequest request = await oauth
            .validateAuthorization(
              clientId: (client ?? web).client.id,
              redirectUri: redirectUri,
              scopes: scopes,
              codeChallenge: _challenge(verifier),
              codeChallengeMethod: 'S256',
              state: 'xyz',
            );
        return oauth.approve(request, userId: userId, tenant: tenant);
      }

      Future<DVOAuthTokenResponse> exchange(
        DVIssuedAuthorizationCode code, {
        DVRegisteredOAuthClient? client,
        String redirectUri = webRedirect,
        String? verifier = _verifier,
      }) {
        final DVRegisteredOAuthClient c = client ?? web;
        return oauth.exchangeCode(
          clientId: c.client.id,
          clientSecret: c.secret,
          code: code.code,
          redirectUri: redirectUri,
          codeVerifier: verifier,
        );
      }

      group('client registration', () {
        test(
          'a confidential client gets a secret once, stored only hashed',
          () async {
            expect(web.secret, isNotNull);
            expect(web.client.isPublic, isFalse);
            expect(mobile.secret, isNull);
            final String dump = <Object?>[
              ...await database.query('SELECT * FROM dv_oauth_clients'),
              ...await database.query(
                'SELECT * FROM dv_oauth_clients__history',
              ),
            ].toString();
            expect(dump, isNot(contains(web.secret!)));
            expect('$web', isNot(contains(web.secret!)));
          },
        );

        test('asking for an undefined scope is refused at registration '
            '(DV-APIKEY-004)', () async {
          await expectLater(
            oauth.registerClient(
              name: 'Greedy',
              redirectUris: const <String>['https://greedy.example/cb'],
              scopes: const <String>['orders:read', 'admin'],
            ),
            throwsA(
              isA<DVUndefinedOAuthScope>()
                  .having(
                    (DVUndefinedOAuthScope e) => e.code,
                    'code',
                    'DV-APIKEY-004',
                  )
                  .having(
                    (DVUndefinedOAuthScope e) => e.scopes,
                    'scopes',
                    <String>['admin'],
                  ),
            ),
          );
        });

        test('a redirect URI must be exact-matchable and not a plain-http '
            'remote', () async {
          for (final String bad in <String>[
            'http://partner.example/callback',
            'https://partner.example/callback#frag',
            '/relative',
            'https://*.partner.example/cb',
          ]) {
            await expectLater(
              oauth.registerClient(
                name: 'Bad',
                redirectUris: <String>[bad],
                scopes: const <String>['orders:read'],
              ),
              throwsArgumentError,
              reason: bad,
            );
          }
          // Loopback over plain http is how a native app receives a code.
          await oauth.registerClient(
            name: 'CLI',
            redirectUris: const <String>['http://127.0.0.1:8123/cb'],
            scopes: const <String>['orders:read'],
            public: true,
          );
        });
      });

      group('authorization request', () {
        test(
          'the consent screen names scopes in the declaration\'s words',
          () async {
            final DVAuthorizationRequest request = await oauth
                .validateAuthorization(
                  clientId: web.client.id,
                  redirectUri: webRedirect,
                  scopes: const <String>['orders:read', 'orders:write'],
                  codeChallenge: _challenge(_verifier),
                  codeChallengeMethod: 'S256',
                );
            expect(oauth.describe(request), <(String, String)>[
              ('orders:read', 'See your orders'),
              ('orders:write', 'orders:write'),
            ]);
          },
        );

        test('a redirect URI is matched exactly, never by prefix', () async {
          for (final String near in <String>[
            '$webRedirect/evil',
            '${webRedirect}x',
            '$webRedirect?next=https://evil.example',
            'https://partner.example/Callback',
            'https://partner.example/callback/',
            'https://partner.example.evil.example/callback',
          ]) {
            await expectLater(
              oauth.validateAuthorization(
                clientId: web.client.id,
                redirectUri: near,
                scopes: const <String>['orders:read'],
                codeChallenge: _challenge(_verifier),
                codeChallengeMethod: 'S256',
              ),
              throwsA(
                _oauthError('invalid_request').having(
                  (DVOAuthError e) => e.redirectable,
                  'redirectable',
                  isFalse,
                ),
              ),
              reason: near,
            );
          }
        });

        test(
          'PKCE is required, for public and confidential clients alike',
          () async {
            for (final DVRegisteredOAuthClient client
                in <DVRegisteredOAuthClient>[mobile, web]) {
              await expectLater(
                oauth.validateAuthorization(
                  clientId: client.client.id,
                  redirectUri: client.client.redirectUris.single,
                  scopes: const <String>['orders:read'],
                ),
                throwsA(_oauthError('invalid_request')),
              );
            }
          },
        );

        test('the plain PKCE method is refused', () async {
          await expectLater(
            oauth.validateAuthorization(
              clientId: mobile.client.id,
              redirectUri: mobileRedirect,
              scopes: const <String>['orders:read'],
              // Well-formed, so only the method can be why it is refused.
              codeChallenge: _challenge(_verifier),
              codeChallengeMethod: 'plain',
            ),
            throwsA(_oauthError('invalid_request')),
          );
        });

        test('a scope the client did not register is invalid_scope', () async {
          await expectLater(
            oauth.validateAuthorization(
              clientId: mobile.client.id,
              redirectUri: mobileRedirect,
              scopes: const <String>['orders:write'],
              codeChallenge: _challenge(_verifier),
              codeChallengeMethod: 'S256',
            ),
            throwsA(_oauthError('invalid_scope')),
          );
          await expectLater(
            oauth.validateAuthorization(
              clientId: mobile.client.id,
              redirectUri: mobileRedirect,
              scopes: const <String>['orders'],
              codeChallenge: _challenge(_verifier),
              codeChallengeMethod: 'S256',
            ),
            throwsA(_oauthError('invalid_scope')),
          );
        });

        test('approval redirects with the code and the state', () async {
          final DVIssuedAuthorizationCode code = await authorize();
          expect(code.redirect.toString(), startsWith('$webRedirect?'));
          expect(code.redirect.queryParameters['code'], code.code);
          expect(code.redirect.queryParameters['state'], 'xyz');
          expect('$code', isNot(contains(code.code)));
        });

        test(
          'approval records consent, and a covered request needs none',
          () async {
            final DVAuthorizationRequest request = await oauth
                .validateAuthorization(
                  clientId: web.client.id,
                  redirectUri: webRedirect,
                  scopes: const <String>['orders:read'],
                  codeChallenge: _challenge(_verifier),
                  codeChallengeMethod: 'S256',
                );
            expect(
              await oauth.needsConsent(request, userId: 'ada', tenant: 'acme'),
              isTrue,
            );
            await oauth.approve(request, userId: 'ada', tenant: 'acme');
            expect(
              await oauth.needsConsent(request, userId: 'ada', tenant: 'acme'),
              isFalse,
            );
            // Consent in one tenant is not consent in another.
            expect(
              await oauth.needsConsent(
                request,
                userId: 'ada',
                tenant: 'globex',
              ),
              isTrue,
            );
            final DVOAuthConsent consent = (await oauth.consents(
              'ada',
              tenant: 'acme',
            )).single;
            expect(consent.clientId, web.client.id);
            expect(consent.scopes, <String>['orders:read']);
          },
        );
      });

      group('authorization code', () {
        test(
          'exchanges once for tokens that authenticate as the person',
          () async {
            final DVOAuthTokenResponse tokens = await exchange(
              await authorize(),
            );
            expect(tokens.tokenType, 'Bearer');
            expect(tokens.scopes, <String>['orders:read']);
            expect(tokens.refreshToken, isNotNull);
            final DVApiPrincipal principal = (await oauth.authenticate(
              tokens.accessToken,
            ))!;
            expect(principal.kind, DVApiPrincipalKind.oauthUser);
            expect(principal.subject, 'ada');
            expect(principal.clientId, web.client.id);
            expect(principal.tenant, 'acme');
            expect(principal.permits('Order.view'), isTrue);
            expect(principal.permits('Order.create'), isFalse);
            expect(tokens.toJson()['token_type'], 'Bearer');
            expect('$tokens', isNot(contains(tokens.accessToken)));
          },
        );

        test(
          'a code used twice fails, and revokes what the first use issued',
          () async {
            final DVIssuedAuthorizationCode code = await authorize();
            final DVOAuthTokenResponse first = await exchange(code);
            await expectLater(
              exchange(code),
              throwsA(_oauthError('invalid_grant')),
            );
            expect(await oauth.authenticate(first.accessToken), isNull);
            await expectLater(
              oauth.refresh(
                clientId: web.client.id,
                clientSecret: web.secret,
                refreshToken: first.refreshToken!,
              ),
              throwsA(_oauthError('invalid_grant')),
            );
          },
        );

        test(
          'two exchanges of one code racing give tokens to at most one',
          () async {
            // Both exchanges read the code before either spends it, so the
            // `used_at` check alone cannot tell them apart and only the
            // versioned write can. Without the gate the second exchange
            // reads after the first has written, and this proves nothing.
            final _GatedCodeReads gated = _GatedCodeReads(database);
            oauth = DVOAuthProvider(
              database: gated,
              scopes: _scopes,
              clock: () => now,
            );
            final DVIssuedAuthorizationCode code = await authorize();
            gated.arm(2);
            final List<Object> outcomes = await Future.wait(<Future<Object>>[
              for (int i = 0; i < 2; i++)
                exchange(code).then<Object>(
                  (DVOAuthTokenResponse t) => t,
                  onError: (Object e) => e,
                ),
            ]);
            expect(
              outcomes.whereType<DVOAuthTokenResponse>().length,
              lessThanOrEqualTo(1),
            );
            expect(outcomes.whereType<DVOAuthError>(), isNotEmpty);
          },
        );

        test('nothing stored holds a code or a token', () async {
          final DVIssuedAuthorizationCode code = await authorize();
          final DVOAuthTokenResponse tokens = await exchange(code);
          final List<Object?> rows = <Object?>[];
          for (final String table in <String>[
            'dv_oauth_codes',
            'dv_oauth_tokens',
            'dv_oauth_grants',
            'dv_oauth_grants__history',
          ]) {
            rows.addAll(await database.query('SELECT * FROM $table'));
          }
          final String dump = '$rows';
          expect(dump, isNot(contains(code.code)));
          expect(dump, isNot(contains(tokens.accessToken)));
          expect(dump, isNot(contains(tokens.refreshToken!)));
        });

        test(
          'the exchange needs the verifier that matches the challenge',
          () async {
            await expectLater(
              exchange(await authorize(), verifier: null),
              throwsA(_oauthError('invalid_grant')),
            );
            await expectLater(
              exchange(
                await authorize(),
                verifier: '${_verifier.substring(1)}X',
              ),
              throwsA(_oauthError('invalid_grant')),
            );
            // A public client too: PKCE is its only proof.
            final DVIssuedAuthorizationCode code = await authorize(
              client: mobile,
              redirectUri: mobileRedirect,
            );
            await expectLater(
              exchange(
                code,
                client: mobile,
                redirectUri: mobileRedirect,
                verifier: null,
              ),
              throwsA(_oauthError('invalid_grant')),
            );
          },
        );

        test('a failed verifier still spends the code', () async {
          final DVIssuedAuthorizationCode code = await authorize();
          await expectLater(
            exchange(code, verifier: 'x' * 43),
            throwsA(_oauthError('invalid_grant')),
          );
          await expectLater(
            exchange(code),
            throwsA(_oauthError('invalid_grant')),
          );
        });

        test('the exchange must repeat the redirect URI exactly', () async {
          await expectLater(
            exchange(await authorize(), redirectUri: '$webRedirect/'),
            throwsA(_oauthError('invalid_grant')),
          );
        });

        test('a code is bound to the client it was issued to', () async {
          final DVRegisteredOAuthClient other = await oauth.registerClient(
            name: 'Other',
            redirectUris: const <String>[webRedirect],
            scopes: const <String>['orders:read'],
          );
          await expectLater(
            exchange(await authorize(), client: other),
            throwsA(_oauthError('invalid_grant')),
          );
        });

        test('a confidential client must present its secret', () async {
          final DVIssuedAuthorizationCode code = await authorize();
          await expectLater(
            oauth.exchangeCode(
              clientId: web.client.id,
              clientSecret: null,
              code: code.code,
              redirectUri: webRedirect,
              codeVerifier: _verifier,
            ),
            throwsA(_oauthError('invalid_client')),
          );
          await expectLater(
            oauth.exchangeCode(
              clientId: web.client.id,
              clientSecret: '${web.secret!}x',
              code: (await authorize()).code,
              redirectUri: webRedirect,
              codeVerifier: _verifier,
            ),
            throwsA(_oauthError('invalid_client')),
          );
        });

        test('an expired code is refused', () async {
          final DVIssuedAuthorizationCode code = await authorize();
          now = now.add(oauth.codeLifetime);
          await expectLater(
            exchange(code),
            throwsA(_oauthError('invalid_grant')),
          );
        });
      });

      group('refresh tokens', () {
        late DVOAuthTokenResponse tokens;

        setUp(() async {
          tokens = await exchange(
            await authorize(scopes: const <String>['orders:read', 'profile']),
          );
        });

        Future<DVOAuthTokenResponse> refresh(
          String token, {
          List<String>? scopes,
        }) => oauth.refresh(
          clientId: web.client.id,
          clientSecret: web.secret,
          refreshToken: token,
          scopes: scopes,
        );

        test('a refresh rotates the refresh token', () async {
          final DVOAuthTokenResponse next = await refresh(tokens.refreshToken!);
          expect(next.refreshToken, isNot(tokens.refreshToken));
          expect(await oauth.authenticate(next.accessToken), isNotNull);
          expect((await refresh(next.refreshToken!)).accessToken, isNotEmpty);
        });

        test(
          'a rotated refresh token presented again revokes the whole family',
          () async {
            final DVOAuthTokenResponse next = await refresh(
              tokens.refreshToken!,
            );
            await expectLater(
              refresh(tokens.refreshToken!),
              throwsA(_oauthError('invalid_grant')),
            );
            // Whoever held the newer tokens -- the legitimate client or the
            // thief -- is signed out too, because nobody can tell which it is.
            expect(await oauth.authenticate(next.accessToken), isNull);
            expect(await oauth.authenticate(tokens.accessToken), isNull);
            await expectLater(
              refresh(next.refreshToken!),
              throwsA(_oauthError('invalid_grant')),
            );
          },
        );

        test('a refresh can narrow scopes and never widen them', () async {
          final DVOAuthTokenResponse narrow = await refresh(
            tokens.refreshToken!,
            scopes: <String>['profile'],
          );
          expect(narrow.scopes, <String>['profile']);
          await expectLater(
            refresh(
              narrow.refreshToken!,
              scopes: <String>['profile', 'orders:write'],
            ),
            throwsA(_oauthError('invalid_scope')),
          );
        });

        test('an access token is not a refresh token', () async {
          await expectLater(
            refresh(tokens.accessToken),
            throwsA(_oauthError('invalid_grant')),
          );
        });

        test('a refresh token is bound to its client', () async {
          final DVRegisteredOAuthClient other = await oauth.registerClient(
            name: 'Other',
            redirectUris: const <String>[webRedirect],
            scopes: const <String>['orders:read', 'profile'],
          );
          await expectLater(
            oauth.refresh(
              clientId: other.client.id,
              clientSecret: other.secret,
              refreshToken: tokens.refreshToken!,
            ),
            throwsA(_oauthError('invalid_grant')),
          );
          // And the attempt did not spend the token for its real client.
          expect((await refresh(tokens.refreshToken!)).accessToken, isNotEmpty);
        });
      });

      group('introspection, revocation and tenants', () {
        late DVOAuthTokenResponse tokens;

        setUp(() async {
          tokens = await exchange(await authorize());
        });

        test('introspection answers in RFC 7662\'s shape', () async {
          final DVOAuthIntrospection active = await oauth.introspect(
            tokens.accessToken,
          );
          expect(active.toJson(), <String, Object?>{
            'active': true,
            'scope': 'orders:read',
            'client_id': web.client.id,
            'sub': 'ada',
            'token_type': 'access_token',
            'exp':
                now.add(oauth.accessTokenLifetime).millisecondsSinceEpoch ~/
                1000,
            'tenant': 'acme',
          });
          expect(
            (await oauth.introspect('dvat_nonsense')).toJson(),
            <String, Object?>{'active': false},
          );
        });

        test('an access token expires', () async {
          now = now.add(oauth.accessTokenLifetime);
          expect(await oauth.authenticate(tokens.accessToken), isNull);
        });

        test('a token is refused by another tenant\'s request', () async {
          expect(
            await oauth.authenticate(tokens.accessToken, tenant: 'globex'),
            isNull,
          );
          expect(
            (await oauth.introspect(
              tokens.accessToken,
              tenant: 'globex',
            )).active,
            isFalse,
          );
          expect(
            await const DVTenants().withTenant(
              'globex',
              () => oauth.authenticate(tokens.accessToken),
            ),
            isNull,
          );
          expect(
            await const DVTenants().withTenant(
              'acme',
              () => oauth.authenticate(tokens.accessToken),
            ),
            isNotNull,
          );
        });

        test('revoking a refresh token ends the family', () async {
          await oauth.revokeToken(
            tokens.refreshToken!,
            clientId: web.client.id,
            clientSecret: web.secret,
          );
          expect(await oauth.authenticate(tokens.accessToken), isNull);
        });

        test('revoking an access token ends only that token', () async {
          await oauth.revokeToken(
            tokens.accessToken,
            clientId: web.client.id,
            clientSecret: web.secret,
          );
          expect(await oauth.authenticate(tokens.accessToken), isNull);
          final DVOAuthTokenResponse next = await oauth.refresh(
            clientId: web.client.id,
            clientSecret: web.secret,
            refreshToken: tokens.refreshToken!,
          );
          expect(await oauth.authenticate(next.accessToken), isNotNull);
        });

        test('one client cannot revoke another client\'s tokens', () async {
          final DVRegisteredOAuthClient other = await oauth.registerClient(
            name: 'Other',
            redirectUris: const <String>[webRedirect],
            scopes: const <String>['orders:read'],
          );
          await oauth.revokeToken(
            tokens.accessToken,
            clientId: other.client.id,
            clientSecret: other.secret,
          );
          expect(await oauth.authenticate(tokens.accessToken), isNotNull);
        });

        test(
          'a revoked client\'s tokens stop, and it cannot get more',
          () async {
            await oauth.revokeClient(web.client.id, actor: 'ops');
            expect(await oauth.authenticate(tokens.accessToken), isNull);
            await expectLater(
              oauth.refresh(
                clientId: web.client.id,
                clientSecret: web.secret,
                refreshToken: tokens.refreshToken!,
              ),
              throwsA(_oauthError('invalid_client')),
            );
            await expectLater(
              oauth.validateAuthorization(
                clientId: web.client.id,
                redirectUri: webRedirect,
                scopes: const <String>['orders:read'],
                codeChallenge: _challenge(_verifier),
                codeChallengeMethod: 'S256',
              ),
              throwsA(_oauthError('invalid_client')),
            );
          },
        );

        test('withdrawing consent ends the tokens it allowed', () async {
          await oauth.revokeConsent('ada', web.client.id, tenant: 'acme');
          expect(await oauth.authenticate(tokens.accessToken), isNull);
          await expectLater(
            oauth.refresh(
              clientId: web.client.id,
              clientSecret: web.secret,
              refreshToken: tokens.refreshToken!,
            ),
            throwsA(_oauthError('invalid_grant')),
          );
          expect(await oauth.consents('ada', tenant: 'acme'), isEmpty);
        });

        test(
          'an OAuth principal is scope-limited in DV.Auth.authorization',
          () async {
            const DVAuthAuthorization authorization = DVAuthAuthorization();
            const DVTestHarness().resetPolicies();
            addTearDown(() => const DVTestHarness().resetPolicies());
            authorization.register<Object?, _Order>('create', (_, __) => true);
            final DVApiPrincipal principal = (await oauth.authenticate(
              tokens.accessToken,
            ))!;
            expect(
              await authorization.can<Object?, _Order>(
                principal,
                'create',
                const _Order(),
              ),
              isFalse,
            );
          },
        );
      });

      group('client credentials are an API key with a grant', () {
        late DVApiKeys keys;
        late DVIssuedApiKey key;

        setUp(() async {
          keys = DVApiKeys(
            database: database,
            scopes: _scopes,
            clock: () => now,
          );
          await keys.ensureSchema();
          oauth = DVOAuthProvider(
            database: database,
            scopes: _scopes,
            apiKeys: keys,
            clock: () => now,
          );
          key = await keys.issue(
            tenant: 'acme',
            scopes: const <String>['orders:read', 'orders:write'],
          );
        });

        test(
          'the key\'s id and secret get a token with the key\'s scopes',
          () async {
            final DVOAuthTokenResponse tokens = await oauth.clientCredentials(
              clientId: key.key.prefix,
              clientSecret: key.secret,
              scopes: const <String>['orders:read'],
            );
            expect(tokens.refreshToken, isNull);
            final DVApiPrincipal principal = (await oauth.authenticate(
              tokens.accessToken,
            ))!;
            expect(principal.kind, DVApiPrincipalKind.oauthClient);
            expect(principal.subject, key.key.id);
            expect(principal.tenant, 'acme');
            expect(principal.scopes, <String>{'orders:read'});
          },
        );

        test('it cannot widen past the key\'s scopes', () async {
          await expectLater(
            oauth.clientCredentials(
              clientId: key.key.prefix,
              clientSecret: key.secret,
              scopes: const <String>['profile'],
            ),
            throwsA(_oauthError('invalid_scope')),
          );
        });

        test('the id must be the key\'s own', () async {
          final DVIssuedApiKey other = await keys.issue(
            tenant: 'acme',
            scopes: const <String>['orders:read'],
          );
          await expectLater(
            oauth.clientCredentials(
              clientId: other.key.prefix,
              clientSecret: key.secret,
            ),
            throwsA(_oauthError('invalid_client')),
          );
        });

        test(
          'revoking the key stops the tokens it was exchanged for',
          () async {
            final DVOAuthTokenResponse tokens = await oauth.clientCredentials(
              clientId: key.key.prefix,
              clientSecret: key.secret,
            );
            await keys.revoke(key.key.id);
            expect(await oauth.authenticate(tokens.accessToken), isNull);
            await expectLater(
              oauth.clientCredentials(
                clientId: key.key.prefix,
                clientSecret: key.secret,
              ),
              throwsA(_oauthError('invalid_client')),
            );
          },
        );
      });
    });
  }
}

class _Order {
  const _Order();
}

/// Holds the next [arm]ed reads of `dv_oauth_codes` until all of them have
/// arrived, so concurrent callers see the same row before any writes it.
class _GatedCodeReads implements DVDatabaseAdapter {
  _GatedCodeReads(this.inner);

  final DVDatabaseAdapter inner;
  int _waiting = 0;
  Completer<void>? _gate;

  void arm(int readers) {
    _waiting = readers;
    _gate = Completer<void>();
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final Completer<void>? gate = _gate;
    if (gate != null && _waiting > 0 && sql.contains('FROM dv_oauth_codes')) {
      final List<Map<String, Object?>> rows = await inner.query(sql, params);
      if (--_waiting == 0) {
        _gate = null;
        gate.complete();
      }
      await gate.future;
      return rows;
    }
    return inner.query(sql, params);
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) =>
      inner.execute(sql, params);
}
