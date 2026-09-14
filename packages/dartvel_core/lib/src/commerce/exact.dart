/// Exact arithmetic for money: rationals over BigInt, one rounding rule per
/// call, and allocation that sums to its total by construction.
///
/// Not exported. Every commerce calculation that divides -- a tax rate, a
/// percentage discount, a proportional refund, a payout split -- comes through
/// here, so there is one place where a remainder can go missing rather than
/// one per feature.
library dartvel.commerce.exact;

/// An exact non-negative quantity `numerator / denominator`.
class DVExact {
  DVExact(this.numerator, this.denominator) {
    if (denominator <= BigInt.zero) {
      throw ArgumentError.value(denominator, 'denominator', 'must be positive');
    }
    if (numerator < BigInt.zero) {
      throw ArgumentError.value(numerator, 'numerator', 'must not be negative');
    }
  }

  DVExact.integer(int value) : this(BigInt.from(value), BigInt.one);

  final BigInt numerator;
  final BigInt denominator;

  DVExact operator +(DVExact other) {
    final BigInt g = denominator.gcd(other.denominator);
    final BigInt lcm = denominator ~/ g * other.denominator;
    return DVExact(
      numerator * (lcm ~/ denominator) + other.numerator * (lcm ~/ other.denominator),
      lcm,
    );
  }

  /// This quantity times `n / d`.
  DVExact scale(BigInt n, BigInt d) => DVExact(numerator * n, denominator * d);

  /// Rounded to an integer. [halfEven] decides only an exact half.
  int round({required bool halfEven}) {
    final BigInt q = numerator ~/ denominator;
    final BigInt twice = (numerator % denominator) * BigInt.two;
    final BigInt rounded;
    if (twice > denominator) {
      rounded = q + BigInt.one;
    } else if (twice < denominator) {
      rounded = q;
    } else {
      rounded = !halfEven || q.isOdd ? q + BigInt.one : q;
    }
    return _toInt(rounded);
  }

  int get floor => _toInt(numerator ~/ denominator);

  static int _toInt(BigInt value) {
    if (!value.isValidInt) {
      throw ArgumentError.value(value, 'amount', 'is too large to hold');
    }
    return value.toInt();
  }
}

/// Splits the integer [total] across [shares], each at most one unit from its
/// exact value, summing to [total] exactly.
///
/// Largest remainder: every share gets its floor, and the units left over go
/// to the shares with the largest fractional parts, the earlier share first on
/// a tie. Rounding each share on its own is the version that drifts -- three
/// thirds of a cent each round to nothing, or each round up to a cent more
/// than was collected.
List<int> dvAllocate(int total, List<DVExact> shares) {
  if (shares.isEmpty) {
    if (total != 0) {
      throw ArgumentError.value(total, 'total', 'cannot be split across nothing');
    }
    return <int>[];
  }
  final List<int> result = <int>[for (final DVExact s in shares) s.floor];
  int left = total - result.fold<int>(0, (int a, int b) => a + b);
  final List<int> order = <int>[for (int i = 0; i < shares.length; i++) i]
    ..sort((int a, int b) {
      final DVExact x = shares[a];
      final DVExact y = shares[b];
      final BigInt fx = (x.numerator % x.denominator) * y.denominator;
      final BigInt fy = (y.numerator % y.denominator) * x.denominator;
      final int byFraction = fy.compareTo(fx);
      return byFraction != 0 ? byFraction : a.compareTo(b);
    });
  if (left < 0 || left > shares.length) {
    throw StateError(
      'cannot allocate $total across shares whose floors sum to '
      '${total - left}; the total is not the sum of these shares',
    );
  }
  for (int i = 0; i < left; i++) {
    result[order[i]] += 1;
  }
  left = 0;
  return result;
}

/// Splits [total] in proportion to [weights], exactly.
List<int> dvAllocateByWeight(int total, List<int> weights) {
  final int sum = weights.fold<int>(0, (int a, int b) => a + b);
  if (weights.any((int w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'must not be negative');
  }
  if (sum == 0) {
    if (total == 0) return <int>[for (final int _ in weights) 0];
    throw ArgumentError.value(weights, 'weights', 'sum to zero');
  }
  return dvAllocate(total, <DVExact>[
    for (final int w in weights)
      DVExact(BigInt.from(total) * BigInt.from(w), BigInt.from(sum)),
  ]);
}

/// A non-negative decimal written as a string, such as `8.875`, as an exact
/// fraction. Null when the text is not one.
DVExact? dvParseDecimal(String text) {
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
  if (match == null) return null;
  final String fraction = match.group(2) ?? '';
  return DVExact(
    BigInt.parse('${match.group(1)}$fraction'),
    BigInt.from(10).pow(fraction.length),
  );
}
