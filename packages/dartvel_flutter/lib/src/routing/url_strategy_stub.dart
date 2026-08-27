/// Off the web there is no URL strategy to choose, so this does nothing.
///
/// A no-op rather than a throw: the generated router calls it unconditionally,
/// and a router that crashed on desktop to report a web-only concern would be
/// the worse failure.
library dartvel_flutter.routing.url_strategy.stub;

void dvUsePathUrlStrategy() {}
