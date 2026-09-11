import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// Exported from Dartvel Studio. Ordinary page source: edit
// freely, the builder is no longer involved.
//
// The sitemap argument is here rather than in a test fixture because it is a
// nested call inside the annotation, and every parser of `@DVPage(...)` used
// to stop at its first close parenthesis -- which dropped this page out of
// the router entirely, with the build still succeeding. A page in the
// example is read by the real generator and then compiled, so that cannot
// come back quietly.
@DVPage(
  title: 'Pricing',
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
@pragma('vm:entry-point')
Widget _pricingPage(BuildContext context) => DVBox.list([
  // The page's level-1 heading: it has no bar to carry its title.
  const DVText('Plans')
      .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
  DVBox.row([
    const DVText('Free'),
    // The price the model declares, read rather than repeated. A static
    // the generator emits and nothing calls is the same gap the
    // annotation had before it was emitted at all -- this page is where
    // a compiler and a screenshot both see it.
    DVText(Product.nativePrice?.toString() ?? 'Free'),
    const DVText('Pro').modifier(
      const DVModifier().onPressed(
        DV.Navigation.to(const DVRouteTarget('/checkout')),
      ),
    ),
  ]),
]);
