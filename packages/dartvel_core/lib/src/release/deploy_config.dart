/// `dartvel.deploy` in `pubspec.yaml`: the strategy, its canary steps, and the
/// health gate's thresholds.
///
/// Read strictly. A value that cannot be read is refused rather than defaulted,
/// because a typo that quietly became a default is a rollout nobody chose.
library;

/// How a new release replaces the running one.
enum DVDeployStrategy {
  recreate('recreate'),
  blueGreen('blue-green'),
  canary('canary');

  const DVDeployStrategy(this.configName);

  /// How `pubspec.yaml` spells it.
  final String configName;
}

/// The Backend Function Request Lifecycle's stages, numbered as the
/// specification numbers them, so a failure has a place rather than a rate.
enum DVRequestStage {
  received(1),
  traceCreated(2),
  envelopeDecoded(3),
  contextCreated(4),
  environmentResolved(5),
  tenantResolved(6),
  authentication(7),
  originChecks(8),
  rateLimits(9),
  parametersDecoded(10),
  validation(11),
  authorization(12),
  transactionOpened(13),
  execution(14),
  reversibleOperations(15),
  deferredOperations(16),
  commit(17),
  afterCommit(18),
  responseEncoded(19),
  telemetry(20),
  responseReturned(21);

  const DVRequestStage(this.number);

  final int number;
}

/// The weights a canary moves through, and how long it holds at each.
final class DVCanaryConfig {
  const DVCanaryConfig({
    this.steps = const <int>[5, 25, 50, 100],
    this.hold = const Duration(minutes: 10),
  });

  /// Percentages of traffic, strictly increasing, ending at 100.
  final List<int> steps;

  /// How long each step is watched before the gate is read.
  final Duration hold;

  /// Throws when the steps cannot complete a rollout.
  void validate() {
    final String? problem = _problem(steps, hold);
    if (problem != null) throw ArgumentError(problem);
  }

  static String? _problem(List<int> steps, Duration hold) {
    if (steps.isEmpty) return 'canary steps are empty';
    int last = 0;
    for (final int step in steps) {
      if (step < 1 || step > 100) {
        return 'canary step $step is not a percentage between 1 and 100';
      }
      if (step <= last) {
        return 'canary steps must climb: $step follows $last';
      }
      last = step;
    }
    // A rollout whose last step is below 100 never completes: it sits at the
    // last weight and reads as a rollout in progress forever.
    if (last != 100) return 'canary steps end at $last, not 100';
    if (hold <= Duration.zero) return 'a canary hold must be positive';
    return null;
  }
}

/// What the health gate tolerates, relative to the release being replaced.
///
/// Every threshold is a margin over the previous release's own number:
/// absolute numbers encode one deployment's traffic and are wrong on the next.
final class DVReleaseThresholds {
  const DVReleaseThresholds({
    this.errorRate = 0.01,
    this.stages = const <DVRequestStage, double>{
      DVRequestStage.commit: 0.001,
      DVRequestStage.authorization: 0.02,
    },
    this.latencyP95Increase = 0.20,
  });

  /// How far the candidate's failure rate may exceed the previous release's,
  /// as a share of requests: 0.01 is one percentage point.
  final double errorRate;

  /// The same margin for failures at one lifecycle stage.
  final Map<DVRequestStage, double> stages;

  /// How much slower the candidate's p95 may be, as a share of the previous
  /// release's: 0.20 is twenty per cent.
  final double latencyP95Increase;
}

/// `dartvel.deploy`.
final class DVDeployConfig {
  const DVDeployConfig({
    this.strategy = DVDeployStrategy.recreate,
    this.canary = const DVCanaryConfig(),
    this.gate = const DVReleaseThresholds(),
  });

  final DVDeployStrategy strategy;
  final DVCanaryConfig canary;

  /// Never absent. A missing `gate` section is the default thresholds: a gate
  /// with none passes every release, which is no gate that reads as one.
  final DVReleaseThresholds gate;

  /// Reads the `dartvel.deploy` map. Null is the defaults.
  ///
  /// Under `gate`, a key left out takes its default; `stages`, when given,
  /// replaces the default stages rather than adding to them, so a project can
  /// say which stages it gates on.
  factory DVDeployConfig.fromConfig(Map<Object?, Object?>? deploy) {
    if (deploy == null) return const DVDeployConfig();
    _onlyKeys(deploy, 'dartvel.deploy', const <String>{
      'strategy',
      'canary',
      'gate',
    });

    DVDeployStrategy strategy = DVDeployStrategy.recreate;
    final Object? rawStrategy = deploy['strategy'];
    if (rawStrategy != null) {
      strategy = DVDeployStrategy.values.firstWhere(
        (DVDeployStrategy s) => s.configName == rawStrategy,
        orElse: () => throw FormatException(
          'dartvel.deploy.strategy must be one of '
          '${DVDeployStrategy.values.map((DVDeployStrategy s) => s.configName).join(' | ')}, '
          'got $rawStrategy',
        ),
      );
    }

    DVCanaryConfig canary = const DVCanaryConfig();
    final Object? rawCanary = deploy['canary'];
    if (rawCanary != null) {
      final Map<Object?, Object?> map = _map(rawCanary, 'dartvel.deploy.canary');
      _onlyKeys(map, 'dartvel.deploy.canary', const <String>{'steps', 'hold'});
      List<int> steps = canary.steps;
      if (map.containsKey('steps')) {
        final Object? raw = map['steps'];
        if (raw is! List || raw.any((Object? s) => s is! int)) {
          throw FormatException(
            'dartvel.deploy.canary.steps must be a list of percentages, got $raw',
          );
        }
        steps = List<int>.unmodifiable(raw.cast<int>());
      }
      Duration hold = canary.hold;
      if (map.containsKey('hold')) hold = _duration(map['hold']);
      final String? problem = DVCanaryConfig._problem(steps, hold);
      if (problem != null) {
        throw FormatException('dartvel.deploy.canary: $problem');
      }
      canary = DVCanaryConfig(steps: steps, hold: hold);
    }

    DVReleaseThresholds gate = const DVReleaseThresholds();
    final Object? rawGate = deploy['gate'];
    if (rawGate != null) {
      final Map<Object?, Object?> map = _map(rawGate, 'dartvel.deploy.gate');
      _onlyKeys(map, 'dartvel.deploy.gate', const <String>{
        'errorRate',
        'stages',
        'latencyP95',
      });
      Map<DVRequestStage, double> stages = gate.stages;
      if (map.containsKey('stages')) {
        final Map<Object?, Object?> rawStages = _map(
          map['stages'],
          'dartvel.deploy.gate.stages',
        );
        stages = <DVRequestStage, double>{};
        for (final MapEntry<Object?, Object?> e in rawStages.entries) {
          final DVRequestStage stage = DVRequestStage.values.firstWhere(
            (DVRequestStage s) => s.name == e.key,
            orElse: () => throw FormatException(
              'dartvel.deploy.gate.stages.${e.key} is not a lifecycle stage',
            ),
          );
          stages[stage] = _percent(
            e.value,
            'dartvel.deploy.gate.stages.${e.key}',
            max: 1,
          );
        }
      }
      gate = DVReleaseThresholds(
        errorRate: map.containsKey('errorRate')
            ? _percent(map['errorRate'], 'dartvel.deploy.gate.errorRate', max: 1)
            : gate.errorRate,
        stages: Map<DVRequestStage, double>.unmodifiable(stages),
        latencyP95Increase: map.containsKey('latencyP95')
            ? _percent(map['latencyP95'], 'dartvel.deploy.gate.latencyP95')
            : gate.latencyP95Increase,
      );
    }

    return DVDeployConfig(strategy: strategy, canary: canary, gate: gate);
  }

  static Map<Object?, Object?> _map(Object? value, String path) {
    if (value is Map) return value.cast<Object?, Object?>();
    throw FormatException('$path must be a map, got $value');
  }

  static void _onlyKeys(
    Map<Object?, Object?> map,
    String path,
    Set<String> allowed,
  ) {
    for (final Object? key in map.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
          '$path.$key is not a setting; expected one of ${allowed.join(', ')}',
        );
      }
    }
  }

  static Duration _duration(Object? value) {
    final Match? match = value is String
        ? RegExp(r'^\s*(\d+)\s*([smh])\s*$').firstMatch(value)
        : null;
    if (match == null) {
      throw FormatException(
        'dartvel.deploy.canary.hold must be seconds, minutes or hours '
        '(e.g. 10m), got $value',
      );
    }
    final int n = int.parse(match.group(1)!);
    final Duration hold = switch (match.group(2)) {
      's' => Duration(seconds: n),
      'h' => Duration(hours: n),
      _ => Duration(minutes: n),
    };
    if (hold <= Duration.zero) {
      throw FormatException('dartvel.deploy.canary.hold must be positive, got $value');
    }
    return hold;
  }

  /// `1%`, `0.1%`, `+20%`. A bare number is refused: `1` could mean one per
  /// cent or all of it.
  static double _percent(Object? value, String path, {double? max}) {
    final Match? match = value is String
        ? RegExp(r'^\s*\+?\s*(\d+(?:\.\d+)?)\s*%\s*$').firstMatch(value)
        : null;
    if (match == null) {
      throw FormatException('$path must be a percentage (e.g. 1%), got $value');
    }
    final double fraction = double.parse(match.group(1)!) / 100;
    if (max != null && fraction > max) {
      throw FormatException('$path cannot exceed ${max * 100}%, got $value');
    }
    return fraction;
  }
}
