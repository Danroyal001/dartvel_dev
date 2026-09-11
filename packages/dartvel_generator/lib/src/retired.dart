import 'dart:async';

import 'package:build/build.dart';

/// What every dartvel_generator builder logs, once per build.
///
/// The build_runner path is retired in favour of the `dartvel` CLI, which
/// generates the whole client -- the barrel every page imports included, so it
/// can start from a clean checkout where these builders cannot.
const String dartvelGeneratorRetirementNotice =
    "dartvel_generator's build_runner builders are retired and will be "
    'removed in dartvel_generator 2.0.0. Generate with '
    '`dart run dartvel_cli:dartvel routes`, or just run `dartvel build`, '
    'which generates before it builds. The CLI writes the whole client -- '
    'the dartvel_client barrel, router, page bodies, functional widgets, '
    'models, functions and config -- where these builders write only part of '
    'it and cannot generate a client from a clean checkout at all. To '
    'migrate: drop build_runner and dartvel_generator from dev_dependencies '
    'and run `dart run dartvel_cli:dartvel routes`.';

/// A builder that still does its work and says it is on its way out.
///
/// Retired in place rather than deleted: `auto_apply: dependents` means every
/// project depending on dartvel_generator runs these, and a builder that
/// vanishes takes its previously generated `build_to: source` output with it,
/// which breaks a working project with no explanation. This keeps the output
/// identical and puts the migration in the build log instead.
class RetiredBuilder implements Builder {
  RetiredBuilder(this._inner);

  final Builder _inner;

  /// One warning per build, not one per input: these builders run over every
  /// file under `lib/`, and a warning each would bury the rest of the log.
  bool _announced = false;

  @override
  Map<String, List<String>> get buildExtensions => _inner.buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!_announced) {
      _announced = true;
      log.warning(dartvelGeneratorRetirementNotice);
    }
    return _inner.build(buildStep);
  }

  @override
  String toString() => '$_inner (retired)';
}
