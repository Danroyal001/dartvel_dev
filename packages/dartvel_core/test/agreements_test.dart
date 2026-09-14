// Versioned agreements and the acceptance records that answer, years later,
// whether somebody accepted the version that was in force.
//
// The silent failures: a version bump that does not ask again, so an
// acceptance of last year's terms stands for this year's; an acceptance that
// was never written being treated as given; a dispute answered from the
// current version rather than the one in force on the day; and an erasure
// that destroys the evidence or leaves the person's id on it.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

class _FailingWrites implements DVDatabaseAdapter {
  _FailingWrites(this.inner);
  final DVDatabaseAdapter inner;
  bool failing = false;

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    if (failing && sql.startsWith('INSERT INTO ${DVAgreements.table} ')) {
      throw StateError('disk full');
    }
    return inner.execute(sql, params);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);
}

void main() {
  test('agreements are read from dartvel.agreements', () {
    final List<DVAgreement> read = DVAgreement.fromConfig(<String, Object?>{
      'terms': <String, Object?>{'version': '2026-09-01', 'route': '/legal/terms'},
      'privacy': <String, Object?>{
        'version': '2026-09-01',
        'route': '/legal/privacy',
      },
    });
    expect(read.map((DVAgreement a) => a.id), <String>['terms', 'privacy']);
    expect(read.first.version, '2026-09-01');
    expect(read.first.route, '/legal/terms');
  });

  test('a version is a date somebody sets, not a hash or a counter', () {
    expect(() => DVAgreement(id: 'terms', version: '3', route: '/t'),
        throwsArgumentError);
    expect(
        () => DVAgreement(
            id: 'terms', version: 'e3b0c44298fc1c14', route: '/t'),
        throwsArgumentError);
    expect(() => DVAgreement(id: 'terms', version: '2026-02-30', route: '/t'),
        throwsArgumentError);
  });

  for (final _Adapter adapter in _adapters) {
    group('acceptance (${adapter.$1})', () {
      late DVDatabaseAdapter database;
      DateTime now = DateTime.utc(2026, 9, 2, 10);

      Future<DVAgreements> open(String termsVersion,
          {DVDatabaseAdapter? db}) async {
        final DVAgreements agreements = DVAgreements(
          agreements: <DVAgreement>[
            DVAgreement(id: 'terms', version: termsVersion, route: '/legal/terms'),
            DVAgreement(
                id: 'privacy', version: '2026-09-01', route: '/legal/privacy'),
          ],
          database: db ?? database,
          clock: () => now,
        );
        await agreements.ensureSchema();
        return agreements;
      }

      setUp(() {
        database = adapter.$2();
        now = DateTime.utc(2026, 9, 2, 10);
      });

      test('nothing accepted means everything is pending', () async {
        final DVAgreements agreements = await open('2026-09-01');
        expect(
            (await agreements.pending(actor: 'u1')).map((DVAgreement a) => a.id),
            <String>['terms', 'privacy']);
      });

      test('an acceptance is a record of actor, version, time and tenant',
          () async {
        final DVAgreements agreements = await open('2026-09-01');
        final DVAcceptance a =
            await agreements.accept('terms', actor: 'u1', tenant: 'acme');
        expect(a.agreement, 'terms');
        expect(a.version, '2026-09-01');
        expect(a.actor, 'u1');
        expect(a.tenant, 'acme');
        expect(a.acceptedAt, now);
        expect(await agreements.needsAcceptance('terms', actor: 'u1'), isFalse);
        expect(await agreements.needsAcceptance('terms', actor: 'u2'), isTrue);
        expect(
            (await agreements.pending(actor: 'u1')).map((DVAgreement a) => a.id),
            <String>['privacy']);
      });

      test('a version bump asks again', () async {
        final DVAgreements first = await open('2026-09-01');
        await first.accept('terms', actor: 'u1');
        final DVAgreements bumped = await open('2027-01-15');
        expect(await bumped.needsAcceptance('terms', actor: 'u1'), isTrue);
        now = DateTime.utc(2027, 1, 20);
        await bumped.accept('terms', actor: 'u1');
        expect(await bumped.needsAcceptance('terms', actor: 'u1'), isFalse);
      });

      test('an acceptance that cannot be written is not an acceptance',
          () async {
        final _FailingWrites failing = _FailingWrites(database);
        final DVAgreements agreements = await open('2026-09-01', db: failing);
        failing.failing = true;
        await expectLater(agreements.accept('terms', actor: 'u1'),
            throwsA(isA<DVAgreementRecordError>()));
        failing.failing = false;
        expect(await agreements.needsAcceptance('terms', actor: 'u1'), isTrue);
      });

      test('an unknown agreement is refused', () async {
        final DVAgreements agreements = await open('2026-09-01');
        expect(() => agreements.accept('cookies', actor: 'u1'),
            throwsArgumentError);
      });

      test('a dispute is answered from the version in force on the day, not '
          'the current one', () async {
        final DVAgreements v1 = await open('2026-09-01');
        await v1.accept('terms', actor: 'u1');
        await v1.accept('terms', actor: 'u2');

        final DVAgreements v2 = await open('2027-01-15');
        now = DateTime.utc(2027, 2, 1);
        await v2.accept('terms', actor: 'u2');

        // On 2026-12-01 the 2026-09-01 terms were in force: both accepted.
        final DateTime december = DateTime.utc(2026, 12, 1);
        expect(await v2.inForce('terms', at: december), '2026-09-01');
        expect((await v2.acceptedInForce('terms', actor: 'u1', at: december))
            ?.version, '2026-09-01');

        // On 2027-03-01 the 2027-01-15 terms were: only u2 had accepted them.
        final DateTime march = DateTime.utc(2027, 3, 1);
        expect(await v2.inForce('terms', at: march), '2027-01-15');
        expect(await v2.acceptedInForce('terms', actor: 'u1', at: march),
            isNull);
        expect((await v2.acceptedInForce('terms', actor: 'u2', at: march))
            ?.version, '2027-01-15');

        // An acceptance given after the day does not answer for the day.
        final DateTime jan20 = DateTime.utc(2027, 1, 20);
        expect(await v2.acceptedInForce('terms', actor: 'u2', at: jan20),
            isNull);
      });

      test('an earlier version is still known once the configuration has moved '
          'on', () async {
        await open('2026-09-01');
        final DVAgreements later = await open('2027-01-15');
        expect(await later.inForce('terms', at: DateTime.utc(2026, 10, 1)),
            '2026-09-01');
        expect(await later.inForce('terms', at: DateTime.utc(2026, 8, 1)),
            isNull);
      });

      test('erasure keeps the acceptance as evidence under the pseudonym, and '
          'export carries it', () async {
        final DVAgreements agreements = await open('2026-09-01');
        await agreements.accept('terms', actor: 'u1', tenant: 'acme');
        await agreements.accept('terms', actor: 'u2', tenant: 'acme');
        final DVPrivacy privacy = DVPrivacy(
          models: <DVPrivacyModel>[],
          database: database,
          signingKey: List<int>.filled(32, 3),
          adapters: <DVPrivacyAdapter>[agreements.privacyAdapter()],
        );
        await privacy.ensureSchema();

        final DVExportArchive archive = await privacy.export(subject: 'u1');
        final String exported = jsonEncode(archive.adapters['agreements']);
        expect(exported, contains('2026-09-01'));
        expect(exported, isNot(contains('u2')));

        final DVErasureResult result =
            await privacy.erase(subject: 'u1', reason: 'request');
        expect(result.complete, isTrue);
        expect(await agreements.acceptances(actor: 'u1'), isEmpty);
        final List<DVAcceptance> kept =
            await agreements.acceptances(actor: privacy.pseudonym('u1'));
        expect(kept, hasLength(1));
        expect(kept.single.version, '2026-09-01');
        expect(await agreements.acceptances(actor: 'u2'), hasLength(1));
      });
    });
  }
}
