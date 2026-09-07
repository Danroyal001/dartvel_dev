import 'package:dartvel_core/dartvel.dart';

/// Three things the generated router has to wire, in one function.
///
/// It is here because nothing in this repository compiles generated backend
/// output. The unit tests read `dartvel_backend_routes.g.dart` as a string
/// and assert what is in it, which is why a policy gate written across a
/// line break, a missing import and an interpolation resolved against the
/// generator's own scope all shipped in one commit and were found by a build
/// of the site rather than by the suite.
///
/// The example's client is generated and compiled on every run, so a
/// declaration here is a compiler reading the emitted code:
///
///   * `policy` puts a gate in front of the handler,
///   * `@DVUseMiddleware` wraps it in the chain,
///   * the `DVContext` first parameter is injected rather than decoded from
///     the request, and is dropped from the generated client's signature.
@DVBackendFunction(policy: DVPolicies.exportData)
@DVUseMiddleware(<DVMiddlewareKey>[
  DVMiddlewares.securityHeaders,
  DVMiddlewares.locale,
])
Future<Map<String, Object?>> quote(DVContext context, String symbol) async {
  return <String, Object?>{
    'symbol': symbol,
    // The request lifecycle is a signal that changes now rather than an enum
    // reporting one value forever, and reading it here is what proves the
    // injected context carries a real one.
    'state': context.lifecycle.request.value.name,
  };
}
