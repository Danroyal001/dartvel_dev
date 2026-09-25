// The parts of dartvel_flutter that need no generated code.
//
// A Dartvel application is normally made with `dartvel create`, and its pages,
// routes and data models come from the code generator (see ../README.md). The
// UI primitives, the DVModifier chain, signals and DV.global are ordinary
// runtime classes, so they work in any Flutter app, including this one, which
// has no pages directory and no generated client.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

/// Settings the whole application reads.
///
/// Registered once with DV.global and read anywhere. There is no separate
/// service container to set up.
class Shop {
  const Shop({required this.name, required this.currency});

  final String name;
  final String currency;

  String price(num cents) => '$currency ${(cents / 100).toStringAsFixed(2)}';
}

void main() {
  DV.global<Shop>(const Shop(name: 'Corner Roasters', currency: 'EUR'));
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'dartvel_flutter example',
        home: Material(child: SafeArea(child: OrderPanel())),
      );
}

/// One product, a quantity and a checkbox, all held in signals.
///
/// In a generated app this would be a private `@DVPage` function in
/// lib/pages/. Here it is a plain widget: `context.signal` works in any
/// build method.
class OrderPanel extends StatelessWidget {
  const OrderPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final Shop shop = context.global<Shop>();

    // Signals are matched by call order, like hooks, so create them
    // unconditionally at the top of build.
    final DVSignal<int> quantity = context.signal(1);
    final DVSignal<int> unitPrice = context.signal(1450); // cents
    final DVSignal<bool> agreed = context.signal(false);

    // Operating on signals gives signals that track their sources. Reading
    // .value below subscribes this widget to quantity, unitPrice and agreed.
    final total = unitPrice * quantity;
    final canOrder = (quantity > 0) & agreed;

    return DVBox.scrollableList(<Widget>[
      DVText(shop.name).modifier(
        const DVModifier()
            .fontSize(28)
            .fontWeight(FontWeight.w700)
            .semanticHeading(1),
      ),
      const DVText('House espresso, 250 g'),
      DVBox.row(<Widget>[
        _button('Remove one', () {
          if (quantity.value > 0) quantity.update((int n) => n - 1);
        }),
        DVText('${quantity.value}').modifier(
          const DVModifier().fontSize(20).semanticLabel('Quantity'),
        ),
        _button('Add one', () => quantity.update((int n) => n + 1)),
      ], spacing: 12, crossAlign: DVCrossAlign.center),
      DVText('Total ${shop.price(total.value)}').modifier(
        const DVModifier().fontSize(20).fontWeight(FontWeight.w600),
      ),
      DVText(agreed.value ? '[x] I accept the terms' : '[ ] I accept the terms')
          .modifier(
        const DVModifier()
            .paddingSymmetric(vertical: 8)
            .minimumTapTarget()
            .semanticButton()
            .onTap(() => agreed.value = !agreed.value),
      ),
      DVText(canOrder.value ? 'Ready to order' : 'Accept the terms to order')
          .modifier(
        const DVModifier().color(
          canOrder.value ? const Color(0xFF15803D) : const Color(0xFF6B7280),
        ),
      ),
    ], spacing: 16).modifier(const DVModifier().padding(24).maxWidth(480));
  }

  Widget _button(String label, VoidCallback onTap) => DVText(label).modifier(
        const DVModifier()
            .paddingSymmetric(horizontal: 16, vertical: 10)
            .backgroundColor(const Color(0xFF2F6BFF))
            .color(const Color(0xFFFFFFFF))
            .rounded(8)
            .animate(const Duration(milliseconds: 150))
            .hover(const DVModifier().opacity(0.9))
            .minimumTapTarget()
            .semanticButton()
            .onTap(onTap),
      );
}
