import 'dart:async';

import 'secrets_unsupported.dart'
    if (dart.library.io) 'secrets_io.dart' as env;

/// What [DVSecrets.captureState] hands back, for [DVSecrets.restoreState].
///
/// Opaque on purpose: the point is that a test cannot restore half of it.
class DVSecretsState {
  const DVSecretsState._(this._overrides, this._hooks, this._redactable);
  final Map<String, String> _overrides;
  final Map<String, List<FutureOr<void> Function(String)>> _hooks;
  final Set<String> _redactable;
}

/// What a redacted secret is replaced with.
///
/// Present rather than removed, so a reader can tell a value that was taken
/// out from a field that was never set.
const String dvRedactedMarker = '[redacted]';

/// Thrown when a secret is asked for and no source provides it.
class DVSecretNotFoundException implements Exception {
  final String key;
  final String reason;

  const DVSecretNotFoundException(this.key, this.reason);

  @override
  String toString() => 'DVSecretNotFoundException: "$key" — $reason';
}

/// Replaces every resolved secret value in [text] with a redaction marker.
///
/// The declaration makes the secrets an enumerable set and [DVSecrets] is the
/// only thing that hands their values out, so a log line, a trace attribute or
/// an exception message can be checked against the values themselves rather
/// than against a list of key names that look suspicious. Matching on the key
/// misses the cases that actually leak: a connection string filed under `url`,
/// an upstream error quoting the credential back, a sentence somebody typed
/// during an incident.
///
/// Only values that were resolved at least once can be matched, which is no
/// real limit -- code cannot print a secret it never read -- and better said
/// out loud than implied.
String dvRedactSecrets(String text) => DVSecrets.redact(text);

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

  /// Values this has handed out, for [redact] to strike out of any text.
  ///
  /// Filled on resolution rather than on declaration: a value nobody read is
  /// a value nobody can print, and matching against it would only widen the
  /// chance of blanking innocent text.
  static final Set<String> _redactable = <String>{};

  /// Below this length a value is not matched, and the reason is damage
  /// rather than laziness.
  ///
  /// Redaction is substring replacement. A three-character secret occurs
  /// inside ordinary words, so matching it would hollow out every log line in
  /// the process and cost an incident the evidence it needed. Anything this
  /// short is not a credential worth the trade.
  static const int minimumRedactableLength = 8;

  /// Drops everything [configure] registered, every rotation hook, and every
  /// value [redact] would strike out.
  ///
  /// Hooks too, or one test's hook fires in another's rotation. The redaction
  /// set too, or a value supplied by one test goes on blanking text in the
  /// tests after it and the failure reads as a bug in the code under test.
  static void reset() {
    _overrides.clear();
    _hooks.clear();
    _redactable.clear();
  }

  /// Remembers [value] as something [redact] must strike out.
  ///
  /// `PUBLIC_` values are skipped on purpose. They are declared to ship to
  /// every visitor, so hiding them from the operator's own logs conceals the
  /// configuration people are trying to read and protects nothing.
  static void _rememberForRedaction(String key, String value) {
    if (key.startsWith('PUBLIC_')) return;
    if (value.length < minimumRedactableLength) return;
    _redactable.add(value);
  }

  /// [text] with every resolved secret value replaced by [dvRedactedMarker].
  ///
  /// Longest first, so a secret that contains another is not left as a
  /// recognisable fragment wrapped around a marker.
  static String redact(String text) {
    if (_redactable.isEmpty || text.isEmpty) return text;
    final List<String> values = _redactable.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    String out = text;
    for (final String value in values) {
      if (!out.contains(value)) continue;
      out = out.replaceAll(value, dvRedactedMarker);
    }
    return out;
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
    // Both values stay redacted from here. The one being replaced is live
    // until every holder has caught up, so printing it during the changeover
    // is exactly as bad as printing it before.
    _rememberForRedaction(key, value);

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
        Set<String>.of(_redactable),
      );

  /// Puts back what [captureState] took.
  static void restoreState(DVSecretsState state) {
    _overrides
      ..clear()
      ..addAll(state._overrides);
    _hooks
      ..clear()
      ..addAll(state._hooks);
    _redactable
      ..clear()
      ..addAll(state._redactable);
  }

  /// Whether [key] resolves to a non-empty value.
  bool has(String key) => maybeGet(key) != null;

  /// The value of [key], or null when nothing provides it.
  String? maybeGet(String key) {
    final override = _overrides[key];
    if (override != null && override.isNotEmpty) {
      _rememberForRedaction(key, override);
      return override;
    }
    final value = env.readEnvironment(key);
    if (value == null || value.isEmpty) return null;
    _rememberForRedaction(key, value);
    return value;
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
