// OpenSearchProvider against a real OpenSearch.
//
// The provider has existed for a while and had never been run against the
// engine. What only a real one can settle: an aggregation must name a keyword
// field, because pointed at an analysed text field it counts word fragments
// and returns plausible numbers for values nobody ever stored.
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

Future<String> engine(
  String method,
  String path, {
  Object? body,
  String contentType = 'application/json',
}) async {
  final io.HttpClient client = io.HttpClient();
  final io.HttpClientRequest request =
      await client.openUrl(method, base.replace(path: path));
  request.headers.set('content-type', contentType);
  if (body != null) {
    request.add(utf8.encode(body is String ? body : jsonEncode(body)));
  }
  final io.HttpClientResponse response = await request.close();
  final String text = await response.transform(utf8.decoder).join();
  client.close();
  if (response.statusCode >= 300) {
    fail('$method $path -> ${response.statusCode}: $text');
  }
  return text;
}

void main() {
  final String? endpoint = io.Platform.environment['DARTVEL_OPENSEARCH'];
  if (endpoint == null || endpoint.isEmpty) {
    test('skipped: DARTVEL_OPENSEARCH is not set', () {}, skip: true);
    return;
  }

  base = Uri.parse(endpoint);
  indexName = 'people${DateTime.now().millisecondsSinceEpoch}';

  late OpenSearchProvider<Person, Facets> search;

  setUpAll(() async {
    // An explicit mapping: `role` gets a keyword sub-field so the aggregation
    // counts values rather than analysed tokens.
    await engine('PUT', '/$indexName', body: <String, Object?>{
      'mappings': <String, Object?>{
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'keyword'},
          'name': <String, Object?>{'type': 'text'},
          'role': <String, Object?>{
            'type': 'text',
            'fields': <String, Object?>{
              'keyword': <String, Object?>{'type': 'keyword'},
            },
          },
        },
      },
    });

    // The bulk API takes newline-delimited JSON under its own media type and
    // rejects application/json outright.
    final StringBuffer ndjson = StringBuffer();
    for (final Person p in people) {
      ndjson
        ..writeln(jsonEncode(<String, Object?>{
          'index': <String, Object?>{'_index': indexName, '_id': p.id},
        }))
        ..writeln(jsonEncode(p.toJson()));
    }
    await engine('POST', '/_bulk',
        body: ndjson.toString(),
        contentType: 'application/x-ndjson');
    await engine('POST', '/$indexName/_refresh');

    search = OpenSearchProvider<Person, Facets>(
      baseUrl: base,
      indexName: indexName,
      fromJson: Person.fromJson,
      searchFields: const <String>['name', 'role'],
      facetFields: const <String>['role.keyword'],
      facetFilter: (Facets? f) => f?.role == null
          ? const <String>[]
          : <String>[
              f!.role!.map((String r) => 'role.keyword:"$r"').join(' OR ')
            ],
    );
  });

  test('a query finds the record and hydrates it from _source', () async {
    final DVSearchResultPage<Person> page = await search.query('lovelace');

    expect(page.items.single, isA<Person>());
    expect(page.items.single.name, 'Ada Lovelace');
  });

  test('an empty query matches everything rather than nothing', () async {
    // A multi_match with an empty string matches nothing, so an unfiltered
    // listing would come back empty; match_all is what the provider sends.
    final DVSearchResultPage<Person> page = await search.query('');

    expect(page.total, 3);
  });

  test('total is read from the object form 7.x returns', () async {
    // `hits.total` became an object in Elasticsearch 7. Reading it as a bare
    // int throws; reading `.value` works on both.
    final DVSearchResultPage<Person> page = await search.query('');

    expect(page.total, isA<int>());
    expect(page.total, 3);
  });

  test('highlights come back for the matched field', () async {
    final DVSearchResultPage<Person> page = await search.query('lovelace');

    expect(page.highlights.first, contains('<mark>'));
  });

  test('facet counts are values, not analysed fragments', () async {
    // The whole reason the mapping above exists. Aggregated over the text
    // field this returns counts for "admin" and "engineer" as tokens of
    // something else, which look like answers.
    final DVSearchResultPage<Person> page = await search.query('');

    expect(page.facetCounts['role.keyword'],
        <String, int>{'admin': 2, 'engineer': 1});
  });

  test('a facet filter narrows the result', () async {
    final DVSearchResultPage<Person> page = await search.query(
      '',
      facets: const Facets(role: <String>['engineer']),
    );

    expect(page.items.map((Person p) => p.name), <String>['Alan Turing']);
  });

  test('paging is translated from pages to an offset', () async {
    final DVSearchResultPage<Person> first =
        await search.query('', page: 1, perPage: 2);
    final DVSearchResultPage<Person> second =
        await search.query('', page: 2, perPage: 2);

    expect(first.items.length, 2);
    expect(second.items.length, 1);
    final Set<String> firstIds = first.items.map((Person p) => p.id).toSet();
    expect(firstIds.contains(second.items.single.id), isFalse);
  });
}
