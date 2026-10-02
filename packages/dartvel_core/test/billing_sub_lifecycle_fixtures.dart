/// Fixture loaders for subscription lifecycle tests.
///
/// Each fixture is a recorded payload from the provider's documented API or
/// webhook shape. They are never called against a live endpoint.
import 'dart:io';

String get stripeActiveSubscriptionFixture =>
    File('test/fixtures/stripe_subscription_active.json').readAsStringSync();
