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
  static Future<bool> allows(String policy, String path) async {
    final Future<bool> Function(String, String)? answer = decide;
    if (answer == null) return false;
    return answer(policy, path);
  }
}
