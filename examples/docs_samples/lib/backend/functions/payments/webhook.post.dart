import 'package:dartvel_core/dartvel.dart';

// docs:start backend-raw-path
// Served at POST /payments/webhook, outside /api.
@DVBackendFunction(rawPath: '/payments/webhook')
Future<Map<String, Object?>> _paymentWebhook(String event, String reference) async {
  await recordPayment(event, reference);
  return <String, Object?>{'received': true};
}
// docs:end

Future<void> recordPayment(String event, String reference) async {}
