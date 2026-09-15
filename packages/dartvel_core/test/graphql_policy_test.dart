// A GraphQL field runs under the policy of what it resolves through.
//
// The generated /graphql route answered whatever the application registered on
// DVGraphQL, and nothing between the request and a resolver asked a policy: a
// mutation that resolves through a backend function guarded by Order.create
// ran for a key whose scopes cover only Order.view, because the scopes were
// checked on the backend function's own route and GraphQL is not that route.
// A field now declares the Resource.action it runs under, and it is asked the
// way that route asks -- scopes first, then the registry, then decide -- before
// its resolver runs.
//
// The silent failures:
//  * a mutation reaching its resolver for a key whose scopes do not cover it;
//  * a field that declares no policy answering a key, where no scope can have
//    been checked;
//  * a refused field still running its resolver and only hiding the result;
//  * a subscription started for a caller its policy refuses.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class GqlOrder {}

class GqlNote {}

DVApiPrincipal key(Set<String> actions) => DVApiPrincipal(
      kind: DVApiPrincipalKind.apiKey,
      subject: 'key-1',
      tenant: 'acme',
      scopes: <String>{'s'},
      actions: actions,
    );

void main() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();
  late List<String> ran;

  setUpAll(() {
    authorization.registerDeclared<Object?, GqlOrder?>(
        'view', (Object? user, GqlOrder? order) => true);
    authorization.registerDeclared<Object?, GqlOrder?>(
        'create', (Object? user, GqlOrder? order) => user is DVApiPrincipal);
    authorization.registerDeclared<Object?, GqlNote?>(
        'view', (Object? user, GqlNote? note) => false);
  });

  setUp(() {
    ran = <String>[];
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('Order', <DVGraphQLField>[
      const DVGraphQLField('id', 'String!'),
      DVGraphQLField('note', 'String', policy: 'GqlNote.view',
          resolve: (Map<String, Object?> args, Object? parent) {
        ran.add('note');
        return 'secret';
      }),
    ]));
    DVGraphQL.registerQuery(DVGraphQLField('orders', '[Order!]!',
        policy: 'GqlOrder.view',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('orders');
      return <Object?>[
        <String, Object?>{'id': 'o1'},
      ];
    }));
    DVGraphQL.registerQuery(DVGraphQLField('open', 'String!',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('open');
      return 'open';
    }));
    DVGraphQL.registerMutation(DVGraphQLField('createOrder', 'String!',
        policy: 'GqlOrder.create',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('createOrder');
      return 'created';
    }));
    DVGraphQL.registerMutation(DVGraphQLField('unwritten', 'String!',
        policy: 'GqlInvoice.create',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('unwritten');
      return 'written';
    }));
    DVGraphQL.registerSubscription(DVGraphQLField('orderCreated', 'String!',
        policy: 'GqlOrder.create',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('orderCreated');
      return Stream<String>.value('o1');
    }));
  });

  tearDown(() => DVBackendPolicy.decide = null);

  Future<Map<String, Object?>> asKey(Set<String> actions, String document) =>
      DVApiPrincipal.actingAs(key(actions), () => DVGraphQL.execute(document));

  List<Object?> errorsOf(Map<String, Object?> result) =>
      (result['errors'] as List<Object?>?) ?? const <Object?>[];

  test('a mutation outside the key\'s scopes never reaches its resolver',
      () async {
    final Map<String, Object?> result =
        await asKey(<String>{'GqlOrder.view'}, 'mutation { createOrder }');

    expect(ran, isEmpty);
    expect((result['data'] as Map?)?['createOrder'], isNull);
    expect(errorsOf(result).toString(), contains('GqlOrder.create'));
  });

  test('a mutation inside the key\'s scopes runs, and its policy sees the key',
      () async {
    final Map<String, Object?> result =
        await asKey(<String>{'GqlOrder.create'}, 'mutation { createOrder }');

    expect(ran, <String>['createOrder']);
    expect(result['data'], <String, Object?>{'createOrder': 'created'});
  });

  test('without a key the policy still decides', () async {
    final Map<String, Object?> result =
        await DVGraphQL.execute('mutation { createOrder }');

    // The policy allows only a platform caller.
    expect(ran, isEmpty);
    expect(errorsOf(result).toString(), contains('GqlOrder.create'));

    final Map<String, Object?> read =
        await DVGraphQL.execute('{ orders { id } }');
    expect(read['data'], <String, Object?>{
      'orders': <Object?>[
        <String, Object?>{'id': 'o1'},
      ],
    });
  });

  test('a field that declares no policy answers no key', () async {
    final Map<String, Object?> keyed =
        await asKey(<String>{'GqlOrder.view'}, '{ open }');
    expect(ran, isEmpty);
    expect(errorsOf(keyed), isNotEmpty);

    // It is the key that is refused; the field is open to the application.
    final Map<String, Object?> anonymous = await DVGraphQL.execute('{ open }');
    expect(anonymous['data'], <String, Object?>{'open': 'open'});
  });

  test('an action nothing registered is refused although decide says yes',
      () async {
    DVBackendPolicy.decide = (String policy, String path) async => true;

    final Map<String, Object?> result =
        await DVGraphQL.execute('mutation { unwritten }');

    expect(ran, isEmpty);
    expect(errorsOf(result).toString(), contains('GqlInvoice.create'));
  });

  test('a nested field with a policy is refused on its own', () async {
    final Map<String, Object?> result =
        await asKey(<String>{'GqlOrder.view', 'GqlNote.view'},
            '{ orders { id note } }');

    // The order is served; the note's policy denies, so its resolver did not
    // run and the note is null with an error beside it. A plain field of the
    // order, which declares nothing, is not refused for being read by a key.
    expect(ran, <String>['orders']);
    expect(result['data'], <String, Object?>{
      'orders': <Object?>[
        <String, Object?>{'id': 'o1', 'note': null},
      ],
    });
    expect(errorsOf(result).toString(), contains('GqlNote.view'));
  });

  test('a subscription runs as whoever subscribed, wherever it is listened to',
      () async {
    // A server writes a response stream from wherever it calls the producer,
    // which need not be the request's zone. Subscribed as a key allowed to
    // create, on acme, and listened to from outside both: without the caller
    // the policy (platform callers only) refuses, and without the tenant the
    // resolver reads the process default.
    final List<String> tenants = <String>[];
    DVGraphQL.registerSubscription(DVGraphQLField('orderCreated', 'String!',
        policy: 'GqlOrder.create',
        resolve: (Map<String, Object?> args, Object? parent) {
      ran.add('orderCreated');
      tenants.add(const DVTenants().currentTenant);
      return Stream<String>.value('o1');
    }));
    final Stream<Map<String, Object?>> subscribed =
        await const DVTenants().withTenant('acme', () {
      return DVApiPrincipal.actingAs(key(<String>{'GqlOrder.create'}),
          () async => DVGraphQL.subscribe('subscription { orderCreated }'));
    });

    final List<Map<String, Object?>> events = await subscribed.toList();

    expect(ran, <String>['orderCreated']);
    expect(tenants, <String>['acme']);
    expect(events.single['data'],
        <String, Object?>{'orderCreated': 'o1'});
  });

  test('a subscription its policy refuses is never started', () async {
    final List<Map<String, Object?>> events =
        await DVApiPrincipal.actingAs(key(<String>{'GqlOrder.view'}), () async {
      return DVGraphQL.subscribe('subscription { orderCreated }').toList();
    });

    expect(ran, isEmpty);
    expect(events.single['errors'].toString(), contains('GqlOrder.create'));
  });
}
