import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late List<Map<String, Object?>> users;
  late int resolved;

  setUp(() {
    resolved = 0;
    users = <Map<String, Object?>>[
      <String, Object?>{'slug': 'ada', 'name': 'Ada'},
      <String, Object?>{'slug': 'grace', 'name': 'Grace'},
    ];
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('User', <DVGraphQLField>[
      const DVGraphQLField('slug', 'String!'),
      const DVGraphQLField('name', 'String!'),
      DVGraphQLField(
        'friends',
        '[User!]!',
        args: const <String, String>{'first': 'Int'},
        resolve: (args, parent) {
          resolved++;
          return users;
        },
      ),
    ]));
    DVGraphQL.registerQuery(DVGraphQLField(
      'users',
      '[User!]!',
      args: const <String, String>{'first': 'Int'},
      resolve: (args, parent) {
        resolved++;
        return users;
      },
    ));
    DVGraphQL.registerQuery(DVGraphQLField(
      'user',
      'User',
      args: const <String, String>{'slug': 'String!'},
      resolve: (args, parent) {
        resolved++;
        return users.first;
      },
    ));
  });

  tearDown(DVGraphQL.reset);

  /// The refusal's extensions, after checking it is a refusal and not a
  /// trimmed answer.
  Map<String, Object?> refusalOf(Map<String, Object?> result) {
    expect(result.containsKey('data'), isFalse,
        reason: 'an over-budget query is refused, not truncated');
    final errors = result['errors']! as List<Object?>;
    expect(errors, hasLength(1));
    final error = errors.single! as Map<String, Object?>;
    return (error['extensions']! as Map<Object?, Object?>)
        .cast<String, Object?>();
  }

  group('depth', () {
    test('counts every level, not only the root fields', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxDepth: 3);
      const document = '{ users { friends { friends { name } } } }';

      expect(DVGraphQL.analyze(document).depth, 4);
      final refusal = refusalOf(await DVGraphQL.execute(document));
      expect(refusal['code'], 'DV-EDGE-001');
      expect(refusal['budget'], 'depth');
      expect(refusal['limit'], 3);
      expect(refusal['actual'], 4);
      expect(refusal['excess'], 1);
      expect(resolved, 0, reason: 'a refused query runs no resolver');
    });

    test('a named fragment does not hide the levels it adds', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxDepth: 3);
      final refusal = refusalOf(await DVGraphQL.execute('''
        query { users { ...Deep } }
        fragment Deep on User { friends { friends { name } } }
      '''));
      expect(refusal['budget'], 'depth');
      expect(refusal['actual'], 4);
    });

    test('an inline fragment does not hide the levels it adds', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxDepth: 3);
      final refusal = refusalOf(await DVGraphQL.execute(
        '{ users { ... on User { friends { friends { name } } } } }',
      ));
      expect(refusal['budget'], 'depth');
    });

    test('a query within the budget runs', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxDepth: 3);
      final result =
          await DVGraphQL.execute('{ users { friends { name } } }');
      expect(result['errors'], isNull);
      expect((result['data']! as Map)['users'], hasLength(2));
    });

    test('a subscription over budget is refused too', () async {
      DVGraphQL.registerSubscription(DVGraphQLField(
        'arrivals',
        'User!',
        resolve: (args, parent) {
          resolved++;
          return Stream<Object?>.value(users.first);
        },
      ));
      DVGraphQL.limits = const DVGraphQLLimits(maxDepth: 3);
      final events = await DVGraphQL.subscribe(
        'subscription { arrivals { friends { friends { name } } } }',
      ).toList();
      expect(refusalOf(events.single)['code'], 'DV-EDGE-001');
      expect(resolved, 0);
    });
  });

  group('cost', () {
    test('aliases each cost what they ask for', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxCost: 30);
      String aliased(int count) => '{ ${[
            for (var i = 0; i < count; i++) 'a$i: user(slug: "ada") { name }',
          ].join(' ')} }';

      final refusal = refusalOf(await DVGraphQL.execute(aliased(20)));
      expect(refusal['budget'], 'cost');
      expect(refusal['limit'], 30);
      expect(refusal['actual'], 40);
      expect(refusal['excess'], 10);
      expect(resolved, 0);

      final result = await DVGraphQL.execute(aliased(10));
      expect(result['errors'], isNull);
    });

    test('a fragment spread several times is counted each time', () async {
      DVGraphQL.registerQuery(const DVGraphQLField(
        'report',
        'String!',
        cost: 40,
      ));
      DVGraphQL.limits = const DVGraphQLLimits(maxCost: 100);
      final refusal = refusalOf(await DVGraphQL.execute('''
        query { ...R ...R ...R }
        fragment R on Query { report }
      '''));
      expect(refusal['actual'], 120);
    });

    test('a list multiplies by the page size it asks for', () async {
      DVGraphQL.limits =
          const DVGraphQLLimits(maxCost: 500, defaultPageSize: 20);

      expect(DVGraphQL.analyze('{ users { name } }').cost, 40);
      expect(DVGraphQL.analyze('{ users(first: 10) { name } }').cost, 20);

      final refusal = refusalOf(
        await DVGraphQL.execute('{ users(first: 1000) { name } }'),
      );
      expect(refusal['actual'], 2000);
      expect(
        (await DVGraphQL.execute('{ users(first: 10) { name } }'))['errors'],
        isNull,
      );
    });

    test('a page size passed in a variable is priced too', () async {
      DVGraphQL.limits =
          const DVGraphQLLimits(maxCost: 500, defaultPageSize: 20);
      final refusal = refusalOf(await DVGraphQL.execute(
        r'query Q($n: Int) { users(first: $n) { name } }',
        variables: <String, Object?>{'n': 1000},
      ));
      expect(refusal['actual'], 2000);
    });

    test('a nested list multiplies by both page sizes', () {
      expect(
        DVGraphQL.analyze(
          '{ users(first: 10) { friends(first: 10) { name } } }',
        ).cost,
        10 * (1 + 10 * (1 + 1)),
      );
    });

    test('a backend-function field costs what it declares', () async {
      DVGraphQL.registerQuery(DVGraphQLField(
        'report',
        'String!',
        cost: 400,
        resolve: (args, parent) {
          resolved++;
          return 'expensive';
        },
      ));
      DVGraphQL.limits = const DVGraphQLLimits(maxCost: 100);
      final result = await DVGraphQL.execute('{ report }');
      final refusal = refusalOf(result);
      expect(refusal['limit'], 100);
      expect(refusal['actual'], 400);
      expect(refusal['excess'], 300);
      final message =
          ((result['errors']! as List).single! as Map)['message'] as String;
      expect(message, allOf(contains('100'), contains('300')));
      expect(resolved, 0);
    });
  });

  group('auto budgets', () {
    test('auto depth allows one step back into a cycle and refuses a walk',
        () async {
      expect(DVGraphQL.autoMaxDepth, 3);
      final ok = await DVGraphQL.execute(
        '{ users(first: 2) { friends(first: 2) { name } } }',
      );
      expect(ok['errors'], isNull);

      final refusal = refusalOf(await DVGraphQL.execute(
        '{ users(first: 2) { friends(first: 2) { friends(first: 2) '
        '{ name } } } }',
      ));
      expect(refusal['budget'], 'depth');
      expect(refusal['limit'], 3);
    });

    test('auto depth is derived from the graph, not a constant', () async {
      DVGraphQL.registerType(DVGraphQLObjectType('Org', const <DVGraphQLField>[
        DVGraphQLField('name', 'String!'),
      ]));
      DVGraphQL.registerType(DVGraphQLObjectType('Team', const <DVGraphQLField>[
        DVGraphQLField('name', 'String!'),
        DVGraphQLField('org', 'Org!'),
      ]));
      DVGraphQL.registerType(DVGraphQLObjectType('User', <DVGraphQLField>[
        const DVGraphQLField('name', 'String!'),
        const DVGraphQLField('team', 'Team!'),
        DVGraphQLField('friends', '[User!]!', resolve: (a, p) => users),
      ]));
      for (final user in users) {
        user['team'] = <String, Object?>{
          'name': 'core',
          'org': <String, Object?>{'name': 'acme'},
        };
      }

      expect(DVGraphQL.autoMaxDepth, 5);
      final result = await DVGraphQL.execute(
        '{ users(first: 1) { friends(first: 1) { team { org { name } } } } }',
      );
      expect(result['errors'], isNull);
    });

    test('auto cost refuses the same list-in-list asked for twice', () async {
      const once = '{ a: users { friends { name } } }';
      const twice =
          '{ a: users { friends { name } } b: users { friends { name } } }';
      expect((await DVGraphQL.execute(once))['errors'], isNull);
      expect(refusalOf(await DVGraphQL.execute(twice))['budget'], 'cost');
    });

    test('auto budgets are computed without walking every path', () {
      // Forty types, each related to every other: the number of simple paths
      // through this graph is astronomical, so an analyser that enumerates
      // them never returns.
      DVGraphQL.reset();
      for (var i = 0; i < 40; i++) {
        DVGraphQL.registerType(DVGraphQLObjectType('T$i', <DVGraphQLField>[
          const DVGraphQLField('name', 'String!'),
          for (var j = 0; j < 40; j++) DVGraphQLField('t$j', '[T$j!]!'),
        ]));
        DVGraphQL.registerQuery(DVGraphQLField('t$i', '[T$i!]!'));
      }
      expect(DVGraphQL.autoMaxDepth, greaterThan(2));
      expect(DVGraphQL.autoMaxCost, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('documents built to hang the analyser', () {
    test('fragments that double at every level are refused, not expanded',
        () async {
      // F80 expands to 2^80 fields: more than an int holds, so a counter that
      // wraps would come back negative and let it through.
      final fragments = StringBuffer('fragment F0 on User { name }\n');
      for (var i = 1; i <= 80; i++) {
        fragments.writeln('fragment F$i on User { ...F${i - 1} ...F${i - 1} }');
      }
      final result = await DVGraphQL.execute(
        '{ user(slug: "ada") { ...F80 } }\n$fragments',
      );
      final refusal = refusalOf(result);
      expect(refusal['budget'], 'cost');
      expect(refusal['actual'] as int, greaterThan(0));
      expect(resolved, 0);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a fragment that spreads itself is a request error', () async {
      final result = await DVGraphQL.execute('''
        { users { ...A } }
        fragment A on User { name ...B }
        fragment B on User { slug ...A }
      ''');
      expect(result.containsKey('data'), isFalse);
      final message =
          ((result['errors']! as List).single! as Map)['message'] as String;
      expect(message, contains('cycle'));
      expect(resolved, 0);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('introspection', () {
    const schemaQuery = '{ __schema { types { name } } }';

    Future<bool> refused(String document, {bool authenticated = false}) async {
      final result = await DVGraphQL.execute(document,
          authenticated: authenticated);
      if (result.containsKey('data')) return false;
      final message =
          ((result['errors']! as List).single! as Map)['message'] as String;
      expect(message, contains('Introspection'));
      return true;
    }

    test('defaults to development only', () {
      expect(const DVGraphQLLimits().introspection,
          DVGraphQLIntrospection.development);
    });

    test('never refuses __schema and __type but still answers __typename',
        () async {
      DVGraphQL.limits =
          const DVGraphQLLimits(introspection: DVGraphQLIntrospection.never);
      expect(await refused(schemaQuery), isTrue);
      expect(await refused('{ __type(name: "User") { name } }'), isTrue);
      expect(await refused('query { ...I } fragment I on Query { __schema '
          '{ types { name } } }'), isTrue);
      final typename = await DVGraphQL.execute('{ __typename }');
      expect((typename['data']! as Map)['__typename'], 'Query');
    });

    test('development answers only outside production', () async {
      DVGraphQL.limits = const DVGraphQLLimits(production: false);
      expect(await refused(schemaQuery), isFalse);
      DVGraphQL.limits = const DVGraphQLLimits(production: true);
      expect(await refused(schemaQuery), isTrue);
    });

    test('authenticated answers only an authenticated request', () async {
      DVGraphQL.limits = const DVGraphQLLimits(
        introspection: DVGraphQLIntrospection.authenticated,
        production: true,
      );
      expect(await refused(schemaQuery), isTrue);
      expect(await refused(schemaQuery, authenticated: true), isFalse);
    });
  });
}
