import 'package:dartvel_core/dartvel.dart';

/// A schedule and two tools, under the backend and off the route table.
///
/// `lib/backend/functions/` is what becomes routes; this file is one level
/// up, so these are a cron entry and two AI tools and nothing answers a URL.
///
/// They are here for the same reason as `quote.get.dart`: the generated
/// registration and the generated scheduler are code nothing compiled. A
/// tool returning `Future<void>` is the case that caught it -- `await` on
/// one produces void, and the handler used to assign that to a variable.
@DVBackendCron('0 3 * * *')
Future<void> nightlyDigest() async {}

@DVAITool(description: 'Tell the owner an order shipped')
Future<void> tellOwner(String orderId) async {}

@DVAITool(description: 'How many orders are waiting')
Future<int> openOrders(String status) async => status.isEmpty ? 0 : 1;
