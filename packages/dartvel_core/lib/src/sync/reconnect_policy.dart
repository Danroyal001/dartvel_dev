/// How the sync carrier comes back after its connection drops.
library dartvel_core.sync.reconnect_policy;

import 'dart:math';

/// Exponential backoff with jitter, optionally bounded in attempts.
///
/// Every client of a server that restarts loses its connection at the same
/// moment; jitter spreads their return so they do not arrive in one wave.
class DVReconnectPolicy {
  /// The wait before the first attempt.
  final Duration initialDelay;

  /// The longest wait between attempts.
  final Duration maxDelay;

  /// How much each wait grows over the one before.
  final double multiplier;

  /// The share of each wait that is randomised, `0` to `1`: with `0.2` a
  /// one-second wait is somewhere between 800 ms and one second.
  final double jitter;

  /// Attempts before giving up; null keeps trying for as long as the
  /// carrier is open.
  final int? maxAttempts;

  const DVReconnectPolicy({
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2,
    this.jitter = 0.2,
    this.maxAttempts,
  });

  /// Never reconnects: a dropped connection leaves the carrier failed.
  static const DVReconnectPolicy never = DVReconnectPolicy(maxAttempts: 0);

  static final Random _random = Random();

  /// The wait before attempt number [attempt] (1 is the first after a
  /// drop), or null when the policy has given up.
  Duration? delayFor(int attempt, {Random? random}) {
    final int? limit = maxAttempts;
    if (attempt < 1 || (limit != null && attempt > limit)) return null;
    final double grown = initialDelay.inMicroseconds *
        pow(multiplier, min(attempt - 1, 62)).toDouble();
    final double capped = min(grown, maxDelay.inMicroseconds.toDouble());
    final double spread = jitter.clamp(0, 1).toDouble();
    final double factor =
        spread == 0 ? 1 : 1 - spread * (random ?? _random).nextDouble();
    return Duration(microseconds: (capped * factor).round());
  }
}
