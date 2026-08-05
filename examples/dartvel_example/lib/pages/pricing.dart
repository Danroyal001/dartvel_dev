import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// Exported from Dartvel Studio. Ordinary page source: edit
// freely, the builder is no longer involved.
@DVPage(title: 'Pricing')
@pragma('vm:entry-point')
Widget _pricingPage(BuildContext context) =>
    DVBox.list([
      const DVText('Plans').modifier(const DVModifier().fontSize(24.0)),
      DVBox.row([
        const DVText('Free'),
        const DVText('Pro').modifier(const DVModifier().onPressed(DV.Navigation.to(const DVRouteTarget('/checkout')))),
      ]),
    ]);
