import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Product {
  final String id;
  final String title;

  const Product(this.id, this.title);
}

class ProductFacets {
  final List<String>? category;
  const ProductFacets({this.category});
}

class _Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final DVHttpResponse response;

  _Recorder(this.response);

  factory _Recorder.json(Object? payload, {int statusCode = 200}) =>
      _Recorder(DVHttpResponse(
        statusCode: statusCode,
        body: jsonEncode(payload),
      ));

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return response;
  }

  DVHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }

  Map<String, Object?> get json =>
      jsonDecode(utf8.decode(single.body)) as Map<String, Object?>;
}

Product productFrom(Map<String, Object?> hit) =>
    Product(hit['id']! as String, hit['title']! as String);

List<String> categoryFilter(ProductFacets? facets) => <String>[
      if (facets?.category case final categories?)
        for (final category in categories) 'category = "$category"',
    ];

void main() {
  group('MeilisearchProvider', () {
    test('posts the search payload and reads hits', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <Object?>[
          <String, Object?>{'id': '1', 'title': 'Keyboard'},
          <String, Object?>{'id': '2', 'title': 'Mouse'},
        ],
        'totalHits': 7,
      });

      final results = await MeilisearchProvider<Product, ProductFacets>(
        baseUrl: Uri.https('search.example.com'),
        apiKey: 'ms_key',
        indexName: 'products',
        fromJson: productFrom,
        transport: recorder.send,
      ).query('key', page: 2, perPage: 2);

      expect(
        recorder.single.url.toString(),
        'https://search.example.com/indexes/products/search',
      );
      expect(recorder.single.headers['authorization'], 'Bearer ms_key');
      expect(recorder.json['q'], 'key');
      expect(recorder.json['page'], 2, reason: 'Meilisearch pages are 1-based');
      expect(recorder.json['hitsPerPage'], 2);
      expect(recorder.json.containsKey('filter'), isFalse);

      expect(results.items.map((product) => product.title),
          <String>['Keyboard', 'Mouse']);
      expect(results.total, 7);
      expect(results.page, 2);
      expect(results.perPage, 2);
    });

    test('sends facet filters when there are any', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <Object?>[],
        'totalHits': 0,
      });

      await MeilisearchProvider<Product, ProductFacets>(
        baseUrl: Uri.https('search.example.com'),
        apiKey: 'ms_key',
        indexName: 'products',
        fromJson: productFrom,
        facetFilter: categoryFilter,
        transport: recorder.send,
      ).query('x', facets: const ProductFacets(category: <String>['audio']));

      expect(recorder.json['filter'], <String>['category = "audio"']);
    });
  });

  group('AlgoliaSearchProvider', () {
    test('translates paging between Dartvel and Algolia', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <Object?>[
          <String, Object?>{'id': '9', 'title': 'Monitor'},
        ],
        'nbHits': 30,
        'page': 2,
      });

      final results = await AlgoliaSearchProvider<Product, ProductFacets>(
        applicationId: 'APPID',
        apiKey: 'algolia_key',
        indexName: 'products',
        fromJson: productFrom,
        transport: recorder.send,
      ).query('monitor', page: 3, perPage: 10);

      // Uri normalises the host to lower case, which DNS treats as identical.
      expect(
        recorder.single.url.toString(),
        'https://appid-dsn.algolia.net/1/indexes/products/query',
      );
      expect(recorder.single.headers['x-algolia-api-key'], 'algolia_key');
      expect(recorder.single.headers['x-algolia-application-id'], 'APPID');

      expect(recorder.json['page'], 2,
          reason: 'Dartvel page 3 is Algolia page 2');
      expect(results.page, 3,
          reason: 'Algolia page 2 is reported back as Dartvel page 3');
      expect(results.total, 30);
      expect(results.items.single.title, 'Monitor');
    });

    test('joins facet filters with AND', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <Object?>[],
        'nbHits': 0,
        'page': 0,
      });

      await AlgoliaSearchProvider<Product, ProductFacets>(
        applicationId: 'APPID',
        apiKey: 'k',
        indexName: 'products',
        fromJson: productFrom,
        facetFilter: categoryFilter,
        transport: recorder.send,
      ).query(
        'x',
        facets: const ProductFacets(category: <String>['audio', 'video']),
      );

      expect(
        recorder.json['filters'],
        'category = "audio" AND category = "video"',
      );
    });

    test('honours a self-hosted base url', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <Object?>[],
        'nbHits': 0,
        'page': 0,
      });

      await AlgoliaSearchProvider<Product, ProductFacets>(
        applicationId: 'APPID',
        apiKey: 'k',
        indexName: 'products',
        fromJson: productFrom,
        baseUrl: Uri.https('search.internal'),
        transport: recorder.send,
      ).query('x');

      expect(
        recorder.single.url.toString(),
        'https://search.internal/1/indexes/products/query',
      );
    });
  });

  group('OpenSearchProvider', () {
    OpenSearchProvider<Product, ProductFacets> provider(
      _Recorder recorder, {
      String? username,
      String? password,
      String apiKey = '',
    }) =>
        OpenSearchProvider<Product, ProductFacets>(
          baseUrl: Uri.https('search.example.com'),
          indexName: 'products',
          fromJson: productFrom,
          username: username,
          password: password,
          apiKey: apiKey,
          facetFilter: categoryFilter,
          transport: recorder.send,
        );

    test('reads models out of the nested hits envelope', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{
          'total': <String, Object?>{'value': 42, 'relation': 'eq'},
          'hits': <Object?>[
            <String, Object?>{
              '_id': 'a',
              '_source': <String, Object?>{'id': '1', 'title': 'Keyboard'},
            },
            <String, Object?>{
              '_id': 'b',
              '_source': <String, Object?>{'id': '2', 'title': 'Mouse'},
            },
          ],
        },
      });

      final results = await provider(recorder).query('key', perPage: 10);

      expect(
        recorder.single.url.toString(),
        'https://search.example.com/products/_search',
      );
      expect(results.items.map((product) => product.title),
          <String>['Keyboard', 'Mouse']);
      expect(results.total, 42);
    });

    test('translates a page number into a from/size offset', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });

      final results = await provider(recorder).query('x', page: 4, perPage: 25);

      expect(recorder.json['from'], 75, reason: 'page 4 of 25 starts at 75');
      expect(recorder.json['size'], 25);
      expect(results.page, 4, reason: 'the caller still sees a page number');
    });

    test('reads a bare integer total from older clusters', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 7, 'hits': <Object?>[]},
      });

      expect((await provider(recorder).query('x')).total, 7);
    });

    test('matches everything when the query is blank', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });
      await provider(recorder).query('   ');

      final must = ((recorder.json['query']! as Map<String, Object?>)['bool']!
          as Map<String, Object?>)['must']! as List<Object?>;
      expect((must.single as Map<String, Object?>).containsKey('match_all'),
          isTrue);
    });

    test('sends facets as bool filters', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });
      await provider(recorder).query(
        'x',
        facets: const ProductFacets(category: <String>['audio']),
      );

      final bool_ = (recorder.json['query']! as Map<String, Object?>)['bool']!
          as Map<String, Object?>;
      expect(bool_['filter'], hasLength(1));
    });

    test('authenticates with basic auth when credentials are given', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });
      await provider(recorder, username: 'ada', password: 'secret').query('x');

      expect(
        recorder.single.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('ada:secret'))}',
      );
    });

    test('uses an ApiKey header when only a key is given', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });
      await provider(recorder, apiKey: 'abc123').query('x');

      expect(recorder.single.headers['authorization'], 'ApiKey abc123');
    });

    test('sends no authorization header for an open cluster', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{'total': 0, 'hits': <Object?>[]},
      });
      await provider(recorder).query('x');

      expect(recorder.single.headers.containsKey('authorization'), isFalse);
    });

    test('rejects a malformed hits envelope', () async {
      final recorder = _Recorder.json(<String, Object?>{'hits': <Object?>[]});

      await expectLater(
        provider(recorder).query('x'),
        throwsA(
          isA<DVSearchProviderException>().having(
            (error) => error.message,
            'message',
            contains('"hits" was not a JSON object'),
          ),
        ),
      );
    });

    test('skips a hit with no _source rather than crashing', () async {
      final recorder = _Recorder.json(<String, Object?>{
        'hits': <String, Object?>{
          'total': 2,
          'hits': <Object?>[
            <String, Object?>{'_id': 'a'},
            <String, Object?>{
              '_id': 'b',
              '_source': <String, Object?>{'id': '2', 'title': 'Mouse'},
            },
          ],
        },
      });

      final results = await provider(recorder).query('x');
      expect(results.items, hasLength(1));
      expect(results.items.single.title, 'Mouse');
    });
  });

  group('shared hosted-search behaviour', () {
    DVHttpSearchProvider<Product, ProductFacets> provider(_Recorder recorder) =>
        MeilisearchProvider<Product, ProductFacets>(
          baseUrl: Uri.https('search.example.com'),
          apiKey: 'k',
          indexName: 'products',
          fromJson: productFrom,
          transport: recorder.send,
        );

    test('a rejected query throws rather than returning an empty page',
        () async {
      final recorder = _Recorder(
        const DVHttpResponse(statusCode: 403, body: '{"message":"forbidden"}'),
      );

      await expectLater(
        provider(recorder).query('x'),
        throwsA(
          isA<DVSearchProviderException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.provider, 'provider', 'meilisearch')
              .having((error) => error.responseBody, 'responseBody',
                  contains('forbidden')),
        ),
      );
    });

    test('a non-JSON response throws', () async {
      final recorder = _Recorder(
        const DVHttpResponse(statusCode: 200, body: '<html>oops</html>'),
      );

      await expectLater(
        provider(recorder).query('x'),
        throwsA(isA<DVSearchProviderException>()),
      );
    });

    test('a response missing hits throws', () async {
      final recorder = _Recorder.json(<String, Object?>{'totalHits': 3});

      await expectLater(
        provider(recorder).query('x'),
        throwsA(
          isA<DVSearchProviderException>().having(
            (error) => error.message,
            'message',
            contains('"hits" was not a JSON array'),
          ),
        ),
      );
    });

    test('rejects non-positive paging arguments before any request', () async {
      final recorder = _Recorder.json(<String, Object?>{'hits': <Object?>[]});

      await expectLater(
        provider(recorder).query('x', page: 0),
        throwsArgumentError,
      );
      await expectLater(
        provider(recorder).query('x', perPage: 0),
        throwsArgumentError,
      );
      expect(recorder.requests, isEmpty);
    });

    test('both providers satisfy DVSearchProvider', () {
      final recorder = _Recorder.json(<String, Object?>{'hits': <Object?>[]});
      expect(
        provider(recorder),
        isA<DVSearchProvider<Product, ProductFacets>>(),
      );
      expect(
        AlgoliaSearchProvider<Product, ProductFacets>(
          applicationId: 'a',
          apiKey: 'k',
          indexName: 'i',
          fromJson: productFrom,
        ),
        isA<DVSearchProvider<Product, ProductFacets>>(),
      );
    });
  });
}
