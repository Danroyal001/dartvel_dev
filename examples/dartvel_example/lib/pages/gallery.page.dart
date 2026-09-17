import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

import '../components/shop_ui.dart';

/// One large declared image, drawn through DVImageView.
///
/// Here so a web build of this example exercises the whole image pipeline
/// rather than each piece of it alone: the build writes the image at every
/// configured width narrower than it, this page asks for the variant its
/// 400-pixel slot needs on the screen it is on, and the link here prefetches
/// that same file before anybody taps it. A denser screen needs a different
/// file, which is the point of the slot being narrower than the image.
@DVPage(title: 'Gallery')
@pragma('vm:entry-point')
Widget _galleryPage(BuildContext context) => const ShopScroll(
  children: <Widget>[
    BackToShop(),
    PageHeading(
      'Responsive images',
      subtitle:
          'The build writes this image at every configured width, and '
          'the page asks for the one its slot needs on this screen.',
    ),
    DVImageView(
      DVImage.asset(
        'assets/social-card.png',
        alt: 'The Dartvel social card',
        width: 1200,
        height: 630,
      ),
      width: 400,
      height: 210,
    ),
  ],
);
