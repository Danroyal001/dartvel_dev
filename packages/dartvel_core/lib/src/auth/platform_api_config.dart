/// `dartvel.platformApi` from `pubspec.yaml`: the scopes, the rate plans and
/// whether the application is an OAuth provider.
///
/// One parser for both ends. `dartvel routes` reads the declaration with it
/// and stops the build on anything it does not understand; the generated
/// registry hands the same declaration to the same parser at startup, so what
/// the build checked and what the server runs cannot drift apart.
library dartvel_core.auth.platform_api_config;

import 'api_keys.dart';
import 'api_scopes.dart';

/// A `dartvel.platformApi` value the parser does not understand.
class DVPlatformApiConfigError implements Exception {
  const DVPlatformApiConfigError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How long the OAuth provider's codes and tokens live.
class DVOAuthSettings {
  const DVOAuthSettings({
    this.codeLifetime = const Duration(minutes: 1),
    this.accessTokenLifetime = const Duration(hours: 1),
    this.refreshTokenLifetime = const Duration(days: 30),
  });

  final Duration codeLifetime;
  final Duration accessTokenLifetime;
  final Duration refreshTokenLifetime;
}

/// The whole `dartvel.platformApi` declaration.
class DVPlatformApiConfig {
  DVPlatformApiConfig({
    required this.scopes,
    Map<String, DVApiRatePlan> ratePlans = const <String, DVApiRatePlan>{},
    this.requireExpiry = false,
    this.oauth,
  }) : ratePlans = Map<String, DVApiRatePlan>.unmodifiable(ratePlans);

  final DVApiScopes scopes;

  /// Requests per window, by plan name. A key names its plan at issue.
  final Map<String, DVApiRatePlan> ratePlans;

  /// Whether a key issued with no expiry raises `DV-APIKEY-005`.
  final bool requireExpiry;

  /// Null when the application is not an OAuth provider, which is the
  /// default: an application that serves no authorization endpoint has no
  /// authorization endpoint to get wrong.
  final DVOAuthSettings? oauth;

  static const Set<String> _keys = <String>{
    'scopes',
    'ratePlans',
    'requireExpiry',
    'oauth',
  };
  static const Set<String> _oauthKeys = <String>{
    'codeLifetime',
    'accessTokenLifetime',
    'refreshTokenLifetime',
  };
  static final RegExp _scopeName = RegExp(r'^\S+$');
  static final RegExp _action = RegExp(r'^[A-Za-z_]\w*\.[A-Za-z_]\w*$');
  static final RegExp _duration = RegExp(r'^\s*(\d+)\s*(ms|s|m|h|d)\s*$');

  /// Parses the `dartvel.platformApi` map.
  ///
  /// Throws [DVPlatformApiConfigError] naming the key for anything it does
  /// not understand. A key it skipped would be a setting the application
  /// believes it made: `scope:` for `scopes:` is an application with no
  /// scopes at all.
  factory DVPlatformApiConfig.fromConfig(Object? declared) {
    if (declared is! Map) {
      throw DVPlatformApiConfigError(
        'dartvel.platformApi must be a map with scopes, not "$declared".',
      );
    }
    for (final Object? key in declared.keys) {
      if (!_keys.contains('$key')) {
        throw DVPlatformApiConfigError(
          'dartvel.platformApi.$key is not a platform API setting. '
          'Accepted: ${_keys.join(', ')}.',
        );
      }
    }

    final Object? scopeMap = declared['scopes'];
    if (scopeMap is! Map || scopeMap.isEmpty) {
      throw const DVPlatformApiConfigError(
        'dartvel.platformApi.scopes must name at least one scope, as in '
        'orders:read: [Order.view]. A platform API with no scopes has '
        'nothing a key can be allowed to do.',
      );
    }
    final Map<String, List<String>> scopes = <String, List<String>>{};
    final Map<String, String> descriptions = <String, String>{};
    for (final MapEntry<Object?, Object?> entry in scopeMap.entries) {
      final String name = '${entry.key}';
      final String where = 'dartvel.platformApi.scopes.$name';
      if (!_scopeName.hasMatch(name)) {
        throw DVPlatformApiConfigError(
          '$where: a scope name has no spaces and is not empty.',
        );
      }
      Object? actions = entry.value;
      final Object? value = entry.value;
      if (value is Map) {
        for (final Object? key in value.keys) {
          if (key != 'actions' && key != 'description') {
            throw DVPlatformApiConfigError(
              '$where.$key is not a scope setting. Accepted: actions, '
              'description.',
            );
          }
        }
        actions = value['actions'];
        final Object? description = value['description'];
        if (description != null) descriptions[name] = '$description';
      }
      if (actions is! List || actions.isEmpty) {
        throw DVPlatformApiConfigError(
          '$where: a scope is a list of policy actions, as in '
          '[Order.view, Order.update].',
        );
      }
      final List<String> names = <String>[];
      for (final Object? action in actions) {
        if (!_action.hasMatch('$action')) {
          throw DVPlatformApiConfigError(
            '$where names "$action"; an action is Resource.action, as in '
            'Order.view.',
          );
        }
        names.add('$action');
      }
      scopes[name] = names;
    }

    final Map<String, DVApiRatePlan> plans = <String, DVApiRatePlan>{};
    final Object? planMap = declared['ratePlans'];
    if (planMap != null) {
      if (planMap is! Map) {
        throw const DVPlatformApiConfigError(
          'dartvel.platformApi.ratePlans must map a plan name to '
          '{ maxRequests, window }.',
        );
      }
      for (final MapEntry<Object?, Object?> entry in planMap.entries) {
        final String where = 'dartvel.platformApi.ratePlans.${entry.key}';
        final Object? plan = entry.value;
        if (plan is! Map) {
          throw DVPlatformApiConfigError(
            '$where must be { maxRequests, window }.',
          );
        }
        for (final Object? key in plan.keys) {
          if (key != 'maxRequests' && key != 'window') {
            throw DVPlatformApiConfigError(
              '$where.$key is not a rate plan setting. Accepted: '
              'maxRequests, window.',
            );
          }
        }
        final Object? max = plan['maxRequests'];
        if (max is! int || max <= 0) {
          throw DVPlatformApiConfigError(
            '$where needs maxRequests, a whole number above zero.',
          );
        }
        if (plan['window'] == null) {
          // Not defaulted. A plan with no window read as a minute, or as no
          // limit at all, is a quota nobody chose.
          throw DVPlatformApiConfigError(
            '$where needs a window, such as 1m or 1h.',
          );
        }
        plans['${entry.key}'] = DVApiRatePlan(
          maxRequests: max,
          window: _durationOf(plan['window'], '$where.window'),
        );
      }
    }

    final Object? requireExpiry = declared['requireExpiry'];
    if (requireExpiry != null && requireExpiry is! bool) {
      throw DVPlatformApiConfigError(
        'dartvel.platformApi.requireExpiry must be true or false, not '
        '"$requireExpiry".',
      );
    }

    DVOAuthSettings? oauth;
    final Object? oauthValue = declared['oauth'];
    if (oauthValue == true) {
      oauth = const DVOAuthSettings();
    } else if (oauthValue is Map) {
      for (final Object? key in oauthValue.keys) {
        if (!_oauthKeys.contains('$key')) {
          throw DVPlatformApiConfigError(
            'dartvel.platformApi.oauth.$key is not an OAuth setting. '
            'Accepted: ${_oauthKeys.join(', ')}.',
          );
        }
      }
      const DVOAuthSettings defaults = DVOAuthSettings();
      Duration lifetime(String key, Duration fallback) =>
          oauthValue[key] == null
          ? fallback
          : _durationOf(oauthValue[key], 'dartvel.platformApi.oauth.$key');
      oauth = DVOAuthSettings(
        codeLifetime: lifetime('codeLifetime', defaults.codeLifetime),
        accessTokenLifetime: lifetime(
          'accessTokenLifetime',
          defaults.accessTokenLifetime,
        ),
        refreshTokenLifetime: lifetime(
          'refreshTokenLifetime',
          defaults.refreshTokenLifetime,
        ),
      );
    } else if (oauthValue != null && oauthValue != false) {
      throw DVPlatformApiConfigError(
        'dartvel.platformApi.oauth must be true, false, or a map of '
        'lifetimes, not "$oauthValue".',
      );
    }

    return DVPlatformApiConfig(
      scopes: DVApiScopes(scopes, descriptions: descriptions),
      ratePlans: plans,
      requireExpiry: requireExpiry == true,
      oauth: oauth,
    );
  }

  static Duration _durationOf(Object? value, String where) {
    if (value is int && value > 0) return Duration(seconds: value);
    final RegExpMatch? match = _duration.firstMatch('$value');
    final int amount = match == null ? 0 : int.parse(match.group(1)!);
    if (match == null || amount <= 0) {
      throw DVPlatformApiConfigError(
        '$where: "$value" is not a duration. Write a whole number with ms, '
        's, m, h or d, such as 15m.',
      );
    }
    return switch (match.group(2)) {
      'ms' => Duration(milliseconds: amount),
      's' => Duration(seconds: amount),
      'm' => Duration(minutes: amount),
      'h' => Duration(hours: amount),
      _ => Duration(days: amount),
    };
  }
}
