/// `dartvel.capture` in pubspec.yaml: where captured data models go.
///
/// An application writes `@DVModel(capture: true)` on a data model and this
/// declaration, and nothing else. The build parses it before generating
/// anything, so a declaration that cannot be honoured stops the build; the
/// generated server parses the same declaration again from what the build
/// wrote, so the two cannot disagree about what it says.
///
/// ```yaml
/// dartvel:
///   capture:
///     retention: 7d
///     destinations:
///       warehouse:
///         type: database
///         connection: WAREHOUSE_URL   # the secret holding it, by name
///         models: [Order]             # optional; every captured model
///         lagThreshold: 10m           # optional; DV-CDC-003 past it
/// ```
library dartvel_core.data.capture_config;

import '../schema/backfill.dart' show dvParseSchemaDuration;
import 'change_capture.dart' show DVCapture;

/// Where a destination's copies are written.
enum DVCaptureDestinationType {
  /// Another database Dartvel runs on, reached through the same record
  /// operations as the application's own: a collection per data model,
  /// holding each record's newest state.
  database,
}

/// `DV-CDC-006`, `DV-CDC-007` or `DV-CDC-008`: `dartvel.capture` says
/// something the framework cannot do.
class DVCaptureConfigError implements Exception {
  const DVCaptureConfigError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// One destination the captured data models are delivered to.
final class DVCaptureDestination {
  const DVCaptureDestination({
    required this.name,
    required this.type,
    required this.connection,
    this.models,
    this.lagThreshold,
  });

  /// What the pubspec calls it. Its position in the log is kept under this
  /// name, so renaming a destination starts it again with a backfill.
  final String name;
  final DVCaptureDestinationType type;

  /// The name of the secret holding the connection -- read through
  /// `DV.Secrets` when the server starts, never written into the pubspec.
  final String connection;

  /// The data models delivered, by class name; null for every captured one.
  final Set<String>? models;

  /// Past this, lag is reported as `DV-CDC-003`.
  final Duration? lagThreshold;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        'connection': connection,
        if (models != null) 'models': (models!.toList()..sort()),
        if (lagThreshold != null) 'lagThreshold': _format(lagThreshold!),
      };
}

/// `dartvel.capture`, as declared.
final class DVCaptureConfig {
  const DVCaptureConfig({
    this.retention = DVCapture.defaultRetention,
    this.destinations = const <DVCaptureDestination>[],
  });

  /// How long the log keeps a delivered change. A destination further
  /// behind than this is backfilled rather than handed a gap.
  final Duration retention;
  final List<DVCaptureDestination> destinations;

  static const Set<String> _keys = <String>{'retention', 'destinations'};
  static const Set<String> _destinationKeys = <String>{
    'type',
    'connection',
    'models',
    'lagThreshold',
  };
  static final RegExp _name = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
  static final RegExp _secret = RegExp(r'^[A-Z][A-Z0-9_]*$');
  static final RegExp _model = RegExp(r'^[A-Z][A-Za-z0-9_]*$');

  /// The declaration in [section], or null when there is none.
  ///
  /// Throws [DVCaptureConfigError] for anything it cannot honour: an unknown
  /// key, a type no adapter implements, a duration that is not one
  /// (`DV-CDC-006`), and a connection written out rather than named
  /// (`DV-CDC-007`).
  static DVCaptureConfig? parse(Object? section) {
    if (section == null) return null;
    final Map<Object?, Object?> map = _map(section, 'dartvel.capture');
    _refuseUnknown(map, _keys, 'dartvel.capture');
    final Duration retention = map['retention'] == null
        ? DVCapture.defaultRetention
        : _duration(map['retention'], 'dartvel.capture.retention');
    final Object? rawDestinations = map['destinations'];
    final List<DVCaptureDestination> destinations = <DVCaptureDestination>[];
    if (rawDestinations != null) {
      final Map<Object?, Object?> declared =
          _map(rawDestinations, 'dartvel.capture.destinations');
      for (final MapEntry<Object?, Object?> entry in declared.entries) {
        destinations.add(_destination('${entry.key}', entry.value));
      }
    }
    return DVCaptureConfig(retention: retention, destinations: destinations);
  }

  /// `DV-CDC-008` when a destination names a data model that is not among
  /// [captured], the class names of every `@DVModel(capture: true)`.
  void checkModels(Set<String> captured) {
    for (final DVCaptureDestination destination in destinations) {
      final List<String> strangers = <String>[
        for (final String model in destination.models ?? const <String>{})
          if (!captured.contains(model)) model,
      ]..sort();
      if (strangers.isEmpty) continue;
      throw DVCaptureConfigError(
        'DV-CDC-008',
        'dartvel.capture.destinations.${destination.name} takes '
            '${strangers.join(', ')}, which ${strangers.length == 1 ? 'is' : 'are'} '
            'not a captured data model. Write @DVModel(capture: true) on '
            '${strangers.length == 1 ? 'it' : 'each'}, or take '
            '${strangers.length == 1 ? 'it' : 'them'} out of models. '
            '${captured.isEmpty ? 'No data model is captured.' : 'Captured: ${(captured.toList()..sort()).join(', ')}.'}',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'retention': _format(retention),
        'destinations': <String, Object?>{
          for (final DVCaptureDestination d in destinations) d.name: d.toJson(),
        },
      };

  static DVCaptureDestination _destination(String name, Object? raw) {
    final String at = 'dartvel.capture.destinations.$name';
    if (!_name.hasMatch(name)) {
      throw DVCaptureConfigError(
        'DV-CDC-006',
        '$at: a destination is named with letters, digits, "-" and "_", '
            'starting with a letter.',
      );
    }
    final Map<Object?, Object?> map = _map(raw, at);
    _refuseUnknown(map, _destinationKeys, at);

    final Object? type = map['type'];
    final DVCaptureDestinationType? known = <DVCaptureDestinationType?>[
      ...DVCaptureDestinationType.values,
    ].firstWhere((DVCaptureDestinationType? t) => t?.name == '$type',
        orElse: () => null);
    if (type == null || known == null) {
      throw DVCaptureConfigError(
        'DV-CDC-006',
        '$at.type is ${type == null ? 'missing' : '"$type", which no destination adapter implements'}. '
            'It is one of: ${DVCaptureDestinationType.values.map((DVCaptureDestinationType t) => t.name).join(', ')}.',
      );
    }

    final Object? connection = map['connection'];
    if (connection == null) {
      throw DVCaptureConfigError(
        'DV-CDC-006',
        '$at.connection is missing: name the secret that holds where the '
            'destination is, such as WAREHOUSE_URL.',
      );
    }
    if (connection is! String || !_secret.hasMatch(connection)) {
      // Not repeated: what was written may be a URL with a password in it.
      throw DVCaptureConfigError(
        'DV-CDC-007',
        '$at.connection is written out rather than named. A connection '
            'carries credentials, and the pubspec is committed and shipped: '
            'put it in a secret and write the secret\'s name here, such as '
            'WAREHOUSE_URL.',
      );
    }

    Set<String>? models;
    final Object? rawModels = map['models'];
    if (rawModels != null) {
      if (rawModels is! List) {
        throw DVCaptureConfigError(
          'DV-CDC-006',
          '$at.models is a list of data model names, such as [Order].',
        );
      }
      models = <String>{};
      for (final Object? model in rawModels) {
        if (model is! String || !_model.hasMatch(model)) {
          throw DVCaptureConfigError(
            'DV-CDC-006',
            '$at.models names data models by their class, such as Order; '
                '"$model" is not one.',
          );
        }
        models.add(model);
      }
    }

    return DVCaptureDestination(
      name: name,
      type: known,
      connection: connection,
      models: models == null ? null : Set<String>.unmodifiable(models),
      lagThreshold: map['lagThreshold'] == null
          ? null
          : _duration(map['lagThreshold'], '$at.lagThreshold'),
    );
  }

  static Map<Object?, Object?> _map(Object? value, String at) {
    if (value is Map) return value.cast<Object?, Object?>();
    throw DVCaptureConfigError('DV-CDC-006', '$at is a map of settings.');
  }

  static void _refuseUnknown(
    Map<Object?, Object?> map,
    Set<String> keys,
    String at,
  ) {
    for (final Object? key in map.keys) {
      if (!keys.contains('$key')) {
        throw DVCaptureConfigError(
          'DV-CDC-006',
          '$at.$key is not a setting. $at takes '
              '${(keys.toList()..sort()).join(', ')}.',
        );
      }
    }
  }

  static Duration _duration(Object? value, String at) {
    Duration? parsed;
    if (value is String) {
      try {
        parsed = dvParseSchemaDuration(value);
      } on FormatException {
        parsed = null;
      }
    }
    if (parsed == null || parsed <= Duration.zero) {
      throw DVCaptureConfigError(
        'DV-CDC-006',
        '$at is a positive duration with its unit, such as 7d, 12h, 10m or '
            '30s; "$value" is not one.',
      );
    }
    return parsed;
  }
}

String _format(Duration d) => d.inMicroseconds % Duration.microsecondsPerSecond == 0
    ? '${d.inSeconds}s'
    : '${d.inMilliseconds}ms';
