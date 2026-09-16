// docs:start backend-context
// lib/backend/functions/orders/[id].put.dart is served at PUT /api/orders/:id.
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(
  policy: 'Order.update',
  mfa: DVMfa.recent(Duration(minutes: 15)),
)
Future<Map<String, Object?>> _updateOrder(
  DVContext context, // injected, and never sent by the client
  String id,
  String status,
) async {
  context.afterCommit(() => notifyCustomer(id));
  return <String, Object?>{
    'id': id,
    'status': status,
    'by': context.session?.userId,
  };
}
// docs:end

Future<void> notifyCustomer(String orderId) async {}
