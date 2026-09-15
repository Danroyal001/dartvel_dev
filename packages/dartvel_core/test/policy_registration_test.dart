// A policy the build found, a policy the application registered, and a route
// that declares one.
//
// The generated server registered no @DVPolicy class, so a route declaring
// 'Order.view' was answered by DVBackendPolicy.decide alone: an application
// whose decide said yes opened a route whose policy nobody had written, and
// one with no decide refused a route whose policy was written and allowed it.
// These hold the runtime half of the fix to account -- the layer the generated
// registrations go into, the gate a route asks, and the check that refuses to
// start a server whose routes name a policy nothing registered.
//
// The silent failures:
//  * a route whose declared action is not registered answering yes because
//    decide said so;
//  * a generated registration replacing one the application made (or the
//    reverse, depending on which happened to run first);
//  * a policy that needs a resource asked without one, which throws a cast
//    error from inside the registry where a refusal belongs;
//  * a principal outside its scopes let through because the policy allows.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// One resource type per test, because the registry is process-wide and a
// registration one test makes would otherwise answer another test's question.
class Ledger {}

class Invoice {}

class Refund {}

class Shipment {}

class Parcel {}

class Crate {}

class Voucher {}

class Receipt {}

class Rota {}

DVApiPrincipal principal(Set<String> actions) => DVApiPrincipal(
      kind: DVApiPrincipalKind.apiKey,
      subject: 'key-1',
      tenant: 'acme',
      scopes: <String>{'s'},
      actions: actions,
    );

void main() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();

  tearDown(() => DVBackendPolicy.decide = null);

  group('declared registrations', () {
    test('a declared policy answers when the application registered none',
        () async {
      authorization.registerDeclared<Object?, Ledger>(
        'view',
        (Object? user, Ledger ledger) => true,
      );

      expect(await authorization.can<Object?, Ledger>(null, 'view', Ledger()),
          isTrue);
      expect(authorization.registeredPolicies, contains('view:Ledger'));
      expect(authorization.declaredPolicies, contains('view:Ledger'));
    });

    test('the application\'s own registration wins when it came first',
        () async {
      authorization.register<Object?, Invoice>(
        'delete',
        (Object? user, Invoice invoice) => false,
      );
      authorization.registerDeclared<Object?, Invoice>(
        'delete',
        (Object? user, Invoice invoice) => true,
      );

      expect(
          await authorization.can<Object?, Invoice>(null, 'delete', Invoice()),
          isFalse);
      expect(authorization.overriddenPolicies, contains('delete:Invoice'));
    });

    test('the application\'s own registration wins when it came second',
        () async {
      // The generated server registers where it starts, and an application
      // may register after that. Which one answers cannot depend on that.
      authorization.registerDeclared<Object?, Refund>(
        'create',
        (Object? user, Refund refund) => true,
      );
      authorization.register<Object?, Refund>(
        'create',
        (Object? user, Refund refund) => false,
      );

      expect(
          await authorization.can<Object?, Refund>(null, 'create', Refund()),
          isFalse);
      // Registering the declared one again, as a second router build does,
      // does not take the answer back.
      authorization.registerDeclared<Object?, Refund>(
        'create',
        (Object? user, Refund refund) => true,
      );
      expect(
          await authorization.can<Object?, Refund>(null, 'create', Refund()),
          isFalse);
    });
  });

  group('asking by action name', () {
    test('a policy that takes no resource answers without one', () async {
      authorization.registerDeclared<Object?, Shipment?>(
        'viewAny',
        (Object? user, Shipment? shipment) => user == null,
      );

      expect(await authorization.canAction(null, 'Shipment.viewAny'), isTrue);
      expect(await authorization.canAction('someone', 'Shipment.viewAny'),
          isFalse);
    });

    test('a policy that needs a resource is refused without one, not thrown',
        () async {
      authorization.registerDeclared<Object?, Parcel>(
        'update',
        (Object? user, Parcel parcel) => true,
      );

      expect(await authorization.canAction(null, 'Parcel.update'), isFalse);
      expect(
        await authorization.canAction(null, 'Parcel.update',
            resource: Parcel()),
        isTrue,
      );
    });

    test('a caller of the wrong type is refused, not thrown', () async {
      authorization.registerDeclared<String, Crate?>(
        'view',
        (String user, Crate? crate) => true,
      );

      expect(await authorization.canAction(null, 'Crate.view'), isFalse);
      expect(await authorization.canAction('ada', 'Crate.view'), isTrue);
    });

    test('a principal outside its scopes is refused although the policy allows',
        () async {
      authorization.registerDeclared<Object?, Voucher?>(
        'create',
        (Object? user, Voucher? voucher) => true,
      );

      expect(
        await authorization.canAction(
            principal(<String>{'Voucher.view'}), 'Voucher.create'),
        isFalse,
      );
      expect(
        await authorization.canAction(
            principal(<String>{'Voucher.create'}), 'Voucher.create'),
        isTrue,
      );
    });

    test('an action nobody registered is refused', () async {
      expect(await authorization.canAction(null, 'Nothing.view'), isFalse);
    });
  });

  group('the route gate', () {
    test('an action nobody registered is refused even when decide says yes',
        () async {
      DVBackendPolicy.decide = (String policy, String path) async => true;

      expect(await DVBackendPolicy.allowsAction('Unwritten.view', '/x'),
          isFalse);
    });

    test('with no decide the registered policy answers', () async {
      authorization.registerDeclared<Object?, Receipt?>(
        'view',
        (Object? user, Receipt? receipt) => true,
      );
      authorization.registerDeclared<Object?, Receipt?>(
        'delete',
        (Object? user, Receipt? receipt) => false,
      );

      expect(await DVBackendPolicy.allowsAction('Receipt.view', '/r'), isTrue);
      expect(
          await DVBackendPolicy.allowsAction('Receipt.delete', '/r'), isFalse);
    });

    test('with a decide, decide answers a registered action', () async {
      authorization.registerDeclared<Object?, Rota?>(
        'view',
        (Object? user, Rota? rota) => true,
      );
      final List<String> asked = <String>[];
      DVBackendPolicy.decide = (String policy, String path) async {
        asked.add('$policy $path');
        return false;
      };

      expect(await DVBackendPolicy.allowsAction('Rota.view', '/rota'), isFalse);
      expect(asked, <String>['Rota.view /rota']);
    });

    test('a named policy is still the application\'s to decide', () async {
      // DVPolicies.refund names no Resource.action, so no registry can
      // answer it; decide does, and without one it is refused.
      expect(await DVBackendPolicy.allows('DVPolicies.refund', '/r'), isFalse);
      DVBackendPolicy.decide = (String policy, String path) async => true;
      expect(await DVBackendPolicy.allows('DVPolicies.refund', '/r'), isTrue);
    });
  });

  group('starting a server', () {
    test('refuses when a route names an action nothing registered', () {
      authorization.registerDeclared<Object?, Ledger>(
        'update',
        (Object? user, Ledger ledger) => true,
      );

      expect(
        () => DVBackendPolicy.verifyRegistered(
            const <String>['Ledger.update', 'DVApiKeyResource.forceDelete']),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('DVApiKeyResource.forceDelete'),
              isNot(contains('Ledger.update'))),
        )),
      );
      expect(
        () => DVBackendPolicy.verifyRegistered(const <String>['Ledger.update']),
        returnsNormally,
      );
    });
  });
}
