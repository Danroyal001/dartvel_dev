// MeilisearchProvider against a real Meilisearch.
//
// The provider has existed for a while and had never been run against the
// engine. Two of its behaviours can only be checked here: Meilisearch returns
// neither highlights nor facet counts unless the query asks for them, so a
// provider that only reads the response finds nothing and reports nothing --
// an empty facet map that looks like "no matches" rather than "never asked".
//
// Indexing is the model-sync layer's job, so these tests put documents in over
// plain HTTP and exercise only the query path.
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Person {
  const Person({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  static Person fromJson(Map<String, Object?> d) => Person(
        id: '${d['id']}',
        name: '${d['name']}',
        role: '${d['role']}',
      );

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'name': name, 'role': role};
}

class Facets {
  const Facets({this.role});
  final List<String>? role;
}

const List<Person> people = <Person>[
  Person(id: '1', name: 'Ada Lovelace', role: 'admin'),
  Person(id: '2', name: 'Grace Hopper', role: 'admin'),
  Person(id: '3', name: 'Alan Turing', role: 'engineer'),
];

late Uri base;
late String indexName;

/// Talks to the engine directly, for the setup the provider does not do.
Future<Map<String, Object?>> engine(
  String method,
  String path, {
  Object? body,
}) async {
  final io.HttpClient client = io.HttpClient();
  final io.HttpClientRequest request =
      await client.openUrl(method, base.replace(path: path));
  request.headers.set('content-type', 'application/json');
  if (body != null) request.add(utf8.encode(jsonEncode(body)));
  final io.HttpClientResponse response = await request.close();
  final String text = await response.transform(utf8.decoder).join();
  client.close();
  if (text.isEmpty) return const <String, Object?>{};
  final Object? decoded = jsonDecode(text);
  return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
}

/// Meilisearch indexes asynchronously; returning before the task finishes
/// makes the next query miss documents it already accepted.
Future<void> awaitTask(Object? uid) async {
  if (uid == null) return;
  for (int attempt = 0; attempt < 200; attempt += 1) {
    final Map<String, Object?> status = await engine('GET', '/tasks/$uid');
    if (status['status'] == 'succeeded') return;
    if (status['status'] == 'failed') {
      fail('indexing task $uid failed: ${jsonEncode(status)}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('indexing task $uid never finished');
}

void main() {
  final String? endpoint = io.Platform.environment['DARTVEL_MEILISEARCH'];
  if (endpoint == null || endpoint.isEmpty) {
    test('skipped: DARTVEL_MEILISEARCH is not set', () {}, skip: true);
    return;
  }

  base = Uri.parse(endpoint);
  indexName = 'people${DateTime.now().millisecondsSinceEpoch}';

  late MeilisearchProvider<Person, Facets> search;

  setUpAll(() async {
    // `role` has to be declared filterable, or facet counts come back empty
    // and a filter on it is rejected.
    final Map<String, Object?> settings = await engine(
      'PATCH',
      '/indexes/$indexName/settings',
      body: <String, Object?>{
        'filterableAttributes': <String>['role'],
      },
    );
    await awaitTask(settings['taskUid']);

    final Map<String, Object?> added = await engine(
      'POST',
      '/indexes/$indexName/documents',
      body: people.map((Person p) => p.toJson()).toList(),
    );
    await awaitTask(added['taskUid']);

    search = MeilisearchProvider<Person, Facets>(
      baseUrl: base,
      apiKey: io.Platform.environment['DARTVEL_MEILISEARCH_KEY'] ?? '',
      indexName: indexName,
      fromJson: Person.fromJson,
      facetFields: const <String>['role'],
      facetFilter: (Facets? f) => f?.role == null
          ? const <String>[]
          : <String>[f!.role!.map((String r) => 'role = "$r"').join(' OR ')],
    );
  });

  test('a query finds the record and hydrates it into a model', () async {
    final DVSearchResultPage<Person> page = await search.query('lovelace');

    expect(page.items.single, isA<Person>());
    expect(page.items.single.name, 'Ada Lovelace');
    expect(page.total, greaterThan(0));
  });

  test('the engine tolerates a typo without being asked twice', () async {
    // Typo tolerance is the engine's, not post-processing. Re-checking here
    // could only ever remove a match the engine already made.
    final DVSearchResultPage<Person> page = await search.query('lovelice');

    expect(page.items.map((Person p) => p.name), contains('Ada Lovelace'));
  });

  test('highlights come back, because the query asked for them', () async {
    final DVSearchResultPage<Person> page = await search.query('lovelace');

    expect(page.highlights, isNotEmpty);
    expect(page.highlights.first, contains('<mark>'));
  });

  test('facet counts come back for a filterable field', () async {
    final DVSearchResultPage<Person> page = await search.query('');

    expect(page.facetCounts['role'], <String, int>{'admin': 2, 'engineer': 1});
  });

  test('a facet filter narrows the result', () async {
    final DVSearchResultPage<Person> page = await search.query(
      '',
      facets: const Facets(role: <String>['engineer']),
    );

    expect(page.items.map((Person p) => p.name), <String>['Alan Turing']);
  });

  test('paging returns disjoint pages', () async {
    // Off by one is the classic paging bug here: the second page silently
    // repeats or skips, and nothing surfaces but a missing record.
    final DVSearchResultPage<Person> first =
        await search.query('', page: 1, perPage: 2);
    final DVSearchResultPage<Person> second =
        await search.query('', page: 2, perPage: 2);

    expect(first.items.length, 2);
    expect(second.items.length, 1);
    final Set<String> firstIds = first.items.map((Person p) => p.id).toSet();
    expect(firstIds.contains(second.items.single.id), isFalse);
  });

  test('total counts every match, not the page', () async {
    final DVSearchResultPage<Person> page =
        await search.query('', page: 1, perPage: 2);

    expect(page.items.length, 2);
    expect(page.total, 3);
  });
}
