/// Versioned agreements — terms, privacy notice — and the acceptance records
/// that answer, years later, whether somebody accepted the version in force.
library dartvel_core.analytics.agreements;

import 'dart:async';

import '../database/adapter.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart';

final RegExp _dateVersion = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// One agreement as `dartvel.agreements` declares it.
final class DVAgreement {
  /// [version] is a date, `YYYY-MM-DD`, that somebody sets: a typo fix is not
  /// a new agreement, and a hash of the document would make it one.
  ///
  /// Not const: a constant would skip the check, and a counter or a hash
  /// would be accepted as a version.
  DVAgreement({
    required this.id,
    required this.version,
    required this.route,
  }) {
    validate();
  }

  /// Reads `dartvel.agreements` from `pubspec.yaml`.
  static List<DVAgreement> fromConfig(Map<String, Object?> agreements) =>
      <DVAgreement>[
        for (final MapEntry<String, Object?> e in agreements.entries)
          if (e.value case final Map<Object?, Object?> body)
            DVAgreement(
              id: e.key,
              version: '${body['version']}',
              route: '${body['route']}',
            )
          else
            throw ArgumentError.value(e.value, e.key, 'must be a map'),
      ];

  final String id;
  final String version;
  final String route;

  /// The day the version took effect.
  DateTime get effective => _effective(version)!;

  /// Throws when [version] is not a real calendar date.
  void validate() {
    if (_effective(version) == null) {
      throw ArgumentError.value(version, '$id.version',
          'must be a date somebody sets (YYYY-MM-DD), not a hash or a counter');
    }
  }

  static DateTime? _effective(String version) {
    final RegExpMatch? m = _dateVersion.firstMatch(version);
    if (m == null) return null;
    final int y = int.parse(m.group(1)!);
    final int mo = int.parse(m.group(2)!);
    final int d = int.parse(m.group(3)!);
    final DateTime date = DateTime.utc(y, mo, d);
    if (date.year != y || date.month != mo || date.day != d) return null;
    return date;
  }
}

/// One acceptance, as it was recorded.
final class DVAcceptance {
  const DVAcceptance({
    required this.id,
    required this.agreement,
    required this.version,
    required this.actor,
    required this.tenant,
    required this.acceptedAt,
  });

  final String id;
  final String agreement;
  final String version;
  final String actor;
  final String? tenant;
  final DateTime acceptedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'agreement': agreement,
        'version': version,
        'actor': actor,
        'tenant': tenant,
        'acceptedAt': acceptedAt.toIso8601String(),
      };

  static DVAcceptance _fromRow(Map<String, Object?> row) => DVAcceptance(
        id: '${row['id']}',
        agreement: '${row['agreement']}',
        version: '${row['version']}',
        actor: '${row['actor']}',
        tenant: row['tenant'] as String?,
        acceptedAt: DateTime.parse('${row['accepted_at']}'),
      );
}

/// An acceptance that could not be written, and so was not given.
class DVAgreementRecordError implements Exception {
  DVAgreementRecordError(this.agreement, this.cause);

  final String agreement;
  final Object cause;

  @override
  String toString() =>
      'DVAgreementRecordError: the acceptance of "$agreement" could not be '
      'recorded ($cause); it has not been accepted';
}

/// The declared agreements, and every acceptance of them.
class DVAgreements {
  DVAgreements({
    required List<DVAgreement> agreements,
    required this.database,
    DateTime Function()? clock,
  })  : agreements = List<DVAgreement>.unmodifiable(agreements),
        _clock = clock ?? DateTime.now {
    final Set<String> ids = <String>{};
    for (final DVAgreement a in agreements) {
      a.validate();
      if (!ids.add(a.id)) {
        throw ArgumentError.value(a.id, 'id', 'is declared twice');
      }
    }
  }

  static const String table = 'dv_agreement_acceptances';
  static const String versionsTable = 'dv_agreement_versions';

  final List<DVAgreement> agreements;
  final DVDatabaseAdapter database;
  final DateTime Function() _clock;
  int _ids = 0;

  /// Creates the tables and remembers the versions configured now.
  ///
  /// The configuration only ever names the current version, so the versions
  /// before it are known from here: a dispute about last year needs last
  /// year's version after the configuration has moved on.
  Future<void> ensureSchema() async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $table (id, agreement, version, actor, '
      'tenant, accepted_at)',
    );
    await database.execute(
        'CREATE TABLE IF NOT EXISTS $versionsTable (agreement, version)');
    for (final DVAgreement a in agreements) {
      final List<Map<String, Object?>> known = await database.query(
        'SELECT version FROM $versionsTable WHERE agreement = ? AND version = ?',
        <Object?>[a.id, a.version],
      );
      if (known.isEmpty) {
        await database.execute(
          'INSERT INTO $versionsTable (agreement, version) VALUES (?, ?)',
          <Object?>[a.id, a.version],
        );
      }
    }
  }

  DVAgreement _agreement(String id) {
    for (final DVAgreement a in agreements) {
      if (a.id == id) return a;
    }
    throw ArgumentError.value(id, 'agreement', 'is not declared');
  }

  /// Records that [actor] accepted the current version of [agreement].
  ///
  /// Throws [DVAgreementRecordError] when the record cannot be written: an
  /// acceptance nobody can produce in a dispute was not given.
  Future<DVAcceptance> accept(
    String agreement, {
    required String actor,
    String? tenant,
  }) async {
    final DVAgreement a = _agreement(agreement);
    final DateTime at = _clock().toUtc();
    final DVAcceptance acceptance = DVAcceptance(
      id: '${a.id}-${at.microsecondsSinceEpoch}-${_ids++}',
      agreement: a.id,
      version: a.version,
      actor: actor,
      tenant: tenant,
      acceptedAt: at,
    );
    try {
      await database.execute(
        'INSERT INTO $table (id, agreement, version, actor, tenant, '
        'accepted_at) VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[
          acceptance.id,
          acceptance.agreement,
          acceptance.version,
          acceptance.actor,
          acceptance.tenant,
          at.toIso8601String(),
        ],
      );
    } on Object catch (error) {
      throw DVAgreementRecordError(a.id, error);
    }
    return acceptance;
  }

  /// Acceptances by [actor], oldest first, optionally of one [agreement].
  Future<List<DVAcceptance>> acceptances({
    required String actor,
    String? agreement,
  }) async {
    final List<Map<String, Object?>> rows = await database
        .query('SELECT * FROM $table WHERE actor = ?', <Object?>[actor]);
    return <DVAcceptance>[
      for (final Map<String, Object?> row in rows)
        if (agreement == null || row['agreement'] == agreement)
          DVAcceptance._fromRow(row),
    ]..sort((DVAcceptance x, DVAcceptance y) =>
        x.acceptedAt.compareTo(y.acceptedAt));
  }

  /// Whether [actor] has yet to accept the current version of [agreement].
  Future<bool> needsAcceptance(String agreement, {required String actor}) async {
    final DVAgreement a = _agreement(agreement);
    return !(await acceptances(actor: actor, agreement: a.id))
        .any((DVAcceptance x) => x.version == a.version);
  }

  /// The agreements [actor] has yet to accept, for the application to gate on
  /// where it chooses.
  Future<List<DVAgreement>> pending({required String actor}) async =>
      <DVAgreement>[
        for (final DVAgreement a in agreements)
          if (await needsAcceptance(a.id, actor: actor)) a,
      ];

  /// The version of [agreement] in force on [at]: the latest known version
  /// that had taken effect by then, or null before the first.
  Future<String?> inForce(String agreement, {required DateTime at}) async {
    _agreement(agreement);
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT version FROM $versionsTable WHERE agreement = ?',
      <Object?>[agreement],
    );
    String? found;
    for (final Map<String, Object?> row in rows) {
      final String version = '${row['version']}';
      final DateTime? effective = DVAgreement._effective(version);
      if (effective == null || effective.isAfter(at)) continue;
      if (found == null || version.compareTo(found) > 0) found = version;
    }
    return found;
  }

  /// The acceptance that answers "did [actor] accept the version of
  /// [agreement] in force on [at]?", or null when none does. An acceptance
  /// given after [at] does not answer for it.
  Future<DVAcceptance?> acceptedInForce(
    String agreement, {
    required String actor,
    required DateTime at,
  }) async {
    final String? version = await inForce(agreement, at: at);
    if (version == null) return null;
    for (final DVAcceptance a
        in await acceptances(actor: actor, agreement: agreement)) {
      if (a.version == version && !a.acceptedAt.isAfter(at)) return a;
    }
    return null;
  }

  /// Export carries the subject's acceptances; erasure keeps them as evidence
  /// under the pseudonym.
  DVPrivacyAdapter privacyAdapter() => _DVAgreementsPrivacyAdapter(this);
}

class _DVAgreementsPrivacyAdapter implements DVPrivacyAdapter {
  _DVAgreementsPrivacyAdapter(this.agreements);

  final DVAgreements agreements;

  @override
  String get name => 'agreements';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    final List<DVAcceptance> held =
        await agreements.acceptances(actor: '${subject.id}');
    for (final DVAcceptance a in held) {
      await agreements.database.execute(
        'UPDATE ${DVAgreements.table} SET actor = ? WHERE id = ?',
        <Object?>[subject.pseudonym, a.id],
      );
    }
    if (held.isNotEmpty) {
      DVObservability.log(
        '${held.length} agreement acceptances were kept after erasure as '
        'evidence, under the pseudonym',
        context: <String, Object?>{'subject': subject.pseudonym},
      );
    }
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'acceptances': <Map<String, Object?>>[
          for (final DVAcceptance a
              in await agreements.acceptances(actor: '${subject.id}'))
            a.toJson(),
        ],
      };
}
