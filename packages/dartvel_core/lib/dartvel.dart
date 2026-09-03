library dartvel_core;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'src/ai/ai.dart';
import 'src/secrets/secrets.dart';
import 'src/database/adapter.dart';
import 'src/http/aws_sigv4.dart';
import 'src/http/flat_buffer.dart';
import 'src/http/transport.dart';
// import 'dart:io'; // Removed to avoid breaking web builds
import 'src/http/wintercg.dart' as dv;
import 'src/mail/smtp.dart';
import 'src/notifications/web_push.dart';
import 'src/notifications/web_push_vapid.dart';
import 'src/scheduling/cron.dart';
import 'src/search/search_tuning.dart';

export 'src/ai/ai.dart';
export 'src/ai/mcp.dart';
export 'src/analytics/analytics.dart';
export 'src/annotations/annotations.dart';
export 'src/auth/auth.dart';
export 'src/billing/paddle.dart';
export 'src/billing/stripe.dart';
// LDAP is a raw TCP protocol, so a browser cannot speak it. Exported
// unconditionally this pulls dart:io into every web build, which is what broke
// the site build -- as a cascade of unrelated type errors in another file
// rather than as anything mentioning dart:io.
export 'src/auth/ldap_unsupported.dart'
    if (dart.library.io) 'src/auth/ldap.dart';
export 'src/auth/oauth2.dart';
export 'src/auth/password.dart';
export 'src/auth/saml.dart';
export 'src/auth/tokens.dart';
export 'src/auth/web3.dart';
export 'src/auth/webauthn.dart';
export 'src/cache/adapters.dart';
export 'src/cache/distributed.dart';
export 'src/cache/memcached.dart';
export 'src/cache/redis.dart';
export 'src/crypto/app_key.dart';
export 'src/crypto/key_stores.dart';
export 'src/database/adapters.dart';
export 'src/database/mysql.dart';
export 'src/database/postgres.dart';
export 'src/diagnostics/startup_profile.dart';
export 'src/graphql/graphql.dart';
export 'src/http/aws_sigv4.dart';
export 'src/http/flat_buffer.dart';
// Conditional, because the native client needs dart:ffi and web has none.
// Exporting it unconditionally broke the web build with "Dart library
// 'dart:ffi' is not available on this platform", and nothing noticed because
// nothing built web afterwards.
export 'src/http/native_client_web.dart'
    if (dart.library.ffi) 'src/http/native_client.dart';
export 'src/http/transport.dart';
// Re-export common types so backends can import only dartvel_core.
// The wire types live here now. dartvel_core is on both sides of the wire, so
// owning them is what lets a frontend depend on nothing else -- it used to
// reach into dartvel_shelf for three type names and acquire a server package
// along with them.
// Three names, which is the surface this barrel has always had. `Body` and
// `URLPattern` are generic enough that exporting them here collides with
// application code -- it broke the Dartvel site, which has its own `Body`
// widget. Server code that wants the full set imports
// `package:dartvel_core/http.dart`.
export 'src/http/wintercg.dart' show Request, Response, Headers;
export 'src/data/import_chunking.dart';
export 'src/diagnostics/diagnostics.dart';
export 'src/i18n/locale_negotiation.dart';
export 'src/i18n/plural_rules.dart';
export 'src/kiosk/enforcement.dart';
export 'src/kiosk/policy.dart';
export 'src/kiosk/runtime.dart';
export 'src/lifecycle/lifecycle.dart';
export 'src/mail/smtp.dart';
export 'src/media/image.dart';
export 'src/modules/modules.dart';
export 'src/notifications/web_push.dart';
export 'src/notifications/web_push_vapid.dart';
export 'src/observability/observability.dart';
export 'src/platform_config.dart';
export 'src/queues/redis_queue.dart';
export 'src/scheduling/cron.dart';
export 'src/scheduling/scheduler.dart';
export 'src/search/postgres_search.dart';
export 'src/search/search_tuning.dart';
export 'src/secrets/secrets.dart';
export 'src/shell/shell.dart';
export 'src/storage/adapters.dart';
export 'src/storage/azure_blob.dart';
export 'src/storage/gcs.dart';
export 'src/sync/model_sync.dart';
export 'src/sync/presence.dart';
export 'src/tenancy/tenants.dart';
export 'src/transaction/transaction.dart';
export 'src/updates/ota.dart';
export 'src/web/page_data.dart';
export 'src/web/page_text.dart';
export 'src/web/seo_head.dart';
export 'src/windowing/single_instance.dart';

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
            } else if (part.headers['content-type'] == dvFlatContentType) {
              // A field packed as a binary flat buffer, which is what the
              // transport spec asks for: over text multipart every value
              // arrives as a String and the type is gone by the time a
              // parameter is decoded.
              //
              // A damaged buffer is refused rather than falling back to text.
              // Handing a parameter the raw bytes of a corrupt envelope is
              // exactly the plausible-looking wrong value this is meant to
              // prevent.
              final bytes =
                  await part.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
              data[name] = dvFlatDecode(Uint8List.fromList(bytes));
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
    this.highlights = const <String>[],
    this.facetCounts = const <String, Map<String, int>>{},
  });

  /// One highlighted document per item, in the same order.
  ///
  /// Empty when the provider does not highlight; never a different length from
  /// [items], because a list that drifts attributes one record's snippet to
  /// another and still renders.
  final List<String> highlights;

  /// How many results each facet value would leave, keyed by facet then value.
  ///
  /// Describes the current query rather than the whole corpus: a count that
  /// ignores the query offers narrowing that returns nothing.
  final Map<String, Map<String, int>> facetCounts;
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

  /// Facet name to the value a record carries for it, used for counts.
  final Map<String, String Function(TModel)> facetValues;

  /// Synonyms, typo tolerance and highlight markers.
  final DVSearchTuning tuning;

  DVInMemorySearchProvider({
    required List<TModel> records,
    required this.document,
    this.facetMatcher,
    // Not a const default: TModel is a type variable, which a const literal
    // cannot mention.
    Map<String, String Function(TModel)>? facetValues,
    this.tuning = const DVSearchTuning(),
  })  : records = List<TModel>.unmodifiable(records),
        facetValues =
            facetValues ?? <String, String Function(TModel)>{};

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

    final String needle = query.trim();
    final List<String> terms = needle.isEmpty
        ? const <String>[]
        : tuning.expand(needle);

    bool documentMatches(TModel record) {
      if (terms.isEmpty) return true;
      final String text = document(record).toLowerCase();
      for (final String term in terms) {
        if (text.contains(term)) return true;
        // A typo has to be compared word by word: the whole document is never
        // within an edit or two of a single term.
        for (final String word in text.split(RegExp(r'[^A-Za-z0-9]+'))) {
          if (word.isEmpty) continue;
          if (dvTypoMatches(term, word, enabled: tuning.typoTolerance)) {
            return true;
          }
        }
      }
      return false;
    }

    // Facet counts describe what the text query found, before the facet
    // filter narrows it -- otherwise every count but the selected one is zero
    // and the UI can only ever narrow further.
    final List<TModel> textMatches =
        records.where(documentMatches).toList(growable: false);

    final matches = textMatches
        .where((TModel record) => facetMatcher?.call(record, facets) ?? true)
        .toList(growable: false);

    final start = (page - 1) * perPage;
    final end =
        start + perPage > matches.length ? matches.length : start + perPage;
    final pageItems =
        start >= matches.length ? <TModel>[] : matches.sublist(start, end);

    final Map<String, Map<String, int>> counts =
        <String, Map<String, int>>{};
    for (final MapEntry<String, String Function(TModel)> facet
        in facetValues.entries) {
      final Map<String, int> byValue = <String, int>{};
      for (final TModel record in textMatches) {
        final String value = facet.value(record);
        byValue[value] = (byValue[value] ?? 0) + 1;
      }
      counts[facet.key] = byValue;
    }

    return DVSearchResultPage<TModel>(
      items: List<TModel>.unmodifiable(pageItems),
      total: matches.length,
      page: page,
      perPage: perPage,
      highlights: List<String>.unmodifiable(
        pageItems.map(
          (TModel record) => dvHighlight(
            document(record),
            terms,
            pre: tuning.highlightPre,
            post: tuning.highlightPost,
          ),
        ),
      ),
      facetCounts: Map<String, Map<String, int>>.unmodifiable(counts),
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
  /// Reads facet counts out of an engine-shaped `{facet: {value: count}}`.
  ///
  /// The result page declares these, and until now no hosted provider filled
  /// them: a caller asking for facet counts got an empty map from every hosted
  /// engine and a populated one from the local provider, which is worse than
  /// either answer on its own.
  static Map<String, Map<String, int>> readFacetCounts(Object? source) {
    if (source is! Map) return const <String, Map<String, int>>{};
    final counts = <String, Map<String, int>>{};
    source.forEach((Object? facet, Object? values) {
      if (values is! Map) return;
      counts['$facet'] = <String, int>{
        for (final MapEntry<Object?, Object?> e in values.entries)
          if (e.value is int) '${e.key}': e.value! as int,
      };
    });
    return Map<String, Map<String, int>>.unmodifiable(counts);
  }

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
    this.facetFields = const <String>[],
    this.tuning = const DVSearchTuning(),
  });

  /// Fields to return counts for. Meilisearch returns counts only for fields
  /// the query names *and* the index lists as filterable.
  final List<String> facetFields;

  /// Supplies the highlight markers; the engine does the matching.
  final DVSearchTuning tuning;

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
          // Omitted when empty. A Meilisearch with no master key configured
          // rejects `Bearer ` with "The provided API key is invalid", so an
          // empty key is worse than no header: it fails every request rather
          // than none.
          if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(<String, Object?>{
          'q': query,
          'page': page,
          'hitsPerPage': perPage,
          if (filters.isNotEmpty) 'filter': filters,
          // Asked for explicitly. Meilisearch returns neither unless the query
          // requests them, so a provider that only reads the response finds
          // nothing there and reports no highlights and no counts.
          'attributesToHighlight': const <String>['*'],
          'highlightPreTag': tuning.highlightPre,
          'highlightPostTag': tuning.highlightPost,
          if (facetFields.isNotEmpty) 'facets': facetFields,
        })),
      );

  @override
  DVSearchResultPage<TModel> readResponse(
    Map<String, Object?> payload,
    int page,
    int perPage,
  ) {
    final hits = payload['hits'];
    final highlights = <String>[];
    if (hits is List) {
      for (final Object? hit in hits) {
        final Object? formatted =
            hit is Map ? hit['_formatted'] : null;
        highlights.add(
          formatted is Map
              ? formatted.values.whereType<String>().join(' ')
              : '',
        );
      }
    }

    return DVSearchResultPage<TModel>(
      items: readHits(payload, 'hits'),
      // estimatedTotalHits is the default; totalHits appears only when the
      // query asks to be exhaustive, so both are read.
      total: payload['totalHits'] is int
          ? payload['totalHits']! as int
          : payload['estimatedTotalHits'] is int
              ? payload['estimatedTotalHits']! as int
              : readHits(payload, 'hits').length,
      page: page,
      perPage: perPage,
      highlights: List<String>.unmodifiable(highlights),
      facetCounts: DVHttpSearchProvider.readFacetCounts(
        payload['facetDistribution'],
      ),
    );
  }
}

/// Algolia query endpoint.
///
/// Algolia pages are zero-based while Dartvel's contract is one-based, so the
/// page number is translated in both directions.
class AlgoliaSearchProvider<TModel, TFacets>
    extends DVHttpSearchProvider<TModel, TFacets> {
  final String applicationId;

  /// Attributes to return counts for.
  final List<String> facetFields;

  /// Supplies the highlight markers; the engine does the matching.
  final DVSearchTuning tuning;

  AlgoliaSearchProvider({
    required this.applicationId,
    required super.apiKey,
    required super.indexName,
    required super.fromJson,
    this.facetFields = const <String>[],
    this.tuning = const DVSearchTuning(),
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
          'highlightPreTag': tuning.highlightPre,
          'highlightPostTag': tuning.highlightPost,
          if (facetFields.isNotEmpty) 'facets': facetFields,
          // Only sent when off: on is Algolia's default, and sending the
          // default back is noise in every request.
          if (!tuning.typoTolerance) 'typoTolerance': false,
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
        highlights: List<String>.unmodifiable(<String>[
          for (final Object? hit
              in (payload['hits'] is List ? payload['hits']! as List : const []))
            if (hit is Map && hit['_highlightResult'] is Map)
              (hit['_highlightResult']! as Map)
                  .values
                  .whereType<Map>()
                  .map((Map v) => v['value'])
                  .whereType<String>()
                  .join(' ')
            else
              '',
        ]),
        facetCounts: DVHttpSearchProvider.readFacetCounts(payload['facets']),
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

  /// Keyword fields to aggregate on for counts.
  final List<String> facetFields;

  /// Supplies the highlight markers; the engine does the matching.
  final DVSearchTuning tuning;

  final String? username;
  final String? password;

  const OpenSearchProvider({
    required super.baseUrl,
    required super.indexName,
    required super.fromJson,
    super.apiKey = '',
    this.searchFields = const <String>['*'],
    this.facetFields = const <String>[],
    this.tuning = const DVSearchTuning(),
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
          'highlight': <String, Object?>{
            'pre_tags': <String>[tuning.highlightPre],
            'post_tags': <String>[tuning.highlightPost],
            'fields': <String, Object?>{'*': <String, Object?>{}},
          },
          if (facetFields.isNotEmpty)
            'aggs': <String, Object?>{
              // A terms aggregation must name a keyword field. Pointed at an
              // analysed text field it counts word fragments, and returns
              // plausible numbers for values nobody stored.
              for (final field in facetFields)
                field: <String, Object?>{
                  'terms': <String, Object?>{'field': field},
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
      highlights: List<String>.unmodifiable(<String>[
        for (final Object? row in rows)
          if (row is Map && row['highlight'] is Map)
            (row['highlight']! as Map)
                .values
                .whereType<List<Object?>>()
                .expand((List<Object?> l) => l.whereType<String>())
                .join(' ')
          else
            '',
      ]),
      facetCounts: <String, Map<String, int>>{
        // Elasticsearch reports a terms aggregation as a bucket list rather
        // than as the value/count map every other engine uses.
        for (final MapEntry<String, Object?> agg
            in (payload['aggregations'] is Map<String, Object?>
                    ? payload['aggregations']! as Map<String, Object?>
                    : const <String, Object?>{})
                .entries)
          if (agg.value is Map && (agg.value! as Map)['buckets'] is List)
            agg.key: <String, int>{
              for (final Object? bucket
                  in (agg.value! as Map)['buckets']! as List<Object?>)
                if (bucket is Map &&
                    bucket['key'] != null &&
                    bucket['doc_count'] is int)
                  '${bucket['key']}': bucket['doc_count']! as int,
            },
      },
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
  /// Entitlement ids held, by customer.
  final Map<String, Set<String>> _grants = <String, Set<String>>{};
  var _nextSession = 0;

  /// Who holds what, for an entitlements view.
  ///
  /// `hasEntitlement` answers one pair at a time, so a customer who lost
  /// access and one who never had it are indistinguishable without this.
  Map<String, Set<String>> get grants => Map<String, Set<String>>.unmodifiable(
        <String, Set<String>>{
          for (final entry in _grants.entries)
            entry.key: Set<String>.unmodifiable(entry.value),
        },
      );

  void grant(Object customer, Entitlement entitlement) {
    (_grants[_customerKey(customer)] ??= <String>{}).add(entitlement.id);
  }

  void revoke(Object customer, Entitlement entitlement) {
    final held = _grants[_customerKey(customer)];
    if (held == null) return;
    held.remove(entitlement.id);
    if (held.isEmpty) _grants.remove(_customerKey(customer));
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
    return _grants[_customerKey(customer)]?.contains(entitlement.id) ?? false;
  }

  /// Identity, not hash. Keying grants by `customer.hashCode` meant two
  /// customers whose hashes collided shared entitlements — one paying for a
  /// plan could unlock it for a stranger — and made the stored keys
  /// unreadable to anything inspecting them.
  String _customerKey(Object customer) => customer.toString();
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

  /// The header line, for a format that has one.
  ///
  /// Carried on every chunk rather than only the first. Without it a worker
  /// handed chunk 2 of a CSV has no column order and cannot build a record --
  /// which is why resumable CSV import could not work at all.
  final String? header;

  const DVImportChunk({
    required this.model,
    required this.format,
    required this.startRow,
    required this.rows,
    this.header,
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

  /// The parsed schedule.
  ///
  /// The cron used to be stored and never read, so
  /// `scheduleMonthly(cron: '0 8 1 * *')` and
  /// `scheduleMonthly(cron: 'every month')` were indistinguishable: both
  /// produced a payload, both dispatched, and nothing evaluated either.
  ///
  /// Throws naming the report as well as the string, because the string alone
  /// could belong to any of a dozen schedules and the name is what a person
  /// needs to find the declaration.
  DVCronSchedule get schedule {
    try {
      return DVCronSchedule.parse(cron);
    } on FormatException catch (error) {
      throw FormatException(
        'Scheduled report "$name" has an unparseable cron "$cron": '
        '${error.message}',
      );
    }
  }

  /// The next time this report is due after [from], or null if never.
  ///
  /// Null is a real answer: the 31st of February parses and occurs never, and
  /// a report scheduled for it should say so rather than be asked forever.
  DateTime? nextRunAfter(DateTime from) => schedule.nextAfter(from);

  bool isDue(DateTime at) => schedule.matches(at);
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

  /// Drops one dead-lettered job. Flushing a queue to be rid of a single
  /// poison message would take every other job with it.
  Future<bool> discard(String id);

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
  Future<bool> discard(String id) async {
    for (final entry in _deadLetters.entries) {
      final index = entry.value.indexWhere((job) => job.id == id);
      if (index == -1) continue;
      entry.value.removeAt(index);
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

  /// The codec name registered for [TPayload], or null when none is.
  ///
  /// Public so a queue adapter can live outside this library and still use
  /// the one registry — a second registry would drift from this one.
  String? nameFor<TPayload>() => _byType[TPayload]?.name;

  /// Encodes [payload] with its registered codec.
  ///
  /// Throws when nothing is registered: a durable queue that silently
  /// dropped an unencodable payload would lose work with no trace.
  Map<String, Object?> encodeFor<TPayload>(TPayload payload) {
    final codec = _byType[TPayload];
    if (codec == null) {
      throw StateError(
        'No DVJobPayloadCodec registered for $TPayload, so it cannot be '
        'persisted. Register one, or use DVInMemoryQueueAdapter.',
      );
    }
    return codec.encode(payload);
  }

  /// Decodes a payload previously encoded under [name].
  ///
  /// Returns null for an unknown name, which happens when a job outlives the
  /// code that could read it — the caller decides whether that is a
  /// dead-letter or a deploy skew to wait out.
  DVJobPayload? decodeNamed(String name, Map<String, Object?> json) =>
      _byName[name]?.decode(json);

  /// The runtime type registered under [name], for rebuilding an envelope.
  Type? typeNamed(String name) => _byName[name]?.type;

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
  Future<bool> discard(String id) async {
    await initialize();
    // Scoped to dead-lettered rows: discarding a job that is queued or
    // running would delete work nobody asked to abandon.
    final removed = await database.execute(
      'DELETE FROM $tableName WHERE id = ? AND state = ?',
      <Object?>[id, DVJobState.deadLettered.name],
    );
    return removed > 0;
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

  /// Drops one dead-lettered job, for a message that will never succeed.
  Future<bool> discard(String id) {
    return _adapter.discard(id);
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

/// Which APNS environment a device token belongs to.
///
/// A token minted by a development build is not valid in production and vice
/// versa, and the failure is a `BadDeviceToken` that says nothing about which
/// half is wrong — so this is explicit rather than inferred.
enum ApnsEnvironment {
  production('api.push.apple.com'),
  sandbox('api.sandbox.push.apple.com');

  const ApnsEnvironment(this.host);

  final String host;
}

/// What kind of notification is being delivered.
///
/// Required by APNS on iOS 13 and later, and rejected outright when it does
/// not match the payload — a `background` push carrying an alert is an error,
/// not a warning.
enum ApnsPushType {
  alert,
  background,
  location,
  voip,
  complication,
  fileprovider,
  mdm,
  liveactivity,
  pushtotalk;

  String get wireName => name;
}

/// Apple Push Notification service.
///
/// The recipient is the hex device token. Delivery is **HTTP/2 only** — Apple
/// operates no HTTP/1.1 endpoint — which is why this provider pins
/// [DVHttpProtocolChain.http2Only] rather than accepting the default chain. A
/// silent downgrade would surface as a connection error that could not explain
/// itself.
///
/// Authorization is a bearer JWT signed with ES256 over an Apple `.p8` key.
/// Signing that needs an ECDSA implementation Dartvel does not bundle, so the
/// token comes from the application's own credentials layer and is fetched per
/// send — the same arrangement [FirebasePushProvider] uses, and for the same
/// reason. Apple accepts a token for one hour and refuses one older than that,
/// so a supplier that caches should refresh well inside the hour.
class ApnsPushProvider implements DVNotificationProvider {
  /// The app's bundle identifier, sent as `apns-topic`.
  final String topic;

  /// Supplies the bearer JWT.
  final DVAccessTokenSupplier accessToken;

  final ApnsEnvironment environment;

  final ApnsPushType pushType;

  /// 10 delivers immediately; 5 lets the device batch for power. APNS requires
  /// 5 for a `background` push and rejects 10.
  final int priority;

  final DVHttpSend transport;

  ApnsPushProvider({
    required this.topic,
    required this.accessToken,
    this.environment = ApnsEnvironment.production,
    this.pushType = ApnsPushType.alert,
    int? priority,
    this.transport = dvSendHttpRequest,
  }) : priority = priority ??
            (pushType == ApnsPushType.background ? 5 : 10);

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.apns;

  /// The APNS payload for [message].
  ///
  /// Custom data goes at the top level, as a sibling of `aps` — nesting it
  /// inside `aps` is the usual mistake, and Apple silently ignores unknown
  /// keys there rather than reporting them.
  Map<String, Object?> buildPayload(DVNotificationMessage message) {
    return <String, Object?>{
      'aps': <String, Object?>{
        if (pushType == ApnsPushType.background)
          'content-available': 1
        else
          'alert': <String, Object?>{
            'title': message.title,
            'body': message.body,
          },
      },
      ...message.data,
    };
  }

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    final deviceToken = recipient.trim();
    if (deviceToken.isEmpty) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'An APNS notification needs a device token.',
      );
    }

    final token = await accessToken();
    final response = await transport(
      DVHttpRequest(
        url: Uri.https(environment.host, '/3/device/$deviceToken'),
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'bearer $token',
          'apns-topic': topic,
          'apns-push-type': pushType.wireName,
          'apns-priority': '$priority',
        },
        body: utf8.encode(jsonEncode(buildPayload(message))),
        // Apple runs no HTTP/1.1 endpoint. Falling back would fail at a layer
        // that cannot say why.
        protocols: DVHttpProtocolChain.http2Only,
      ),
    );

    if (!response.isSuccess) {
      throw DVPushProviderException(
        'apns',
        apnsFailureReason(response),
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}

/// A readable explanation for an APNS rejection.
///
/// Apple answers failures with `{"reason": "BadDeviceToken"}` and nothing else,
/// which is precise and unhelpful in a log. The few reasons that mean something
/// an operator should act on are spelled out; the rest are passed through so a
/// new one is never swallowed.
String apnsFailureReason(DVHttpResponse response) {
  final data = response.data;
  final reason = data is Map ? data['reason'] : null;
  if (reason is! String || reason.isEmpty) {
    return 'The push service rejected the notification.';
  }
  return switch (reason) {
    'BadDeviceToken' =>
      'BadDeviceToken: the token is malformed, or belongs to the other APNS '
          'environment than the one configured.',
    'Unregistered' =>
      'Unregistered: the app was uninstalled or the token expired. Stop '
          'sending to it.',
    'TopicDisallowed' =>
      'TopicDisallowed: apns-topic does not match the key\'s app.',
    'ExpiredProviderToken' =>
      'ExpiredProviderToken: the bearer JWT is older than one hour.',
    'InvalidProviderToken' =>
      'InvalidProviderToken: the JWT signature or key id was rejected.',
    'PayloadTooLarge' =>
      'PayloadTooLarge: APNS caps a payload at 4KB (5KB for VoIP).',
    _ => reason,
  };
}

/// Web Push, per RFC 8291 (encryption) and RFC 8292 (VAPID).
///
/// The recipient is the browser subscription as JSON, exactly as
/// `PushManager.subscribe()` produced it. It is not a token that can be posted
/// to: the push service is untrusted infrastructure that never sees the
/// plaintext, so the payload is encrypted to a key only the subscribing user
/// agent holds, and the request is signed so the service knows which
/// application server is sending.
///
/// Both halves already exist as [DVWebPush] and [DVWebPushVapid]; this is what
/// puts them on the wire together. Neither is optional — an unencrypted body
/// is a protocol error rather than a degraded mode, and an unsigned POST is
/// refused because anyone who learned the endpoint could otherwise send to it.
class WebPushProvider implements DVNotificationProvider {
  /// The application server's identity key. **Stable across sends**: it is the
  /// public half of this pair that the browser pinned at subscribe time, so
  /// rotating it invalidates every existing subscription.
  final DVWebPushKeyPair vapidKeys;

  /// A `mailto:` or `https:` contact for whoever operates this server. Push
  /// services require one so they can report abuse to a human.
  final String subject;

  /// How long a message may wait if the device is offline.
  final Duration timeToLive;

  final DVHttpSend transport;

  WebPushProvider({
    required this.vapidKeys,
    required this.subject,
    this.timeToLive = const Duration(hours: 24),
    this.transport = dvSendHttpRequest,
  });

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.webPush;

  /// The payload a service worker receives in its `push` event.
  Map<String, Object?> buildPayload(DVNotificationMessage message) =>
      <String, Object?>{
        'title': message.title,
        'body': message.body,
        if (message.data.isNotEmpty) 'data': message.data,
      };

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    final subscription = _parseSubscription(recipient);

    // A fresh key pair per message, which is what stops one recovered key
    // from opening every message ever sent. Distinct from the VAPID pair,
    // which must stay stable — conflating them is the mistake that silently
    // breaks every subscription on the next send.
    final encrypted = DVWebPush.encrypt(
      subscription: subscription,
      payload: utf8.encode(jsonEncode(buildPayload(message))),
    );

    final response = await transport(
      DVHttpRequest(
        url: Uri.parse(subscription.endpoint),
        headers: <String, String>{
          ...encrypted.headers,
          'authorization': DVWebPushVapid.authorizationHeader(
            endpoint: subscription.endpoint,
            keyPair: vapidKeys,
            subject: subject,
          ),
          'ttl': '${timeToLive.inSeconds}',
        },
        body: encrypted.body,
      ),
    );

    if (!response.isSuccess) {
      throw DVPushProviderException(
        'webPush',
        webPushFailureReason(response),
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  DVWebPushSubscription _parseSubscription(String recipient) {
    if (recipient.trim().isEmpty) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'A Web Push notification needs the browser subscription JSON.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(recipient);
    } on FormatException catch (error) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'A Web Push recipient is the subscription JSON from '
            'PushManager.subscribe(): $error',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ArgumentError.value(
        recipient,
        'recipient',
        'A Web Push subscription is a JSON object.',
      );
    }
    return DVWebPushSubscription.fromJson(decoded);
  }
}

/// A readable explanation for a push service rejection.
///
/// Push services answer with a status and little else, and the statuses that
/// matter mean different things here than they do elsewhere — a 410 is not a
/// missing page, it is an instruction to stop sending to this subscription
/// forever.
String webPushFailureReason(DVHttpResponse response) {
  return switch (response.statusCode) {
    404 || 410 =>
      'The subscription is gone: the user revoked permission or cleared site '
          'data. Delete it rather than retrying.',
    413 =>
      'Payload too large. A push service guarantees only 4KB of encrypted '
          'payload.',
    429 => 'Rate limited by the push service. Honour Retry-After.',
    401 || 403 =>
      'VAPID rejected: the signature, the subject, or the key does not match '
          'the one the browser subscribed with.',
    _ => 'The push service rejected the notification.',
  };
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

  /// Every registered policy, as `action:ResourceType`.
  ///
  /// `can` answers one question at a time and returns false for a policy that
  /// was never registered, which is indistinguishable from a policy that
  /// denied. Enumerating them is how that distinction becomes visible.
  Set<String> get registeredPolicies => Set<String>.unmodifiable(_policies.keys);

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

  /// Every tag that currently has keys under it.
  ///
  /// Without this a tag can only be inspected by already knowing its name,
  /// which is no use to an operator asking what is cached.
  Set<String> get tags => Set<String>.unmodifiable(_tags.keys);

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

  /// Supplies [secrets] for the duration of [body], then puts everything
  /// back -- values that were there before, values that were not, and any
  /// rotation hook the body registered.
  ///
  /// So a suite never depends on the developer's environment, and a forgotten
  /// override cannot leak into the next test. Restores on a throw too.
  Future<T> withSecrets<T>(
    Map<String, String> secrets,
    FutureOr<T> Function() body,
  ) async {
    final DVSecretsState before = DVSecrets.captureState();
    DVSecrets.configure(secrets);
    try {
      return await body();
    } finally {
      DVSecrets.restoreState(before);
    }
  }

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
