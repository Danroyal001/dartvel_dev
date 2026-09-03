import 'dart:async';

import 'secrets_unsupported.dart'
    if (dart.library.io) 'secrets_io.dart' as env;

/// What [DVSecrets.captureState] hands back, for [DVSecrets.restoreState].
///
/// Opaque on purpose: the point is that a test cannot restore half of it.
class DVSecretsState {
  const DVSecretsState._(this._overrides, this._hooks);
  final Map<String, String> _overrides;
  final Map<String, List<FutureOr<void> Function(String)>> _hooks;
}

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

  /// Hooks to run when a secret rotates, by key, in registration order.
  static final Map<String, List<FutureOr<void> Function(String)>> _hooks =
      <String, List<FutureOr<void> Function(String)>>{};

  /// Drops everything [configure] registered, and every rotation hook.
  ///
  /// Hooks too, or one test's hook fires in another's rotation.
  static void reset() {
    _overrides.clear();
    _hooks.clear();
  }

  /// Runs [hook] with the new value whenever [key] rotates.
  ///
  /// For a long-lived client holding something built from the secret -- a
  /// payment gateway, a broker connection -- so it can rebuild without a
  /// restart. A secret with no hook is simply re-read on next access. Returns
  /// a function that removes the hook.
  void Function() onRotate(String key, FutureOr<void> Function(String value) hook) {
    final List<FutureOr<void> Function(String)> hooks =
        _hooks.putIfAbsent(key, () => <FutureOr<void> Function(String)>[]);
    hooks.add(hook);
    return () => hooks.remove(hook);
  }

  /// Reports that [key] now resolves to [value], and runs its hooks.
  ///
  /// What a resolver calls when it learns of a new value. The same value
  /// fires nothing: re-reporting must not rebuild every connection. Every
  /// hook runs even if an earlier one throws -- one connection failing to
  /// rebuild must not leave the rest on the old secret -- and the first
  /// error is rethrown once they all have.
  Future<void> rotate(String key, String value) async {
    if (maybeGet(key) == value) return;
    _overrides[key] = value;

    Object? firstError;
    StackTrace? firstTrace;
    for (final FutureOr<void> Function(String) hook
        in List<FutureOr<void> Function(String)>.of(_hooks[key] ?? const [])) {
      try {
        await hook(value);
      } on Object catch (error, trace) {
        firstError ??= error;
        firstTrace ??= trace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstTrace!);
    }
  }

  /// Everything a test could change, for putting back afterwards.
  static DVSecretsState captureState() => DVSecretsState._(
        Map<String, String>.of(_overrides),
        <String, List<FutureOr<void> Function(String)>>{
          for (final MapEntry<String, List<FutureOr<void> Function(String)>> e
              in _hooks.entries)
            e.key: List<FutureOr<void> Function(String)>.of(e.value),
        },
      );

  /// Puts back what [captureState] took.
  static void restoreState(DVSecretsState state) {
    _overrides
      ..clear()
      ..addAll(state._overrides);
    _hooks
      ..clear()
      ..addAll(state._hooks);
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
