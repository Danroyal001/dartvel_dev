/// Off the web there is no URL strategy to choose and no DOM to describe, so
/// these do nothing.
///
/// No-ops rather than throws: the generated router calls them
/// unconditionally, and a router that crashed on desktop to report a web-only
/// concern would be the worse failure.
library dartvel_flutter.routing.url_strategy.stub;

void dvUsePathUrlStrategy() {}

void dvEnsureSemantics() {}
