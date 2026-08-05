import 'secrets_unsupported.dart'
    if (dart.library.io) 'secrets_io.dart' as env;

/// Thrown when a secret is asked for and no source provides it.
class DVSecretNotFoundException implements Exception {
  final String key;
  final String reason;

  const DVSecretNotFoundException(this.key, this.reason);

  @override
  String toString() => 'DVSecretNotFoundException: "$key" — $reason';
}

/// Reads secrets from the process environment.
///
/// Secrets are deliberately *not* part of the generated client. Only
/// `PUBLIC_`-prefixed variables are compiled into `env.g.dart`; everything else
/// stays in the environment of the process that runs the code. That is why a
/// browser build has no environment to read: a secret compiled into a web
/// bundle is a secret published to every visitor. On the web, reach secrets
/// through a backend function instead.
class DVSecrets {
  const DVSecrets();

  /// Values set with [configure], checked before the process environment so a
  /// test can supply a secret without mutating the environment.
  static final Map<String, String> _overrides = <String, String>{};

  /// Registers secrets explicitly. Intended for tests and for hosts that load
  /// secrets from a manager rather than the environment.
  static void configure(Map<String, String> secrets) {
    _overrides.addAll(secrets);
  }

  /// Drops everything [configure] registered.
  static void reset() {
    _overrides.clear();
  }

  /// Whether [key] resolves to a non-empty value.
  bool has(String key) => maybeGet(key) != null;

  /// The value of [key], or null when nothing provides it.
  String? maybeGet(String key) {
    final override = _overrides[key];
    if (override != null && override.isNotEmpty) return override;
    final value = env.readEnvironment(key);
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The value of [key].
  ///
  /// Throws [DVSecretNotFoundException] when it is absent. A secret resolving
  /// to an empty string is treated as absent, because an unset variable read
  /// through a shell commonly arrives as one, and a payment client configured
  /// with `''` fails far from the cause.
  String get(String key) {
    final value = maybeGet(key);
    if (value != null) return value;
    throw DVSecretNotFoundException(key, env.missingSecretReason(key));
  }

  /// The value of [key], falling back to [fallback] when it is absent. Use for
  /// genuinely optional configuration, never to paper over a missing secret.
  String getOr(String key, String fallback) => maybeGet(key) ?? fallback;
}
