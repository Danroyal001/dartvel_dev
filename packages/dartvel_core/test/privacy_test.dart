// Data compliance: erasure, export, retention and the evidence each leaves.
//
// Every failure worth a test here is a silent one. An erasure that reports
// success while a soft-deleted row, an old value in a change log, or a
// ciphertext under a key that still exists survives has erased nothing a
// regulator would recognise. An export that forgets a relation, or includes
// somebody else's identifier, is a breach performed in the name of the right
// it serves. A retention sweep that deletes what a longer retention holds is
// the other regulator's problem. A receipt that still verifies after it was
// edited proves nothing. Each has a test below that fails if the behaviour
// quietly regresses.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

final DateTime _now = DateTime.utc(2026, 9, 13, 12);
final List<int> _signingKey = List<int>.generate(32, (int i) => i * 7 % 256);

String _ago(Duration d) => _now.subtract(d).toIso8601String();

/// A subject-access fixture: users, their addresses (reached through the user,
/// who is deleted), their orders (kept seven years for tax), order lines
/// reached through the order, sessions kept thirty days, messages whose body
/// is tombstoned rather than the row deleted, and a lookup table with no
/// personal data at all.
class _Site {
  _Site(this.database)
    : users = DVRecordTable(
        table: 'users',
        key: 'id',
        columns: const <String>['id', 'email', 'national_id', 'created_at'],
        sensitive: const <String>{'national_id'},
        history: const DVHistory(keep: Duration(days: 365)),
        softDelete: true,
        database: database,
      ),
      addresses = DVRecordTable(
        table: 'addresses',
        key: 'id',
        columns: const <String>['id', 'user_ref', 'line1'],
        database: database,
      ),
      orders = DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: const <String>[
          'id',
          'user_id',
          'address',
          'tax_id',
          'total',
          'created_at',
        ],
        sensitive: const <String>{'tax_id'},
        history: const DVHistory(keep: Duration(days: 365)),
        database: database,
      ),
      lines = DVRecordTable(
        table: 'order_lines',
        key: 'id',
        columns: const <String>['id', 'order_id', 'note'],
        database: database,
      ),
      sessions = DVRecordTable(
        table: 'sessions',
        key: 'id',
        columns: const <String>['id', 'user_id', 'ip', 'created_at'],
        database: database,
      ),
      messages = DVRecordTable(
        table: 'messages',
        key: 'id',
        columns: const <String>['id', 'author_id', 'recipient_id', 'body'],
        database: database,
      ),
      currencies = DVRecordTable(
        table: 'currencies',
        key: 'code',
        columns: const <String>['code', 'name'],
        database: database,
      );

  final DVDatabaseAdapter database;
  final DVRecordTable users;
  final DVRecordTable addresses;
  final DVRecordTable orders;
  final DVRecordTable lines;
  final DVRecordTable sessions;
  final DVRecordTable messages;
  final DVRecordTable currencies;

  List<DVPrivacyModel> get models => <DVPrivacyModel>[
    DVPrivacyModel(
      name: 'users',
      table: users,
      subject: DVSubject.self,
      personal: const <String>{'email'},
      retention: DVRetention.indefinite,
    ),
    DVPrivacyModel(
      name: 'addresses',
      table: addresses,
      subject: const DVSubject.through('user_ref', parent: 'users'),
      personal: const <String>{'line1'},
      retention: DVRetention.indefinite,
    ),
    DVPrivacyModel(
      name: 'orders',
      table: orders,
      subject: const DVSubject.field('user_id'),
      personal: const <String>{'address'},
      retain: const DVRetain(years: 7, because: 'tax law'),
      retention: const DVRetention.days(90, from: 'created_at'),
    ),
    DVPrivacyModel(
      name: 'order_lines',
      table: lines,
      subject: const DVSubject.through('order_id', parent: 'orders'),
      personal: const <String>{'note'},
      retention: DVRetention.indefinite,
    ),
    DVPrivacyModel(
      name: 'sessions',
      table: sessions,
      subject: const DVSubject.field('user_id'),
      personal: const <String>{'ip'},
      retention: const DVRetention.days(30, from: 'created_at'),
    ),
    DVPrivacyModel(
      name: 'messages',
      table: messages,
      subject: const DVSubject.field('author_id'),
      personal: const <String>{'body'},
      anonymizeOnErase: const <String>{'body'},
      otherSubjects: const <String>{'recipient_id'},
      retention: DVRetention.indefinite,
    ),
    DVPrivacyModel(name: 'currencies', table: currencies),
  ];

  Future<void> seed() async {
    for (final DVRecordTable t in <DVRecordTable>[
      users,
      addresses,
      orders,
      lines,
      sessions,
      messages,
      currencies,
    ]) {
      await t.ensureSchema();
    }
    await users.write(<String, Object?>{
      'id': 'u1',
      'email': 'ada@example.com',
      'national_id': 'AB123',
      'created_at': _ago(const Duration(days: 400)),
    });
    await users.write(<String, Object?>{
      'id': 'u2',
      'email': 'bo@example.com',
      'national_id': 'CD456',
      'created_at': _ago(const Duration(days: 400)),
    });
    // A change to u1's email: the old value now sits in the change log.
    final DVRecord? u1 = await users.read('u1');
    await users.write(<String, Object?>{
      ...u1!.values,
      'email': 'ada@new.example',
    }, base: u1);

    await addresses.write(<String, Object?>{
      'id': 'a1',
      'user_ref': 'u1',
      'line1': '9 Ada Close',
    });
    await addresses.write(<String, Object?>{
      'id': 'a2',
      'user_ref': 'u2',
      'line1': '8 Bo Road',
    });
    await orders.write(<String, Object?>{
      'id': 'o1',
      'user_id': 'u1',
      'address': '1 Ada Lane',
      'total': 40,
      'created_at': _ago(const Duration(days: 10)),
    });
    await orders.write(<String, Object?>{
      'id': 'o2',
      'user_id': 'u2',
      'address': '2 Bo Street',
      'total': 15,
      'created_at': _ago(const Duration(days: 10)),
    });
    await lines.write(<String, Object?>{
      'id': 'l1',
      'order_id': 'o1',
      'note': 'gift for Ada',
    });
    await lines.write(<String, Object?>{
      'id': 'l2',
      'order_id': 'o2',
      'note': 'for Bo',
    });
    await sessions.write(<String, Object?>{
      'id': 's1',
      'user_id': 'u1',
      'ip': '10.0.0.1',
      'created_at': _ago(const Duration(days: 1)),
    });
    await sessions.write(<String, Object?>{
      'id': 's2',
      'user_id': 'u2',
      'ip': '10.0.0.2',
      'created_at': _ago(const Duration(days: 1)),
    });
    await messages.write(<String, Object?>{
      'id': 'm1',
      'author_id': 'u1',
      'recipient_id': 'u2',
      'body': 'hi Bo, Ada here',
    });
    await messages.write(<String, Object?>{
      'id': 'm2',
      'author_id': 'u2',
      'recipient_id': 'u1',
      'body': 'hi Ada',
    });
    await currencies.write(<String, Object?>{'code': 'EUR', 'name': 'Euro'});
  }

  /// Every stored value in [tables] and their change logs, as text.
  Future<String> dump([List<String>? tables]) async {
    final StringBuffer out = StringBuffer();
    for (final String t
        in tables ??
            <String>[
              'users',
              'addresses',
              'orders',
              'order_lines',
              'sessions',
              'messages',
            ]) {
      out.writeln(jsonEncode(await database.query('SELECT * FROM $t')));
      if (t == 'users' || t == 'orders') {
        out.writeln(
          jsonEncode(await database.query('SELECT * FROM ${t}__history')),
        );
      }
    }
    return out.toString();
  }
}

class _RecordingAdapter implements DVPrivacyAdapter {
  _RecordingAdapter(this.name, {this.fail = false});

  @override
  final String name;
  final bool fail;
  final List<String> erased = <String>[];

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    if (fail) throw StateError('search index unreachable');
    erased.add('${subject.id}');
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'documents': <String>['doc-for-${subject.id}'],
      };
}

/// A database that holds one statement back until the test lets it through,
/// so another writer can run between a walk's read and its write -- in order,
/// every time, rather than when a sleep happens to line it up.
class _PausingAdapter implements DVDatabaseAdapter {
  _PausingAdapter(this.inner);

  final DVDatabaseAdapter inner;
  bool Function(String sql, List<Object?> params)? _when;
  Completer<void>? _reached;
  Completer<void>? _proceed;

  /// Holds the next statement [when] matches. `reached` completes once it is
  /// held; completing `proceed` sends it on.
  ({Future<void> reached, Completer<void> proceed}) pauseBefore(
    bool Function(String sql, List<Object?> params) when,
  ) {
    _when = when;
    _reached = Completer<void>();
    _proceed = Completer<void>();
    return (reached: _reached!.future, proceed: _proceed!);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) => inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final bool Function(String, List<Object?>)? when = _when;
    if (when != null && when(sql, params ?? const <Object?>[])) {
      _when = null;
      _reached!.complete();
      await _proceed!.future;
    }
    return inner.execute(sql, params);
  }
}

DVPrivacy _privacy(
  _Site site, {
  List<DVPrivacyAdapter> adapters = const <DVPrivacyAdapter>[],
  DateTime? now,
}) => DVPrivacy(
  models: site.models,
  database: site.database,
  signingKey: _signingKey,
  adapters: adapters,
  now: () => now ?? _now,
);

void main() {
  group('declarations', () {
    test('a model with a sensitive field and no subject path is refused', () {
      final DVRecordTable cards = DVRecordTable(
        table: 'cards',
        key: 'id',
        columns: const <String>['id', 'pan'],
        sensitive: const <String>{'pan'},
        database: MemoryDVDatabaseAdapter(),
      );
      final List<DVPrivacyFinding> findings = DVPrivacy.check(<DVPrivacyModel>[
        DVPrivacyModel(name: 'cards', table: cards),
      ]);
      expect(
        findings.map((DVPrivacyFinding f) => f.code),
        contains('DV-PRIVACY-001'),
      );
      expect(
        () => DVPrivacy(
          models: <DVPrivacyModel>[DVPrivacyModel(name: 'cards', table: cards)],
          database: MemoryDVDatabaseAdapter(),
          signingKey: _signingKey,
        ),
        throwsA(isA<DVPrivacyDeclarationError>()),
        reason:
            'an erasure that cannot reach a table must not be constructible',
      );
    });

    test(
      'personal data with no declared retention is a warning, not silence',
      () {
        final DVRecordTable leads = DVRecordTable(
          table: 'leads',
          key: 'id',
          columns: const <String>['id', 'email'],
          database: MemoryDVDatabaseAdapter(),
        );
        final List<DVPrivacyFinding> findings = DVPrivacy.check(
          <DVPrivacyModel>[
            DVPrivacyModel(
              name: 'leads',
              table: leads,
              subject: DVSubject.self,
              personal: const <String>{'email'},
            ),
          ],
        );
        expect(findings.single.code, 'DV-PRIVACY-002');
      },
    );

    test('a model with no personal data declares nothing and is fine', () {
      final _Site site = _Site(MemoryDVDatabaseAdapter());
      expect(
        DVPrivacy.check(
          site.models,
        ).where((DVPrivacyFinding f) => f.model == 'currencies'),
        isEmpty,
      );
    });
  });

  for (final _Adapter adapter in _adapters) {
    group('on ${adapter.$1}', () {
      late _Site site;
      late DVPrivacy privacy;

      setUp(() async {
        DVFieldEncryption.reset();
        site = _Site(adapter.$2());
        await site.seed();
        privacy = _privacy(site);
        await privacy.ensureSchema();
      });

      tearDown(DVFieldEncryption.reset);

      group('erasure', () {
        test(
          "removes the subject's rows across every path and leaves others'",
          () async {
            final DVErasureResult result = await privacy.erase(
              subject: 'u1',
              reason: 'DSAR 2026-114',
            );

            expect(await site.users.read('u1', withDeleted: true), isNull);
            expect(await site.sessions.read('s1'), isNull);
            expect(
              await site.lines.read('l1'),
              isNull,
              reason: 'order lines reach the subject through their order',
            );
            expect(
              await site.addresses.read('a1'),
              isNull,
              reason:
                  'reached through a parent the same erasure deletes, so '
                  'the walk has to be resolved before anything is removed',
            );
            expect(await site.users.read('u2'), isNotNull);
            expect(await site.sessions.read('s2'), isNotNull);
            expect(await site.lines.read('l2'), isNotNull);
            expect(await site.addresses.read('a2'), isNotNull);
            expect(result.complete, isTrue);
            expect(result.deleted['users'], 1);
            expect(result.deleted['order_lines'], 1);
          },
        );

        test(
          'removes a soft-deleted row rather than leaving it marked',
          () async {
            await site.users.delete('u1');
            expect(
              await site.users.read('u1', withDeleted: true),
              isNotNull,
              reason: 'precondition: soft delete keeps the row',
            );

            await privacy.erase(subject: 'u1', reason: 'DSAR');

            final List<Map<String, Object?>> raw = await site.database.query(
              'SELECT * FROM users WHERE id = ?',
              <Object?>['u1'],
            );
            expect(
              raw,
              isEmpty,
              reason: 'a soft-deleted row still holds everything it held',
            );
          },
        );

        test('leaves no personal value in a change log', () async {
          expect(
            await site.dump(),
            contains('ada@example.com'),
            reason: 'precondition: the old email is in the users change log',
          );

          await privacy.erase(subject: 'u1', reason: 'DSAR');

          final String after = await site.dump();
          expect(after, isNot(contains('ada@example.com')));
          expect(after, isNot(contains('ada@new.example')));
          expect(
            after,
            isNot(contains('1 Ada Lane')),
            reason:
                'a kept order is anonymized, and its change log with it; '
                'otherwise a revert puts the address back',
          );
        });

        test(
          'leaves no ciphertext while the key that opens it still exists',
          () async {
            final DVFieldKeyring ring = DVFieldKeyring.parse(
              'k1:${base64Encode(List<int>.generate(32, (int i) => 255 - i))}',
            );
            DVFieldEncryption.configure(DVFieldCipher.secure(ring));
            final String sealed = DVFieldEncryption.encrypt(
              'users',
              'national_id',
              'AB123',
            )!;
            final DVRecord? u1 = await site.users.read('u1');
            await site.users.write(<String, Object?>{
              ...u1!.values,
              'national_id': sealed,
            }, base: u1);
            // And on a row the erasure keeps: the row survives, the sealed
            // sensitive field on it must not.
            final String sealedTax = DVFieldEncryption.encrypt(
              'orders',
              'tax_id',
              'GB-TAX-77',
            )!;
            final DVRecord? o1 = await site.orders.read('o1');
            await site.orders.write(<String, Object?>{
              ...o1!.values,
              'tax_id': sealedTax,
            }, base: o1);
            expect(
              await site.dump(),
              contains(sealed),
              reason: 'precondition: the ciphertext is stored',
            );

            await privacy.erase(subject: 'u1', reason: 'DSAR');

            final String after = await site.dump();
            expect(after, isNot(contains(sealed)));
            expect(await site.orders.read('o1'), isNotNull);
            expect(
              after,
              isNot(contains(sealedTax)),
              reason: 'a kept row is anonymized, sensitive fields included',
            );
            expect(
              DVFieldEncryption.isAvailable,
              isTrue,
              reason:
                  'the key still exists, so only the absence of the '
                  'ciphertext makes the value unrecoverable',
            );
            for (final Match m in RegExp(
              r'dvf1:[A-Za-z0-9_-]+:[A-Za-z0-9+/=]+',
            ).allMatches(after)) {
              String? opened;
              try {
                opened = DVFieldEncryption.decrypt(
                  'users',
                  'national_id',
                  m[0],
                );
              } on Object {
                opened = null;
              }
              expect(opened, isNot('AB123'));
            }
          },
        );

        test('keeps a retained row, anonymizes it, and says why', () async {
          final DVErasureResult result = await privacy.erase(
            subject: 'u1',
            reason: 'DSAR',
          );

          final DVRecord? order = await site.orders.read('o1');
          expect(order, isNotNull, reason: 'seven years for tax');
          expect(order!.values['address'], DVPrivacy.tombstone);
          expect(
            order.values['user_id'],
            privacy.pseudonym('u1'),
            reason: 'a kept row names the tombstone, not the person',
          );
          expect(
            order.values['total'],
            40,
            reason: 'not personal, not touched',
          );
          final DVKeptRecord kept = result.kept.single;
          expect(kept.model, 'orders');
          expect(kept.key, 'o1');
          expect(kept.because, 'tax law');
          expect(result.codes, contains('DV-PRIVACY-003'));
        });

        test(
          'a writer holding a row from before the erasure cannot write it back',
          () async {
            final DVRecord? before = await site.orders.read('o1');
            await privacy.erase(subject: 'u1', reason: 'DSAR');

            await expectLater(
              site.orders.write(before!.values, base: before),
              throwsA(isA<DVConflictError>()),
              reason:
                  'otherwise an open form re-saves the address the erasure '
                  'removed',
            );
            expect(
              (await site.orders.read('o1'))!.values['address'],
              DVPrivacy.tombstone,
            );
          },
        );

        test(
          'tombstones a field declared anonymize-on-erase and keeps the row',
          () async {
            final DVErasureResult result = await privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
            );
            final DVRecord? m1 = await site.messages.read('m1');
            expect(m1, isNotNull);
            expect(m1!.values['body'], DVPrivacy.tombstone);
            expect(
              (await site.messages.read('m2'))!.values['body'],
              'hi Ada',
              reason: "the other person's message is theirs",
            );
            expect(result.anonymized['messages'], 1);
          },
        );

        test(
          'an adapter it could not reach is an error, not a quiet success',
          () async {
            final _RecordingAdapter cache = _RecordingAdapter('cache');
            privacy = _privacy(
              site,
              adapters: <DVPrivacyAdapter>[
                _RecordingAdapter('search', fail: true),
                cache,
              ],
            );
            await privacy.ensureSchema();

            final DVErasureResult result = await privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
            );

            expect(result.complete, isFalse);
            expect(result.unreached, <String>['search']);
            expect(result.codes, contains('DV-PRIVACY-009'));
            expect(
              cache.erased,
              <String>['u1'],
              reason: 'one failure does not stop the rest of the walk',
            );
            expect(await site.users.read('u1', withDeleted: true), isNull);
            expect(
              result.receipt.payload['complete'],
              isFalse,
              reason: 'the receipt must not claim what did not happen',
            );
          },
        );

        test(
          "a device's offline copy is erased, queued writes included",
          () async {
            final DVRecordTable notes = DVRecordTable(
              table: 'notes',
              key: 'id',
              columns: const <String>['id', 'user_id', 'text'],
              database: site.database,
            );
            final DVOfflineStore store = DVOfflineStore(
              table: notes,
              policy: const DVOffline(strategy: DVConflict.lastWriteWins),
              persistent: true,
            );
            await store.ensureSchema();
            await store.write(<String, Object?>{
              'id': 'n1',
              'user_id': 'u1',
              'text': 'ada note',
            });
            await store.write(<String, Object?>{
              'id': 'n2',
              'user_id': 'u2',
              'text': 'bo note',
            });
            // The server's copy of a row this device no longer holds locally.
            await site.database.execute(
              'INSERT INTO ${store.serverTable} (record_key, version, payload) '
              'VALUES (?, ?, ?)',
              <Object?>[
                jsonEncode('n9'),
                3,
                jsonEncode(<String, Object?>{
                  'id': 'n9',
                  'user_id': 'u1',
                  'text': 'ada old',
                }),
              ],
            );
            expect(
              jsonEncode(
                await site.database.query('SELECT * FROM ${store.logTable}'),
              ),
              contains('ada note'),
              reason: 'precondition: the queued write carries the value',
            );

            privacy = _privacy(
              site,
              adapters: <DVPrivacyAdapter>[
                DVOfflineStorePrivacyAdapter(
                  store: store,
                  subject: const DVSubject.field('user_id'),
                ),
              ],
            );
            await privacy.ensureSchema();
            final DVErasureResult result = await privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
            );

            expect(result.complete, isTrue);
            expect(await notes.read('n1'), isNull);
            expect(await notes.read('n2'), isNotNull);
            final String log = jsonEncode(
              await site.database.query('SELECT * FROM ${store.logTable}'),
            );
            expect(
              log,
              isNot(contains('ada note')),
              reason:
                  'a write queued for the server is the subject\'s data too',
            );
            expect(log, contains('bo note'));
            expect(
              jsonEncode(
                await site.database.query('SELECT * FROM ${store.serverTable}'),
              ),
              isNot(contains('ada old')),
              reason: 'the last server copy this device saw is a copy too',
            );
          },
        );

        test('the receipt verifies, and stops verifying once edited', () async {
          final DVErasureResult result = await privacy.erase(
            subject: 'u1',
            reason: 'DSAR',
          );
          final DVErasureReceipt receipt = result.receipt;
          expect(privacy.verifyReceipt(receipt), isTrue);

          final Map<String, Object?> edited =
              jsonDecode(jsonEncode(receipt.payload)) as Map<String, Object?>;
          (edited['deleted']! as Map<String, Object?>)['users'] = 0;
          expect(
            privacy.verifyReceipt(
              DVErasureReceipt(payload: edited, signature: receipt.signature),
            ),
            isFalse,
          );
          expect(
            privacy.verifyReceipt(
              DVErasureReceipt(
                payload: receipt.payload,
                signature: receipt.signature.replaceRange(0, 2, 'AA'),
              ),
            ),
            isFalse,
          );
          expect(
            jsonEncode(receipt.payload),
            isNot(contains('u1')),
            reason: 'the receipt proves the erasure without naming the subject',
          );
        });

        test('a late erasure still runs, and says it was late', () async {
          final DVErasureResult result = await privacy.erase(
            subject: 'u1',
            reason: 'DSAR',
            requestedAt: _now.subtract(const Duration(days: 31)),
          );
          expect(result.late, isTrue);
          expect(result.codes, contains('DV-PRIVACY-004'));
          expect(await site.users.read('u1', withDeleted: true), isNull);
        });

        test(
          'is recorded through record history, without the subject in it',
          () async {
            await privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
              requestedBy: 'dpo',
              runBy: 'ops',
            );
            final List<DVRecord> requests = await privacy.requests.all();
            expect(requests, hasLength(1));
            expect(requests.single.values['kind'], 'erase');
            expect(requests.single.values['requested_by'], 'dpo');
            expect(
              await privacy.requests.history(requests.single.key),
              isNotEmpty,
            );
            final String stored = jsonEncode(
              await site.database.query('SELECT * FROM dv_privacy_requests'),
            );
            expect(stored, isNot(contains('u1')));
            expect(stored, contains(privacy.pseudonym('u1')));
          },
        );

        test(
          'a restored backup is erased again before it serves anything',
          () async {
            final List<Map<String, Object?>> backup = await site.database.query(
              'SELECT * FROM users WHERE id = ?',
              <Object?>['u1'],
            );
            await privacy.erase(subject: 'u1', reason: 'DSAR');
            for (final Map<String, Object?> row in backup) {
              final List<String> cols = row.keys.toList();
              await site.database.execute(
                'INSERT INTO users (${cols.join(', ')}) '
                'VALUES (${List<String>.filled(cols.length, '?').join(', ')})',
                <Object?>[for (final String c in cols) row[c]],
              );
            }
            expect(
              await site.users.read('u1', withDeleted: true),
              isNotNull,
              reason: 'precondition: the backup brought the row back',
            );

            final DVErasureReplay replay = await privacy.replayErasures();

            expect(await site.users.read('u1', withDeleted: true), isNull);
            expect(replay.records, greaterThanOrEqualTo(1));
            expect(replay.codes, contains('DV-PRIVACY-005'));
            final String tombstones = jsonEncode(
              await site.database.query('SELECT * FROM dv_privacy_tombstones'),
            );
            expect(tombstones, isNot(contains('u1')));
          },
        );
      });

      group('export', () {
        test('includes every relation the subject path reaches', () async {
          final DVExportArchive archive = await privacy.export(subject: 'u1');
          expect(archive.records['users']!.single['email'], 'ada@new.example');
          expect(archive.records['addresses']!.single['id'], 'a1');
          expect(archive.records['orders']!.single['id'], 'o1');
          expect(
            archive.records['order_lines']!.single['id'],
            'l1',
            reason: 'a relation reached through a parent is still the subject',
          );
          expect(archive.records['sessions']!.single['id'], 's1');
          expect(archive.records.containsKey('currencies'), isFalse);
          final String json = archive.toJson();
          expect(json, isNot(contains('bo@example.com')));
          expect(json, isNot(contains('2 Bo Street')));
        });

        test(
          "carries the subject's contribution and not the other subject",
          () async {
            final DVExportArchive archive = await privacy.export(subject: 'u1');
            final List<Map<String, Object?>> messages =
                archive.records['messages']!;
            expect(messages.map((Map<String, Object?> m) => m['id']), <Object?>[
              'm1',
            ]);
            expect(
              messages.single['recipient_id'],
              isNull,
              reason: "the recipient's identifier is the recipient's data",
            );
            expect(archive.codes, contains('DV-PRIVACY-006'));
          },
        );

        test('includes what each adapter holds for the subject', () async {
          privacy = _privacy(
            site,
            adapters: <DVPrivacyAdapter>[_RecordingAdapter('storage')],
          );
          await privacy.ensureSchema();
          final DVExportArchive archive = await privacy.export(subject: 'u1');
          expect(archive.adapters['storage'], <String, Object?>{
            'documents': <String>['doc-for-u1'],
          });
        });
      });

      group('retention', () {
        Future<void> addOldSessions() async {
          for (int i = 0; i < 3; i++) {
            await site.sessions.write(<String, Object?>{
              'id': 'old$i',
              'user_id': 'u2',
              'ip': '10.1.0.$i',
              'created_at': _ago(const Duration(days: 45)),
            });
          }
          await site.orders.write(<String, Object?>{
            'id': 'o-old',
            'user_id': 'u2',
            'address': 'old address',
            'total': 9,
            'created_at': _ago(const Duration(days: 200)),
          });
        }

        test(
          'a plan says what a sweep would delete and deletes nothing',
          () async {
            await addOldSessions();
            final DVRetentionPlan plan = await privacy.planRetention();
            expect(plan.deletions['sessions'], 3);
            expect(
              await site.sessions.all(),
              hasLength(5),
              reason: 'a plan is a preview',
            );
          },
        );

        test('a sweep deletes expired rows in resumable batches', () async {
          await addOldSessions();
          final DVRetentionSweep first = await privacy.sweepRetention(
            batchSize: 2,
            maxBatches: 1,
          );
          expect(first.deleted['sessions'], 2);
          expect(first.remaining, greaterThan(0));
          final DVRetentionSweep second = await privacy.sweepRetention(
            batchSize: 2,
          );
          expect(second.deleted['sessions'], 1);
          expect(second.remaining, 0);
          expect(
            await site.sessions.read('s1'),
            isNotNull,
            reason: 'a session inside its thirty days is kept',
          );
          expect(<String>[
            ...first.codes,
            ...second.codes,
          ], contains('DV-PRIVACY-007'));
        });

        test(
          'a longer retention holds a row a shorter one would delete',
          () async {
            await addOldSessions();
            final DVRetentionSweep sweep = await privacy.sweepRetention();
            expect(
              await site.orders.read('o-old'),
              isNotNull,
              reason:
                  '90 days has passed, seven years has not; the longer wins',
            );
            expect(sweep.held['orders'], 1);
            expect(sweep.codes, contains('DV-PRIVACY-008'));
          },
        );
      });

      // A sweep and an erasure read their rows, then write them. A row
      // rewritten in between -- a session renewed, an order moved to another
      // customer -- is a different row by the time the write lands, and
      // deleting or anonymizing it from the stale read destroys data nobody
      // asked to remove, with nothing in the result to say so.
      group('a write between the walk and its write', () {
        late _PausingAdapter db;
        late DVCapture capture;
        late DVRecordTable visits;

        setUp(() async {
          db = _PausingAdapter(adapter.$2());
          capture = DVCapture(
            database: db,
            retention: const Duration(days: 7),
            clock: () => _now,
          );
          await capture.ensureSchema();
          visits = DVRecordTable(
            table: 'visits',
            key: 'id',
            columns: const <String>['id', 'user_id', 'ip', 'created_at'],
            history: const DVHistory(),
            capture: capture,
            database: db,
          );
          await visits.ensureSchema();
        });

        Future<DVRecord> visit(
          String id,
          String user,
          String ip,
          Duration age,
        ) async => (await visits.write(<String, Object?>{
          'id': id,
          'user_id': user,
          'ip': ip,
          'created_at': _ago(age),
        })).record;

        DVPrivacy over({
          DVRetention retention = DVRetention.indefinite,
          DVRetain? retain,
        }) => DVPrivacy(
          models: <DVPrivacyModel>[
            DVPrivacyModel(
              name: 'visits',
              table: visits,
              subject: const DVSubject.field('user_id'),
              personal: const <String>{'ip'},
              retain: retain,
              retention: retention,
            ),
          ],
          database: db,
          signingKey: _signingKey,
          now: () => _now,
        );

        /// Holds the walk's write to row [key] of visits.
        ({Future<void> reached, Completer<void> proceed}) pauseWriteTo(
          String key,
        ) => db.pauseBefore(
          (String sql, List<Object?> params) =>
              RegExp(r'^(DELETE FROM|UPDATE) visits ').hasMatch(sql) &&
              params.contains(key),
        );

        Future<List<DVCapturedChange>> capturedFor(String key) async =>
            <DVCapturedChange>[
              for (final DVCapturedChange c in await capture.changes())
                if ('${c.key}' == key) c,
            ];

        for (final DVRetentionAction action in DVRetentionAction.values) {
          test(
            'a sweep that would ${action.name} leaves a row renewed after it '
            'was read, with its history and its captured changes',
            () async {
              await visit('old', 'u1', '10.1.0.1', const Duration(days: 45));
              await visit('stale', 'u1', '10.1.0.2', const Duration(days: 45));
              final DVPrivacy privacy = over(
                retention: DVRetention.days(
                  30,
                  from: 'created_at',
                  then: action,
                ),
              );
              await privacy.ensureSchema();
              final ({Future<void> reached, Completer<void> proceed}) pause =
                  pauseWriteTo('old');

              final Future<DVRetentionSweep> sweeping = privacy
                  .sweepRetention();
              await pause.reached;
              final DVRecord read = (await visits.read('old'))!;
              final DVRecord renewed = (await visits.write(<String, Object?>{
                ...read.values,
                'ip': '10.9.9.9',
                'created_at': _now.toIso8601String(),
              }, base: read)).record;
              final int history = (await visits.history('old')).length;
              final List<DVCapturedChange> captured = await capturedFor('old');
              pause.proceed.complete();
              final DVRetentionSweep sweep = await sweeping;

              final DVRecord? kept = await visits.read('old');
              expect(
                kept,
                isNotNull,
                reason: 'the row was renewed; it is no longer expired',
              );
              expect(kept!.version, renewed.version);
              expect(kept.values['ip'], '10.9.9.9');
              expect(kept.values['created_at'], _now.toIso8601String());
              expect(
                (await visits.history('old')).length,
                history,
                reason: "a skipped row's change log is its own",
              );
              expect(
                (await capturedFor('old')).map((DVCapturedChange c) => c.id),
                captured.map((DVCapturedChange c) => c.id),
                reason: 'nothing is captured for a write that did not apply',
              );
              expect(
                (await capturedFor(
                  'old',
                )).any((DVCapturedChange c) => c.erased),
                isFalse,
              );

              final Map<String, int> done = action == DVRetentionAction.delete
                  ? sweep.deleted
                  : sweep.anonymized;
              expect(done['visits'], 1, reason: 'the uncontended row is swept');
              expect(sweep.skipped['visits'], 1);
              expect(
                sweep.remaining,
                0,
                reason: 'a renewed row is not left for the next run',
              );
            },
          );
        }

        test(
          'a row rewritten but still expired is skipped, counted as remaining, '
          'and swept on the next run',
          () async {
            await visit('old', 'u1', '10.1.0.1', const Duration(days: 45));
            final DVPrivacy privacy = over(
              retention: const DVRetention.days(30, from: 'created_at'),
            );
            await privacy.ensureSchema();
            final ({Future<void> reached, Completer<void> proceed}) pause =
                pauseWriteTo('old');

            final Future<DVRetentionSweep> sweeping = privacy.sweepRetention();
            await pause.reached;
            final DVRecord read = (await visits.read('old'))!;
            await visits.write(<String, Object?>{
              ...read.values,
              'ip': '10.9.9.9',
            }, base: read);
            pause.proceed.complete();
            final DVRetentionSweep first = await sweeping;

            final DVRecord? rewritten = await visits.read('old');
            expect(rewritten, isNotNull, reason: 'it changed after the read');
            expect(rewritten!.values['ip'], '10.9.9.9');
            expect(first.deleted['visits'], isNull);
            expect(first.skipped['visits'], 1);
            expect(first.remaining, 1, reason: 'still expired; not lost');

            final DVRetentionSweep second = await privacy.sweepRetention();
            expect(await visits.read('old'), isNull);
            expect(second.deleted['visits'], 1);
            expect(second.skipped, isEmpty);
            expect(second.remaining, 0);
            expect(
              (await capturedFor(
                'old',
              )).where((DVCapturedChange c) => c.erased),
              hasLength(1),
            );
          },
        );

        test(
          'an erasure leaves a row moved to another subject after its walk',
          () async {
            await visit('mine', 'u1', '10.1.0.1', const Duration(days: 1));
            await visit('also', 'u1', '10.1.0.2', const Duration(days: 1));
            final DVPrivacy privacy = over();
            await privacy.ensureSchema();
            final ({Future<void> reached, Completer<void> proceed}) pause =
                pauseWriteTo('mine');

            final Future<DVErasureResult> erasing = privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
            );
            await pause.reached;
            final DVRecord read = (await visits.read('mine'))!;
            await visits.write(<String, Object?>{
              ...read.values,
              'user_id': 'u2',
            }, base: read);
            final int history = (await visits.history('mine')).length;
            final List<DVCapturedChange> captured = await capturedFor('mine');
            pause.proceed.complete();
            final DVErasureResult result = await erasing;

            final DVRecord? moved = await visits.read('mine');
            expect(moved, isNotNull, reason: "it is u2's row now");
            expect(moved!.values['user_id'], 'u2');
            expect(moved.values['ip'], '10.1.0.1');
            expect((await visits.history('mine')).length, history);
            expect(
              (await capturedFor('mine')).map((DVCapturedChange c) => c.id),
              captured.map((DVCapturedChange c) => c.id),
            );
            expect(await visits.read('also'), isNull);
            expect(result.deleted['visits'], 1);
          },
        );

        test(
          'an erasure anonymizes a kept row rewritten after its walk past the '
          'rewrite, so the rewriting writer conflicts',
          () async {
            await visit('kept', 'u1', '10.1.0.1', const Duration(days: 1));
            final DVPrivacy privacy = over(
              retain: const DVRetain(years: 7, because: 'audit'),
            );
            await privacy.ensureSchema();
            final ({Future<void> reached, Completer<void> proceed}) pause =
                pauseWriteTo('kept');

            final Future<DVErasureResult> erasing = privacy.erase(
              subject: 'u1',
              reason: 'DSAR',
            );
            await pause.reached;
            final DVRecord read = (await visits.read('kept'))!;
            final DVRecord rewritten = (await visits.write(<String, Object?>{
              ...read.values,
              'ip': '10.9.9.9',
            }, base: read)).record;
            pause.proceed.complete();
            final DVErasureResult result = await erasing;

            final DVRecord erased = (await visits.read('kept'))!;
            expect(erased.values['ip'], DVPrivacy.tombstone);
            expect(erased.values['user_id'], privacy.pseudonym('u1'));
            expect(erased.version, greaterThan(rewritten.version));
            expect(result.kept.single.key, 'kept');
            await expectLater(
              visits.write(rewritten.values, base: rewritten),
              throwsA(isA<DVConflictError>()),
              reason:
                  'otherwise the writer that raced the erasure re-saves the '
                  'value it removed',
            );
            expect(
              jsonEncode(await db.query('SELECT * FROM visits')),
              isNot(contains('10.9.9.9')),
            );
          },
        );
      });

      test('an erasure runs as a durable job on the queue layer', () async {
        privacy.registerJobs(const DVQueues());
        await privacy.requestErasure(subject: 'u1', reason: 'DSAR');
        expect(
          await site.users.read('u1'),
          isNotNull,
          reason: 'requesting queues; the worker erases',
        );
        await const DVQueues().work();
        expect(await site.users.read('u1', withDeleted: true), isNull);
      });
    });
  }
}
