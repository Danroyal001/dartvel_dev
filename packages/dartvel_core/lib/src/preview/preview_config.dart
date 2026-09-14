/// `dartvel.preview` in `pubspec.yaml`.
///
/// Read strictly, the way `dartvel.deploy` is: a value that cannot be read is
/// refused rather than defaulted, because a misspelled `visibility` that
/// quietly became a default is an environment somebody believes is private.
library;

/// Where a preview's database comes from.
enum DVPreviewDatabase {
  /// Empty, migrated by the project's plan and filled by its seeds.
  fresh,

  /// A provider branch of production, used for the schema and sanitized
  /// before anything can read it.
  branch,
}

/// Who can open a preview.
enum DVPreviewVisibility {
  /// Behind the deployment's organization membership.
  members,

  /// Anyone holding an unguessable URL.
  link,

  /// Anyone at all. A declaration, reported as `DV-PREVIEW-007`.
  public,
}

/// `dartvel.preview`.
final class DVPreviewConfig {
  const DVPreviewConfig({
    this.database = DVPreviewDatabase.fresh,
    this.sanitize,
    this.ttl = const Duration(days: 7),
    this.idle = const Duration(minutes: 30),
    this.max = 10,
    this.visibility = DVPreviewVisibility.members,
    this.schedules = const <String>{},
  });

  final DVPreviewDatabase database;

  /// The sanitization step that runs over a branched database before the
  /// preview is deployed. Present exactly when [database] is `branch`.
  final String? sanitize;

  /// How long after its last deploy a preview is destroyed.
  final Duration ttl;

  /// How long a preview may go unrequested before it is suspended.
  final Duration idle;

  /// How many previews may be running at once.
  final int max;

  final DVPreviewVisibility visibility;

  /// Scheduled tasks declared to run in previews. Every other schedule is
  /// off, reported as `DV-PREVIEW-008`.
  final Set<String> schedules;

  static const Set<String> _keys = <String>{
    'database',
    'sanitize',
    'ttl',
    'idle',
    'max',
    'visibility',
    'schedules',
  };

  /// Reads the `dartvel.preview` map. Null is the defaults.
  factory DVPreviewConfig.fromConfig(Map<Object?, Object?>? preview) {
    if (preview == null) return const DVPreviewConfig();
    for (final Object? key in preview.keys) {
      if (!_keys.contains(key)) {
        throw FormatException(
          'dartvel.preview.$key is not a setting; expected one of '
          '${_keys.join(', ')}',
        );
      }
    }

    final DVPreviewDatabase database = _enum(
      preview['database'],
      DVPreviewDatabase.values,
      'dartvel.preview.database',
      DVPreviewDatabase.fresh,
    );

    final Object? rawSanitize = preview['sanitize'];
    if (rawSanitize != null && (rawSanitize is! String || rawSanitize.trim().isEmpty)) {
      throw FormatException(
        'dartvel.preview.sanitize must be the path of a sanitization step, '
        'got $rawSanitize',
      );
    }
    final String? sanitize = rawSanitize as String?;
    if (database == DVPreviewDatabase.branch && sanitize == null) {
      // Refused here as well as at create time, where DV-PREVIEW-003 names
      // the sensitive fields: a project that declares branching has said it
      // will copy production's rows, and the declaration is the place to say
      // what makes that safe.
      throw const FormatException(
        'dartvel.preview.database is branch, so dartvel.preview.sanitize is '
        'required: a branch carries production rows until a sanitization '
        'step has run over them',
      );
    }
    if (database == DVPreviewDatabase.fresh && sanitize != null) {
      throw const FormatException(
        'dartvel.preview.sanitize only runs over a branched database; with '
        'database: fresh it would never run. Remove it, or declare '
        'database: branch',
      );
    }

    final Object? rawMax = preview['max'];
    int max = 10;
    if (rawMax != null) {
      if (rawMax is! int || rawMax < 1) {
        throw FormatException(
          'dartvel.preview.max must be a whole number of at least 1, got $rawMax',
        );
      }
      max = rawMax;
    }

    final Object? rawSchedules = preview['schedules'];
    Set<String> schedules = const <String>{};
    if (rawSchedules != null) {
      if (rawSchedules is! List || rawSchedules.any((Object? s) => s is! String)) {
        throw FormatException(
          'dartvel.preview.schedules must be a list of scheduled task names, '
          'got $rawSchedules',
        );
      }
      schedules = Set<String>.unmodifiable(rawSchedules.cast<String>());
    }

    return DVPreviewConfig(
      database: database,
      sanitize: sanitize,
      ttl: preview.containsKey('ttl')
          ? _duration(preview['ttl'], 'dartvel.preview.ttl')
          : const Duration(days: 7),
      idle: preview.containsKey('idle')
          ? _duration(preview['idle'], 'dartvel.preview.idle')
          : const Duration(minutes: 30),
      max: max,
      visibility: _enum(
        preview['visibility'],
        DVPreviewVisibility.values,
        'dartvel.preview.visibility',
        DVPreviewVisibility.members,
      ),
      schedules: schedules,
    );
  }

  static T _enum<T extends Enum>(
    Object? raw,
    List<T> values,
    String path,
    T fallback,
  ) {
    if (raw == null) return fallback;
    for (final T value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException(
      '$path must be one of ${values.map((T v) => v.name).join(' | ')}, got $raw',
    );
  }

  /// `30m`, `12h`, `7d`. A bare number is refused: `7` could be days or
  /// seconds, and the difference is a week of a machine.
  static Duration _duration(Object? value, String path) {
    final Match? match = value is String
        ? RegExp(r'^\s*(\d+)\s*([smhd])\s*$').firstMatch(value)
        : null;
    if (match == null) {
      throw FormatException(
        '$path must be a number of seconds, minutes, hours or days '
        '(e.g. 30m, 7d), got $value',
      );
    }
    final int n = int.parse(match.group(1)!);
    final Duration duration = switch (match.group(2)) {
      's' => Duration(seconds: n),
      'm' => Duration(minutes: n),
      'h' => Duration(hours: n),
      _ => Duration(days: n),
    };
    if (duration <= Duration.zero) {
      throw FormatException('$path must be positive, got $value');
    }
    return duration;
  }
}
