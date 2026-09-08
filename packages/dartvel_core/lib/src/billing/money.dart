/// A price, and what its integer counts.
///
/// `@DVModel(billable: true, nativePrice: 100)` is in the specification and
/// was read by nothing: both arguments were declared on the annotation, unit
/// tested for holding the values they were given, and never looked at by the
/// generator. A model marked billable generated exactly what an unbillable
/// one did, and 100 was a number in a file.
///
/// A price needs three things before it means anything -- a currency, a rule
/// for what the integer counts, and a conversion that refuses rather than
/// guesses -- and this is those three.
library;

/// How many decimal places a currency's minor unit has, where it is not two.
///
/// ISO 4217 gives most of the world two. The ones that do not are the reason
/// this table exists: 100 JPY is a hundred yen, and a framework that divided
/// every currency by a hundred would price a coffee at a hundredth of a yen
/// with nothing about the number looking wrong.
const Map<String, int> dvCurrencyExponents = <String, int>{
  // No minor unit at all.
  'BIF': 0, 'CLP': 0, 'DJF': 0, 'GNF': 0, 'ISK': 0, 'JPY': 0, 'KMF': 0,
  'KRW': 0, 'PYG': 0, 'RWF': 0, 'UGX': 0, 'UYI': 0, 'VND': 0, 'VUV': 0,
  'XAF': 0, 'XOF': 0, 'XPF': 0,
  // Thousandths.
  'BHD': 3, 'IQD': 3, 'JOD': 3, 'KWD': 3, 'LYD': 3, 'OMR': 3, 'TND': 3,
  // Ten-thousandths.
  'CLF': 4, 'UYW': 4,
};

/// The number of decimal places [currency]'s minor unit has.
///
/// Two for anything not in the table. That is the right default -- it is what
/// most of the world uses -- but it is a default rather than a lookup, which
/// is why the table is the thing that gets extended when a currency is wrong
/// rather than the rounding being adjusted at a call site.
int dvCurrencyExponent(String currency) =>
    dvCurrencyExponents[currency.toUpperCase()] ?? 2;

/// An amount in a currency's minor units.
///
/// Integer, because a price held as a double is a price that is occasionally
/// 9.999999999999998.
class DVMoney {
  DVMoney({required this.amount, required String currency})
      : currency = currency.toUpperCase() {
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'a currency is an ISO 4217 code -- three letters, such as USD',
      );
    }
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'a price is what something costs. A refund is a different operation, '
            'and a negative price is how it gets mistaken for one',
      );
    }
  }

  /// The amount, in [currency]'s minor units: cents for USD, yen for JPY.
  final int amount;

  /// An upper-case ISO 4217 code.
  final String currency;

  /// The decimal places this currency's minor unit has.
  int get exponent => dvCurrencyExponent(currency);

  /// This amount in [to], using a rate the application configured.
  ///
  /// Throws when there is no rate. The alternative -- returning the same
  /// integer under a different code -- is the failure worth refusing: 1000 US
  /// cents becoming 1000 yen is a plausible number in the right shape, and
  /// nothing downstream can tell it was never converted.
  DVMoney inCurrency(String to) {
    final String target = to.toUpperCase();
    if (target == currency) return this;

    final double? rate = DVBillingRates.rateFor(from: currency, to: target);
    if (rate == null) {
      throw StateError(
        'No conversion rate from $currency to $target. Set one with '
        'DVBillingRates.set(from: \'$currency\', to: \'$target\', rate: ...). '
        'Returning the amount unconverted would be a number in the right '
        'shape that nothing downstream could tell was wrong.',
      );
    }

    // Through the major unit, because the two sides count different things.
    // Ten dollars at 150 yen to the dollar is 1500 yen; the same rate applied
    // to the raw minor units gives 150000, wrong by exactly the difference
    // between the exponents.
    final double major = amount / _pow10(exponent);
    final double converted = major * rate;
    return DVMoney(
      amount: (converted * _pow10(dvCurrencyExponent(target))).round(),
      currency: target,
    );
  }

  @override
  String toString() {
    if (exponent == 0) return '$amount $currency';
    final int unit = _pow10(exponent);
    final String minor =
        (amount % unit).toString().padLeft(exponent, '0');
    return '${amount ~/ unit}.$minor $currency';
  }

  @override
  bool operator ==(Object other) =>
      other is DVMoney &&
      other.amount == amount &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  static int _pow10(int places) {
    int value = 1;
    for (int i = 0; i < places; i++) {
      value *= 10;
    }
    return value;
  }
}

/// The conversion rates an application has configured.
///
/// The specification says rates "can be overridden", which means the
/// application is the authority and the framework ships none. A rate nobody
/// set is absent rather than guessed, and a rate set twice is the second one:
/// overriding is what this is for.
class DVBillingRates {
  const DVBillingRates._();

  static final Map<String, double> _rates = <String, double>{};

  /// Sets the rate from one currency to another.
  static void set({
    required String from,
    required String to,
    required double rate,
  }) {
    if (rate <= 0 || !rate.isFinite) {
      throw ArgumentError.value(
        rate,
        'rate',
        'a conversion rate is a positive number',
      );
    }
    _rates[_key(from, to)] = rate;
  }

  /// The configured rate, or null.
  ///
  /// The inverse of a configured rate is not an answer. A published rate has
  /// a spread, and inverting one produces a number the application never
  /// agreed to and cannot be held to.
  static double? rateFor({required String from, required String to}) =>
      _rates[_key(from, to)];

  /// Every configured rate, as `FROM>TO`.
  static Map<String, double> get all => Map<String, double>.unmodifiable(_rates);

  /// Forgets every rate. For tests, and for an application reloading them.
  static void reset() => _rates.clear();

  static String _key(String from, String to) =>
      '${from.toUpperCase()}>${to.toUpperCase()}';
}
