/// The health endpoint a worker or a cron process serves when given
/// `DARTVEL_HEALTH_PORT`.
///
/// Those processes serve nothing, so a supervisor, an orchestrator or a load
/// balancer had nothing to ask whether one was up. It answers `GET` and
/// `HEAD` on `/healthz` and nothing else: a health port that also answered
/// the application would be a worker reachable over HTTP by anybody who
/// found the port.
library;

import 'process_configuration.dart';
import 'process_health_unsupported.dart'
    if (dart.library.io) 'process_health_io.dart' as impl;

/// A running health endpoint.
abstract interface class DVProcessHealth {
  /// Binds [host]:[port] and answers `/healthz` for a [role] process with
  /// `200 {"status": "ok", "role": ...}` while it is open.
  static Future<DVProcessHealth> serve({
    required String host,
    required int port,
    required DVProcessRole role,
  }) =>
      impl.dvServeProcessHealth(host: host, port: port, role: role);

  /// The port bound, which is [serve]'s unless that was 0.
  int get port;

  /// Stops answering. Idempotent.
  Future<void> close();
}
