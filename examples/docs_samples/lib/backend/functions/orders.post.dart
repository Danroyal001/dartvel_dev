// docs:start backend-class-parameter
// lib/backend/functions/orders.post.dart
import 'package:dartvel_core/dartvel.dart';

import '../../models/order_draft.dart';

// OrderDraft is your own class with a fromJson factory. The client sends it
// with toJson, and the server hands the function an OrderDraft.
@DVBackendFunction()
Future<String> _placeOrder(
  OrderDraft draft,
  List<OrderDraft> extras,
  Map<String, Object?> meta,
  OrderDraft? note,
) async => draft.table;
// docs:end
