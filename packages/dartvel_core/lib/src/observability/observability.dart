/// The process-wide metrics and health registries.
///
/// One instance each, because a scrape endpoint and a health endpoint are
/// process-wide by definition: a metric recorded into a registry nothing
/// serves is a metric nobody sees.
library dartvel.observability;

import 'health.dart';
import 'metrics.dart';

export 'health.dart';
export 'metrics.dart';

/// `DV.ObservabilityAndLogging` is built on these.
class DVObservability {
  const DVObservability._();

  static final DVMetrics metrics = DVMetrics();
  static final DVHealth health = DVHealth();

  /// Seconds this process has been up, as a gauge.
  ///
  /// Read at render time rather than recorded on a timer: a value refreshed by
  /// a periodic task is stale by up to its interval and keeps a timer alive
  /// for the life of the process to maintain a number that can be computed.
  static void refresh() {
    metrics
        .gauge('uptime_seconds', const <String, String>{},
            'Seconds since this process started.')
        .set(health.uptime.inMilliseconds / 1000);
  }

  /// The registry in Prometheus text exposition format, with the values that
  /// are computed rather than accumulated brought up to date first.
  static String render() {
    refresh();
    return metrics.render();
  }
}
