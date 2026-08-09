// Entitlement grants, keyed by identity rather than hash.
//
// `DVLocalBillingProvider` keyed grants by `customer.hashCode`, so two
// customers whose hashes collided shared entitlements: one paying for a plan
// unlocked it for a stranger. Dart's String.hashCode makes that easy to
// demonstrate rather than merely argue about.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A customer type whose hashCode deliberately collides, standing in for any
/// domain object with a lossy hash.
class Customer {
  final String id;
  const Customer(this.id);

  @override
  bool operator ==(Object other) => other is Customer && other.id == id;

  // A real collision, of the kind any hash has.
  @override
  int get hashCode => 42;

  @override
  String toString() => 'Customer($id)';
}

void main() {
  late DVLocalBillingProvider billing;

  setUp(() => billing = DVLocalBillingProvider());

  test('one customer cannot see another customer entitlement', () async {
    const paying = Customer('paying');
    const stranger = Customer('stranger');

    billing.grant(paying, Entitlement.analytics);

    expect(await billing.hasEntitlement(paying, Entitlement.analytics), isTrue);
    // Under the hashCode key these two shared a grant.
    expect(
      await billing.hasEntitlement(stranger, Entitlement.analytics),
      isFalse,
    );
  });

  test('revoking takes back only that entitlement', () async {
    const customer = Customer('a');
    billing.grant(customer, Entitlement.analytics);
    billing.grant(customer, const Entitlement('exports'));

    billing.revoke(customer, Entitlement.analytics);

    expect(
      await billing.hasEntitlement(customer, Entitlement.analytics),
      isFalse,
    );
    expect(
      await billing.hasEntitlement(customer, const Entitlement('exports')),
      isTrue,
    );
  });

  test('grants are readable, so an entitlements view can list them', () {
    billing.grant(const Customer('a'), Entitlement.analytics);
    billing.grant(const Customer('b'), const Entitlement('exports'));

    // hashCode keys were unreadable to anything inspecting the store.
    expect(billing.grants.keys, containsAll(<String>[
      'Customer(a)',
      'Customer(b)',
    ]));
    expect(billing.grants['Customer(a)'], <String>{'analytics'});
  });

  test('a customer with nothing granted is absent, not empty', () {
    billing.grant(const Customer('a'), Entitlement.analytics);
    billing.revoke(const Customer('a'), Entitlement.analytics);

    expect(billing.grants, isEmpty);
  });
}
