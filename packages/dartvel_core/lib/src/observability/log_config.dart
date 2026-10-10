/// `dartvel.logging`: what a pubspec says about DV.log.
library dartvel.observability.log_config;

import 'logging.dart';

/// Logging as a project declares it.
///
/// ```yaml
/// dartvel:
///   logging:
///     level: info          # the floor for every destination
///     native: true         # logcat, the unified log, journald, the console
///     file:                # the device's own log; `file: false` keeps none
///       maxBytes: 1048576
///       files: 2
///       retentionDays: 7
///     ship:                # off unless declared
///       enabled: true
///       level: warn        # warn, error or fatal
///       batch: 50
///       perInstallPerHour: 600
///       maxBytes: 262144
/// ```
///
/// Read strictly, for the reason `dartvel.crashes` is: every setting has a
/// default, so a misspelt key or a string where a number belongs would be
/// replaced by the default and look exactly like a setting that was honoured.
/// Each is refused, naming the key.
final class DVLogConfig {
  const DVLogConfig({
    this.level = DVLogLevel.info,
    this.native = true,
    this.file = true,
    this.fileMaxBytes = 1024 * 1024,
    this.fileCount = 2,
    this.fileRetention = const Duration(days: 7),
    this.ship = false,
    this.shipLevel = DVLogLevel.warn,
    this.shipBatch = 50,
    this.ingestPerInstallPerHour = 600,
    this.ingestMaxBytes = 262144,
  });

  /// Records below this go nowhere, on any destination.
  final DVLogLevel level;

  /// Whether records are mirrored to the platform's own log.
  final bool native;

  /// Whether the device keeps a log file.
  final bool file;
  final int fileMaxBytes;
  final int fileCount;
  final Duration fileRetention;

  /// Whether a device sends its records to the application's backend.
  final bool ship;

  /// The lowest level sent. Never below warn: debug and info from every
  /// device in a fleet is a cost and a privacy problem, and the records worth
  /// having from a device someone else holds are the ones saying something
  /// went wrong.
  final DVLogLevel shipLevel;

  /// Records per request.
  final int shipBatch;

  /// Records the backend accepts from one install per hour; past it they are
  /// counted.
  final int ingestPerInstallPerHour;

  /// The largest batch body the backend accepts.
  final int ingestMaxBytes;

  static const String _section = 'dartvel.logging';

  static const List<String> settings = <String>[
    'level',
    'native',
    'file',
    'ship',
  ];
  static const List<String> fileSettings = <String>[
    'maxBytes',
    'files',
    'retentionDays',
  ];
  static const List<String> shipSettings = <String>[
    'enabled',
    'level',
    'batch',
    'perInstallPerHour',
    'maxBytes',
  ];

  /// Reads the `dartvel.logging` section, or the defaults when there is none.
  ///
  /// Throws [ArgumentError] naming the key for anything it cannot honour.
  factory DVLogConfig.parse(Object? section) {
    if (section == null) return const DVLogConfig();
    final Map<Object?, Object?> logging = _map(section, _section, settings);

    final DVLogLevel level = _level(logging['level'], '$_section.level',
        allowed: DVLogLevel.values, fallback: DVLogLevel.info);
    final bool native = _bool(logging['native'], '$_section.native', true);

    bool file = true;
    int fileMaxBytes = 1024 * 1024;
    int fileCount = 2;
    Duration fileRetention = const Duration(days: 7);
    final Object? rawFile = logging['file'];
    if (rawFile == false) {
      file = false;
    } else if (rawFile != null && rawFile != true) {
      final Map<Object?, Object?> fileSection =
          _map(rawFile, '$_section.file', fileSettings);
      fileMaxBytes = _int(fileSection['maxBytes'], '$_section.file.maxBytes',
          fallback: fileMaxBytes, minimum: 4096);
      fileCount = _int(fileSection['files'], '$_section.file.files',
          fallback: fileCount, minimum: 1, maximum: 16);
      fileRetention = Duration(
          days: _int(fileSection['retentionDays'],
              '$_section.file.retentionDays',
              fallback: 7, minimum: 1));
    }

    bool ship = false;
    DVLogLevel shipLevel = DVLogLevel.warn;
    int shipBatch = 50;
    int perInstallPerHour = 600;
    int maxBytes = 262144;
    final Object? rawShip = logging['ship'];
    if (rawShip != null) {
      final Map<Object?, Object?> shipSection =
          _map(rawShip, '$_section.ship', shipSettings);
      ship = _bool(shipSection['enabled'], '$_section.ship.enabled', false);
      shipLevel = _level(shipSection['level'], '$_section.ship.level',
          allowed: const <DVLogLevel>[
            DVLogLevel.warn,
            DVLogLevel.error,
            DVLogLevel.fatal,
          ],
          fallback: DVLogLevel.warn);
      shipBatch = _int(shipSection['batch'], '$_section.ship.batch',
          fallback: shipBatch, minimum: 1, maximum: 500);
      perInstallPerHour = _int(
          shipSection['perInstallPerHour'], '$_section.ship.perInstallPerHour',
          fallback: perInstallPerHour, minimum: 1);
      maxBytes = _int(shipSection['maxBytes'], '$_section.ship.maxBytes',
          fallback: maxBytes, minimum: 4096);
    }

    return DVLogConfig(
      level: level,
      native: native,
      file: file,
      fileMaxBytes: fileMaxBytes,
      fileCount: fileCount,
      fileRetention: fileRetention,
      ship: ship,
      shipLevel: shipLevel,
      shipBatch: shipBatch,
      ingestPerInstallPerHour: perInstallPerHour,
      ingestMaxBytes: maxBytes,
    );
  }

  /// The section as [parse] reads it, for the generated runtime to embed.
  Map<String, Object?> toDeclaration() => <String, Object?>{
        'level': level.name,
        'native': native,
        'file': file
            ? <String, Object?>{
                'maxBytes': fileMaxBytes,
                'files': fileCount,
                'retentionDays': fileRetention.inDays,
              }
            : false,
        'ship': <String, Object?>{
          'enabled': ship,
          'level': shipLevel.name,
          'batch': shipBatch,
          'perInstallPerHour': ingestPerInstallPerHour,
          'maxBytes': ingestMaxBytes,
        },
      };

  static Map<Object?, Object?> _map(
      Object? value, String key, List<String> known) {
    if (value is! Map) {
      throw ArgumentError.value(value, key, 'must be a map of settings');
    }
    for (final Object? name in value.keys) {
      if (!known.contains('$name')) {
        throw ArgumentError.value(value[name], '$key.$name',
            'is not a setting here; the settings are ${known.join(', ')}');
      }
    }
    return value;
  }

  static bool _bool(Object? value, String key, bool fallback) {
    if (value == null) return fallback;
    if (value is! bool) {
      throw ArgumentError.value(value, key, 'must be true or false');
    }
    return value;
  }

  static int _int(Object? value, String key,
      {required int fallback, required int minimum, int? maximum}) {
    if (value == null) return fallback;
    if (value is! int || value < minimum || (maximum != null && value > maximum)) {
      throw ArgumentError.value(
          value,
          key,
          maximum == null
              ? 'must be a whole number, $minimum or more'
              : 'must be a whole number from $minimum to $maximum');
    }
    return value;
  }

  static DVLogLevel _level(Object? value, String key,
      {required List<DVLogLevel> allowed, required DVLogLevel fallback}) {
    if (value == null) return fallback;
    final DVLogLevel? known = allowed
        .where((DVLogLevel level) => level.name == value)
        .firstOrNull;
    if (known == null) {
      throw ArgumentError.value(value, key,
          'must be one of ${allowed.map((DVLogLevel level) => level.name).join(', ')}');
    }
    return known;
  }
}
