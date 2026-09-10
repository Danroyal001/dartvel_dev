// Usage recording is reachable from DV.Billing.
//
// The provider interface grew recordUsage and the facade did not, which
// would have left the method in the same position the annotation arguments
// keep ending up in: implemented, documented, and callable only by code that
// reaches past DV.Billing to the concrete provider. Application code uses
// the facade, so a meter it cannot reach is a meter nothing records.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVUsageMeter apiCalls = DVUsageMeter('api_calls');

void main() {
  tearDown(DV.Test.resetBillingProvider);

  test('a record made through the facade reaches the provider', () async {
    final DVLocalBillingProvider provider = DVLocalBillingProvider();
    DV.Billing.useProvider(provider);

    await DV.Billing.recordUsage(
      customer: 'user_1',
      meter: apiCalls,
      quantity: 12,
      idempotencyKey: 'job_1',
    );

    expect(provider.usage('user_1', apiCalls), 12);
  });

  test('recording with no provider configured says so rather than counting '
      'into nothing', () async {
    DV.Test.resetBillingProvider();

    // A closure rather than a future: the facade refuses before it has one,
    // the same way DV.Billing.checkout does.
    await expectLater(
      () => DV.Billing.recordUsage(
        customer: 'user_1',
        meter: apiCalls,
        quantity: 1,
        idempotencyKey: 'k',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
