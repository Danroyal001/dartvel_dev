/// The code an application asks somebody to type back: `DV.Auth.code()`.
///
/// Every project that mails a sign-in code writes the same few lines, and the
/// ones that reach for `Random()` rather than `Random.secure()` mint codes a
/// patient attacker can predict from a couple of samples. This is those lines,
/// once, with the randomness that belongs in a credential.
library dartvel_core.auth.one_time_code;

import 'dart:math';

/// One-time codes, as digits.
abstract final class DVOneTimeCode {
  /// Shorter than this is guessable inside any sensible rate limit; longer
  /// than this is not a code anybody types.
  static const int shortest = 4;
  static const int longest = 32;

  static final Random _random = Random.secure();

  /// A code of [length] digits, leading zeros kept.
  ///
  /// Built digit by digit rather than from a number, because a number loses
  /// its leading zeros and "012345" typed back as 12345 then fails to match
  /// for a reason nobody can see.
  static String create({int length = 6}) {
    if (length < shortest || length > longest) {
      throw ArgumentError.value(
        length,
        'length',
        'A code is between $shortest and $longest digits',
      );
    }
    final StringBuffer code = StringBuffer();
    for (int i = 0; i < length; i++) {
      code.write(_random.nextInt(10));
    }
    return code.toString();
  }
}
