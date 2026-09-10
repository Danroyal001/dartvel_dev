// Who a grant belongs to.
//
// Every provider keyed entitlements by `customer.toString()`. For a String
// or a class that overrides toString that is an identity; for an ordinary
// Dart object it is the constant "Instance of 'User'". Pass the logged-in
// user straight in -- the obvious thing to do, and what DV.Billing's own
// signature invites, since it takes an Object -- and every user in the
// application shares one key. One person subscribes and everybody has the
// plan.
//
// Nothing about that fails. The subscriber sees what they paid for, the
// tests pass because a test writes toString, and the only symptom is
// revenue that never arrives from people who never had to buy anything.
//
// So the key is either something that identifies a customer or it is an
// error. There is no third behaviour worth having here: guessing an
// identity from a hash code was the previous version of this bug, and
// falling back to the type name is the same bug with better spelling.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// An ordinary domain object. No toString, like most classes.
class User {
  User(this.id);
  final int id;
}

/// A domain object that says which billing customer it is.
class Account implements DVBillingCustomer {
  Account(this.stripeId);
  final String stripeId;

  @override
  String get billingCustomerId => stripeId;
}

void main() {
  late DVLocalBillingProvider billing;
  setUp(() => billing = DVLocalBillingProvider());

  test('an object with no identity is refused rather than shared', () {
    expect(
      () => billing.grant(User(1), Entitlement.analytics),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => e.message.toString(), 'message', contains('User'))),
    );
    expect(billing.grants, isEmpty);
  });

  test('the refusal covers reading as well as writing', () async {
    // A read that answered false would look like a working denial while the
    // application quietly had no billing identity at all.
    await expectLater(
      () => billing.hasEntitlement(User(2), Entitlement.analytics),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('two rows for the same customer are the same customer', () async {
    // The point of an explicit identifier: an object loaded twice is not
    // two subscribers.
    billing.grant(Account('cus_7'), Entitlement.analytics);

    expect(await billing.hasEntitlement(Account('cus_7'), Entitlement.analytics),
        isTrue);
    expect(await billing.hasEntitlement(Account('cus_8'), Entitlement.analytics),
        isFalse);
    expect(billing.grants.keys, <String>['cus_7']);
  });

  test('an empty identifier is not an identifier', () {
    expect(() => billing.grant(Account(''), Entitlement.analytics),
        throwsA(isA<ArgumentError>()));
  });

  test('a string customer still works', () async {
    billing.grant('cus_9', Entitlement.analytics);
    expect(
        await billing.hasEntitlement('cus_9', Entitlement.analytics), isTrue);
  });

  test('a class that spells out its own identity still works', () async {
    // Not everything that identifies itself implements the interface, and a
    // meaningful toString is an identity.
    billing.grant(const _Named('team-4'), Entitlement.analytics);
    expect(await billing.hasEntitlement(const _Named('team-4'),
        Entitlement.analytics), isTrue);
  });

  group('providers', () {
    test('Stripe refuses a customer it cannot name', () async {
      final DVStripeBillingProvider p = DVStripeBillingProvider(
        secretKey: 'sk_test',
        webhookSecret: 'whsec_test',
        prices: const <String, String>{'pro': 'price_pro'},
        entitlements: const <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://app.example/ok'),
        cancelUrl: Uri.parse('https://app.example/no'),
        fetch: (String method, Uri url, Map<String, String> h,
                String? b) async =>
            fail('nothing should have been sent'),
      );

      await expectLater(
        () => p.hasEntitlement(User(3), Entitlement.analytics),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        p.checkout(
            plan: const BillingPlan(
                id: 'pro',
                displayName: 'Pro',
                priceMinorUnits: 0,
                currency: 'USD'),
            customer: User(3)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Paddle refuses a customer it cannot name', () async {
      final DVPaddleBillingProvider p = DVPaddleBillingProvider(
        apiKey: 'pdl_live_key',
        webhookSecret: 's',
        prices: const <String, String>{'pro': 'pri_pro'},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> h,
                String? b) async =>
            fail('nothing should have been sent'),
      );

      await expectLater(
        () => p.hasEntitlement(User(4), Entitlement.analytics),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _Named {
  const _Named(this.name);
  final String name;

  @override
  String toString() => name;
}
