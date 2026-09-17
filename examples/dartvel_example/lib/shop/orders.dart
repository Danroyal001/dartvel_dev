// Placing an order, and the roastery that moves it along.
import 'dart:async';

import '../dartvel_client/dartvel_client.dart';
import 'cart.dart';

/// The steps an order goes through, in order.
const List<String> orderStages = <String>[
  'placed',
  'roasting',
  'packed',
  'shipped',
  'delivered',
];

const Map<String, String> stageLabels = <String, String>{
  'placed': 'Order placed',
  'roasting': 'Roasting',
  'packed': 'Packed',
  'shipped': 'On its way',
  'delivered': 'Delivered',
};

/// Places [cart] as an order for [email]: stores it, queues the confirmation
/// mail, and hands it to the roastery. Empties the cart.
Future<Order> placeOrder({
  required Cart cart,
  required List<Product> catalog,
  required String email,
}) async {
  final Order order = Order(
    id: nextOrderId(),
    email: email,
    summary: cart.summary(catalog),
    itemCount: cart.count,
    totalCents: cart.totalCents(catalog),
    status: orderStages.first,
    placedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await order.save();
  DV.global<Cart>(const Cart());

  await SendOrderConfirmation(
    orderId: order.id,
    email: order.email,
    summary: order.summary,
    totalCents: order.totalCents,
  ).dispatch();
  await DV.Queues.work(queue: SendOrderConfirmation.queue);

  Roastery.instance.follow(order.id);
  return order;
}

int _sequence = 4180;

/// OAK-4181, OAK-4182, ...
String nextOrderId() => 'OAK-${++_sequence}';

/// Past orders for the demo account, so the orders tab has a history.
Future<void> seedOrderHistory(String email) async {
  final List<Order> existing = await Order.all();
  if (existing.any((Order o) => o.email == email)) return;
  final DateTime now = DateTime.now();
  final List<Order> history = <Order>[
    Order(
      id: 'OAK-4102',
      email: email,
      summary: '1 × Harbour Blend, 1 × Yirgacheffe',
      itemCount: 2,
      totalCents: 3400,
      status: 'delivered',
      placedAt: now.subtract(const Duration(days: 12)).millisecondsSinceEpoch,
    ),
    Order(
      id: 'OAK-3977',
      email: email,
      summary: '2 × Huila',
      itemCount: 2,
      totalCents: 3400,
      status: 'delivered',
      placedAt: now.subtract(const Duration(days: 41)).millisecondsSinceEpoch,
    ),
  ];
  for (final Order order in history) {
    await order.save();
  }
}

/// Moves orders through [orderStages], one step every [step].
///
/// A real roastery would do this from its own screen, on the server; here it
/// runs on the device so the demo moves without one. It only ever saves the
/// order, and the save is what every watcher hears -- the orders screen does
/// not know the roastery exists.
class Roastery {
  Roastery({this.step = const Duration(seconds: 8)});

  static Roastery instance = Roastery();

  final Duration step;
  final Map<String, Timer> _timers = <String, Timer>{};

  void follow(String orderId) {
    _timers[orderId]?.cancel();
    _timers[orderId] = Timer.periodic(step, (Timer timer) async {
      final Order? order = await Order.find(orderId);
      if (order == null) {
        timer.cancel();
        _timers.remove(orderId);
        return;
      }
      final int at = orderStages.indexOf(order.status);
      final String next =
          orderStages[(at + 1).clamp(0, orderStages.length - 1)];
      if (at + 1 >= orderStages.length - 1) {
        timer.cancel();
        _timers.remove(orderId);
      }
      await order.copyWith(status: next).save();
    });
  }

  /// Stops every order, for a test's teardown.
  void stop() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
