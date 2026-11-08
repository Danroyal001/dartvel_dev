/// `dartvel.run` in `pubspec.yaml`: the one block DV.run reads of its own
/// (NEW_SPEC.md, Application Entry, Configuration).
///
/// ```yaml
/// dartvel:
///   run:
///     bootBudget: 800ms     # phases 1-5 for an app entry
///     headlessBudget: 5s    # phases 1-6 for a headless entry
///     shutdownGrace: 20s    # server drain
/// ```
class const DVRunConfig({
  final Duration bootBudget = const Duration(milliseconds: 800),
  final Duration headlessBudget = const Duration(seconds: 5),
  final Duration shutdownGrace = const Duration(seconds: 20),
}) {
  static const Set<String> _keys = <String>{
    'bootBudget',
    'headlessBudget',
    'shutdownGrace',
  };

  /// Reads the `dartvel.run` value. Null is every default; a key it does not
  /// know, or a duration it cannot read, is an [ArgumentError], so a misspelt
  /// grace fails the build instead of being served as twenty seconds.
  factory DVRunConfig.parse(Object? value) {
    if (value == null) return const DVRunConfig();
    if (value is! Map) {
      throw ArgumentError.value(value, 'dartvel.run', 'must be a map');
    }
    for (final Object? key in value.keys) {
      if (!_keys.contains(key)) {
        throw ArgumentError.value(key, 'dartvel.run',
            'is not a dartvel.run key (${_keys.join(', ')})');
      }
    }
    Duration read(String key, Duration fallback) {
      final Object? raw = value[key];
      if (raw == null) return fallback;
      return dvParseRunDuration(raw, 'dartvel.run.$key');
    }

    return DVRunConfig(
      bootBudget: read('bootBudget', const Duration(milliseconds: 800)),
      headlessBudget: read('headlessBudget', const Duration(seconds: 5)),
      shutdownGrace: read('shutdownGrace', const Duration(seconds: 20)),
    );
  }
}

final RegExp _runDuration = RegExp(r'^(\d+)(ms|s|m|h)$');

/// `800ms`, `5s`, `1m`, `1h`. A bare number is refused: its unit is a guess.
Duration dvParseRunDuration(Object raw, String name) {
  final RegExpMatch? match = _runDuration.firstMatch('$raw'.trim());
  if (raw is! String || match == null) {
    throw ArgumentError.value(
        raw, name, 'must be a duration such as 800ms, 20s or 1m');
  }
  final int amount = int.parse(match.group(1)!);
  return switch (match.group(2)!) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    _ => Duration(hours: amount),
  };
}
