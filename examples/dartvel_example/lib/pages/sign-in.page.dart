import 'package:flutter/material.dart';

import '../components/shop_ui.dart';
import '../dartvel_client/dartvel_client.dart';
import '../screens/sign_in_form.dart';
import '../theme/palette.dart';

/// Where the checkout guard sends somebody who is not signed in, and where it
/// sends them back from.
@DVPage(title: 'Sign in')
@pragma('vm:entry-point')
Widget _signInPage(BuildContext context) => (() {
  final Palette p = Palette.of(context);
  final String from = context.dvQuery['from'] ?? '/';

  return ShopScroll(
    children: <Widget>[
      const BackToShop(),
      DVBox.list([
        const PageHeading(
          'Sign in',
          subtitle: 'To check out and follow your orders.',
        ),
        SignInForm(from: from),
      ], spacing: 24).modifier(
        cardStyle(p, padding: 28).maxWidth(440).centered(),
      ),
    ],
  );
})();
