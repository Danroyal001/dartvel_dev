// A GraphQL request body, read the way the generated /graphql route reads it.
//
// The route took query, variables and operationName from the body and passed
// no persisted-query hash. So a client following the persisted-query
// convention -- extensions.persistedQuery.sha256Hash, with or without the
// document -- was answered as if it had sent an empty document, and under
// prefer a hash sent beside a different document was never compared with it.
//
// The silent failures:
//  * a hash sent alone answered with a parse error instead of its document;
//  * a known hash carrying a different document past the allow-list;
//  * the configured mode replacing a manifest the application had loaded.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  const String allowed = '{ users { name } }';
  late int resolved;

  String hashOf(String document) =>
      sha256.convert(utf8.encode(document)).toString();

  Map<String, Object?> persisted(String hash, [String? query]) =>
      <String, Object?>{
        if (query != null) 'query': query,
        'extensions': <String, Object?>{
          'persistedQuery': <String, Object?>{
            'version': 1,
            'sha256Hash': hash,
          },
        },
      };

  String? codeOf(Map<String, Object?> result) {
    final List<Object?>? errors = result['errors'] as List<Object?>?;
    if (errors == null) return null;
    final Map<Object?, Object?>? extensions =
        (errors.single! as Map<Object?, Object?>)['extensions']
            as Map<Object?, Object?>?;
    return extensions?['code'] as String?;
  }

  setUp(() {
    resolved = 0;
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('User', const <DVGraphQLField>[
      DVGraphQLField('name', 'String!'),
    ]));
    DVGraphQL.registerQuery(DVGraphQLField('users', '[User!]!',
        resolve: (Map<String, Object?> args, Object? parent) {
      resolved++;
      return <Object?>[
        <String, Object?>{'name': 'Ada'},
      ];
    }));
    DVGraphQL.persistedQueries = DVPersistedQueries(
      mode: DVPersistedQueryMode.require,
      documents: const <String>[allowed],
    );
  });

  tearDown(DVGraphQL.reset);

  test('a hash sent alone runs the document it names', () async {
    final Map<String, Object?> result =
        await DVGraphQL.executeRequest(persisted(hashOf(allowed)));

    expect(result['data'], <String, Object?>{
      'users': <Object?>[
        <String, Object?>{'name': 'Ada'},
      ],
    });
  });

  test('a known hash sent with another document is refused', () async {
    final Map<String, Object?> result = await DVGraphQL.executeRequest(
        persisted(hashOf(allowed), '{ users { name name } }'));

    expect(resolved, 0);
    expect(codeOf(result), 'DV-EDGE-002');
  });

  test('an unknown document under require is refused before it runs',
      () async {
    final Map<String, Object?> result = await DVGraphQL.executeRequest(
        <String, Object?>{'query': '{ users { name name } }'});

    expect(resolved, 0);
    expect(codeOf(result), 'DV-EDGE-002');
  });

  test('a subscription reads the hash from the same place', () async {
    const String subscription = 'subscription { userAdded }';
    DVGraphQL.registerSubscription(DVGraphQLField('userAdded', 'String!',
        resolve: (Map<String, Object?> args, Object? parent) =>
            Stream<String>.value('ada')));
    DVGraphQL.persistedQueries = DVPersistedQueries(
      mode: DVPersistedQueryMode.require,
      documents: const <String>[subscription],
    );

    final List<Map<String, Object?>> events =
        await DVGraphQL.subscribeRequest(persisted(hashOf(subscription)))
            .toList();

    expect(events.single['data'], <String, Object?>{'userAdded': 'ada'});
  });

  test('a body that is not an object is an empty request, not a crash',
      () async {
    final Map<String, Object?> result =
        await DVGraphQL.executeRequest(<Object?>['query']);

    expect(resolved, 0);
    expect(codeOf(result), 'DV-EDGE-002');
  });

  test('the configured mode keeps the manifest the application loaded', () {
    final DVPersistedQueries prefer =
        DVGraphQL.persistedQueries.withMode(DVPersistedQueryMode.prefer);

    expect(prefer.mode, DVPersistedQueryMode.prefer);
    expect(prefer.documentFor(hashOf(allowed)), allowed);
  });
}
