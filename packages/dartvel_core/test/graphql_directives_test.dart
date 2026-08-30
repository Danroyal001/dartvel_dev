// @skip and @include: the two directives the GraphQL specification requires
// every server to support.
//
// A client that sends them to a server which ignores them gets a response that
// parses and is wrong -- fields it asked to omit are present, fields it asked
// for conditionally are missing -- so ignoring them silently is worse than
// refusing them.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> dataOf(Map<String, Object?> result) =>
    result['data']! as Map<String, Object?>;

void main() {
  setUp(() {
    DVGraphQL.reset();
    DVGraphQL.registerQuery(
      DVGraphQLField('name', 'String!', resolve: (_, __) => 'Ada'),
    );
    DVGraphQL.registerQuery(
      DVGraphQLField('role', 'String!', resolve: (_, __) => 'admin'),
    );
  });

  group('@skip', () {
    test('a literal true omits the field', () async {
      final Map<String, Object?> result =
          await DVGraphQL.execute('{ name role @skip(if: true) }');

      expect(result['errors'], isNull);
      expect(dataOf(result).containsKey('role'), isFalse);
      expect(dataOf(result)['name'], 'Ada');
    });

    test('a literal false keeps it', () async {
      final Map<String, Object?> result =
          await DVGraphQL.execute('{ role @skip(if: false) }');

      expect(dataOf(result)['role'], 'admin');
    });

    test('a variable decides at execution time', () async {
      final Map<String, Object?> skipped = await DVGraphQL.execute(
        r'query Q($s: Boolean!) { role @skip(if: $s) }',
        variables: <String, Object?>{'s': true},
      );
      final Map<String, Object?> kept = await DVGraphQL.execute(
        r'query Q($s: Boolean!) { role @skip(if: $s) }',
        variables: <String, Object?>{'s': false},
      );

      expect(dataOf(skipped).containsKey('role'), isFalse);
      expect(dataOf(kept)['role'], 'admin');
    });
  });

  group('@include', () {
    test('it is the inverse of skip', () async {
      final Map<String, Object?> omitted =
          await DVGraphQL.execute('{ role @include(if: false) }');
      final Map<String, Object?> kept =
          await DVGraphQL.execute('{ role @include(if: true) }');

      expect(dataOf(omitted).containsKey('role'), isFalse);
      expect(dataOf(kept)['role'], 'admin');
    });

    test('skip wins when both exclude', () async {
      final Map<String, Object?> result = await DVGraphQL.execute(
        '{ role @skip(if: true) @include(if: true) }',
      );

      expect(dataOf(result).containsKey('role'), isFalse);
    });
  });

  group('fragments', () {
    test('a directive on a fragment spread governs the whole spread', () async {
      final Map<String, Object?> result = await DVGraphQL.execute(
        '{ name ...F @skip(if: true) } fragment F on Query { role }',
      );

      expect(result['errors'], isNull);
      expect(dataOf(result).containsKey('role'), isFalse);
      expect(dataOf(result)['name'], 'Ada');
    });

    test('a directive on an inline fragment governs its selections', () async {
      final Map<String, Object?> result = await DVGraphQL.execute(
        '{ name ... on Query @skip(if: true) { role } }',
      );

      expect(result['errors'], isNull);
      expect(dataOf(result).containsKey('role'), isFalse);
    });
  });

  group('errors', () {
    test('an unknown directive is refused, not ignored', () async {
      // Ignoring it would answer a question the client did not ask.
      final Map<String, Object?> result =
          await DVGraphQL.execute('{ role @deprecated(reason: "x") }');

      expect(result['errors'], isNotNull);
    });

    test('a missing if argument is refused', () async {
      final Map<String, Object?> result =
          await DVGraphQL.execute('{ role @skip }');

      expect(result['errors'], isNotNull);
    });

    test('a non-boolean if is refused rather than coerced', () async {
      // Treating "false" or 0 as truthy is how a field silently disappears.
      final Map<String, Object?> result =
          await DVGraphQL.execute('{ role @skip(if: "true") }');

      expect(result['errors'], isNotNull);
    });
  });

  test('introspection reports the directives the server supports', () async {
    // A client that reads the schema to decide what it may send must not be
    // told the server has none.
    final Map<String, Object?> result = await DVGraphQL.execute(
      '{ __schema { directives { name args { name } } } }',
    );

    final List<Object?> directives =
        ((dataOf(result)['__schema']! as Map<String, Object?>)['directives']!
            as List<Object?>);
    expect(
      directives.map((Object? d) => (d! as Map<String, Object?>)['name']),
      containsAll(<String>['skip', 'include']),
    );
  });
}
