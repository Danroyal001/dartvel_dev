import 'package:flutter/material.dart';

import '../../../components/shop_ui.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../../shop/account.dart';
import '../../../theme/palette.dart';

/// Every order the signed-in person has placed, newest first. Live: a status
/// the roastery changes arrives here without a refresh.
@DVPage(title: 'Orders')
@pragma('vm:entry-point')
Widget _ordersPage(BuildContext context) => (() {
  final Account account = context.global<Account>();
  final Palette p = Palette.of(context);

  if (!account.signedIn) {
    return ShopScroll(
      maxWidth: readingMaxWidth,
      children: <Widget>[
        const PageHeading('Orders'),
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Sign in to see your orders',
          message: 'Your receipts and where each bag is will show up here.',
          action: FilledButton(
            key: const Key('orders-sign-in'),
            onPressed: () => DV.Navigation.navigate(
              DVRoutes.signin.withQuery(<String, String>{
                'from': DVRoutes.orders.path,
              }),
            ),
            child: const Text('Sign in'),
          ),
        ),
      ],
    );
  }

  return ShopScroll(
    maxWidth: readingMaxWidth,
    children: <Widget>[
      const PageHeading(
        'Orders',
        subtitle: 'Statuses update as we roast, pack and ship.',
      ),
      WatchModels<Order>(
        watch: Order.watch,
        builder: (BuildContext context, List<Order>? all) {
          if (all == null) return const LoadingTiles(count: 2);
          final List<Order> mine = <Order>[
            for (final Order o in all)
              if (o.email == account.email) o,
          ]..sort((Order a, Order b) => b.placedAt.compareTo(a.placedAt));
          if (mine.isEmpty) {
            return EmptyState(
              icon: Icons.local_cafe_outlined,
              title: 'No orders yet',
              message:
                  'When you order a coffee, you can follow it from the '
                  'roaster to your door here.',
              action: FilledButton(
                onPressed: () => DV.Navigation.navigate(DVRoutes.index),
                child: const Text('Browse coffee'),
              ),
            );
          }
          return DVBox.list([
            for (final Order order in mine)
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: Key('order-${order.id}'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () =>
                      DV.Navigation.navigate(DVRoutes.ordersId(id: order.id)),
                  child: DVBox.row(
                    [
                      Expanded(
                        child: DVBox.list([
                          DVText(
                            '${order.id} · ${shortDate(order.placedAt)}',
                          ).modifier(p.overline),
                          DVText(
                            order.summary,
                          ).modifier(p.headline.maxLines(2)),
                          StatusPill(order.status),
                        ], spacing: 6),
                      ),
                      DVText(
                        formatPrice(order.totalCents),
                      ).modifier(p.headline),
                      Icon(Icons.chevron_right, color: p.inkFaint),
                    ],
                    spacing: 12,
                    crossAlign: DVCrossAlign.center,
                  ).modifier(cardStyle(p)),
                ),
              ),
          ], spacing: 12);
        },
      ),
    ],
  );
})();
