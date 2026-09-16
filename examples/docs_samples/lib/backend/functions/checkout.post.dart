import 'package:dartvel_core/dartvel.dart';

// docs:start backend-transaction
@DVBackendFunction()
Future<Map<String, Object?>> _checkout(String orderId) =>
    DVTransactionRunner()((DVContext context) async {
      final String charge = await chargeCard(orderId);
      // Runs if anything later in this transaction throws.
      context.compensate(() => refund(charge));
      // Runs only once everything succeeded.
      context.afterCommit(() => sendReceipt(orderId));
      return <String, Object?>{'charge': charge};
    });
// docs:end

Future<String> chargeCard(String orderId) async => 'charge-$orderId';
Future<void> refund(String chargeId) async {}
Future<void> sendReceipt(String orderId) async {}
