/// Subscription lifecycle operations added to [DVBillingProvider] for Step 2.
///
/// Not every provider supports every operation; unsupported paths throw
/// [UnsupportedError] with a message naming the missing capability, so the
/// failure is visible rather than silent.
library dartvel.billing.subscription_lifecycle;

/// The current subscription state read from a provider.
class DVSubscriptionStatus {
  const DVSubscriptionStatus({
    required this.status,
    this.cancelAtPeriodEnd = false,
    this.currentPeriodEnd,
  });

  /// Provider-specific status code (e.g. Stripe `status`, Paddle `status`).
  final String status;

  /// Whether cancellation is deferred to the end of the billing period.
  final bool cancelAtPeriodEnd;

  /// When the current billing period ends, in UTC.
  final DateTime? currentPeriodEnd;

  @override
  String toString() => 'DVSubscriptionStatus($status, '
      'cancelAtPeriodEnd=$cancelAtPeriodEnd, '
      'currentPeriodEnd=$currentPeriodEnd)';
}
