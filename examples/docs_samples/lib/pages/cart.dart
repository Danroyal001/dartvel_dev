import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/cart.dart';

// docs:start state-signals
@DVPage(title: 'Cart')
Widget _cartPage(BuildContext context) {
  final DVSignal<int> quantity = context.signal(1);
  final DVSignal<int> price = context.signal(1200);

  // Each of these is a signal that tracks its sources.
  final total = price * quantity;
  final inStock = quantity > 0;

  return DVBox.list(<Widget>[
    // Reading .value in build redraws this page when a source changes.
    DVText('Total: ${total.value}'),
    DVText(inStock.value ? 'Ready to order' : 'Add something first'),
    DVText('Add one').modifier(
      DVModifier().onTap(() => quantity.value = quantity.value + 1),
    ),
  ]);
}
// docs:end

void operators(BuildContext context) {
  // docs:start state-operators
  final DVSignal<int> price = context.signal(1200);
  final DVSignal<int> quantity = context.signal(2);
  final DVSignal<bool> agreed = context.signal(false);
  final DVSignal<bool> paid = context.signal(false);
  final DVSignal<String> first = context.signal('Ada');

  final subtotal = price * quantity; // + - * / ~/ % on numbers
  final expensive = subtotal >= 10000; // < <= > >= give a bool signal
  final canShip = agreed & paid; // & | ^ on bools
  final greeting = first + ', welcome'; // + on strings
  // docs:end
  // docs:start state-update
  quantity.value = 3; // set
  quantity.update((int n) => n + 1); // set from the current value
  final int now = quantity.read(); // read without subscribing
  // docs:end
  debugPrint('$subtotal $expensive $canShip $greeting $now');
}

void globals(BuildContext context) {
  // docs:start state-global
  // Register one instance at startup.
  DV.global<Cart>(Cart());

  // Read it anywhere. context.global redraws the widget when it is replaced.
  final Cart cart = DV.global<Cart>();
  final Cart same = context.global<Cart>();

  // A namespace keeps two registrations of one type apart.
  DV.global<Cart>(Cart(), 'wishlist');
  final Cart wishlist = DV.global<Cart>(null, 'wishlist');
  // docs:end
  debugPrint('$cart $same $wishlist');
}

void reactiveModel(BuildContext context, Cart cart) {
  // docs:start state-lifecycle
  DV.lifecycle.app.listen((DVAppLifecycle state) {
    if (state == DVAppLifecycle.backgrounded) {
      // Save a draft before the app is paused.
    }
  });
  // docs:end
}
