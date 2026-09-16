import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start routing-sitemap
@DVPage(
  title: 'Pricing',
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
Widget _pricingPage(BuildContext context) => const DVText('Plans');
// docs:end
