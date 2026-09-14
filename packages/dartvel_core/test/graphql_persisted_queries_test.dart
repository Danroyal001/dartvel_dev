import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  const allowed = '{ users { name } }';
  const adHoc = '{ users { slug name } }';
  late int resolved;

  String hashOf(String document) =>
      sha256.convert(utf8.encode(document)).toString();

  setUp(() {
    resolved = 0;
    DVGraphQL.reset();
    DVGraphQL.registerType(DVGraphQLObjectType('User', const <DVGraphQLField>[
      DVGraphQLField('slug', 'String!'),
      DVGraphQLField('name', 'String!'),
    ]));
    DVGraphQL.registerQuery(DVGraphQLField(
      'users',
      '[User!]!',
      resolve: (args, parent) {
        resolved++;
        return <Object?>[
          <String, Object?>{'slug': 'ada', 'name': 'Ada'},
        ];
      },
    ));
  });

  tearDown(DVGraphQL.reset);

  String? codeOf(Map<String, Object?> result) {
    final errors = result['errors'] as List<Object?>?;
    if (errors == null) return null;
    final extensions = (errors.single! as Map)['extensions'] as Map?;
    return extensions?['code'] as String?;
  }

  DVPersistedQueries manifest(DVPersistedQueryMode mode) =>
      DVPersistedQueries(mode: mode, documents: const <String>[allowed]);

  test('the manifest is keyed by the sha256 of the exact document text', () {
    final queries = manifest(DVPersistedQueryMode.require);
    expect(queries.documentFor(hashOf(allowed)), allowed);
    expect(queries.documentFor(hashOf(allowed).toUpperCase()), allowed);
    expect(queries.documentFor(hashOf('{users{name}}')), isNull);
  });

  test('a shipped manifest whose hash is not its document is rejected', () {
    expect(
      DVPersistedQueries.fromManifest(<String, String>{hashOf(allowed): allowed})
          .documentFor(hashOf(allowed)),
      allowed,
    );
    expect(
      () => DVPersistedQueries.fromManifest(
        <String, String>{hashOf(allowed): adHoc},
      ),
      throwsArgumentError,
      reason: 'otherwise any document runs under a hash the endpoint trusts',
    );
  });

  test('persisted queries are off until configured', () async {
    expect(DVGraphQL.persistedQueries.mode, DVPersistedQueryMode.off);
    expect((await DVGraphQL.execute(adHoc))['errors'], isNull);
  });

  group('require', () {
    setUp(() {
      DVGraphQL.persistedQueries = manifest(DVPersistedQueryMode.require);
    });

    test('refuses a document that is not in the manifest', () async {
      final result = await DVGraphQL.execute(adHoc);
      expect(codeOf(result), 'DV-EDGE-002');
      expect(result.containsKey('data'), isFalse);
      expect(resolved, 0);
    });

    test('refuses an unknown hash', () async {
      final result = await DVGraphQL.execute('',
          persistedQueryHash: hashOf(adHoc));
      expect(codeOf(result), 'DV-EDGE-002');
      expect(resolved, 0);
    });

    test('runs a manifest document sent by its hash alone', () async {
      final result = await DVGraphQL.execute('',
          persistedQueryHash: hashOf(allowed));
      expect(result['errors'], isNull);
      expect((result['data']! as Map)['users'], hasLength(1));
    });

    test('runs a manifest document sent in full', () async {
      final result = await DVGraphQL.execute(allowed);
      expect(result['errors'], isNull);
    });

    test('refuses a subscription that is not in the manifest', () async {
      DVGraphQL.registerSubscription(DVGraphQLField(
        'arrivals',
        'User!',
        resolve: (a, p) => Stream<Object?>.value(<String, Object?>{}),
      ));
      final events = await DVGraphQL.subscribe(
        'subscription { arrivals { name } }',
      ).toList();
      expect(codeOf(events.single), 'DV-EDGE-002');
    });
  });

  for (final mode in <DVPersistedQueryMode>[
    DVPersistedQueryMode.require,
    DVPersistedQueryMode.prefer,
  ]) {
    test('${mode.name}: a known hash sent with a different document is '
        'refused, not run', () async {
      DVGraphQL.persistedQueries = manifest(mode);
      final result = await DVGraphQL.execute(adHoc,
          persistedQueryHash: hashOf(allowed));
      expect(codeOf(result), 'DV-EDGE-002');
      expect(resolved, 0);
    });
  }

  group('prefer', () {
    setUp(() {
      DVGraphQL.persistedQueries = manifest(DVPersistedQueryMode.prefer);
    });

    test('runs an ad-hoc document', () async {
      expect((await DVGraphQL.execute(adHoc))['errors'], isNull);
    });

    test('answers an unknown hash with no document so the client resends',
        () async {
      final result = await DVGraphQL.execute('',
          persistedQueryHash: hashOf(adHoc));
      expect(result.containsKey('data'), isFalse);
      final error = (result['errors']! as List).single! as Map;
      expect(error['message'], 'PersistedQueryNotFound');
      expect(resolved, 0);
    });

    test('still prices an ad-hoc document', () async {
      DVGraphQL.limits = const DVGraphQLLimits(maxCost: 5);
      expect(codeOf(await DVGraphQL.execute(adHoc)), 'DV-EDGE-001');
    });
  });

  test('off ignores the manifest', () async {
    DVGraphQL.persistedQueries = manifest(DVPersistedQueryMode.off);
    expect((await DVGraphQL.execute(adHoc))['errors'], isNull);
  });
}
