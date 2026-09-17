import 'package:flutter/material.dart';

import '../../../components/shop_ui.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../../theme/palette.dart';

/// One order, and where it is now.
///
/// Nothing here asks for updates. The roastery saves the order, the save
/// publishes a change, and `Order.watch` rebuilds this page with it.
@DVPage(title: 'Order', showAppBar: true)
@pragma('vm:entry-point')
Widget _orderPage(BuildContext context) => (() {
  final String id = context.dvParams['id'] ?? '';
  final Palette p = Palette.of(context);

  return WatchModels<Order>(
    watch: Order.watch,
    builder: (BuildContext context, List<Order>? orders) {
      if (orders == null) {
        return const ShopScroll(children: <Widget>[LoadingTiles(count: 1)]);
      }
      final Order? order = orders.where((Order o) => o.id == id).firstOrNull;
      if (order == null) {
        return ShopScroll(
          maxWidth: readingMaxWidth,
          children: <Widget>[
            EmptyState(
              icon: Icons.search_off,
              title: 'No order $id',
              message: 'It may belong to another account.',
              action: FilledButton(
                onPressed: () => DV.Navigation.navigate(DVRoutes.orders),
                child: const Text('Your orders'),
              ),
            ),
          ],
        );
      }
      final bool delivered = order.status == 'delivered';
      return ShopScroll(
        maxWidth: readingMaxWidth,
        children: <Widget>[
          PageHeading(
            delivered ? 'Delivered' : 'On its way to you',
            overline: 'Order ${order.id} · ${shortDate(order.placedAt)}',
            subtitle: delivered
                ? 'Enjoy it. Coffee is at its best two to four weeks after roasting.'
                : 'We send an email at each step, and this page moves as it happens.',
          ),
          DVBox.row([
            Expanded(
              child: DVBox.list([
                DVBox.row([
                  const Expanded(child: SectionHeading('Status')),
                  if (!delivered) const LiveDot(),
                ]),
                StatusTracker(order.status),
              ], spacing: 20).modifier(cardStyle(p, padding: 22)),
            ),
          ]),
          DVBox.list([
            const SectionHeading('Receipt'),
            DVText(order.summary).modifier(p.body),
            DVText('Sent to ${order.email}').modifier(p.muted),
            Divider(color: p.line),
            SummaryLine('Total', formatPrice(order.totalCents), strong: true),
          ], spacing: 12).modifier(cardStyle(p, padding: 22)),
        ],
      );
    },
  );
})();
