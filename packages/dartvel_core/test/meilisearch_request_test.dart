// Meilisearch's request shape, for the parts a live run cannot reach.
//
// The header is one of them. A Meilisearch with no master key configured --
// the ordinary local and CI setup -- rejects `Authorization: Bearer ` with
// "The provided API key is invalid", so sending an empty key is worse than
// sending no header at all. That failed every live assertion at once and read
// as a broken adapter rather than a broken header.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Person {
  const Person(this.name);
  final String name;
  static Person fromJson(Map<String, Object?> d) => Person('${d['name']}');
}

class Facets {
  const Facets();
}

MeilisearchProvider<Person, Facets> providerWith(String apiKey) =>
    MeilisearchProvider<Person, Facets>(
      baseUrl: Uri.parse('http://localhost:7700'),
      apiKey: apiKey,
      indexName: 'people',
      fromJson: Person.fromJson,
      facetFields: const <String>['role'],
    );

Map<String, Object?> bodyOf(MeilisearchProvider<Person, Facets> provider) =>
    jsonDecode(utf8.decode(
      provider.buildRequest('ada', const <String>[], 1, 20).body,
    )) as Map<String, Object?>;

void main() {
  test('an empty key sends no authorization header', () {
    final request =
        providerWith('').buildRequest('ada', const <String>[], 1, 20);

    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('a real key is sent as a bearer token', () {
    final request =
        providerWith('master-key').buildRequest('ada', const <String>[], 1, 20);

    expect(request.headers['authorization'], 'Bearer master-key');
  });

  test('highlights are asked for, or the engine returns none', () {
    final Map<String, Object?> body = bodyOf(providerWith('k'));

    expect(body['attributesToHighlight'], <String>['*']);
    expect(body['highlightPreTag'], '<mark>');
    expect(body['highlightPostTag'], '</mark>');
  });

  test('declared facets are asked for, or counts come back empty', () {
    final Map<String, Object?> body = bodyOf(providerWith('k'));

    expect(body['facets'], <String>['role']);
  });

  test('no declared facets means the key is absent, not an empty list', () {
    final MeilisearchProvider<Person, Facets> plain =
        MeilisearchProvider<Person, Facets>(
      baseUrl: Uri.parse('http://localhost:7700'),
      apiKey: 'k',
      indexName: 'people',
      fromJson: Person.fromJson,
    );

    expect(bodyOf(plain).containsKey('facets'), isFalse);
  });
}
