/// Fixture-based tests for subscription lifecycle interface (Step 2).
///
/// These use recorded Stripe and Paddle fixtures; no live API keys are used.
/// The fixtures represent the documented webhook/subscription payload shapes.
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../dartvel.dart';
import 'billing_sub_lifecycle_fixtures.dart';

void main() {
  group('Subscription lifecycle fixtures', () {
    test('Stripe active subscription fixture is readable', () {
      final payload = stripeActiveSubscriptionFixture;
      final decoded = jsonDecode(payload);
      expect(decoded['status'], 'active');
      expect(decoded['customer'], 'cus_test_001');
      expect(decoded['cancel_at_period_end'], false);
    });

    test('DVSubscriptionStatus reads from Stripe fixture', () {
      final payload = stripeActiveSubscriptionFixture;
      final decoded = jsonDecode(payload);
      final status = DVSubscriptionStatus(
        status: '${decoded['status'] ?? ''}',
        cancelAtPeriodEnd: decoded['cancel_at_period_end'] == true,
        currentPeriodEnd: (decoded['current_period_end'] as int?) != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (decoded['current_period_end'] as int) * 1000,
                isUtc: true)
            : null,
      );
      expect(status.status, 'active');
      expect(status.cancelAtPeriodEnd, false);
      expect(status.currentPeriodEnd, isNotNull);
    });
  });
}
