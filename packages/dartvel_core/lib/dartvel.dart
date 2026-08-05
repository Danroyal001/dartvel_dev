library dartvel_core;

import 'dart:async';
import 'dart:convert';
// import 'dart:io'; // Removed to avoid breaking web builds
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'src/ai/ai.dart';
import 'src/database/adapter.dart';
import 'src/http/aws_sigv4.dart';
import 'src/http/transport.dart';
import 'src/mail/smtp.dart';

// Re-export common types so backends can import only dartvel_core.
export 'package:dartvel_shelf/dartvel_shelf.dart'
    show Request, Response, Headers;

export 'src/ai/ai.dart';
export 'src/analytics/analytics.dart';
export 'src/annotations/annotations.dart';
export 'src/auth/auth.dart';
export 'src/auth/oauth2.dart';
export 'src/auth/password.dart';
export 'src/cache/adapters.dart';
export 'src/database/adapters.dart';
export 'src/http/aws_sigv4.dart';
export 'src/http/transport.dart';
export 'src/lifecycle/lifecycle.dart';
export 'src/mail/smtp.dart';
export 'src/media/image.dart';
export 'src/modules/modules.dart';
export 'src/platform_config.dart';
export 'src/secrets/secrets.dart';
export 'src/shell/shell.dart';
export 'src/storage/adapters.dart';
export 'src/sync/model_sync.dart';
export 'src/tenancy/tenants.dart';
export 'src/transaction/transaction.dart';
export 'src/updates/ota.dart';

typedef RequestType = dv.Request;
typedef ResponseType = dv.Response;

enum DVCronTarget { backend, client }

class DVCronEntry {
  final String name;
  final String cron;
  final DVCronTarget target;
  final String importUri;
  final String filePath;

  const DVCronEntry({
    required this.name,
    required this.cron,
    required this.target,
    required this.importUri,
    required this.filePath,
  });
}

class DVAIToolEntry {
  final String name;
  final String description;
  final String importUri;
  final String filePath;

  const DVAIToolEntry({
    required this.name,
    required this.description,
    required this.importUri,
    required this.filePath,
  });
}

// Simple HeaderValue parser to avoid dart:io dependency
class _HeaderValue {
  final String value;
  final Map<String, String> parameters;

  _HeaderValue(this.value, this.parameters);

  static _HeaderValue parse(String headerValue) {
    final parts = headerValue.split(';');
    final value = parts.first.trim();
    final parameters = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i].trim();
      final index = part.indexOf('=');
      if (index != -1) {
        final key = part.substring(0, index).trim();
        var val = part.substring(index + 1).trim();
        if (val.startsWith('"') && val.endsWith('"')) {
          val = val.substring(1, val.length - 1);
        }
        parameters[key] = val;
      }
    }
    return _HeaderValue(value, parameters);
  }
}

extension RequestFormData on dv.Request {
  Future<Map<String, Object?>> formData() async {
    final contentType = headers.get('content-type');
    if (contentType == null) return {};

    final mediaType = MediaType.parse(contentType);
    if (mediaType.mimeType == 'application/x-www-form-urlencoded') {
      final text = await body.text();
      return Uri.splitQueryString(text);
    }

    if (mediaType.mimeType == 'multipart/form-data') {
      final boundary = mediaType.parameters['boundary'];
      if (boundary == null) return {};

      final transformer = MimeMultipartTransformer(boundary);
      final parts = body.stream.transform(transformer);

      final data = <String, Object?>{};

      await for (final part in parts) {
        final contentDisposition = part.headers['content-disposition'];
        if (contentDisposition != null) {
          final header = _HeaderValue.parse(contentDisposition);
          final name = header.parameters['name'];
          final filename = header.parameters['filename'];

          if (name != null) {
            if (filename != null) {
              // It's a file
              final bytes =
                  await part.fold<List<int>>([], (p, e) => p..addAll(e));
              data[name] = MultipartFile(
                filename: filename,
                contentType: part.headers['content-type'],
                bytes: bytes,
              );
            } else {
              // It's a field
              final value = await utf8.decodeStream(part);
              data[name] = value;
            }
          }
        }
      }
      return data;
    }

    return {};
  }
}

class MultipartFile {
  final String filename;
  final String? contentType;
  final List<int> bytes;

  MultipartFile({
    required this.filename,
    this.contentType,
    required this.bytes,
  });

  @override
  String toString() =>
      'MultipartFile(filename: $filename, bytes: ${bytes.length})';
}

class Res {
  static dv.Response json(Object data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response(status,
          headers: dv.Headers(
              {'content-type': 'application/json; charset=utf-8', ...?headers}),
          body: Stream<List<int>>.value(utf8.encode(jsonEncode(data))));

  static dv.Response text(String data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response.text(data,
          status: status, headers: dv.Headers(headers ?? const {}));

  static dv.Response bytes(List<int> data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response(status,
          headers: dv.Headers(headers ?? const {}),
          body: Stream<List<int>>.value(data));

  static dv.Response notFound([String message = 'Not found']) =>
      text(message, status: 404);

  static dv.Response sse(Stream<String> events,
      {int status = 200, Map<String, String>? headers}) {
    final stream = events
        .map((e) => 'data: ${e.replaceAll('\n', '\ndata: ')}\n\n')
        .map(utf8.encode);
    return dv.Response(status,
        headers: dv.Headers({
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
          ...?headers,
        }),
        body: stream);
  }
}

// Middleware hints for dartvel_shelf (string-identifiable)
class _CorsMw {
  @override
  String toString() => 'cors';
}

Object cors() => _CorsMw();

enum DVJobState {
  queued,
  running,
  completed,
  failed,
  deadLettered,
}

/// Type-erased queue storage marker. User job payloads remain strongly typed
/// at dispatch and handler registration boundaries.
abstract class DVJobPayload {
  const DVJobPayload();

  Type get payloadType;

  /// Wraps a decoded payload so a durable adapter can rebuild the envelope a
  /// handler expects. Handlers are routed by [payloadType], so [TPayload] must
  /// be the type the handler was registered for.
  static DVJobPayload of<TPayload>(TPayload value) =>
      _DVStoredJobPayload<TPayload>(value);
}

class _DVStoredJobPayload<TPayload> extends DVJobPayload {
  final TPayload value;

  const _DVStoredJobPayload(this.value);

  @override
  Type get payloadType => TPayload;
}

typedef DVJobHandler<TPayload> = FutureOr<void> Function(TPayload payload);
typedef DVPolicyCheck<TUser, TResource> = FutureOr<bool> Function(
  TUser user,
  TResource resource,
);

class DVSearchResultPage<TModel> {
  final List<TModel> items;
  final int total;
  final int page;
  final int perPage;

  const DVSearchResultPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });
}

abstract class DVSearchProvider<TModel, TFacets> {
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  });
}

typedef DVSearchDocument<TModel> = String Function(TModel model);
typedef DVSearchFacetMatcher<TModel, TFacets> = bool Function(
  TModel model,
  TFacets? facets,
);

/// A concrete local search provider for development, tests, and small apps.
///
/// Applications should replace this provider with a database or hosted search
/// adapter when their dataset does not fit in memory.
class DVInMemorySearchProvider<TModel, TFacets>
    implements DVSearchProvider<TModel, TFacets> {
  final List<TModel> records;
  final DVSearchDocument<TModel> document;
  final DVSearchFacetMatcher<TModel, TFacets>? facetMatcher;

  DVInMemorySearchProvider({
    required List<TModel> records,
    required this.document,
    this.facetMatcher,
  }) : records = List<TModel>.unmodifiable(records);

  @override
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page', 'must be positive');
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be positive');
    }

    final needle = query.trim().toLowerCase();
    final matches = records.where((record) {
      final textMatches =
          needle.isEmpty || document(record).toLowerCase().contains(needle);
      final facetsMatch = facetMatcher?.call(record, facets) ?? true;
      return textMatches && facetsMatch;
    }).toList(growable: false);
    final start = (page - 1) * perPage;
    final end =
        start + perPage > matches.length ? matches.length : start + perPage;
    final pageItems =
        start >= matches.length ? <TModel>[] : matches.sublist(start, end);

    return DVSearchResultPage<TModel>(
      items: List<TModel>.unmodifiable(pageItems),
      total: matches.length,
      page: page,
      perPage: perPage,
    );
  }
}

/// Full-text search backed by SQLite's FTS5 extension.
///
/// FTS5 does the matching and relevance ranking; the models stay in Dart. That
/// buys real tokenisation and BM25 ordering instead of the substring scan
/// [DVInMemorySearchProvider] performs, so "lovelace" no longer matches
/// "unlovelaced" and better matches sort first.
///
/// Facets are applied in Dart after the index returns candidates, which is the
/// post-filtering the spec allows when a provider cannot enforce them itself.
/// Ranked ids are read in full before paging, so this suits datasets that fit
/// in memory rather than very large corpora.
class DVSqliteSearchProvider<TModel, TFacets>
    implements DVSearchProvider<TModel, TFacets> {
  final DVDatabaseAdapter database;
  final String tableName;
  final DVSearchDocument<TModel> document;
  final DVSearchFacetMatcher<TModel, TFacets>? facetMatcher;

  /// Treats the final term as a prefix, so "ada lov" matches "Ada Lovelace".
  final bool prefixMatchLastTerm;

  List<TModel> _records;
  bool _indexed = false;

  DVSqliteSearchProvider({
    required this.database,
    required List<TModel> records,
    required this.document,
    this.facetMatcher,
    this.tableName = 'dartvel_search',
    this.prefixMatchLastTerm = true,
  }) : _records = List<TModel>.unmodifiable(records) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Search table names must be plain SQL identifiers.',
      );
    }
  }

  List<TModel> get records => _records;

  /// Rebuilds the index. Call it after the underlying records change; passing
  /// [records] replaces the indexed set.
  Future<void> reindex([List<TModel>? records]) async {
    if (records != null) {
      _records = List<TModel>.unmodifiable(records);
    }
    await database.execute('DROP TABLE IF EXISTS $tableName');
    await database.execute(
      'CREATE VIRTUAL TABLE $tableName USING fts5(doc)',
    );
    for (var i = 0; i < _records.length; i++) {
      await database.execute(
        'INSERT INTO $tableName (rowid, doc) VALUES (?, ?)',
        <Object?>[i + 1, document(_records[i])],
      );
    }
    _indexed = true;
  }

  @override
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page', 'must be positive');
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be positive');
    }
    if (!_indexed) await reindex();

    final expression = _toMatchExpression(query);
    final List<TModel> matches;
    if (expression == null) {
      // No usable terms behaves like the in-memory provider's empty query.
      matches = _records.where((record) => _matchesFacets(record, facets))
          .toList(growable: false);
    } else {
      final rows = await database.query(
        'SELECT rowid FROM $tableName WHERE $tableName MATCH ? '
        'ORDER BY bm25($tableName)',
        <Object?>[expression],
      );
      matches = <TModel>[
        for (final row in rows)
          if (row['rowid'] case final int rowid)
            if (rowid >= 1 && rowid <= _records.length)
              if (_matchesFacets(_records[rowid - 1], facets))
                _records[rowid - 1],
      ];
    }

    final start = (page - 1) * perPage;
    final end =
        start + perPage > matches.length ? matches.length : start + perPage;
    final pageItems =
        start >= matches.length ? <TModel>[] : matches.sublist(start, end);

    return DVSearchResultPage<TModel>(
      items: List<TModel>.unmodifiable(pageItems),
      total: matches.length,
      page: page,
      perPage: perPage,
    );
  }

  bool _matchesFacets(TModel record, TFacets? facets) =>
      facetMatcher?.call(record, facets) ?? true;

  /// Builds a safe FTS5 MATCH expression from raw user input.
  ///
  /// Every term is quoted, so FTS5 operators typed by a user ("AND", "*", ":",
  /// quotes) are matched literally instead of being executed as query syntax
  /// or raising a syntax error. Returns null when nothing searchable remains.
  String? _toMatchExpression(String query) {
    final terms = query
        .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return null;

    final quoted = <String>[
      for (var i = 0; i < terms.length; i++)
        if (prefixMatchLastTerm && i == terms.length - 1)
          '"${terms[i].replaceAll('"', '""')}"*'
        else
          '"${terms[i].replaceAll('"', '""')}"',
    ];
    return quoted.join(' ');
  }
}

/// Builds provider filter expressions from typed facets. Meilisearch and
/// Algolia both express facets as filter strings, so this is where an
/// application maps its own facet type onto that syntax.
typedef DVSearchFacetFilter<TFacets> = List<String> Function(TFacets? facets);

/// Thrown when a hosted search service rejects a query or answers with a shape
/// Dartvel cannot read. A failed search never degrades to an empty page.
class DVSearchProviderException implements Exception {
  final String provider;
  final int? statusCode;
  final String message;
  final String? responseBody;

  const DVSearchProviderException(
    this.provider,
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVSearchProviderException[$provider]$status: $message$body';
  }
}

/// Shared behaviour for hosted search services reached over HTTP.
///
/// The service owns the index, so results arrive as JSON documents; [fromJson]
/// turns each hit back into the application's model.
abstract class DVHttpSearchProvider<TModel, TFacets>
    implements DVSearchProvider<TModel, TFacets> {
  final Uri baseUrl;
  final String apiKey;
  final String indexName;
  final TModel Function(Map<String, Object?> hit) fromJson;
  final DVSearchFacetFilter<TFacets>? facetFilter;
  final DVHttpSend transport;

  const DVHttpSearchProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.indexName,
    required this.fromJson,
    this.facetFilter,
    this.transport = dvSendHttpRequest,
  });

  String get providerName;

  DVHttpRequest buildRequest(
    String query,
    List<String> filters,
    int page,
    int perPage,
  );

  DVSearchResultPage<TModel> readResponse(
    Map<String, Object?> payload,
    int page,
    int perPage,
  );

  @override
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page', 'must be positive');
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be positive');
    }

    final filters = facetFilter?.call(facets) ?? const <String>[];
    final response = await transport(
      buildRequest(query, filters, page, perPage),
    );
    if (!response.isSuccess) {
      throw DVSearchProviderException(
        providerName,
        'The search service rejected the query.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw DVSearchProviderException(
        providerName,
        'Response was not valid JSON: ${error.message}',
        responseBody: response.body,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw DVSearchProviderException(
        providerName,
        'Expected a JSON object at the top level of the response.',
        responseBody: response.body,
      );
    }
    return readResponse(decoded, page, perPage);
  }

  List<TModel> readHits(Map<String, Object?> payload, String key) {
    final hits = payload[key];
    if (hits is! List<Object?>) {
      throw DVSearchProviderException(
        providerName,
        '"$key" was not a JSON array.',
        responseBody: jsonEncode(payload),
      );
    }
    return List<TModel>.unmodifiable(<TModel>[
      for (final hit in hits)
        if (hit is Map<String, Object?>) fromJson(hit),
    ]);
  }
}

/// Meilisearch search endpoint. Paging is 1-based, matching Dartvel.
class MeilisearchProvider<TModel, TFacets>
    extends DVHttpSearchProvider<TModel, TFacets> {
  const MeilisearchProvider({
    required super.baseUrl,
    required super.apiKey,
    required super.indexName,
    required super.fromJson,
    super.facetFilter,
    super.transport,
  });

  @override
  String get providerName => 'meilisearch';

  @override
  DVHttpRequest buildRequest(
    String query,
    List<String> filters,
    int page,
    int perPage,
  ) =>
      DVHttpRequest(
        url: baseUrl.replace(path: '/indexes/$indexName/search'),
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'q': query,
          'page': page,
          'hitsPerPage': perPage,
          if (filters.isNotEmpty) 'filter': filters,
        })),
      );

  @override
  DVSearchResultPage<TModel> readResponse(
    Map<String, Object?> payload,
    int page,
    int perPage,
  ) =>
      DVSearchResultPage<TModel>(
        items: readHits(payload, 'hits'),
        total: payload['totalHits'] is int
            ? payload['totalHits']! as int
            : readHits(payload, 'hits').length,
        page: page,
        perPage: perPage,
      );
}

/// Algolia query endpoint.
///
/// Algolia pages are zero-based while Dartvel's contract is one-based, so the
/// page number is translated in both directions.
class AlgoliaSearchProvider<TModel, TFacets>
    extends DVHttpSearchProvider<TModel, TFacets> {
  final String applicationId;

  AlgoliaSearchProvider({
    required this.applicationId,
    required super.apiKey,
    required super.indexName,
    required super.fromJson,
    Uri? baseUrl,
    super.facetFilter,
    super.transport,
  }) : super(baseUrl: baseUrl ?? Uri.https('$applicationId-dsn.algolia.net'));

  @override
  String get providerName => 'algolia';

  @override
  DVHttpRequest buildRequest(
    String query,
    List<String> filters,
    int page,
    int perPage,
  ) =>
      DVHttpRequest(
        url: baseUrl.replace(path: '/1/indexes/$indexName/query'),
        headers: <String, String>{
          'content-type': 'application/json',
          'x-algolia-api-key': apiKey,
          'x-algolia-application-id': applicationId,
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'query': query,
          // Dartvel pages are 1-based; Algolia counts from zero.
          'page': page - 1,
          'hitsPerPage': perPage,
          if (filters.isNotEmpty) 'filters': filters.join(' AND '),
        })),
      );

  @override
  DVSearchResultPage<TModel> readResponse(
    Map<String, Object?> payload,
    int page,
    int perPage,
  ) =>
      DVSearchResultPage<TModel>(
        items: readHits(payload, 'hits'),
        total: payload['nbHits'] is int
            ? payload['nbHits']! as int
            : readHits(payload, 'hits').length,
        // Translate back, so callers always see the page they asked for.
        page: payload['page'] is int ? (payload['page']! as int) + 1 : page,
        perPage: perPage,
      );
}

/// OpenSearch and Elasticsearch, which share this query API.
///
/// Three things differ from the other hosted providers, and each is translated
/// here so callers see one contract: paging is offset-based (`from`/`size`)
/// rather than page numbers, hits are nested under `hits.hits[]._source`, and
/// the total is an object on 7.x but a bare integer on 6.x.
class OpenSearchProvider<TModel, TFacets>
    extends DVHttpSearchProvider<TModel, TFacets> {
  /// Fields to match against. `['*']` searches every indexed field.
  final List<String> searchFields;

  final String? username;
  final String? password;

  const OpenSearchProvider({
    required super.baseUrl,
    required super.indexName,
    required super.fromJson,
    super.apiKey = '',
    this.searchFields = const <String>['*'],
    this.username,
    this.password,
    super.facetFilter,
    super.transport,
  });

  @override
  String get providerName => 'opensearch';

  Map<String, String> get _authHeaders {
    if (username != null && password != null) {
      final token = base64Encode(utf8.encode('$username:$password'));
      return <String, String>{'authorization': 'Basic $token'};
    }
    if (apiKey.isNotEmpty) {
      return <String, String>{'authorization': 'ApiKey $apiKey'};
    }
    return const <String, String>{};
  }

  @override
  DVHttpRequest buildRequest(
    String query,
    List<String> filters,
    int page,
    int perPage,
  ) =>
      DVHttpRequest(
        url: baseUrl.replace(path: '/$indexName/_search'),
        headers: <String, String>{
          'content-type': 'application/json',
          ..._authHeaders,
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          // Dartvel pages are 1-based; Elasticsearch takes an offset.
          'from': (page - 1) * perPage,
          'size': perPage,
          'query': <String, Object?>{
            'bool': <String, Object?>{
              'must': <Object?>[
                if (query.trim().isEmpty)
                  <String, Object?>{'match_all': <String, Object?>{}}
                else
                  <String, Object?>{
                    'multi_match': <String, Object?>{
                      'query': query,
                      'fields': searchFields,
                    },
                  },
              ],
              if (filters.isNotEmpty)
                'filter': <Object?>[
                  for (final filter in filters)
                    <String, Object?>{'query_string': <String, Object?>{
                      'query': filter,
                    }},
                ],
            },
          },
        })),
      );

  @override
  DVSearchResultPage<TModel> readResponse(
    Map<String, Object?> payload,
    int page,
    int perPage,
  ) {
    final envelope = payload['hits'];
    if (envelope is! Map<String, Object?>) {
      throw DVSearchProviderException(
        providerName,
        '"hits" was not a JSON object.',
        responseBody: jsonEncode(payload),
      );
    }
    final rows = envelope['hits'];
    if (rows is! List<Object?>) {
      throw DVSearchProviderException(
        providerName,
        '"hits.hits" was not a JSON array.',
        responseBody: jsonEncode(payload),
      );
    }

    return DVSearchResultPage<TModel>(
      items: List<TModel>.unmodifiable(<TModel>[
        for (final row in rows)
          if (row is Map<String, Object?>)
            if (row['_source'] case final Map<String, Object?> source)
              fromJson(source),
      ]),
      total: _readTotal(envelope, rows.length),
      page: page,
      perPage: perPage,
    );
  }

  /// 7.x reports `{"value": n, "relation": "eq"}`; 6.x reports a bare integer.
  static int _readTotal(Map<String, Object?> envelope, int fallback) {
    final total = envelope['total'];
    if (total is int) return total;
    if (total is Map<String, Object?> && total['value'] is int) {
      return total['value']! as int;
    }
    return fallback;
  }
}

/// Fails loudly when a searchable model has no configured provider.
class DVUnconfiguredSearchProvider<TModel, TFacets>
    implements DVSearchProvider<TModel, TFacets> {
  const DVUnconfiguredSearchProvider();

  @override
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  }) {
    throw StateError(
      'No search provider is configured. Call Model.Search.useProvider(...) '
      'before querying a searchable model.',
    );
  }
}

class BillingPlan {
  final String id;
  final String displayName;
  final int priceMinorUnits;
  final String currency;

  const BillingPlan({
    required this.id,
    required this.displayName,
    required this.priceMinorUnits,
    required this.currency,
  });

  static const pro = BillingPlan(
    id: 'pro',
    displayName: 'Pro',
    priceMinorUnits: 0,
    currency: 'USD',
  );
}

class Entitlement {
  final String id;

  const Entitlement(this.id);

  static const analytics = Entitlement('analytics');
}

class DVBillingCheckoutSession {
  final String id;
  final BillingPlan plan;
  final Object customer;
  final Uri? checkoutUrl;
  final DateTime createdAt;

  const DVBillingCheckoutSession({
    required this.id,
    required this.plan,
    required this.customer,
    required this.createdAt,
    this.checkoutUrl,
  });
}

abstract class DVBillingProvider {
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  });

  Future<bool> hasEntitlement(Object customer, Entitlement entitlement);
}

class DVLocalBillingProvider implements DVBillingProvider {
  final Set<String> _grants = <String>{};
  var _nextSession = 0;

  void grant(Object customer, Entitlement entitlement) {
    _grants.add(_key(customer, entitlement));
  }

  void revoke(Object customer, Entitlement entitlement) {
    _grants.remove(_key(customer, entitlement));
  }

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    _nextSession += 1;
    return DVBillingCheckoutSession(
      id: 'local_checkout_$_nextSession',
      plan: plan,
      customer: customer,
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async {
    return _grants.contains(_key(customer, entitlement));
  }

  String _key(Object customer, Entitlement entitlement) {
    return '${customer.hashCode}:${entitlement.id}';
  }
}

class DVImportRowError {
  final int row;
  final String message;

  const DVImportRowError({
    required this.row,
    required this.message,
  });
}

class DVImportResult<TModel> {
  final List<TModel> items;
  final List<DVImportRowError> errors;

  const DVImportResult({
    required this.items,
    this.errors = const <DVImportRowError>[],
  });

  bool get hasErrors => errors.isNotEmpty;
}

class DVImportChunk {
  final String model;
  final String format;
  final int startRow;
  final List<String> rows;

  const DVImportChunk({
    required this.model,
    required this.format,
    required this.startRow,
    required this.rows,
  });
}

class DVExportResult {
  final String fileName;
  final String contentType;
  final List<int> bytes;
  final Map<String, String> metadata;

  const DVExportResult({
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.metadata = const <String, String>{},
  });
}

class DVExportOptions<TModel> {
  final String? tenantId;
  final bool Function(TModel item)? policyFilter;
  final int chunkSize;
  final Map<String, String> metadata;

  /// Whether `@DVModel.sensitiveField()` columns are written to the export.
  ///
  /// Off by default: an export is a file that leaves the system, and the
  /// spec excludes sensitive fields from generated tables unless something
  /// asks for them. Turning it on is the explicit authorization step.
  final bool includeSensitiveFields;

  const DVExportOptions({
    this.tenantId,
    this.policyFilter,
    this.chunkSize = 1000,
    this.metadata = const <String, String>{},
    this.includeSensitiveFields = false,
  });

  Iterable<TModel> apply(Iterable<TModel> items) {
    final filter = policyFilter;
    return filter == null ? items : items.where(filter);
  }

  Map<String, String> exportMetadata() => <String, String>{
        if (tenantId != null) 'tenantId': tenantId!,
        ...metadata,
      };
}

class DVReportResult {
  final String name;
  final DateTime generatedAt;
  final Map<String, Object?> metrics;

  const DVReportResult({
    required this.name,
    required this.generatedAt,
    required this.metrics,
  });
}

class DVScheduledReport {
  final String name;
  final String model;
  final String report;
  final String cron;
  final String queue;
  final DateTime scheduledAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final Map<String, String> metadata;

  const DVScheduledReport({
    required this.name,
    required this.model,
    required this.report,
    required this.cron,
    required this.queue,
    required this.scheduledAt,
    this.periodStart,
    this.periodEnd,
    this.metadata = const <String, String>{},
  });
}

class DVJobEnvelope<TPayload> {
  final String id;
  final String queue;
  final Type payloadType;
  final TPayload payload;
  final int priority;
  final int maxAttempts;
  final Duration backoff;
  final DateTime createdAt;
  final int attempts;
  final DVJobState state;
  final String? lastError;

  const DVJobEnvelope({
    required this.id,
    required this.queue,
    required this.payloadType,
    required this.payload,
    required this.priority,
    required this.maxAttempts,
    required this.backoff,
    required this.createdAt,
    required this.attempts,
    required this.state,
    this.lastError,
  });

  DVJobEnvelope<TPayload> copyWith({
    int? attempts,
    DVJobState? state,
    String? lastError,
  }) {
    return DVJobEnvelope<TPayload>(
      id: id,
      queue: queue,
      payloadType: payloadType,
      payload: payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      state: state ?? this.state,
      lastError: lastError ?? this.lastError,
    );
  }
}

abstract class DVQueueAdapter {
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority,
    int maxAttempts,
    Duration backoff,
  });

  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue);
  Future<void> complete(String id);
  Future<void> fail(String id, String error, StackTrace stackTrace);
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue);
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue);
  Future<bool> retry(String id);
  Future<int> flush(String queue);
}

class DVInMemoryQueueAdapter implements DVQueueAdapter {
  final Map<String, List<DVJobEnvelope<DVJobPayload>>> _pending = {};
  final Map<String, DVJobEnvelope<DVJobPayload>> _reserved = {};
  final Map<String, List<DVJobEnvelope<DVJobPayload>>> _deadLetters = {};
  int _sequence = 0;

  @override
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) async {
    final envelope = DVJobEnvelope<TPayload>(
      id: 'job-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      queue: queue,
      payloadType: TPayload,
      payload: payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
      createdAt: DateTime.now(),
      attempts: 0,
      state: DVJobState.queued,
    );
    final stored = DVJobEnvelope<DVJobPayload>(
      id: envelope.id,
      queue: envelope.queue,
      payloadType: envelope.payloadType,
      payload: _DVStoredJobPayload<TPayload>(payload),
      priority: envelope.priority,
      maxAttempts: envelope.maxAttempts,
      backoff: envelope.backoff,
      createdAt: envelope.createdAt,
      attempts: envelope.attempts,
      state: envelope.state,
    );
    (_pending[queue] ??= []).add(stored);
    _pending[queue]!.sort((a, b) => b.priority.compareTo(a.priority));
    return envelope;
  }

  @override
  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue) async {
    final list = _pending[queue];
    if (list == null || list.isEmpty) return null;
    final next = list.removeAt(0).copyWith(state: DVJobState.running);
    _reserved[next.id] = next;
    return next;
  }

  @override
  Future<void> complete(String id) async {
    _reserved.remove(id);
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    final current = _reserved.remove(id);
    if (current == null) return;
    final failed = current.copyWith(
      attempts: current.attempts + 1,
      state: current.attempts + 1 >= current.maxAttempts
          ? DVJobState.deadLettered
          : DVJobState.failed,
      lastError: error,
    );
    if (failed.state == DVJobState.deadLettered) {
      (_deadLetters[failed.queue] ??= []).add(failed);
    } else {
      (_pending[failed.queue] ??= []).add(failed.copyWith(
        state: DVJobState.queued,
      ));
    }
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) async {
    return List<DVJobEnvelope<DVJobPayload>>.unmodifiable(
      _pending[queue] ?? const <DVJobEnvelope<DVJobPayload>>[],
    );
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) async {
    return List<DVJobEnvelope<DVJobPayload>>.unmodifiable(
      _deadLetters[queue] ?? const <DVJobEnvelope<DVJobPayload>>[],
    );
  }

  @override
  Future<bool> retry(String id) async {
    for (final entry in _deadLetters.entries) {
      final index = entry.value.indexWhere((job) => job.id == id);
      if (index == -1) continue;
      final job = entry.value.removeAt(index);
      (_pending[job.queue] ??= []).add(job.copyWith(
        attempts: 0,
        state: DVJobState.queued,
      ));
      _pending[job.queue]!.sort((a, b) => b.priority.compareTo(a.priority));
      return true;
    }
    return false;
  }

  @override
  Future<int> flush(String queue) async {
    final pending = _pending.remove(queue)?.length ?? 0;
    final deadLetters = _deadLetters.remove(queue)?.length ?? 0;
    return pending + deadLetters;
  }
}

/// Converts a job payload to and from JSON so a durable queue can store it.
///
/// [name] is written to the database and read back after a restart, so it must
/// stay stable across releases even if the Dart class is renamed.
class DVJobPayloadCodec<TPayload> {
  final String name;
  final Map<String, Object?> Function(TPayload payload) encode;
  final TPayload Function(Map<String, Object?> json) decode;

  const DVJobPayloadCodec({
    required this.name,
    required this.encode,
    required this.decode,
  });
}

class _DVRegisteredCodec {
  final String name;
  final Type type;
  final Map<String, Object?> Function(Object? value) encode;
  final DVJobPayload Function(Map<String, Object?> json) decode;

  const _DVRegisteredCodec({
    required this.name,
    required this.type,
    required this.encode,
    required this.decode,
  });
}

/// Codecs that let [DVDatabaseQueueAdapter] persist job payloads.
///
/// In-memory queues keep the Dart object itself and need no codec. A durable
/// queue has to write bytes, so every persisted payload type must be
/// registered; enqueueing an unregistered type fails loudly rather than
/// storing something that cannot be read back.
class DVJobPayloadCodecs {
  static final Map<Type, _DVRegisteredCodec> _byType = {};
  static final Map<String, _DVRegisteredCodec> _byName = {};

  const DVJobPayloadCodecs();

  void register<TPayload>(DVJobPayloadCodec<TPayload> codec) {
    if (codec.name.trim().isEmpty) {
      throw ArgumentError.value(
        codec.name,
        'name',
        'Job payload codec names cannot be empty.',
      );
    }
    final existing = _byName[codec.name];
    if (existing != null && existing.type != TPayload) {
      throw ArgumentError.value(
        codec.name,
        'name',
        'Codec name "${codec.name}" is already registered for '
            '${existing.type}.',
      );
    }
    final registered = _DVRegisteredCodec(
      name: codec.name,
      type: TPayload,
      encode: (value) => codec.encode(value as TPayload),
      decode: (json) => DVJobPayload.of<TPayload>(codec.decode(json)),
    );
    _byType[TPayload] = registered;
    _byName[codec.name] = registered;
  }

  bool supports(Type type) => _byType.containsKey(type);

  List<String> get names => List<String>.unmodifiable(_byName.keys);

  void clear() {
    _byType.clear();
    _byName.clear();
  }
}

/// Queue storage backed by a [DVDatabaseAdapter], so dispatched jobs survive a
/// process restart. With SQLite this is the durable local queue the spec calls
/// for, sharing one database file with the application and cache.
///
/// Payload types must be registered with [DVJobPayloadCodecs] first.
class DVDatabaseQueueAdapter implements DVQueueAdapter {
  final DVDatabaseAdapter database;
  final String tableName;

  bool _initialized = false;
  int _sequence = 0;

  DVDatabaseQueueAdapter(
    this.database, {
    this.tableName = 'dartvel_jobs',
  }) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tableName)) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        'Queue table names must be plain SQL identifiers.',
      );
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        queue TEXT NOT NULL,
        payload_name TEXT NOT NULL,
        payload TEXT NOT NULL,
        priority INTEGER NOT NULL,
        max_attempts INTEGER NOT NULL,
        backoff_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL,
        state TEXT NOT NULL,
        last_error TEXT
      )
    ''');
    _initialized = true;
  }

  @override
  Future<DVJobEnvelope<TPayload>> enqueue<TPayload>(
    String queue,
    TPayload payload, {
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) async {
    await initialize();
    final codec = DVJobPayloadCodecs._byType[TPayload];
    if (codec == null) {
      throw StateError(
        'No DVJobPayloadCodec registered for $TPayload, so it cannot be '
        'persisted. Register one, or use DVInMemoryQueueAdapter.',
      );
    }

    final envelope = DVJobEnvelope<TPayload>(
      id: 'job-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      queue: queue,
      payloadType: TPayload,
      payload: payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
      createdAt: DateTime.now(),
      attempts: 0,
      state: DVJobState.queued,
    );

    await database.execute(
      'INSERT INTO $tableName (id, queue, payload_name, payload, priority, '
      'max_attempts, backoff_ms, created_at, attempts, state, last_error) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)',
      <Object?>[
        envelope.id,
        queue,
        codec.name,
        jsonEncode(codec.encode(payload)),
        priority,
        maxAttempts,
        backoff.inMilliseconds,
        envelope.createdAt.millisecondsSinceEpoch,
        0,
        DVJobState.queued.name,
      ],
    );
    return envelope;
  }

  @override
  Future<DVJobEnvelope<DVJobPayload>?> reserve(String queue) async {
    await initialize();
    final rows = await database.query(
      'SELECT * FROM $tableName WHERE queue = ? AND state = ? '
      'ORDER BY priority DESC, created_at ASC LIMIT 1',
      <Object?>[queue, DVJobState.queued.name],
    );
    if (rows.isEmpty) return null;

    final id = rows.first['id'] as String;
    await database.execute(
      'UPDATE $tableName SET state = ? WHERE id = ?',
      <Object?>[DVJobState.running.name, id],
    );
    return _toEnvelope(rows.first, state: DVJobState.running);
  }

  @override
  Future<void> complete(String id) async {
    await initialize();
    await database.execute(
      'DELETE FROM $tableName WHERE id = ?',
      <Object?>[id],
    );
  }

  @override
  Future<void> fail(String id, String error, StackTrace stackTrace) async {
    await initialize();
    final rows = await database.query(
      'SELECT attempts, max_attempts FROM $tableName WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) return;

    final attempts = (rows.first['attempts'] as int) + 1;
    final maxAttempts = rows.first['max_attempts'] as int;
    final state =
        attempts >= maxAttempts ? DVJobState.deadLettered : DVJobState.queued;

    await database.execute(
      'UPDATE $tableName SET attempts = ?, state = ?, last_error = ? '
      'WHERE id = ?',
      <Object?>[attempts, state.name, error, id],
    );
  }

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> pending(String queue) =>
      _select(queue, DVJobState.queued);

  @override
  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters(String queue) =>
      _select(queue, DVJobState.deadLettered);

  @override
  Future<bool> retry(String id) async {
    await initialize();
    final moved = await database.execute(
      'UPDATE $tableName SET state = ?, attempts = 0 '
      'WHERE id = ? AND state = ?',
      <Object?>[
        DVJobState.queued.name,
        id,
        DVJobState.deadLettered.name,
      ],
    );
    return moved > 0;
  }

  @override
  Future<int> flush(String queue) async {
    await initialize();
    return database.execute(
      'DELETE FROM $tableName WHERE queue = ?',
      <Object?>[queue],
    );
  }

  Future<List<DVJobEnvelope<DVJobPayload>>> _select(
    String queue,
    DVJobState state,
  ) async {
    await initialize();
    final rows = await database.query(
      'SELECT * FROM $tableName WHERE queue = ? AND state = ? '
      'ORDER BY priority DESC, created_at ASC',
      <Object?>[queue, state.name],
    );
    return List<
        DVJobEnvelope<DVJobPayload>>.unmodifiable(<DVJobEnvelope<DVJobPayload>>[
      for (final row in rows) _toEnvelope(row, state: state),
    ]);
  }

  DVJobEnvelope<DVJobPayload> _toEnvelope(
    Map<String, Object?> row, {
    required DVJobState state,
  }) {
    final name = row['payload_name'] as String;
    final codec = DVJobPayloadCodecs._byName[name];
    if (codec == null) {
      throw StateError(
        'Job ${row['id']} was stored with payload codec "$name", which is '
        'not registered in this process. Register it before draining the '
        'queue, or the job cannot be decoded.',
      );
    }
    final decoded = jsonDecode(row['payload'] as String);
    return DVJobEnvelope<DVJobPayload>(
      id: row['id'] as String,
      queue: row['queue'] as String,
      payloadType: codec.type,
      payload: codec.decode(
        decoded is Map<String, Object?> ? decoded : const <String, Object?>{},
      ),
      priority: row['priority'] as int,
      maxAttempts: row['max_attempts'] as int,
      backoff: Duration(milliseconds: row['backoff_ms'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      attempts: row['attempts'] as int,
      state: state,
      lastError: row['last_error'] as String?,
    );
  }
}

abstract class _DVRegisteredJobHandler {
  Future<void> invoke(DVJobPayload payload);
}

class _DVTypedRegisteredJobHandler<TPayload>
    implements _DVRegisteredJobHandler {
  final DVJobHandler<TPayload> handler;

  const _DVTypedRegisteredJobHandler(this.handler);

  @override
  Future<void> invoke(DVJobPayload payload) async {
    final stored = payload as _DVStoredJobPayload<TPayload>;
    await handler(stored.value);
  }
}

class DVQueues {
  static DVQueueAdapter _adapter = DVInMemoryQueueAdapter();
  static final Map<Type, _DVRegisteredJobHandler> _handlers = {};

  const DVQueues();

  void useAdapter(DVQueueAdapter adapter) {
    _adapter = adapter;
  }

  void register<TPayload>(DVJobHandler<TPayload> handler) {
    _handlers[TPayload] = _DVTypedRegisteredJobHandler<TPayload>(handler);
  }

  Future<DVJobEnvelope<TPayload>> dispatch<TPayload>(
    TPayload payload, {
    String queue = 'default',
    int priority = 0,
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 30),
  }) {
    return _adapter.enqueue<TPayload>(
      queue,
      payload,
      priority: priority,
      maxAttempts: maxAttempts,
      backoff: backoff,
    );
  }

  Future<int> work({
    String queue = 'default',
    int maxJobs = 1,
  }) async {
    var completed = 0;
    for (var i = 0; i < maxJobs; i++) {
      final envelope = await _adapter.reserve(queue);
      if (envelope == null) break;
      final handler = _handlers[envelope.payloadType];
      if (handler == null) {
        await _adapter.fail(
          envelope.id,
          'No DV job handler registered for ${envelope.payloadType}.',
          StackTrace.current,
        );
        continue;
      }
      try {
        await handler.invoke(envelope.payload);
        await _adapter.complete(envelope.id);
        completed++;
      } catch (error, stackTrace) {
        await _adapter.fail(envelope.id, error.toString(), stackTrace);
      }
    }
    return completed;
  }

  Future<List<DVJobEnvelope<DVJobPayload>>> pending([
    String queue = 'default',
  ]) {
    return _adapter.pending(queue);
  }

  Future<List<DVJobEnvelope<DVJobPayload>>> deadLetters([
    String queue = 'default',
  ]) {
    return _adapter.deadLetters(queue);
  }

  Future<bool> retry(String id) {
    return _adapter.retry(id);
  }

  Future<int> flush({String queue = 'default'}) {
    return _adapter.flush(queue);
  }
}

enum DVMailPriority { low, normal, high }

class DVMailAddress {
  final String email;
  final String? name;

  const DVMailAddress(this.email, {this.name});
}

class DVMailMessage {
  final DVMailAddress from;
  final List<DVMailAddress> to;
  final String subject;
  final String text;
  final String? html;
  final DVMailPriority priority;
  final Map<String, String> headers;

  const DVMailMessage({
    required this.from,
    required this.to,
    required this.subject,
    required this.text,
    this.html,
    this.priority = DVMailPriority.normal,
    this.headers = const <String, String>{},
  });
}

abstract class DVMailProvider {
  Future<void> send(DVMailMessage message);
}

/// Thrown when a mail provider rejects a message. Delivery failures are never
/// swallowed - a caller always learns the message did not go out.
class DVMailProviderException implements Exception {
  final String provider;
  final int? statusCode;
  final String message;
  final String? responseBody;

  const DVMailProviderException(
    this.provider,
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVMailProviderException[$provider]$status: $message$body';
  }
}

/// Shared behaviour for mail providers that speak HTTP.
///
/// Each provider supplies the endpoint, headers and body encoding for its own
/// API; this posts the request and turns a non-2xx answer into a
/// [DVMailProviderException] carrying the status and body.
abstract class DVHttpMailProvider implements DVMailProvider {
  final String apiKey;
  final Uri baseUrl;
  final DVHttpSend transport;

  const DVHttpMailProvider({
    required this.apiKey,
    required this.baseUrl,
    required this.transport,
  });

  String get providerName;

  DVHttpRequest buildRequest(DVMailMessage message);

  @override
  Future<void> send(DVMailMessage message) async {
    if (message.to.isEmpty) {
      throw ArgumentError.value(
        message.to,
        'to',
        'A mail message needs at least one recipient.',
      );
    }
    final response = await transport(buildRequest(message));
    if (!response.isSuccess) {
      throw DVMailProviderException(
        providerName,
        'The provider rejected the message.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// RFC 5322 display form, e.g. `Ada Lovelace <ada@example.com>`.
  static String formatAddress(DVMailAddress address) {
    final name = address.name;
    if (name == null || name.trim().isEmpty) return address.email;
    final escaped = name.replaceAll('"', '');
    return '"$escaped" <${address.email}>';
  }
}

/// Resend (https://resend.com) transactional mail.
class ResendMailProvider extends DVHttpMailProvider {
  ResendMailProvider({
    required super.apiKey,
    Uri? baseUrl,
    super.transport = dvSendHttpRequest,
  }) : super(baseUrl: baseUrl ?? Uri.https('api.resend.com'));

  @override
  String get providerName => 'resend';

  @override
  DVHttpRequest buildRequest(DVMailMessage message) => DVHttpRequest(
        url: baseUrl.replace(path: '/emails'),
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'from': DVHttpMailProvider.formatAddress(message.from),
          'to': <String>[
            for (final address in message.to)
              DVHttpMailProvider.formatAddress(address),
          ],
          'subject': message.subject,
          'text': message.text,
          if (message.html != null) 'html': message.html,
          if (message.headers.isNotEmpty) 'headers': message.headers,
        })),
      );
}

/// SendGrid v3 mail send.
class SendGridMailProvider extends DVHttpMailProvider {
  SendGridMailProvider({
    required super.apiKey,
    Uri? baseUrl,
    super.transport = dvSendHttpRequest,
  }) : super(baseUrl: baseUrl ?? Uri.https('api.sendgrid.com'));

  @override
  String get providerName => 'sendgrid';

  @override
  DVHttpRequest buildRequest(DVMailMessage message) => DVHttpRequest(
        url: baseUrl.replace(path: '/v3/mail/send'),
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'personalizations': <Object?>[
            <String, Object?>{
              'to': <Object?>[
                for (final address in message.to)
                  <String, Object?>{
                    'email': address.email,
                    if (address.name != null) 'name': address.name,
                  },
              ],
            },
          ],
          'from': <String, Object?>{
            'email': message.from.email,
            if (message.from.name != null) 'name': message.from.name,
          },
          'subject': message.subject,
          'content': <Object?>[
            <String, Object?>{'type': 'text/plain', 'value': message.text},
            if (message.html != null)
              <String, Object?>{'type': 'text/html', 'value': message.html},
          ],
          if (message.headers.isNotEmpty) 'headers': message.headers,
        })),
      );
}

/// Postmark single-message send.
class PostmarkMailProvider extends DVHttpMailProvider {
  final String messageStream;

  PostmarkMailProvider({
    required super.apiKey,
    this.messageStream = 'outbound',
    Uri? baseUrl,
    super.transport = dvSendHttpRequest,
  }) : super(baseUrl: baseUrl ?? Uri.https('api.postmarkapp.com'));

  @override
  String get providerName => 'postmark';

  @override
  DVHttpRequest buildRequest(DVMailMessage message) => DVHttpRequest(
        url: baseUrl.replace(path: '/email'),
        headers: <String, String>{
          'content-type': 'application/json',
          'accept': 'application/json',
          'x-postmark-server-token': apiKey,
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'From': DVHttpMailProvider.formatAddress(message.from),
          'To': message.to.map(DVHttpMailProvider.formatAddress).join(', '),
          'Subject': message.subject,
          'TextBody': message.text,
          if (message.html != null) 'HtmlBody': message.html,
          'MessageStream': messageStream,
          if (message.headers.isNotEmpty)
            'Headers': <Object?>[
              for (final entry in message.headers.entries)
                <String, Object?>{'Name': entry.key, 'Value': entry.value},
            ],
        })),
      );
}

/// Sends through an SMTP server.
///
/// Unlike the HTTP providers this speaks the SMTP protocol over a raw socket,
/// so it is unavailable on web; constructing a connection there throws with the
/// HTTP alternatives named. STARTTLS is used automatically when the server
/// advertises it and the connection is not already secure.
class SmtpMailProvider implements DVMailProvider {
  final DVSmtpClient client;

  SmtpMailProvider({
    required String host,
    int port = 587,
    bool secure = false,
    String? username,
    String? password,
    String clientName = 'dartvel',
    DVSmtpConnect connect = dvConnectSmtp,
  }) : client = DVSmtpClient(
          host: host,
          port: port,
          secure: secure,
          username: username,
          password: password,
          clientName: clientName,
          connect: connect,
        );

  @override
  Future<void> send(DVMailMessage message) async {
    if (message.to.isEmpty) {
      throw ArgumentError.value(
        message.to,
        'to',
        'A mail message needs at least one recipient.',
      );
    }
    await client.send(
      envelopeFrom: message.from.email,
      recipients: <String>[for (final address in message.to) address.email],
      fromHeader: DVHttpMailProvider.formatAddress(message.from),
      toHeaders: <String>[
        for (final address in message.to)
          DVHttpMailProvider.formatAddress(address),
      ],
      subject: message.subject,
      text: message.text,
      html: message.html,
      headers: message.headers,
    );
  }
}

/// Amazon SES v2, signed with AWS Signature Version 4.
///
/// SES has no API-key auth, so this signs each request with the account's
/// credentials. Temporary credentials work too: a session token is included in
/// the signature when present.
class SesMailProvider extends DVHttpMailProvider {
  final DVAwsCredentials credentials;
  final String region;

  /// Injectable clock. SigV4 signatures are time-bound, so tests pin it.
  final DateTime Function() now;

  SesMailProvider({
    required this.credentials,
    required this.region,
    Uri? baseUrl,
    DateTime Function()? now,
    super.transport = dvSendHttpRequest,
  })  : now = now ?? DateTime.now,
        super(
          apiKey: '',
          baseUrl: baseUrl ?? Uri.https('email.$region.amazonaws.com'),
        );

  @override
  String get providerName => 'ses';

  @override
  DVHttpRequest buildRequest(DVMailMessage message) {
    final url = baseUrl.replace(path: '/v2/email/outbound-emails');
    final body = utf8.encode(jsonEncode(<String, Object?>{
      'FromEmailAddress': DVHttpMailProvider.formatAddress(message.from),
      'Destination': <String, Object?>{
        'ToAddresses': <String>[
          for (final address in message.to) address.email,
        ],
      },
      'Content': <String, Object?>{
        'Simple': <String, Object?>{
          'Subject': <String, Object?>{'Data': message.subject},
          'Body': <String, Object?>{
            'Text': <String, Object?>{'Data': message.text},
            if (message.html != null)
              'Html': <String, Object?>{'Data': message.html},
          },
        },
      },
    }));

    const baseHeaders = <String, String>{'content-type': 'application/json'};
    return DVHttpRequest(
      url: url,
      headers: <String, String>{
        ...baseHeaders,
        ...DVAwsSigV4.signedHeaders(
          method: 'POST',
          url: url,
          headers: baseHeaders,
          body: body,
          credentials: credentials,
          region: region,
          service: 'ses',
          timestamp: now(),
        ),
      },
      body: body,
    );
  }
}

/// Mailgun messages API. Unlike the others this is form-encoded, and it
/// authenticates with HTTP Basic using the literal user name `api`.
class MailgunMailProvider extends DVHttpMailProvider {
  final String domain;

  MailgunMailProvider({
    required super.apiKey,
    required this.domain,
    Uri? baseUrl,
    super.transport = dvSendHttpRequest,
  }) : super(baseUrl: baseUrl ?? Uri.https('api.mailgun.net'));

  @override
  String get providerName => 'mailgun';

  @override
  DVHttpRequest buildRequest(DVMailMessage message) {
    final credentials = base64Encode(utf8.encode('api:$apiKey'));
    return DVHttpRequest(
      url: baseUrl.replace(path: '/v3/$domain/messages'),
      headers: <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
        'authorization': 'Basic $credentials',
      },
      body: dvEncodeFormBody(<(String, String)>[
        ('from', DVHttpMailProvider.formatAddress(message.from)),
        for (final address in message.to)
          ('to', DVHttpMailProvider.formatAddress(address)),
        ('subject', message.subject),
        ('text', message.text),
        if (message.html != null) ('html', message.html!),
        for (final entry in message.headers.entries)
          ('h:${entry.key}', entry.value),
      ]),
    );
  }
}

class DVMemoryMailProvider implements DVMailProvider {
  final List<DVMailMessage> sent = <DVMailMessage>[];

  @override
  Future<void> send(DVMailMessage message) async {
    sent.add(message);
  }
}

class DVNotificationMail {
  static DVMailProvider? _provider;

  const DVNotificationMail();

  void useProvider(DVMailProvider provider) {
    _provider = provider;
  }

  Future<void> send(DVMailMessage message) {
    final provider = _provider;
    if (provider == null) {
      throw StateError(
        'No mail provider registered. Configure SMTP, a hosted mail provider, or an explicit local/test provider.',
      );
    }
    return provider.send(message);
  }
}

enum DVNotificationChannel {
  inApp,
  email,
  push,
  sms,
  webPush,
}

enum DVNotificationProviderKind {
  firebase,
  apns,
  webPush,
  sms,
  windows,
  macos,
  linux,
  tizen,
  webos,
  local,
}

class DVNotificationMessage {
  final String title;
  final String body;
  final Map<String, String> data;
  final List<DVNotificationChannel> channels;

  const DVNotificationMessage({
    required this.title,
    required this.body,
    this.data = const <String, String>{},
    this.channels = const <DVNotificationChannel>[DVNotificationChannel.inApp],
  });
}

abstract class DVNotificationProvider {
  DVNotificationProviderKind get kind;
  Future<void> send(String recipient, DVNotificationMessage message);
}

class DVSentNotification {
  final String recipient;
  final DVNotificationMessage message;

  const DVSentNotification({
    required this.recipient,
    required this.message,
  });
}

/// Supplies a short-lived OAuth2 access token for a push service.
///
/// Minting one requires signing a service-account JWT, which needs an RSA
/// implementation Dartvel does not bundle. Applications supply the token from
/// their own credentials layer instead, and it is fetched per send so an
/// expired token is never reused.
typedef DVAccessTokenSupplier = Future<String> Function();

/// Thrown when a push service rejects a notification.
class DVPushProviderException implements Exception {
  final String provider;
  final int? statusCode;
  final String message;
  final String? responseBody;

  const DVPushProviderException(
    this.provider,
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  /// True when the service says this device token is no longer valid, so the
  /// application should stop sending to it and prune its record.
  bool get isUnregisteredToken {
    if (statusCode == 404) return true;
    final body = responseBody;
    if (body == null) return false;
    return body.contains('UNREGISTERED') || body.contains('NOT_FOUND');
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVPushProviderException[$provider]$status: $message$body';
  }
}

/// Firebase Cloud Messaging, HTTP v1.
///
/// The recipient is an FCM registration token. A stale token surfaces as a
/// [DVPushProviderException] whose [DVPushProviderException.isUnregisteredToken]
/// is true, which is the signal to drop it rather than retry.
class FirebasePushProvider implements DVNotificationProvider {
  final String projectId;
  final DVAccessTokenSupplier accessToken;
  final Uri baseUrl;
  final DVHttpSend transport;

  FirebasePushProvider({
    required this.projectId,
    required this.accessToken,
    Uri? baseUrl,
    this.transport = dvSendHttpRequest,
  }) : baseUrl = baseUrl ?? Uri.https('fcm.googleapis.com');

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.firebase;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    if (recipient.trim().isEmpty) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'A push notification needs an FCM registration token.',
      );
    }

    final token = await accessToken();
    final response = await transport(
      DVHttpRequest(
        url: baseUrl.replace(path: '/v1/projects/$projectId/messages:send'),
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'message': <String, Object?>{
            'token': recipient,
            'notification': <String, Object?>{
              'title': message.title,
              'body': message.body,
            },
            if (message.data.isNotEmpty) 'data': message.data,
          },
        })),
      ),
    );

    if (!response.isSuccess) {
      throw DVPushProviderException(
        'firebase',
        'The push service rejected the notification.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}

/// Twilio SMS.
///
/// The recipient is the destination number in E.164 form (`+15551234567`).
/// [DVNotificationMessage] carries a title and a body; SMS has no title, so a
/// non-empty title is prefixed on its own line rather than dropped.
class TwilioSmsProvider implements DVNotificationProvider {
  final String accountSid;
  final String authToken;

  /// The sending number, in E.164 form.
  final String? fromNumber;

  /// A Twilio Messaging Service, used instead of a single sending number.
  final String? messagingServiceSid;

  final Uri baseUrl;
  final DVHttpSend transport;

  TwilioSmsProvider({
    required this.accountSid,
    required this.authToken,
    this.fromNumber,
    this.messagingServiceSid,
    Uri? baseUrl,
    this.transport = dvSendHttpRequest,
  }) : baseUrl = baseUrl ?? Uri.https('api.twilio.com') {
    if ((fromNumber == null) == (messagingServiceSid == null)) {
      throw ArgumentError(
        'Provide exactly one of fromNumber or messagingServiceSid.',
      );
    }
  }

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.sms;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    if (recipient.trim().isEmpty) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'An SMS needs a destination number.',
      );
    }

    final credentials = base64Encode(utf8.encode('$accountSid:$authToken'));
    final response = await transport(DVHttpRequest(
      url: baseUrl.replace(
        path: '/2010-04-01/Accounts/$accountSid/Messages.json',
      ),
      headers: <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
        'accept': 'application/json',
        'authorization': 'Basic $credentials',
      },
      body: dvEncodeFormBody(<(String, String)>[
        ('To', recipient.trim()),
        if (fromNumber case final from?) ('From', from),
        if (messagingServiceSid case final service?)
          ('MessagingServiceSid', service),
        ('Body', smsBody(message)),
      ]),
    ));

    if (!response.isSuccess) {
      throw DVPushProviderException(
        'twilio',
        _describe(response.body),
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// SMS has no subject line, so a title becomes the first line.
  static String smsBody(DVNotificationMessage message) =>
      message.title.trim().isEmpty
          ? message.body
          : '${message.title}\n${message.body}';

  static String _describe(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?> && decoded['message'] is String) {
        final code = decoded['code'];
        return code == null
            ? decoded['message']! as String
            : '${decoded['message']} (Twilio code $code)';
      }
    } on FormatException {
      // Fall through to the generic message below.
    }
    return 'Twilio rejected the message.';
  }
}

class DVMemoryNotificationProvider implements DVNotificationProvider {
  final List<DVSentNotification> sent = <DVSentNotification>[];

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.local;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    sent.add(DVSentNotification(recipient: recipient, message: message));
  }
}

class DVNotificationsService {
  static final Map<DVNotificationProviderKind, DVNotificationProvider>
      _providers = {};

  const DVNotificationsService();

  DVNotificationMail get mail => const DVNotificationMail();

  void register(DVNotificationProvider provider) {
    _providers[provider.kind] = provider;
  }

  Future<void> send(
    String recipient,
    DVNotificationMessage message, {
    DVNotificationProviderKind provider = DVNotificationProviderKind.local,
  }) {
    final selected = _providers[provider];
    if (selected == null) {
      throw StateError('No notification provider registered for $provider.');
    }
    return selected.send(recipient, message);
  }
}

class DVAuthAuthorization {
  static final Map<String, FutureOr<bool> Function(Object?, Object?)>
      _policies = {};

  const DVAuthAuthorization();

  void register<TUser, TResource>(
    String action,
    DVPolicyCheck<TUser, TResource> check,
  ) {
    _policies['$action:${TResource.toString()}'] =
        (user, resource) => check(user as TUser, resource as TResource);
  }

  Future<bool> can<TUser, TResource>(
    TUser user,
    String action,
    TResource resource,
  ) async {
    final check = _policies['$action:${TResource.toString()}'];
    if (check == null) return false;
    return check(user, resource);
  }

  Future<void> authorize<TUser, TResource>(
    TUser user,
    String action,
    TResource resource,
  ) async {
    if (!await can<TUser, TResource>(user, action, resource)) {
      throw StateError('Action "$action" is not authorized for $TResource.');
    }
  }
}

class DVCacheTags {
  static final Map<String, Set<String>> _tags = {};

  const DVCacheTags();

  void tag(String key, Iterable<String> tags) {
    for (final tag in tags) {
      (_tags[tag] ??= <String>{}).add(key);
    }
  }

  Set<String> keysForTag(String tag) {
    return Set<String>.unmodifiable(_tags[tag] ?? const <String>{});
  }

  Set<String> revalidateTag(String tag) {
    final keys = _tags.remove(tag) ?? const <String>{};
    return Set<String>.unmodifiable(keys);
  }

  void clear() {
    _tags.clear();
  }
}

class DVTestHarness {
  const DVTestHarness();

  DVInMemoryQueueAdapter fakeQueue() {
    final adapter = DVInMemoryQueueAdapter();
    const DVQueues().useAdapter(adapter);
    DVQueues._handlers.clear();
    return adapter;
  }

  DVMemoryMailProvider fakeMail() {
    final provider = DVMemoryMailProvider();
    const DVNotificationMail().useProvider(provider);
    return provider;
  }

  DVMemoryNotificationProvider fakeNotifications() {
    final provider = DVMemoryNotificationProvider();
    const DVNotificationsService().register(provider);
    return provider;
  }

  void resetQueues() {
    fakeQueue();
  }

  void resetSignals() {
    resetQueues();
  }

  void resetPolicies() {
    DVAuthAuthorization._policies.clear();
  }

  void resetCacheTags() {
    DVCacheTags._tags.clear();
  }

  void resetAITools() {
    const DVAIToolRegistry().clear();
  }

  void resetMail() {
    const DVNotificationMail().useProvider(DVMemoryMailProvider());
  }

  void clearMailProvider() {
    DVNotificationMail._provider = null;
  }

  void resetNotifications() {
    DVNotificationsService._providers
      ..clear()
      ..[DVNotificationProviderKind.local] = DVMemoryNotificationProvider();
  }

  void clearNotificationProviders() {
    DVNotificationsService._providers.clear();
  }
}
