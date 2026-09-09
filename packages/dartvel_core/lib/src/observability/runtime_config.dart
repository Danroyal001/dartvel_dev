/// What the server reads out of its environment when it starts.
///
/// The functions take the environment as a map rather than reaching for
/// `Platform.environment` themselves, for two reasons. This file is on the
/// import path of a Flutter web build, where `dart:io` does not exist; and a
/// configuration rule that can only be exercised by starting a real process
/// is a rule that gets tested by hand once and then drifts.
library dartvel.observability.runtime_config;

import 'observability.dart';

/// Whether this process should answer `GET /_dartvel/logs` and
/// `GET /_dartvel/traces`.
///
/// Anything that is not an affirmative spelling is a no, including a value
/// somebody typed wrong. Defaulting an unrecognised value to "on" would mean
/// a typo publishes the log buffer.
bool dvDiagnosticsEnabled(Map<String, String> environment) {
  final String value =
      (environment['DARTVEL_DIAGNOSTICS'] ?? '').trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes' || value == 'on';
}

/// Attaches the server's own log destination.
///
/// [write] takes a line; the server passes `stdout.writeln`. Container
/// runtimes, systemd and every hosted platform collect a process's stdout, so
/// writing there is what makes a log line reach the place an operator already
/// looks -- and one JSON object per line is what makes it queryable once it
/// gets there.
///
/// `DARTVEL_LOG_LEVEL` sets the floor. An unreadable value falls back to
/// `info` rather than throwing: a mistyped level in a deployment's
/// configuration must not be the reason a service will not boot.
void dvConfigureRuntimeLogging(
  Map<String, String> environment, {
  required void Function(String line) write,
}) {
  DVObservability.useLogging(
    sinks: <DVLogSink>[DVJsonLinesSink(write)],
    level: DVLogLevel.parse(environment['DARTVEL_LOG_LEVEL'] ?? 'info'),
  );
  DVObservability.diagnosticsEndpoints = dvDiagnosticsEnabled(environment);
}
