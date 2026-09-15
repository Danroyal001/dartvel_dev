/// Who may call a backend function that declares a policy.
///
/// `@DVBackendFunction(policy: DVPolicies.refund)` is the specification's own
/// example, and until now nothing read it -- on either side. The
/// specification is explicit that "backend functions and model queries
/// enforce policies even if UI guards are bypassed", which makes this the
/// half that matters: a page guard without a function guard is a lock on the
/// front door of a building with open windows.
///
/// The application supplies the decision, for the same reason the page side
/// does. A backend has no session of its own here -- who is calling is
/// whatever the application's auth made of the request -- so a framework
/// that invented a user would be answering a question it cannot see.
library dartvel_core.auth.backend_policy;

import '../observability/observability.dart';
import 'api_scopes.dart';

/// The gate the generated backend router calls before running a function.
class DVBackendPolicy {
  const DVBackendPolicy._();

  /// What decides. Set by the application from its own auth.
  ///
  /// Null is not "allow". A function declaring a policy in an application
  /// with no way to answer it is refused, because the alternative is a
  /// function that declares a guard and runs for everybody -- which is the
  /// bug this exists to close, reintroduced as a default.
  static Future<bool> Function(String policy, String path)? decide;

  /// Whether this request may run a function guarded by [policy].
  ///
  /// A request authenticated with an API key or an OAuth token is refused
  /// first when its scopes do not cover [policy] as `Resource.action`
  /// (`DV-APIKEY-002`), before the application is asked. Inside its scopes
  /// the application still decides, so a scope narrows what the policy allows
  /// and never widens it.
  static Future<bool> allows(String policy, String path) async {
    final DVApiPrincipal? principal = DVApiPrincipal.current;
    if (principal != null && !principal.permits(policy)) {
      DVObservability.logger.warn('${DVApiScopeRefused(policy, principal.scopes)}');
      return false;
    }
    final Future<bool> Function(String, String)? answer = decide;
    if (answer == null) return false;
    return answer(policy, path);
  }
}
