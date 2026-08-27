/// Path URLs on the web.
library dartvel_flutter.routing.url_strategy.web;

import 'package:flutter_web_plugins/url_strategy.dart' as web;

/// Switch the browser off the default hash strategy.
///
/// Idempotent: the generated router calls it on every construction, and a
/// second call replaces the strategy with an equivalent one.
void dvUsePathUrlStrategy() => web.usePathUrlStrategy();
