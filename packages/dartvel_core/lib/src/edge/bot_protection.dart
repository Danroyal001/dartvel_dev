/// Bot protection as an adapter interface.
///
/// Turnstile, hCaptcha, reCAPTCHA or a private scorer: captcha providers are a
/// market with jurisdictional and privacy trade-offs an application must be
/// free to make, so no provider is bundled.
library dartvel_core.edge.bot_protection;

import '../middleware/middleware.dart';
import '../observability/observability.dart';
import 'request_parts.dart';

/// What a provider concluded about a challenge token.
class DVBotVerdict {
  const DVBotVerdict.human()
      : human = true,
        reason = null;

  const DVBotVerdict.bot(String this.reason) : human = false;

  final bool human;

  /// Why it was not taken for a human, for logs.
  final String? reason;
}

/// A challenge provider.
abstract interface class DVBotProtection {
  /// For logs: `turnstile`, `hcaptcha`, `test`.
  String get provider;

  /// Verifies the token the challenge widget produced. [action] names what is
  /// being protected (`sign-up`); [source] is the client address, which some
  /// providers check the token against.
  Future<DVBotVerdict> verify(String? token, {String? action, String? source});
}

/// A provider that accepts a fixed set of tokens. For tests.
class DVTestBotProtection implements DVBotProtection {
  DVTestBotProtection({
    this.acceptedTokens = const <String>{},
    this.failWith,
  });

  final Set<String> acceptedTokens;

  /// Thrown from [verify], to exercise a provider that is down.
  final Object? failWith;

  @override
  String get provider => 'test';

  @override
  Future<DVBotVerdict> verify(
    String? token, {
    String? action,
    String? source,
  }) async {
    final failure = failWith;
    if (failure != null) throw failure;
    if (token == null || token.isEmpty) {
      return const DVBotVerdict.bot('no challenge token');
    }
    return acceptedTokens.contains(token)
        ? const DVBotVerdict.human()
        : const DVBotVerdict.bot('the token was not accepted');
  }
}

/// A request refused for not passing the challenge.
class DVBotRefusal implements Exception {
  const DVBotRefusal(this.reason);

  /// For logs; the client is told only [message].
  final String reason;

  String get message => 'The challenge was not passed.';

  @override
  String toString() => 'DVBotRefusal: $reason';
}

/// A challenge in front of an action.
///
/// It fails closed: a provider that throws or times out is a challenge not
/// passed, because a check that lets requests through whenever the provider
/// is unreachable is bypassed by making it unreachable.
class DVBotChallenge {
  const DVBotChallenge(
    this.protection, {
    this.header = 'x-dv-challenge',
    this.action,
  });

  final DVBotProtection protection;

  /// The request header the challenge token travels in.
  final String header;

  final String? action;

  Future<DVBotVerdict> check(String? token, {String? source}) async {
    try {
      return await protection.verify(token, action: action, source: source);
    } catch (error) {
      DVObservability.log(
        'The ${protection.provider} challenge check failed; refusing.',
        level: DVLogLevel.warn,
        error: error,
      );
      return DVBotVerdict.bot('the ${protection.provider} check failed');
    }
  }

  Middleware middleware() => (request, context) async {
        final verdict = await check(dvEdgeHeader(request, header));
        if (verdict.human) return;
        context.abort();
        context.data['botError'] = 'Challenge required';
      };
}
