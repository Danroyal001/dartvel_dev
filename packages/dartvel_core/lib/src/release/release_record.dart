/// A release, the provenance record it carries, and the history rollback
/// reads.
///
/// The release is the unit of rollback. Its record says what was built, from
/// which commit, with which generated protocol version, which migration plan
/// ran, and who released it -- the same record an OTA patch carries -- so a
/// rollback can name what it restores rather than "whatever was there before".
library;

import 'release_diagnostics.dart';

/// Where one expand/contract migration stands, as the release section numbers
/// the deploy's choreography.
///
/// Ordered: a later phase has done everything an earlier one did.
enum DVReleaseMigrationPhase {
  /// The new shape exists alongside the old one; nothing reads it.
  expanded,

  /// Generated model code writes both shapes; reads stay on the old one.
  dualWriting,

  /// Existing rows have been copied to the new shape.
  backfilled,

  /// Every chunk agrees on both shapes, and reads have not moved. Every
  /// release that reads the old shape is still a safe rollback target.
  verified,

  /// Reads have moved to the new shape. The old shape is still written, so a
  /// release that reads it is still a safe rollback target.
  readSwitched,

  /// The old shape is no longer kept current: it has stopped being written,
  /// or has been dropped. No release built for an earlier phase can read it.
  contracted,
}

/// What a release was, recorded when it was released.
final class DVReleaseRecord {
  DVReleaseRecord({
    required this.id,
    required this.commit,
    required this.artifact,
    required this.protocolVersion,
    required this.migrationPlan,
    required this.releasedBy,
    required this.releasedAt,
    Set<String> functions = const <String>{},
    Map<String, DVReleaseMigrationPhase> schema =
        const <String, DVReleaseMigrationPhase>{},
  }) : functions = Set<String>.unmodifiable(functions),
       schema = Map<String, DVReleaseMigrationPhase>.unmodifiable(schema) {
    _nonBlank(id, 'id');
    _nonBlank(commit, 'commit');
    _nonBlank(artifact, 'artifact');
    _nonBlank(releasedBy, 'releasedBy');
    if (protocolVersion < 0) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'a protocol version is not negative',
      );
    }
    final String? plan = migrationPlan;
    if (plan != null) _nonBlank(plan, 'migrationPlan');
  }

  /// The release's name, e.g. `2026-09-11T14:02Z` or a build number.
  final String id;

  /// The commit it was built from.
  final String commit;

  /// What was built: the artifact's digest.
  final String artifact;

  /// The generated protocol version it serves.
  final int protocolVersion;

  /// The migration plan that ran with it, or null when none did.
  ///
  /// Null is written out rather than left out, so a record that forgot the
  /// field is distinguishable from one that ran no migration.
  final String? migrationPlan;

  /// Who released it.
  final String releasedBy;
  final DateTime releasedAt;

  /// The backend functions released together. In function mode they deploy
  /// independently and still roll back as this set.
  final Set<String> functions;

  /// The phase each expand/contract migration had reached when this release
  /// was deployed: the schema this release was built to run against.
  final Map<String, DVReleaseMigrationPhase> schema;

  DVReleaseRecord copyWith({
    String? migrationPlan,
    Map<String, DVReleaseMigrationPhase>? schema,
    Set<String>? functions,
  }) => DVReleaseRecord(
    id: id,
    commit: commit,
    artifact: artifact,
    protocolVersion: protocolVersion,
    migrationPlan: migrationPlan ?? this.migrationPlan,
    releasedBy: releasedBy,
    releasedAt: releasedAt,
    functions: functions ?? this.functions,
    schema: schema ?? this.schema,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'commit': commit,
    'artifact': artifact,
    'protocolVersion': protocolVersion,
    'migrationPlan': migrationPlan,
    'releasedBy': releasedBy,
    'releasedAt': releasedAt.toUtc().toIso8601String(),
    'functions': functions.toList()..sort(),
    'schema': <String, String>{
      for (final MapEntry<String, DVReleaseMigrationPhase> e in schema.entries)
        e.key: e.value.name,
    },
  };

  /// Reads a record. Every field is required and none is defaulted: a record
  /// with a guessed commit names a build nobody made.
  factory DVReleaseRecord.fromJson(Map<String, Object?> json) {
    T field<T>(String key) {
      if (!json.containsKey(key)) {
        throw FormatException('a release record needs "$key"');
      }
      final Object? value = json[key];
      if (value is! T) {
        throw FormatException('release record "$key" is not a $T: $value');
      }
      return value;
    }

    final DateTime? releasedAt = DateTime.tryParse(field<String>('releasedAt'));
    if (releasedAt == null) {
      throw FormatException(
        'release record "releasedAt" is not a timestamp: ${json['releasedAt']}',
      );
    }
    final Map<String, DVReleaseMigrationPhase> schema =
        <String, DVReleaseMigrationPhase>{};
    for (final MapEntry<Object?, Object?> e in field<Map>('schema').entries) {
      final DVReleaseMigrationPhase? phase = DVReleaseMigrationPhase.values
          .where((DVReleaseMigrationPhase p) => p.name == e.value)
          .firstOrNull;
      if (phase == null) {
        throw FormatException(
          'release record schema phase for ${e.key} is unknown: ${e.value}',
        );
      }
      schema['${e.key}'] = phase;
    }
    try {
      return DVReleaseRecord(
        id: field<String>('id'),
        commit: field<String>('commit'),
        artifact: field<String>('artifact'),
        protocolVersion: field<int>('protocolVersion'),
        migrationPlan: field<String?>('migrationPlan'),
        releasedBy: field<String>('releasedBy'),
        releasedAt: releasedAt,
        functions: <String>{
          for (final Object? f in field<List>('functions'))
            if (f is String)
              f
            else
              throw FormatException('release record function is not a name: $f'),
        },
        schema: schema,
      );
    } on ArgumentError catch (error) {
      throw FormatException('release record is not valid: ${error.message}');
    }
  }

  static void _nonBlank(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be blank');
    }
  }
}

/// One deploy in the history.
final class DVDeployedRelease {
  DVDeployedRelease._(
    this.id,
    this.at,
    this.provenance, {
    required this.isRollback,
    bool rolledBackFrom = false,
  }) : _rolledBackFrom = rolledBackFrom;

  final String id;
  final DateTime at;

  /// The release's record, or null when it was deployed without one
  /// (`DV-RELEASE-006`).
  final DVReleaseRecord? provenance;

  /// This deploy restored an earlier release.
  final bool isRollback;

  bool _rolledBackFrom;

  /// A later rollback took this deploy away. It is never the "previous"
  /// release again: going back to it is rolling forward onto what was removed.
  bool get rolledBackFrom => _rolledBackFrom;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'provenance': provenance?.toJson(),
    'rollback': isRollback,
    'rolledBackFrom': _rolledBackFrom,
  };
}

/// Every deploy, oldest first.
final class DVReleaseHistory {
  DVReleaseHistory({DVReleaseDiagnosticSink? onDiagnostic})
    : _diagnose = onDiagnostic ?? dvLogReleaseDiagnostic;

  final DVReleaseDiagnosticSink _diagnose;
  final List<DVDeployedRelease> _releases = <DVDeployedRelease>[];

  /// The on-disk format.
  static const int format = 1;

  List<DVDeployedRelease> get releases =>
      List<DVDeployedRelease>.unmodifiable(_releases);

  /// The release serving now.
  DVDeployedRelease? get current => _releases.isEmpty ? null : _releases.last;

  /// [id] was deployed at [at], with its [provenance] record or without one.
  ///
  /// A deploy without a record is still recorded -- it happened -- and reports
  /// `DV-RELEASE-006`, because rollback cannot name it.
  void deployed(
    String id, {
    required DVReleaseRecord? provenance,
    required DateTime at,
  }) {
    _add(id, provenance, at, isRollback: false);
  }

  /// The current release was rolled back to [to], an earlier release, at [at].
  ///
  /// Every deploy after [to]'s most recent one is marked rolled back from.
  void rolledBack({required String to, required DateTime at}) {
    final DVDeployedRelease? now = current;
    if (now == null) {
      throw StateError('nothing has been deployed, so nothing can roll back');
    }
    if (now.id == to) {
      throw ArgumentError.value(to, 'to', 'is the release already serving');
    }
    int target = -1;
    for (int i = _releases.length - 2; i >= 0; i--) {
      if (_releases[i].id == to) {
        target = i;
        break;
      }
    }
    if (target < 0) {
      throw ArgumentError.value(to, 'to', 'was never deployed before this one');
    }
    _checkOrder(at);
    for (int i = target + 1; i < _releases.length; i++) {
      if (_releases[i].id != to) _releases[i]._rolledBackFrom = true;
    }
    _add(to, _releases[target].provenance, at, isRollback: true);
  }

  /// The release that was serving before the current one: not the current
  /// release again, and not one a rollback took away.
  DVDeployedRelease? previous() {
    final DVDeployedRelease? now = current;
    if (now == null) return null;
    for (int i = _releases.length - 2; i >= 0; i--) {
      final DVDeployedRelease candidate = _releases[i];
      if (candidate.id == now.id || candidate.rolledBackFrom) continue;
      return candidate;
    }
    return null;
  }

  /// The release serving at [at]: the newest deployed at or before it.
  DVDeployedRelease? servingAt(DateTime at) {
    for (int i = _releases.length - 1; i >= 0; i--) {
      if (!_releases[i].at.isAfter(at)) return _releases[i];
    }
    return null;
  }

  /// The most recent deploy of [id], or null.
  DVDeployedRelease? find(String id) {
    for (int i = _releases.length - 1; i >= 0; i--) {
      if (_releases[i].id == id) return _releases[i];
    }
    return null;
  }

  void _add(
    String id,
    DVReleaseRecord? provenance,
    DateTime at, {
    required bool isRollback,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'a release needs a name');
    }
    if (provenance != null && provenance.id != id) {
      throw ArgumentError.value(
        provenance.id,
        'provenance',
        'is the record of a different release than $id',
      );
    }
    _checkOrder(at);
    _releases.add(
      DVDeployedRelease._(id, at, provenance, isRollback: isRollback),
    );
    if (provenance == null) {
      _diagnose(
        'DV-RELEASE-006',
        'release $id was deployed with no provenance record; rollback cannot '
            'name what it would restore',
      );
    }
  }

  void _checkOrder(DateTime at) {
    final DVDeployedRelease? last = current;
    if (last != null && !at.isAfter(last.at)) {
      throw ArgumentError.value(
        at,
        'at',
        'is not after the last deploy (${last.at.toIso8601String()})',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'releases': <Object?>[for (final DVDeployedRelease r in _releases) r.toJson()],
  };

  /// Reads a history. Diagnostics are not raised again for deploys that
  /// already happened.
  factory DVReleaseHistory.fromJson(
    Map<String, Object?> json, {
    DVReleaseDiagnosticSink? onDiagnostic,
  }) {
    if (json['format'] != format) {
      throw FormatException(
        'release history format ${json['format']} is not $format',
      );
    }
    final Object? releases = json['releases'];
    if (releases is! List) {
      throw const FormatException('release history needs "releases"');
    }
    final DVReleaseHistory history = DVReleaseHistory(
      onDiagnostic: onDiagnostic,
    );
    for (final Object? raw in releases) {
      if (raw is! Map || !raw.containsKey('provenance')) {
        throw FormatException('release history entry is not readable: $raw');
      }
      final Object? id = raw['id'];
      final DateTime? at = raw['at'] is String
          ? DateTime.tryParse(raw['at'] as String)
          : null;
      final Object? provenance = raw['provenance'];
      if (id is! String ||
          at == null ||
          raw['rollback'] is! bool ||
          raw['rolledBackFrom'] is! bool ||
          (provenance != null && provenance is! Map)) {
        throw FormatException('release history entry is not readable: $raw');
      }
      history._checkOrder(at);
      history._releases.add(
        DVDeployedRelease._(
          id,
          at,
          provenance == null
              ? null
              : DVReleaseRecord.fromJson(
                  (provenance as Map).cast<String, Object?>(),
                ),
          isRollback: raw['rollback'] as bool,
          rolledBackFrom: raw['rolledBackFrom'] as bool,
        ),
      );
    }
    return history;
  }
}
