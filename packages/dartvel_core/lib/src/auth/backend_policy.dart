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

import '../../dartvel.dart' show DVAuthAuthorization;
import '../observability/observability.dart';
import 'api_scopes.dart';
import 'session_authentication.dart';

/// What a route's policy made of a request.
enum DVPolicyDecision {
  /// The function runs.
  allowed,

  /// Nobody authenticated, and the policy needs a caller: 401. Signing in is
  /// the answer, and a client told so can send the person to sign in.
  unauthenticated,

  /// Refused whoever is asking: 403. Signing in again would not help.
  forbidden,
}

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

  static final RegExp _actionShape =
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$');

  /// Whether [policy] names a `Resource.action` a registry can answer.
  static bool isAction(String policy) => _actionShape.hasMatch(policy);

  /// Whether this request may run a function guarded by [action], a
  /// `Resource.action` such as `Order.view`.
  ///
  /// In order, each refusing before the next is asked:
  ///
  /// * a request authenticated with an API key or OAuth token whose scopes do
  ///   not cover [action] (`DV-APIKEY-002`);
  /// * an action nothing registered in `DV.Auth.authorization`. [decide] is not
  ///   asked: a route whose policy nobody wrote is not opened because the
  ///   application's route-level answer is yes;
  /// * [decide], when the application set one -- it answers for the route,
  ///   with the principal current;
  /// * otherwise the registered policy itself, asked with the principal (or
  ///   no caller) and no resource.
  static Future<bool> allowsAction(String action, String path) async =>
      await checkAction(action, path) == DVPolicyDecision.allowed;

  /// [allowsAction], saying why a refusal is one: in the same order, with
  /// [DVPolicyDecision.unauthenticated] where the registered policy would be
  /// asked with no caller and its user parameter is not nullable. Every
  /// other refusal -- outside a key's scopes, an action nothing registered,
  /// decide saying no, a caller the policy cannot take, the policy saying no
  /// -- is [DVPolicyDecision.forbidden].
  static Future<DVPolicyDecision> checkAction(String action, String path) async {
    final DVApiPrincipal? principal = DVApiPrincipal.current;
    if (principal != null && !principal.permits(action)) {
      DVObservability.logger.warn('${DVApiScopeRefused(action, principal.scopes)}');
      return DVPolicyDecision.forbidden;
    }
    const DVAuthAuthorization authorization = DVAuthAuthorization();
    if (!isAction(action) ||
        !authorization.registeredPolicies
            .contains(DVApiScopes.policyKeyOf(action))) {
      DVObservability.logger.warn(
        'No policy is registered for $action, so $path was refused. Write '
        'the method on a @DVPolicy class, or register it with '
        'DV.Auth.authorization.',
      );
      return DVPolicyDecision.forbidden;
    }
    final Future<bool> Function(String, String)? answer = decide;
    if (answer != null) {
      return await answer(action, path)
          ? DVPolicyDecision.allowed
          : DVPolicyDecision.forbidden;
    }
    final Object? caller = callerFor(action);
    if (caller == null && authorization.requiresCaller(action)) {
      return DVPolicyDecision.unauthenticated;
    }
    return await authorization.canAction(caller, action)
        ? DVPolicyDecision.allowed
        : DVPolicyDecision.forbidden;
  }

  /// Who the registered policy for [action] is asked about on this request.
  ///
  /// The API key or OAuth principal when the platform API authenticated the
  /// request. For the application's own session, the application's user
  /// when the policy can take it -- which a policy taking `Object?` can, so
  /// `user is Account` answers for a signed-in account -- then the session
  /// principal when the policy is written against that. When the policy can
  /// take neither, the user (or the principal) is still what it is asked
  /// with, so the refusal names the caller it could not take. Null for a
  /// request that authenticated nobody.
  static Object? callerFor(String action) {
    final DVApiPrincipal? key = DVApiPrincipal.current;
    if (key != null) return key;
    final DVSessionPrincipal? session = DVSessionPrincipal.current;
    if (session == null) return null;
    const DVAuthAuthorization authorization = DVAuthAuthorization();
    final Object? user = session.user;
    if (user != null && authorization.acceptsCaller(action, user)) return user;
    if (authorization.acceptsCaller(action, session)) return session;
    return user ?? session;
  }

  /// Refuses to start a server whose routes declare an action nothing has
  /// registered.
  ///
  /// Called by the generated backend after it registers the `@DVPolicy`
  /// classes and before any route can answer. The build already refuses an
  /// action no policy class defines; what is left to know only here is an
  /// action on a framework resource, such as `DVApiKeyResource.viewAny`,
  /// which the application answers by registering it before the server
  /// starts. Each would be refused on every request anyway, and a server that
  /// starts in that state reads as a working deployment with a broken policy.
  static void verifyRegistered(Iterable<String> actions) {
    const DVAuthAuthorization authorization = DVAuthAuthorization();
    final Set<String> registered = authorization.registeredPolicies;
    final List<String> missing = <String>{
      for (final String action in actions)
        if (!isAction(action) ||
            !registered.contains(DVApiScopes.policyKeyOf(action)))
          action,
    }.toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw StateError(
        'This backend declares ${missing.join(', ')} on its routes and nothing '
        'registered ${missing.length == 1 ? 'it' : 'them'}, so it will not '
        'start. Register each with DV.Auth.authorization before the server '
        'starts, or write the method on a @DVPolicy class.',
      );
    }
    final List<String> overridden = authorization.overriddenPolicies.toList()
      ..sort();
    if (overridden.isNotEmpty) {
      DVObservability.logger.info(
        'The application registered its own answer for ${overridden.join(', ')}; '
        'it is asked instead of the @DVPolicy class for each.',
      );
    }
  }
}
