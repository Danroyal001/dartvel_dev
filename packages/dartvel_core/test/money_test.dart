// `@DVModel(billable: true, nativePrice: 100)` is in the specification and
// was read by nothing. Both arguments were declared on the annotation, unit
// tested for holding the values they were given, and never looked at by the
// generator -- so a model marked billable generated exactly what an
// unbillable one did, and 100 was a number in a file.
//
// A price needs three things before it means anything: a currency, a rule
// for what the integer counts, and a conversion that refuses rather than
// guesses. This is those three.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('what the integer counts', () {
    test('most currencies count hundredths', () {
      expect(const DVMoney(amount: 100, currency: 'USD').toString(), '1.00 USD');
      expect(const DVMoney(amount: 5, currency: 'EUR').toString(), '0.05 EUR');
    });

    test('yen counts yen', () {
      // 100 JPY is a hundred yen, not one. A framework that divided every
      // currency by a hundred would price a coffee at a hundredth of a yen
      // and nothing about the number would look wrong.
      expect(const DVMoney(amount: 100, currency: 'JPY').toString(), '100 JPY');
    });

    test('dinars count thousandths', () {
      expect(
        const DVMoney(amount: 1500, currency: 'KWD').toString(),
        '1.500 KWD',
      );
    });

    test('a currency nobody tabulated counts hundredths and says so', () {
      // Two decimal places is what ISO 4217 uses for most of the world, so
      // it is the right default -- but the answer is a guess and the
      // exponent says which currencies were actually looked up.
      expect(dvCurrencyExponent('ZWG'), 2);
      expect(dvCurrencyExponent('JPY'), 0);
    });

    test('a currency code is three letters, or it is not a currency', () {
      expect(
        () => DVMoney(amount: 1, currency: 'dollars'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a negative amount is refused', () {
      // A price is what something costs. A refund is a different operation
      // and a negative price is how it gets mistaken for one.
      expect(
        () => DVMoney(amount: -1, currency: 'USD'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('converting a price', () {
    setUp(DVBillingRates.reset);

    test('a rate the application configured is applied', () {
      DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0.92);

      expect(
        const DVMoney(amount: 1000, currency: 'USD').inCurrency('EUR'),
        const DVMoney(amount: 920, currency: 'EUR'),
      );
    });

    test('a rate is overridable, which is the point of setting one', () {
      DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0.92);
      DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0.85);

      expect(
        const DVMoney(amount: 1000, currency: 'USD').inCurrency('EUR').amount,
        850,
      );
    });

    test('a conversion with no rate refuses rather than returning the number',
        () {
      // The failure worth refusing: 1000 US cents becoming 1000 yen because
      // nobody configured a rate. It is a plausible number in the right
      // shape, and nothing downstream can tell it was never converted.
      expect(
        () => const DVMoney(amount: 1000, currency: 'USD').inCurrency('JPY'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('USD'), contains('JPY')),
          ),
        ),
      );
    });

    test('a currency converted to itself needs no rate', () {
      expect(
        const DVMoney(amount: 1000, currency: 'USD').inCurrency('USD').amount,
        1000,
      );
    });

    test('crossing exponents rescales rather than reinterpreting', () {
      // 10.00 USD at 150 yen to the dollar is 1500 yen, not 150000. The
      // integers are in different units on each side and a rate applied to
      // the raw minor units gets it wrong by a factor of a hundred.
      DVBillingRates.set(from: 'USD', to: 'JPY', rate: 150);

      expect(
        const DVMoney(amount: 1000, currency: 'USD').inCurrency('JPY').amount,
        1500,
      );
    });

    test('an inverse is not assumed', () {
      // A published rate has a spread, and inverting one is a number the
      // application never agreed to.
      DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0.92);

      expect(
        () => const DVMoney(amount: 100, currency: 'EUR').inCurrency('USD'),
        throwsStateError,
      );
    });

    test('a rate that is not positive is refused', () {
      expect(
        () => DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
