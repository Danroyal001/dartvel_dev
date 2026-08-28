/// Off the web there is no URL strategy to choose and no DOM to describe, so
/// these do nothing.
///
/// No-ops rather than throws: the generated router calls them
/// unconditionally, and a router that crashed on desktop to report a web-only
/// concern would be the worse failure.
library dartvel_flutter.routing.url_strategy.stub;

void dvUsePathUrlStrategy() {}

void dvEnsureSemantics() {}

/// No-op off the web. There is no document, no anchors and no browser
/// navigation to intercept: a link on a native platform reaches
/// [DVNavLink]'s own handler and nothing else.
void dvInterceptLinkNavigation(void Function(String path) route) {}
