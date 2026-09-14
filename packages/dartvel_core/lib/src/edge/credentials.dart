/// Credential-stuffing defences, where the credentials are: velocity limits
/// per account and per source, breached-password checks over a k-anonymity
/// range query, and refusals that look the same whether an account exists or
/// not.
library dartvel_core.edge.credentials;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../auth/auth.dart';
import '../http/outbound.dart';
import '../observability/observability.dart';
import 'bot_protection.dart';

// --- velocity -----------------------------------------------------------------

/// How many failures a key may have within [window].
class DVVelocityBudget {
  const DVVelocityBudget(this.failures, this.window)
      : assert(failures > 0, 'a budget of no failures refuses everyone');

  final int failures;
  final Duration window;
}

/// Where failure times are kept. In memory for one process; an adapter over a
/// shared store makes the limit hold across every instance of the backend.
abstract interface class DVVelocityStore {
  /// Records a failure for [key], forgetting any older than [keepFor].
  Future<void> record(String key, DateTime at, {required Duration keepFor});

  /// Failure times for [key] after [from], oldest first.
  Future<List<DateTime>> since(String key, DateTime from);

  Future<void> clear(String key);
}

class DVMemoryVelocityStore implements DVVelocityStore {
  final Map<String, List<DateTime>> _failures = <String, List<DateTime>>{};

  @override
  Future<void> record(
    String key,
    DateTime at, {
    required Duration keepFor,
  }) async {
    final failures = _failures[key] ??= <DateTime>[];
    final horizon = at.subtract(keepFor);
    failures
      ..removeWhere((time) => !time.isAfter(horizon))
      ..add(at);
  }

  @override
  Future<List<DateTime>> since(String key, DateTime from) async =>
      <DateTime>[
        for (final time in _failures[key] ?? const <DateTime>[])
          if (time.isAfter(from)) time,
      ]..sort();

  @override
  Future<void> clear(String key) async {
    _failures.remove(key);
  }
}

/// A velocity limit that tripped (`DV-EDGE-005`).
class DVVelocityRefusal implements Exception {
  const DVVelocityRefusal({required this.scope, required this.retryAfter});

  /// `account` or `source`. For logs: the client is told only [message],
  /// which is the same for both.
  final String scope;

  /// When the oldest counted failure leaves the window.
  final Duration retryAfter;

  String get code => 'DV-EDGE-005';

  String get message => 'Too many failed attempts. Try again later.';

  @override
  String toString() => 'DVVelocityRefusal($code, $scope): $message';
}

/// Failure limits per account and per source, distinct from the global rate
/// limit.
///
/// Both are needed: a hundred failures spread across a hundred accounts from
/// one source is the attack a per-account limit cannot see, and a per-source
/// limit alone punishes an office behind one address. Counts are kept by the
/// identifier that was submitted, never by whether an account behind it
/// exists, so a limit trips identically either way.
class DVVelocityLimiter {
  DVVelocityLimiter({
    this.perAccount = const DVVelocityBudget(5, Duration(minutes: 15)),
    this.perSource = const DVVelocityBudget(100, Duration(minutes: 15)),
    DVVelocityStore? store,
    DateTime Function()? clock,
  })  : store = store ?? DVMemoryVelocityStore(),
        _clock = clock ?? DateTime.now;

  final DVVelocityBudget perAccount;
  final DVVelocityBudget perSource;
  final DVVelocityStore store;
  final DateTime Function() _clock;

  static String _accountKey(String account) =>
      'account:${account.trim().toLowerCase()}';

  static String _sourceKey(String source) => 'source:${source.trim()}';

  /// The refusal for an attempt now, or null when it may be tried.
  Future<DVVelocityRefusal?> check({
    required String account,
    required String source,
  }) async {
    final now = _clock();
    return await _over('account', _accountKey(account), perAccount, now) ??
        await _over('source', _sourceKey(source), perSource, now);
  }

  Future<void> recordFailure({
    required String account,
    required String source,
  }) async {
    final now = _clock();
    await store.record(_accountKey(account), now, keepFor: perAccount.window);
    await store.record(_sourceKey(source), now, keepFor: perSource.window);
  }

  /// The per-source refusal alone, for attempts whose failure must not be
  /// counted against an account -- a sign-up that hit a taken address, where
  /// locking the address would announce that it is taken.
  Future<DVVelocityRefusal?> checkSource({required String source}) =>
      _over('source', _sourceKey(source), perSource, _clock());

  Future<void> recordSourceFailure({required String source}) => store
      .record(_sourceKey(source), _clock(), keepFor: perSource.window);

  /// Clears the account's failures. The source's stay: one success in a
  /// spray does not make the rest of it innocent.
  Future<void> recordSuccess({required String account}) =>
      store.clear(_accountKey(account));

  Future<DVVelocityRefusal?> _over(
    String scope,
    String key,
    DVVelocityBudget budget,
    DateTime now,
  ) async {
    final recent = await store.since(key, now.subtract(budget.window));
    if (recent.length < budget.failures) return null;
    final freesAt = recent[recent.length - budget.failures].add(budget.window);
    return DVVelocityRefusal(scope: scope, retryAfter: freesAt.difference(now));
  }
}

// --- breached passwords -------------------------------------------------------

/// A breach corpus, asked whether a password is in it.
abstract interface class DVBreachedPasswords {
  /// Throws [DVBreachedPasswordsUnavailable] when it cannot answer.
  Future<bool> contains(String password);
}

/// The breach corpus could not be asked.
class DVBreachedPasswordsUnavailable implements Exception {
  const DVBreachedPasswordsUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'DVBreachedPasswordsUnavailable: $cause';
}

/// A password refused because it appears in a breach corpus (`DV-EDGE-004`).
class DVBreachedPasswordRefusal implements Exception {
  const DVBreachedPasswordRefusal();

  String get code => 'DV-EDGE-004';

  String get message =>
      'That password appears in a known data breach. Choose another.';

  @override
  String toString() => 'DVBreachedPasswordRefusal($code): $message';
}

String _sha1Hex(String password) =>
    sha1.convert(utf8.encode(password)).toString().toUpperCase();

final RegExp _rangeLine = RegExp(r'^[0-9A-Fa-f]{35}:\d+$');

/// A k-anonymity range query: the first five characters of the password's
/// SHA-1 go to the service, which answers every suffix it holds under that
/// prefix. The password and its full hash never leave the process.
///
/// [fetchRange] fetches the range for a prefix; [overHttp] builds one over
/// `DV.Http`. No service is built in.
class DVRangeQueryBreachedPasswords implements DVBreachedPasswords {
  DVRangeQueryBreachedPasswords(this.fetchRange);

  /// A range query over `DV.Http`, asking [endpoint] for each prefix.
  factory DVRangeQueryBreachedPasswords.overHttp(
    Uri Function(String prefix) endpoint, {
    DVHttp http = const DVHttp(),
    Map<String, String> headers = const <String, String>{},
  }) =>
      DVRangeQueryBreachedPasswords((prefix) async {
        final response = await http.get(endpoint(prefix), headers: headers);
        if (response.status != 200) {
          throw StateError('the range service answered ${response.status}');
        }
        return await response.body?.text() ?? '';
      });

  final Future<String> Function(String prefix) fetchRange;

  @override
  Future<bool> contains(String password) async {
    final hash = _sha1Hex(password);
    final String range;
    try {
      range = await fetchRange(hash.substring(0, 5));
    } catch (error) {
      throw DVBreachedPasswordsUnavailable(error);
    }

    final suffix = hash.substring(5);
    var found = false;
    for (final raw in const LineSplitter().convert(range)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!_rangeLine.hasMatch(line)) {
        // An error page served with a 200 has no suffixes in it; reading it
        // as "not breached" would pass every password.
        throw const DVBreachedPasswordsUnavailable(
          'the range service answered something that is not a range',
        );
      }
      final colon = line.indexOf(':');
      if (line.substring(0, colon).toUpperCase() != suffix) continue;
      // A count of zero is padding some services add to hide the range size.
      found = int.parse(line.substring(colon + 1)) > 0;
    }
    return found;
  }
}

/// A breach corpus held in memory, as hashes. For tests and small private
/// lists.
class DVMemoryBreachedPasswords implements DVBreachedPasswords {
  DVMemoryBreachedPasswords(Iterable<String> passwords)
      : _hashes = <String>{
          for (final password in passwords) _sha1Hex(password),
        };

  final Set<String> _hashes;

  @override
  Future<bool> contains(String password) async =>
      _hashes.contains(_sha1Hex(password));
}

// --- the guard ----------------------------------------------------------------

/// Sign-in and sign-up with the credential defences in front of an
/// [AuthProvider].
class DVCredentialGuard {
  DVCredentialGuard({
    required this.provider,
    DVVelocityLimiter? velocity,
    this.breachedPasswords,
    this.botProtection,
    this.breachCheckFailsClosed = false,
    this.refusalFloor = const Duration(milliseconds: 400),
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  })  : velocity = velocity ?? DVVelocityLimiter(clock: clock),
        _clock = clock ?? DateTime.now,
        _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final AuthProvider provider;
  final DVVelocityLimiter velocity;
  final DVBreachedPasswords? breachedPasswords;
  final DVBotProtection? botProtection;

  /// Whether sign-up and password change are refused while the breach corpus
  /// cannot be asked. Off by default, and logged when it happens: the check
  /// is hygiene on top of hashing, and a sign-up form that depends on someone
  /// else's uptime is the dependency the spec declines for captchas.
  final bool breachCheckFailsClosed;

  /// The least time a refused sign-in takes, however quickly the provider
  /// answered, so an unknown account is not refused faster than a wrong
  /// password.
  final Duration refusalFloor;

  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;

  /// The one refusal a bad sign-in gets, whether or not the account exists.
  ///
  /// The same refusal the Dartvel providers give unguarded, so wrapping a
  /// provider changes when a refusal arrives and never what it says.
  static const AuthException credentialsRefused =
      AuthException.invalidCredentials;

  /// Signs in, or throws [credentialsRefused] or a [DVVelocityRefusal].
  ///
  /// The Dartvel providers already refuse a missing account and a wrong
  /// password alike after the same hashing work. What the guard adds is what
  /// a provider cannot do alone: a refusal floor, which hides the time a
  /// remote identity service or a database lookup takes, the velocity counts,
  /// and collapsing a provider that still throws the two distinct failures.
  ///
  /// A tripped limit is refused without trying the password, so a locked
  /// account cannot confirm a guess.
  Future<AuthUser?> signIn(
    String email,
    String password, {
    required String source,
  }) async {
    final started = _clock();
    final locked = await velocity.check(account: email, source: source);
    if (locked != null) {
      DVObservability.log(
        'A ${locked.scope} velocity limit tripped; the sign-in was not tried.',
        level: DVLogLevel.warn,
        code: locked.code,
      );
      await _padFrom(started);
      throw locked;
    }

    AuthUser? user;
    try {
      user = await provider.signIn(email, password);
    } on AuthException catch (error) {
      if (!_refusesCredentials(error.failure)) rethrow;
    }
    if (user == null) {
      await velocity.recordFailure(account: email, source: source);
      await _padFrom(started);
      throw credentialsRefused;
    }
    await velocity.recordSuccess(account: email);
    return user;
  }

  static bool _refusesCredentials(AuthFailure failure) => switch (failure) {
        AuthFailure.invalidCredentials => true,
        // A provider written against the old contract; collapsed here.
        // ignore: deprecated_member_use_from_same_package
        AuthFailure.unknownAccount || AuthFailure.invalidPassword => true,
        _ => false,
      };

  /// Signs up after the source limit, the challenge and the breach check
  /// pass.
  ///
  /// A sign-up that signs somebody in cannot hide that an address was free,
  /// so what the guard can do is make probing expensive: each sign-up that
  /// hits a taken address counts against the source that sent it, and a
  /// source over its budget is refused before the provider is asked. The
  /// count is never kept against the address, because a sign-in lockout that
  /// only taken addresses can trip would be the oracle again.
  Future<AuthUser?> signUp(
    String email,
    String password, {
    String? name,
    required String source,
    String? challengeToken,
  }) async {
    final limited = await velocity.checkSource(source: source);
    if (limited != null) {
      DVObservability.log(
        'A source velocity limit tripped; the sign-up was not tried.',
        level: DVLogLevel.warn,
        code: limited.code,
      );
      throw limited;
    }
    final bots = botProtection;
    if (bots != null) {
      final verdict = await DVBotChallenge(bots, action: 'sign-up')
          .check(challengeToken, source: source);
      if (!verdict.human) {
        throw DVBotRefusal(verdict.reason ?? 'the challenge was not passed');
      }
    }
    await checkNewPassword(password);
    try {
      return await provider.signUp(email, password, name: name);
    } on AuthException catch (error) {
      if (error.failure == AuthFailure.accountExists) {
        await velocity.recordSourceFailure(source: source);
      }
      rethrow;
    }
  }

  /// Throws [DVBreachedPasswordRefusal] for a password in the breach corpus.
  /// Call it on every password change as well as sign-up.
  Future<void> checkNewPassword(String password) async {
    final breached = breachedPasswords;
    if (breached == null) return;

    final bool found;
    try {
      found = await breached.contains(password);
    } catch (error) {
      final unavailable = error is DVBreachedPasswordsUnavailable
          ? error
          : DVBreachedPasswordsUnavailable(error);
      if (breachCheckFailsClosed) throw unavailable;
      DVObservability.log(
        'The breached-password check could not be made; the password was '
        'accepted unchecked.',
        level: DVLogLevel.warn,
        error: unavailable.cause,
      );
      return;
    }
    if (found) {
      const refusal = DVBreachedPasswordRefusal();
      DVObservability.log(refusal.message,
          level: DVLogLevel.warn, code: refusal.code);
      throw refusal;
    }
  }

  Future<void> _padFrom(DateTime started) async {
    final elapsed = _clock().difference(started);
    if (elapsed < refusalFloor) await _delay(refusalFloor - elapsed);
  }
}
