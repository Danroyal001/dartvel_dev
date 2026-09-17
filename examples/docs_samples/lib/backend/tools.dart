import 'package:dartvel_core/dartvel.dart';

// Under lib/backend and outside functions/, so this is a tool and no URL.

// docs:start ai-tool
@DVAITool(description: 'How many orders are waiting in a status')
Future<int> openOrders(String status) async => status == 'paid' ? 3 : 0;
// docs:end
