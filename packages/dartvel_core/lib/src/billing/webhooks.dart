/// The parts of billing that are not one provider's.
///
/// These lived in `stripe.dart` because Stripe was written first, which left
/// Paddle importing its errors, its result type and its fetch signature from
/// a library named after a competitor. Worse, the webhook contract had no
/// name at all: verification was a method on each concrete class, so an
/// application holding a [DVBillingProvider] -- which is what DV.Billing
/// hands out -- could not verify a webhook without downcasting to whichever
/// provider it had configured, or writing the HMAC comparison again in the
/// route. The second is how a billing endpoint ends up trusting whatever is
/// posted to it.
library dartvel.billing.webhooks;

import '../../dartvel.dart' show Entitlement;

/// A billing operation that could not proceed, with a message safe to show.
class DVBillingError implements Exception {
  const DVBillingError(this.message);
  final String message;
  @override
  String toString() => 'DVBillingError: $message';
}

/// What a webhook did.
class DVBillingWebhookResult {
  const DVBillingWebhookResult({
    required this.type,
    required this.handled,
    this.customer,
    this.granted = const <Entitlement>{},
    this.revoked = const <Entitlement>{},
    this.stale = false,
  });

  final String type;

  /// Whether this provider acted on the event. False is still an
  /// acknowledgement: Stripe retries an unacknowledged webhook for days.
  final bool handled;

  /// Whether the event described a moment older than one already applied to
  /// the same subscription, and was therefore ignored.
  ///
  /// Being late is not being wrong, so a stale event is acknowledged like
  /// any other. This says why nothing changed, which is otherwise
  /// indistinguishable from an event that changed nothing.
  final bool stale;
  final String? customer;
  final Set<Entitlement> granted;
  final Set<Entitlement> revoked;
}

/// `(status, body)` for an HTTP [method] request to [url] with [headers].
///
/// [body] is null for a read. It used to be a required String and the method
/// was implied, which meant a provider could only write -- and a provider
/// that cannot read cannot check what a price actually costs before sending
/// somebody to pay it.
typedef DVBillingFetch = Future<(int, String)> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
);

/// A provider that accepts signed webhooks.
///
/// Separate from `DVBillingProvider` because not every provider has them:
/// nothing signs a local grant, and putting an unverified path behind the
/// same call as the verified ones is worse than not offering it.
abstract class DVBillingWebhookReceiver {
  /// The HTTP header this provider signs under, such as `Stripe-Signature`.
  ///
  /// Named by the provider so a caller does not have to know which one is
  /// configured in order to find the signature. A surface that made the
  /// caller pick the header would not be provider-independent.
  String get signatureHeaderName;

  /// Verifies [signatureHeader] against [payload] and applies the event.
  ///
  /// Throws when the signature is missing, wrong, or outside the accepted
  /// time window; nothing is changed in that case.
  Future<DVBillingWebhookResult> handleWebhook(
    String payload,
    String signatureHeader,
  );
}
