/// Subscription lifecycle operations added to [DVBillingProvider] for Step 2.
///
/// Not every provider supports every operation; unsupported paths throw
/// [UnsupportedError] with a message naming the missing capability, so the
/// failure is visible rather than silent.
library dartvel.billing.subscription_lifecycle;

import '../../dartvel.dart' show BillingPlan;

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

/// Changing, pausing, resuming and cancelling a subscription, and reading its
/// state. A separate interface from [DVBillingProvider] so a provider written
/// before these existed still compiles; Stripe, Paddle and the local provider
/// implement both. Check with `provider is DVSubscriptionLifecycle`.
abstract interface class DVSubscriptionLifecycle {
  /// Change the customer's subscription to [plan]. When [prorate] is true,
  /// the provider applies proration if it supports it; when false, the change
  /// takes effect at the next billing period without proration.
  ///
  /// Throws [UnsupportedError] when the provider does not implement plan
  /// changes (e.g. a provider that bills through metered quantities rather
  /// than subscription price updates).
  Future<void> changeSubscriptionPlan({
    required Object customer,
    required BillingPlan plan,
    bool prorate = true,
  });

  /// Cancel the customer's subscription. When [atPeriodEnd] is true, the
  /// subscription remains active until the current billing period ends and
  /// is then revoked; when false, it is revoked immediately.
  ///
  /// Throws [UnsupportedError] when the provider does not support deferred
  /// cancellation.
  Future<void> cancelSubscription({
    required Object customer,
    bool atPeriodEnd = false,
  });

  /// Resume a previously paused or canceled-at-period-end subscription.
  ///
  /// Throws [UnsupportedError] when the provider does not support resumption.
  Future<void> resumeSubscription({required Object customer});

  /// Pause the customer's subscription. The subscription stays active with no
  /// charge until resumed; the exact behavior depends on the provider.
  ///
  /// Throws [UnsupportedError] when the provider does not support pausing.
  Future<void> pauseSubscription({required Object customer});

  /// The subscription status for [customer], including whether it is deferred
  /// for cancellation at period end.
  ///
  /// Throws [UnsupportedError] when the provider does not expose subscription
  /// status through this surface.
  Future<DVSubscriptionStatus> subscriptionStatus({required Object customer});

  /// A URL the customer can open to manage their billing (update card,
  /// download invoices, view subscription details).
  ///
  /// Throws [UnsupportedError] when the provider does not expose a customer
  /// portal through this surface.
  Future<String> customerPortalUrl({required Object customer});
}
