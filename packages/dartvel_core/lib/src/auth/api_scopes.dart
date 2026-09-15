/// Scopes: named sets of the policy actions authorization already defines.
///
/// The runtime half of the specification's `# Platform API: Keys, Scopes and
/// OAuth Provider`. A scope is not a string compared by hand beside the API:
///
/// ```yaml
/// dartvel:
///   platformApi:
///     scopes:
///       orders:read: [Order.view, Order.list]
/// ```
///
/// A third-party caller resolves to a [DVApiPrincipal], and
/// `DV.Auth.authorization` refuses any action outside its scopes before the
/// policy runs (`DV-APIKEY-002`). Inside them the policy still decides, so a
/// scope can narrow what a policy allows and never widen it.
library dartvel_core.auth.api_scopes;

import 'dart:async';

import '../tenancy/tenants.dart';

/// The scopes an application declares under `dartvel.platformApi.scopes`.
final class DVApiScopes {
  DVApiScopes(
    Map<String, List<String>> scopes, {
    Map<String, String> descriptions = const <String, String>{},
  }) : _scopes = <String, Set<String>>{
         for (final MapEntry<String, List<String>> entry in scopes.entries)
           entry.key: Set<String>.unmodifiable(entry.value),
       },
       descriptions = Map<String, String>.unmodifiable(descriptions) {
    for (final MapEntry<String, Set<String>> entry in _scopes.entries) {
      if (!_scopeName.hasMatch(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'scopes',
          'a scope name has no spaces and is not empty',
        );
      }
      for (final String action in entry.value) {
        if (!_action.hasMatch(action)) {
          throw ArgumentError.value(
            action,
            'scopes',
            'scope "${entry.key}" names "$action"; an action is '
                'Resource.action, as in Order.view',
          );
        }
      }
    }
  }

  /// Reads the `dartvel.platformApi` map from `pubspec.yaml`.
  ///
  /// A scope is either a list of actions or `{actions: [...], description:
  /// ...}`; the description is the wording a consent screen shows.
  factory DVApiScopes.fromConfig(Map<String, Object?> platformApi) {
    final Object? declared = platformApi['scopes'];
    final Map<String, List<String>> scopes = <String, List<String>>{};
    final Map<String, String> descriptions = <String, String>{};
    if (declared is Map) {
      for (final MapEntry<Object?, Object?> entry in declared.entries) {
        final String name = '${entry.key}';
        final Object? value = entry.value;
        if (value is List) {
          scopes[name] = <String>[for (final Object? a in value) '$a'];
        } else if (value is Map) {
          final Object? actions = value['actions'];
          scopes[name] = <String>[
            if (actions is List)
              for (final Object? a in actions) '$a',
          ];
          final Object? description = value['description'];
          if (description != null) descriptions[name] = '$description';
        } else {
          throw ArgumentError.value(
            value,
            name,
            'a scope is a list of policy actions',
          );
        }
      }
    }
    return DVApiScopes(scopes, descriptions: descriptions);
  }

  static final RegExp _scopeName = RegExp(r'^\S+$');
  static final RegExp _action = RegExp(r'^[A-Za-z_]\w*\.[A-Za-z_]\w*$');

  final Map<String, Set<String>> _scopes;

  /// Consent-screen wording, by scope name.
  final Map<String, String> descriptions;

  Set<String> get names => Set<String>.unmodifiable(_scopes.keys);

  /// Whether [scope] is declared, by its whole name.
  bool defines(String scope) => _scopes.containsKey(scope);

  /// The actions [scope] grants, or an empty set when it is not declared.
  Set<String> actionsFor(String scope) => _scopes[scope] ?? const <String>{};

  /// Every action [scopes] grant between them. A name that is not declared
  /// grants nothing: names are looked up whole, never matched as prefixes.
  Set<String> actionsOf(Iterable<String> scopes) => <String>{
    for (final String scope in scopes) ...actionsFor(scope),
  };

  /// Whether [granted] covers [action], compared whole.
  bool covers(Iterable<String> granted, String action) =>
      actionsOf(granted).contains(action);

  /// The words a consent screen uses for [scope].
  String describe(String scope) => descriptions[scope] ?? scope;

  /// The names in [scopes] this application does not declare.
  List<String> undeclared(Iterable<String> scopes) => <String>[
    for (final String scope in scopes)
      if (!defines(scope)) scope,
  ];

  /// Throws [DVUndeclaredApiScope] when any of [scopes] is not declared.
  void requireDeclared(Iterable<String> scopes) {
    final List<String> missing = undeclared(scopes);
    if (missing.isNotEmpty) throw DVUndeclaredApiScope(missing, names);
  }

  /// The key `DV.Auth.authorization` registers [action] under:
  /// `Order.view` is `view:Order`.
  static String policyKeyOf(String action) {
    final int dot = action.indexOf('.');
    return '${action.substring(dot + 1)}:${action.substring(0, dot)}';
  }

  /// The action `DV.Auth.authorization` checks for [action] on [resource].
  static String actionName(String resource, String action) =>
      '$resource.$action';

  /// Fails with `DV-APIKEY-001` when a scope names an action no registered
  /// policy defines.
  ///
  /// Without this a partner's integration asks for a scope that resolves to
  /// an action nobody wrote a policy for, every call is refused, and the
  /// failure reads as the partner's bug.
  void validateAgainst(Set<String> registeredPolicies) {
    final Map<String, Set<String>> missing = <String, Set<String>>{};
    for (final MapEntry<String, Set<String>> entry in _scopes.entries) {
      for (final String action in entry.value) {
        if (!registeredPolicies.contains(policyKeyOf(action))) {
          (missing[entry.key] ??= <String>{}).add(action);
        }
      }
    }
    if (missing.isNotEmpty) throw DVUndefinedScopeAction(missing);
  }
}

/// Something a request can be authenticated as that carries scopes.
///
/// `DV.Auth.authorization` refuses any action this principal does not
/// [permits], before the policy is asked.
abstract interface class DVScopedPrincipal {
  Set<String> get scopes;

  /// Whether the scopes cover [action], as `Resource.action`.
  bool permits(String action);
}

enum DVApiPrincipalKind {
  /// An API key, acting for its organization.
  apiKey,

  /// An OAuth access token a person granted, acting for that person.
  oauthUser,

  /// A client-credentials access token, acting for the client itself.
  oauthClient,
}

/// Who a third-party request is: resolved at the authentication stage, and
/// the policy context at the authorization stage.
class DVApiPrincipal implements DVScopedPrincipal {
  DVApiPrincipal({
    required this.kind,
    required this.subject,
    required this.tenant,
    required Set<String> scopes,
    required Set<String> actions,
    this.organizationId,
    this.clientId,
    this.ratePlan,
    this.expiresAt,
  }) : scopes = Set<String>.unmodifiable(scopes),
       actions = Set<String>.unmodifiable(actions);

  final DVApiPrincipalKind kind;

  /// The key id for an API key or a client-credentials token, and the user id
  /// for a token a person granted.
  final String subject;

  /// The data boundary the credential was issued for. A request resolved to
  /// any other tenant does not authenticate with it.
  final String tenant;

  final String? organizationId;

  /// The OAuth client, for a token.
  final String? clientId;

  @override
  final Set<String> scopes;

  /// The policy actions [scopes] resolve to under the current declaration.
  final Set<String> actions;

  final String? ratePlan;
  final DateTime? expiresAt;

  @override
  bool permits(String action) => actions.contains(action);

  static const Symbol _zoneKey = #dartvelApiPrincipal;

  /// The third-party caller the current request authenticated as, or null
  /// for a request that presented no platform credential.
  ///
  /// A zone value rather than a field: a server has many requests in flight
  /// and hands the isolate between them at every await, so a field would be
  /// whichever caller arrived last.
  static DVApiPrincipal? get current {
    final Object? principal = Zone.current[_zoneKey];
    return principal is DVApiPrincipal ? principal : null;
  }

  /// Runs [body] with [principal] as [current].
  static Future<T> actingAs<T>(
    DVApiPrincipal principal,
    Future<T> Function() body,
  ) => runZoned(body, zoneValues: <Object?, Object?>{_zoneKey: principal});

  /// Runs [body] on this principal's tenant, so every tenant filter below it
  /// is the one already there.
  Future<T> run<T>(FutureOr<T> Function() body) =>
      const DVTenants().withTenant(tenant, () async => body());

  @override
  String toString() => 'DVApiPrincipal(${kind.name} $subject on $tenant)';
}

/// A call outside the caller's scopes (`DV-APIKEY-002`).
class DVApiScopeRefused implements Exception {
  DVApiScopeRefused(this.action, Set<String> scopes)
    : scopes = Set<String>.unmodifiable(scopes);

  final String action;
  final Set<String> scopes;

  String get code => 'DV-APIKEY-002';

  @override
  String toString() =>
      '$code: $action refused; the caller\'s scopes ${scopes.toList()..sort()} '
      'do not cover it.';
}

/// A scope naming a policy action nothing defines (`DV-APIKEY-001`).
class DVUndefinedScopeAction implements Exception {
  DVUndefinedScopeAction(this.missing);

  /// The undefined actions, by the scope that names them.
  final Map<String, Set<String>> missing;

  String get code => 'DV-APIKEY-001';

  @override
  String toString() =>
      '$code: ${<String>[for (final MapEntry<String, Set<String>> e in missing.entries) 'scope "${e.key}" names ${e.value.toList()..sort()}'].join('; ')}, and no policy defines them.';
}

/// A key issued for a scope the application does not declare.
class DVUndeclaredApiScope implements Exception {
  DVUndeclaredApiScope(this.scopes, Set<String> declared)
    : declared = Set<String>.unmodifiable(declared);

  final List<String> scopes;
  final Set<String> declared;

  @override
  String toString() =>
      'DVUndeclaredApiScope: $scopes '
      '${scopes.length == 1 ? 'is' : 'are'} not declared under '
      'dartvel.platformApi.scopes (declared: ${declared.toList()..sort()}).';
}
