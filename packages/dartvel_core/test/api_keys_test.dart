// API keys and scopes, against the adapters Dartvel runs on without a network:
// the in-memory adapter and SQLite.
//
// The failures worth the effort are the silent ones. A key stored in clear
// still authenticates, so nothing notices until the database leaks. A scope
// matched on a prefix grants `orders:read` to whoever holds `orders`. A
// revoked key that is still accepted looks exactly like a working key. A key
// issued for one tenant that another tenant's request accepts reads the wrong
// customer's data with a valid credential. Each has a test below that fails
// if its guard is removed.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

class Order {
  const Order();
}

final DVApiScopes _scopes = DVApiScopes(const <String, List<String>>{
  'orders:read': <String>['Order.view', 'Order.list'],
  'orders:write': <String>['Order.create', 'Order.update'],
  'orders': <String>['Order.delete'],
});

void main() {
  group('DVApiScopes', () {
    test('a scope grants exactly the policy actions it names', () {
      expect(
        _scopes.covers(const <String>['orders:read'], 'Order.view'),
        isTrue,
      );
      expect(
        _scopes.covers(const <String>['orders:read'], 'Order.create'),
        isFalse,
      );
    });

    test('a scope name is matched whole, never as a prefix', () {
      // `orders` is a declared scope of its own; holding it must not grant
      // what `orders:read` grants, and a made-up `orders:read:extra` must
      // not grant anything.
      expect(_scopes.covers(const <String>['orders'], 'Order.view'), isFalse);
      expect(
        _scopes.covers(const <String>['orders:read:extra'], 'Order.view'),
        isFalse,
      );
      expect(
        _scopes.covers(const <String>['orders:rea'], 'Order.view'),
        isFalse,
      );
      // An action is matched whole too.
      expect(
        _scopes.covers(const <String>['orders:read'], 'Order.vie'),
        isFalse,
      );
      expect(
        _scopes.covers(const <String>['orders:read'], 'Order.viewAll'),
        isFalse,
      );
    });

    test('reads the pubspec shape under dartvel.platformApi', () {
      final DVApiScopes scopes = DVApiScopes.fromConfig(<String, Object?>{
        'scopes': <String, Object?>{
          'profile': <Object?>['User.viewSelf'],
        },
      });
      expect(scopes.names, <String>{'profile'});
      expect(scopes.covers(const <String>['profile'], 'User.viewSelf'), isTrue);
    });

    test('a scope naming an action no policy defines is DV-APIKEY-001', () {
      final Set<String> registered = <String>{
        'view:Order',
        'list:Order',
        'create:Order',
        'update:Order',
      };
      expect(
        () => _scopes.validateAgainst(registered),
        throwsA(
          isA<DVUndefinedScopeAction>()
              .having(
                (DVUndefinedScopeAction e) => e.code,
                'code',
                'DV-APIKEY-001',
              )
              .having(
                (DVUndefinedScopeAction e) => e.missing,
                'missing',
                <String, Set<String>>{
                  'orders': <String>{'Order.delete'},
                },
              ),
        ),
      );
      _scopes.validateAgainst(<String>{...registered, 'delete:Order'});
    });

    test('an action is Resource.action, nothing looser', () {
      expect(
        () => DVApiScopes(const <String, List<String>>{
          'bad': <String>['view'],
        }),
        throwsArgumentError,
      );
    });
  });

  group('scopes in DV.Auth.authorization', () {
    // What `DV.Auth.authorization` returns; DV.Auth itself lives in
    // dartvel_flutter.
    const ({DVAuthAuthorization authorization}) auth = (
      authorization: DVAuthAuthorization(),
    );

    setUp(() {
      const DVTestHarness().resetPolicies();
      auth.authorization.register<Object?, Order>('view', (_, __) => true);
      auth.authorization.register<Object?, Order>('create', (_, __) => true);
    });

    tearDown(() => const DVTestHarness().resetPolicies());

    DVApiPrincipal principal(List<String> scopes) => DVApiPrincipal(
      kind: DVApiPrincipalKind.apiKey,
      subject: 'key_1',
      tenant: 'acme',
      organizationId: 'org_1',
      scopes: scopes.toSet(),
      actions: _scopes.actionsOf(scopes),
    );

    test(
      'a call inside the scopes reaches the policy and is decided by it',
      () async {
        expect(
          await auth.authorization.can<Object?, Order>(
            principal(<String>['orders:read']),
            'view',
            const Order(),
          ),
          isTrue,
        );
      },
    );

    test('a call outside the scopes is refused even where the policy allows '
        'it (DV-APIKEY-002)', () async {
      final DVApiPrincipal reader = principal(<String>['orders:read']);
      expect(
        await auth.authorization.can<Object?, Order>(
          reader,
          'create',
          const Order(),
        ),
        isFalse,
      );
      await expectLater(
        auth.authorization.authorize<Object?, Order>(
          reader,
          'create',
          const Order(),
        ),
        throwsA(
          isA<DVApiScopeRefused>()
              .having((DVApiScopeRefused e) => e.code, 'code', 'DV-APIKEY-002')
              .having(
                (DVApiScopeRefused e) => e.action,
                'action',
                'Order.create',
              ),
        ),
      );
    });

    test('a scope does not grant an action its policy denies', () async {
      auth.authorization.register<Object?, Order>('update', (_, __) => false);
      expect(
        await auth.authorization.can<Object?, Order>(
          principal(<String>['orders:write']),
          'update',
          const Order(),
        ),
        isFalse,
      );
    });

    test('a person signed in as themselves is not scope-limited', () async {
      expect(
        await auth.authorization.can<Object?, Order>(
          'ada',
          'create',
          const Order(),
        ),
        isTrue,
      );
    });
  });

  for (final (String name, DVDatabaseAdapter Function() create) in _adapters) {
    group('API keys on $name', () {
      late DateTime now;
      late DVDatabaseAdapter database;
      late DVOrganizations orgs;
      late DVOrganization acme;
      late DVOrganization globex;
      late DVApiKeys keys;

      DVApiKeys build({bool requireExpiry = false, DVLogger? logger}) =>
          DVApiKeys(
            database: database,
            scopes: _scopes,
            organizations: orgs,
            requireExpiry: requireExpiry,
            clock: () => now,
            logger: logger,
          );

      setUp(() async {
        now = DateTime.utc(2026, 9, 14, 9);
        database = create();
        orgs = DVOrganizations(database: database, clock: () => now);
        await orgs.ensureSchema();
        acme = await orgs.create(name: 'Acme', tenant: 'acme', ownerId: 'ada');
        globex = await orgs.create(
          name: 'Globex',
          tenant: 'globex',
          ownerId: 'hank',
        );
        keys = build();
        await keys.ensureSchema();
      });

      Future<List<Map<String, Object?>>> everyRow() async =>
          <Map<String, Object?>>[
            ...await database.query('SELECT * FROM dv_api_keys'),
            ...await database.query('SELECT * FROM dv_api_keys__history'),
          ];

      group('issue', () {
        test(
          'the secret is shown once and authenticates as the organization',
          () async {
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
              expiresIn: const Duration(days: 90),
              actor: 'ada',
            );
            expect(issued.secret, startsWith('dvk_${issued.key.id}_'));
            expect(issued.key.expiresAt, now.add(const Duration(days: 90)));

            final DVApiPrincipal? principal = await keys.authenticate(
              issued.secret,
            );
            expect(principal, isNotNull);
            expect(principal!.kind, DVApiPrincipalKind.apiKey);
            expect(principal.subject, issued.key.id);
            expect(principal.organizationId, acme.id);
            expect(principal.tenant, 'acme');
            expect(principal.scopes, <String>{'orders:read'});
            expect(principal.permits('Order.view'), isTrue);
            expect(principal.permits('Order.create'), isFalse);
          },
        );

        test('neither the table nor its history holds the secret', () async {
          final DVIssuedApiKey issued = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
            actor: 'ada',
          );
          final String secretPart = issued.secret.substring(
            'dvk_${issued.key.id}_'.length,
          );
          final String dump = '${await everyRow()}';
          expect(dump, isNot(contains(secretPart)));
          expect(dump, isNot(contains(issued.secret)));
          // The identifying prefix is there in clear, so support can tell
          // which key somebody means.
          expect(dump, contains(issued.key.id));
        });

        test('the history records the hash changed, never the hash', () async {
          final DVIssuedApiKey issued = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
            actor: 'ada',
          );
          final Map<String, Object?> row = (await database.query(
            'SELECT * FROM dv_api_keys WHERE id = ?',
            <Object?>[issued.key.id],
          )).single;
          final String hash = '${row['secret_hash']}';
          expect(hash, isNotEmpty);
          final String history =
              '${await database.query('SELECT * FROM dv_api_keys__history')}';
          expect(history, isNot(contains(hash)));
        });

        test(
          'nothing printed about an issued key carries the secret',
          () async {
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
            );
            expect('$issued', isNot(contains(issued.secret)));
            expect('${issued.key}', isNot(contains(issued.secret)));
          },
        );

        test('two keys never share a secret or an id', () async {
          final DVIssuedApiKey a = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
          );
          final DVIssuedApiKey b = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
          );
          expect(a.key.id, isNot(b.key.id));
          expect(a.secret, isNot(b.secret));
        });

        test('an undeclared scope is refused at issue', () async {
          await expectLater(
            keys.issue(
              organization: acme,
              scopes: const <String>['orders:admin'],
            ),
            throwsA(isA<DVUndeclaredApiScope>()),
          );
          expect(await database.query('SELECT * FROM dv_api_keys'), isEmpty);
        });

        test('a key is not issued on a closed organization', () async {
          await orgs.close(acme.id, actor: 'ada');
          final DVOrganization closed = (await orgs.find(acme.id))!;
          await expectLater(
            keys.issue(
              organization: closed,
              scopes: const <String>['orders:read'],
            ),
            throwsA(isA<DVOrganizationClosed>()),
          );
        });

        test(
          'no expiry where the configuration requires one is DV-APIKEY-005',
          () async {
            final _Sink sink = _Sink();
            final List<DVLogRecord> logged = sink.records;
            keys = build(
              requireExpiry: true,
              logger: DVLogger(sinks: <DVLogSink>[sink]),
            );
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
            );
            expect(issued.codes, <String>['DV-APIKEY-005']);
            expect(
              logged.map((DVLogRecord r) => r.message).join(),
              contains('DV-APIKEY-005'),
            );
            expect(
              logged.map((DVLogRecord r) => '$r').join(),
              isNot(contains(issued.secret)),
            );

            final DVIssuedApiKey expiring = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
              expiresIn: const Duration(days: 30),
            );
            expect(expiring.codes, isEmpty);
          },
        );
      });

      group('authenticate', () {
        late DVIssuedApiKey issued;

        setUp(() async {
          issued = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
            expiresIn: const Duration(days: 90),
            actor: 'ada',
          );
        });

        String flipLast(String value) {
          final String last = value[value.length - 1];
          return value.substring(0, value.length - 1) +
              (last == 'A' ? 'B' : 'A');
        }

        test(
          'a key with the right id and the wrong secret is refused',
          () async {
            final DVApiKeyCheck check = await keys.check(
              flipLast(issued.secret),
            );
            expect(check.principal, isNull);
            expect(check.failure, DVApiKeyFailure.invalid);
          },
        );

        test('a truncated or extended key is refused', () async {
          final String s = issued.secret;
          expect(await keys.authenticate(s.substring(0, s.length - 1)), isNull);
          expect(await keys.authenticate('${s}A'), isNull);
          expect(await keys.authenticate('dvk_${issued.key.id}_'), isNull);
          expect(await keys.authenticate('dvk_${issued.key.id}'), isNull);
          expect(await keys.authenticate(''), isNull);
          expect(await keys.authenticate('Bearer $s'), isNull);
        });

        test(
          'the stored hash is compared in constant time over its length',
          () async {
            DVSecretHash.debugLastCompared = 0;
            await keys.check(flipLast(issued.secret));
            // A comparison that stops at the first differing character leaks,
            // through its timing, how much of a guess was right.
            expect(DVSecretHash.debugLastCompared, 64);
          },
        );

        test('a revoked key is refused on the very next call', () async {
          await keys.revoke(issued.key.id, actor: 'ada');
          final DVApiKeyCheck check = await keys.check(issued.secret);
          expect(check.principal, isNull);
          expect(check.failure, DVApiKeyFailure.revoked);
          // Coarse at the boundary: a caller is not told which it was.
          expect(check.reveal, 'Invalid API key.');
        });

        test('an expired key is refused', () async {
          now = now.add(const Duration(days: 90));
          expect(
            (await keys.check(issued.secret)).failure,
            DVApiKeyFailure.expired,
          );
        });

        test('a key is refused by another tenant\'s request', () async {
          expect(
            await keys.authenticate(issued.secret, tenant: 'globex'),
            isNull,
          );
          expect(
            (await keys.check(issued.secret, tenant: 'globex')).failure,
            DVApiKeyFailure.wrongTenant,
          );
          // The same refusal when the request's tenant was resolved into the
          // zone rather than passed.
          final DVApiPrincipal? scoped = await const DVTenants().withTenant(
            'globex',
            () => keys.authenticate(issued.secret),
          );
          expect(scoped, isNull);
          expect(
            await const DVTenants().withTenant(
              'acme',
              () => keys.authenticate(issued.secret),
            ),
            isNotNull,
          );
        });

        test('the principal runs its work on its own tenant', () async {
          final DVApiPrincipal principal = (await keys.authenticate(
            issued.secret,
          ))!;
          expect(
            await principal.run(() async => const DVTenants().currentTenant),
            'acme',
          );
        });

        test('a key stops working when its organization closes', () async {
          await orgs.close(acme.id, actor: 'ada');
          expect(
            (await keys.check(issued.secret)).failure,
            DVApiKeyFailure.organizationClosed,
          );
        });

        test('keys of two organizations stay apart', () async {
          final DVIssuedApiKey theirs = await keys.issue(
            organization: globex,
            scopes: const <String>['orders:write'],
          );
          expect((await keys.authenticate(theirs.secret))!.tenant, 'globex');
          expect(
            (await keys.forOrganization(acme.id)).map((DVApiKey k) => k.id),
            <String>[issued.key.id],
          );
        });
      });

      group('rotate and revoke', () {
        late DVIssuedApiKey old;

        setUp(() async {
          old = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read', 'orders:write'],
            expiresIn: const Duration(days: 90),
            actor: 'ada',
          );
        });

        test('rotation leaves both keys live until the overlap ends', () async {
          final DVIssuedApiKey next = await keys.rotate(
            old.key.id,
            overlap: const Duration(days: 7),
            actor: 'ada',
          );
          expect(next.key.id, isNot(old.key.id));
          expect(next.key.scopes, old.key.scopes);
          expect(next.key.rotatedFrom, old.key.id);
          expect(await keys.authenticate(old.secret), isNotNull);
          expect(await keys.authenticate(next.secret), isNotNull);

          now = now.add(const Duration(days: 7));
          final DVApiKeyCheck check = await keys.check(old.secret);
          expect(check.failure, DVApiKeyFailure.expired);
          expect(check.code, 'DV-APIKEY-003');
          expect(await keys.authenticate(next.secret), isNotNull);
        });

        test(
          'rotation never extends the old key past its own expiry',
          () async {
            now = now.add(const Duration(days: 88));
            await keys.rotate(old.key.id, overlap: const Duration(days: 7));
            now = now.add(const Duration(days: 2));
            expect(
              (await keys.check(old.secret)).failure,
              DVApiKeyFailure.expired,
            );
          },
        );

        test(
          'an expired key that was never rotated is not DV-APIKEY-003',
          () async {
            now = now.add(const Duration(days: 91));
            expect((await keys.check(old.secret)).code, isNull);
          },
        );

        test('a revoked key cannot be rotated back to life', () async {
          await keys.revoke(old.key.id, actor: 'ada');
          await expectLater(
            keys.rotate(old.key.id),
            throwsA(isA<DVApiKeyNotLive>()),
          );
        });

        test('issue, rotate and revoke are each in the audit trail', () async {
          final DVIssuedApiKey next = await keys.rotate(
            old.key.id,
            actor: 'bob',
          );
          await keys.revoke(next.key.id, actor: 'carol');
          final List<DVHistoryEntry> oldTrail = await keys.audit(old.key.id);
          expect(oldTrail.map((DVHistoryEntry e) => e.actor), <String?>[
            'ada',
            'bob',
          ]);
          expect(
            oldTrail.every((DVHistoryEntry e) => e.tenant == 'acme'),
            isTrue,
          );
          final List<DVHistoryEntry> nextTrail = await keys.audit(next.key.id);
          expect(nextTrail.map((DVHistoryEntry e) => e.actor), <String?>[
            'bob',
            'carol',
          ]);
          expect(nextTrail.last.changes.keys, contains('revoked_at'));
        });
      });

      group('rate plans and usage', () {
        Future<(bool, MiddlewareContext)> call(
          Middleware middleware,
          String credential,
        ) async {
          final MiddlewareContext context = MiddlewareContext();
          await middleware(<String, String>{
            'authorization': credential,
          }, context);
          return (context.shouldContinue, context);
        }

        String? bearer(Object? request) {
          final String? header =
              (request! as Map<String, String>)['authorization'];
          return header != null && header.startsWith('Bearer ')
              ? header.substring('Bearer '.length)
              : null;
        }

        test(
          'the authentication stage puts the principal on the context',
          () async {
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
            );
            final Middleware authenticate = keys.authentication(
              credentialOf: bearer,
            );
            final (bool ok, MiddlewareContext context) = await call(
              authenticate,
              'Bearer ${issued.secret}',
            );
            expect(ok, isTrue);
            expect(
              (context.data[DVApiKeys.principalKey]! as DVApiPrincipal).subject,
              issued.key.id,
            );
            await keys.revoke(issued.key.id);
            expect(
              (await call(authenticate, 'Bearer ${issued.secret}')).$1,
              isFalse,
            );
            expect((await call(authenticate, 'no header')).$1, isFalse);
          },
        );

        test('a key past its rate plan is throttled (DV-APIKEY-006)', () async {
          final DVIssuedApiKey partner = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
            ratePlan: 'starter',
          );
          final DVIssuedApiKey other = await keys.issue(
            organization: acme,
            scopes: const <String>['orders:read'],
            ratePlan: 'starter',
          );
          final Middleware pipeline = _chain(<Middleware>[
            keys.authentication(credentialOf: bearer),
            keys.rateLimit(const <String, DVApiRatePlan>{
              'starter': DVApiRatePlan(
                maxRequests: 2,
                window: Duration(minutes: 1),
              ),
            }),
          ]);
          expect((await call(pipeline, 'Bearer ${partner.secret}')).$1, isTrue);
          expect((await call(pipeline, 'Bearer ${partner.secret}')).$1, isTrue);
          final (bool ok, MiddlewareContext context) = await call(
            pipeline,
            'Bearer ${partner.secret}',
          );
          expect(ok, isFalse);
          expect(context.data['diagnostic'], 'DV-APIKEY-006');
          expect(context.data['rateLimitError'], isNotNull);
          // Each key has its own budget on the same plan.
          expect((await call(pipeline, 'Bearer ${other.secret}')).$1, isTrue);
        });

        test(
          'a key with a plan the application does not declare is refused',
          () async {
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
              ratePlan: 'enterprise',
            );
            final Middleware pipeline = _chain(<Middleware>[
              keys.authentication(credentialOf: bearer),
              keys.rateLimit(const <String, DVApiRatePlan>{}),
            ]);
            expect(
              (await call(pipeline, 'Bearer ${issued.secret}')).$1,
              isFalse,
            );
          },
        );

        test(
          'calls are metered on the key\'s tenant, and a blocked quota stops '
          'the call',
          () async {
            final DVMemoryMeterStore store = DVMemoryMeterStore();
            final DVMeters meters = DVMeters(store: store, clock: () => now);
            final DVMeterDefinition apiCalls = DVMeterDefinition(
              'api_calls',
              unit: 'call',
              limit: const DVLimit.fixed(2),
              atLimit: DVQuota.block,
            );
            final DVIssuedApiKey issued = await keys.issue(
              organization: acme,
              scopes: const <String>['orders:read'],
            );
            int request = 0;
            final Middleware pipeline = _chain(<Middleware>[
              keys.authentication(credentialOf: bearer),
              keys.usage(
                meters: meters,
                meter: apiCalls,
                requestIdOf: (_) => 'req-${request++}',
              ),
            ]);
            expect(
              (await call(pipeline, 'Bearer ${issued.secret}')).$1,
              isTrue,
            );
            expect(
              (await call(pipeline, 'Bearer ${issued.secret}')).$1,
              isTrue,
            );
            expect(
              (await call(pipeline, 'Bearer ${issued.secret}')).$1,
              isFalse,
            );
            final List<DVMeterRecord> records = await store.recordsIn(
              tenant: 'acme',
              meter: 'api_calls',
              period: DVMeterPeriod.calendarMonth(now),
            );
            expect(records, hasLength(2));
            expect(
              records.every(
                (DVMeterRecord r) =>
                    r.idempotencyKey.startsWith('${issued.key.id}:'),
              ),
              isTrue,
            );
          },
        );
      });
    });
  }
}

/// Runs [middleware] in order, stopping at the first that aborts — what
/// [MiddlewareChain] does, as one [Middleware].
Middleware _chain(List<Middleware> middleware) =>
    (Object? request, MiddlewareContext context) async {
      for (final Middleware step in middleware) {
        await step(request, context);
        if (!context.shouldContinue) return;
      }
    };

class _Sink implements DVLogSink {
  final List<DVLogRecord> records = <DVLogRecord>[];

  @override
  void write(DVLogRecord record) => records.add(record);
}
