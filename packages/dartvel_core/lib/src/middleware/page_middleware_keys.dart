/// What a page's declared middleware can be, and why the rest cannot.
///
/// NEW_SPEC.md puts the page form first under Middleware, and until this
/// existed a page's `@DVUseMiddleware` was read by nothing at all. The
/// backend generator validated the spelling of every `@DVUseMiddleware` in
/// `lib/**` -- pages included -- against the sets written for an HTTP chain,
/// so a page could declare `bodyLimit` and get a green build, a whitelisted
/// name, and no limit anywhere. The router generator never looked at the
/// annotation.
///
/// The backend sets cannot be reused here, and that is the whole reason this
/// file is separate. Nine of those keys only mean something inside a server:
/// there is no `Content-Length` to check before a body is read, no response
/// whose headers a route could set, and no second party to rate limit --
/// the caller and the callee are the same process. A page scope that
/// accepted them would run none, which is the failure the backend sets were
/// written to end, moved one scope sideways.
///
/// So a page key is built or it is refused with somewhere else to put it.
/// There is no third answer, and [dvPageMiddlewareRefusal] is where that is
/// enforced.
library;

/// Keys a page route runs before it activates.
///
/// Small, and honestly so. A page middleware can redirect and nothing else:
/// it runs inside the router's `redirect`, which either returns a location
/// or lets the route through. Both of these are decisions of exactly that
/// shape.
const Set<String> dvPageMiddlewareKeysBuilt = <String>{
  'auth',
  'maintenance',
};

/// Why the remaining keys cannot be page middleware, and where each belongs.
///
/// Every one names a place to put the thing the developer wanted. A refusal
/// that only says no leaves them with a working build and no feature, which
/// is barely better than the silence this replaced.
const Map<String, String> dvPageMiddlewareKeysUnavailableReason =
    <String, String>{
  'policy': 'Nothing in the middleware list says which policy, so this key '
      'cannot decide anything. Declare it where the name goes: '
      '@DVPage(policy: DVPolicies.yourPolicy), which the router enforces '
      'before the page builds.',
  'tenant': 'A tenant is resolved from the request that reaches the server, '
      'and activating a route sends none. Declare it on the '
      '@DVBackendFunction the page calls.',
  'cors': 'CORS is a rule about who may call the server, answered on every '
      'response including the preflight, which never reaches a route at '
      'all. Configure it under dartvel.server.cors.',
  'csrf': 'A CSRF token is checked where the state-changing request is '
      'received. The generated backend already validates one on every such '
      'request; a page has none to check.',
  'rateLimit': 'A limit the caller enforces on itself is not a limit -- the '
      'page and the visitor are the same machine, and anyone who wants past '
      'it can call the API directly. Declare it on the @DVBackendFunction '
      'the page calls.',
  'rateLimitCheckout': 'Nothing implements this in any scope. It is not a '
      'preset of rateLimit; there is no code behind the name. Use '
      'DVMiddlewares.rateLimit on the @DVBackendFunction you meant to '
      'limit.',
  'requestLogging': 'This writes one line per request the server handles, '
      'and a route activation is not one. Declare it on the '
      '@DVBackendFunction.',
  'tracing': 'The tracer spans a server request from arrival to response. A '
      'route activation has neither end. Declare it on the '
      '@DVBackendFunction.',
  'securityHeaders': 'Headers go on an HTTP response, and activating a route '
      'produces none -- the document carrying this page was sent long '
      'before. Declare it on the @DVBackendFunction.',
  'csp': 'A Content-Security-Policy reaches the browser as a header on the '
      'document, and it is applied before any route exists. A route cannot '
      'change the policy the page it is inside was loaded under. Set '
      'dartvel.security.csp and declare DVMiddlewares.csp where the '
      'document is served.',
  'bodyLimit': 'A page never reads a request body, so there is nothing here '
      'to cap. The limit belongs where the body is read: '
      '@DVBackendFunction with DVMiddlewares.bodyLimit.',
  'uploadLimit': 'A page never reads an upload, so there is nothing here to '
      'cap. The limit belongs where the body is read: @DVBackendFunction '
      'with DVMiddlewares.uploadLimit.',
  'compression': 'Compression is negotiated between the server and the '
      'browser when a response is sent. Configure it under '
      'dartvel.server.compression, where false turns it off.',
  'locale': 'The application has one locale at a time and I18n.load sets it. '
      'Negotiating a different one per route would leave the page in one '
      'language and the shell already rendered around it in another.',
  'idempotency': 'An idempotency key belongs to a request that changes '
      'something, and opening a page changes nothing. Declare it on the '
      '@DVBackendFunction that writes.',
  'cacheTags': 'Nothing implements this in any scope. Cache invalidation '
      'lives on DV.Cache.tag and DV.Cache.revalidateTag.',
  'featureFlags': 'Nothing in the middleware list says which flag. If the '
      'flag decides who may open the page, that is @DVPage(policy: ...); if '
      'it decides what a call returns, declare the key on the '
      '@DVBackendFunction.',
};

/// Null when a page route can run [key], otherwise why it cannot.
///
/// The generator refuses a build on anything non-null, so this is the only
/// place the page scope's answer is written down. A key that reaches the
/// fallback is one somebody added to `DVMiddlewares` and to neither page
/// set: refused, because accepting a name nothing here understands is how
/// nineteen keys came to mean nothing in the first place.
String? dvPageMiddlewareRefusal(String key) {
  if (dvPageMiddlewareKeysBuilt.contains(key)) return null;
  final String? reason = dvPageMiddlewareKeysUnavailableReason[key];
  if (reason != null) return reason;
  return 'is not middleware a page route can run in this version of Dartvel.';
}
