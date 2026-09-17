import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // docs:start secrets-test
  test('a secret is supplied for one test and gone after it', () async {
    await DV.Test.withSecrets(<String, String>{'PAYSTACK_SECRET': 'sk_test_1'}, () {
      expect(DV.Secrets.get('PAYSTACK_SECRET'), 'sk_test_1');
    });
    expect(DV.Secrets.has('PAYSTACK_SECRET'), isFalse);
  });
  // docs:end
}
