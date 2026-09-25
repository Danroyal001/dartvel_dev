// docs:start authz-policy
// lib/policies/order_policy.dart
import 'package:dartvel_core/dartvel.dart';

class const Order({required final String id, required final String ownerId});

@DVPolicy(Order)
class OrderPolicy {
  // A route has no order to pass, so the resource is nullable.
  bool view(DVSessionPrincipal? user, Order? order) => user != null;

  bool update(DVSessionPrincipal? user, Order? order) =>
      user != null && (order == null || order.ownerId == user.userId);
}
// docs:end
