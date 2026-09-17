import 'package:dartvel_core/dartvel.dart';

// docs:start secrets-read
@DVBackendFunction(policy: 'Order.update')
Future<Map<String, Object?>> _refund(String reference) async {
  // Backend code has no DV facade, so it reads secrets through DVSecrets.
  final String key = const DVSecrets().get('PAYSTACK_SECRET'); // throws if unset
  final Response response = await const DVHttp().host('paystack').post(
    '/refund',
    json: <String, Object?>{'transaction': reference},
    headers: <String, String>{'authorization': 'Bearer $key'},
    idempotencyKey: 'refund-$reference',
  );
  return <String, Object?>{'status': response.status};
}
// docs:end
