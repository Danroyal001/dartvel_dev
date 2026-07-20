library dartvel_core;

import 'dart:async';
import 'dart:convert';
// import 'dart:io'; // Removed to avoid breaking web builds
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

// Re-export common types so backends can import only dartvel_core.
export 'package:dartvel_shelf/dartvel_shelf.dart'
    show Request, Response, Headers;

export 'src/analytics/analytics.dart';
export 'src/annotations/annotations.dart';
export 'src/auth/auth.dart';
export 'src/platform_config.dart';
export 'src/shell/shell.dart';
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

typedef DVJsonObject = Map<String, DVJsonValue>;
typedef DVAIToolHandler = FutureOr<DVJsonValue> Function(DVJsonObject input);

sealed class DVJsonValue {
  const DVJsonValue();
}

class DVJsonNull extends DVJsonValue {
  const DVJsonNull();
}

class DVJsonString extends DVJsonValue {
  final String value;
  const DVJsonString(this.value);
}

class DVJsonNumber extends DVJsonValue {
  final num value;
  const DVJsonNumber(this.value);
}

class DVJsonBool extends DVJsonValue {
  final bool value;
  const DVJsonBool(this.value);
}

class DVJsonList extends DVJsonValue {
  final List<DVJsonValue> value;
  const DVJsonList(this.value);
}

class DVJsonMap extends DVJsonValue {
  final DVJsonObject value;
  const DVJsonMap(this.value);
}

class DVAIToolRegistry {
  static final Map<String, DVAIToolHandler> _handlers = {};

  const DVAIToolRegistry();

  void register(String name, DVAIToolHandler handler) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'AI tool names cannot be empty.');
    }
    _handlers[name] = handler;
  }

  bool contains(String name) => _handlers.containsKey(name);

  List<String> get names => List<String>.unmodifiable(_handlers.keys);

  Future<DVJsonValue> call(String name, [DVJsonObject input = const {}]) async {
    final handler = _handlers[name];
    if (handler == null) {
      throw StateError('No AI tool registered for "$name".');
    }
    return handler(input);
  }

  void clear() {
    _handlers.clear();
  }
}

class DVAITranscript {
  final String text;
  final String language;
  final Duration duration;
  final DVJsonObject metadata;

  const DVAITranscript({
    required this.text,
    this.language = 'und',
    this.duration = Duration.zero,
    this.metadata = const <String, DVJsonValue>{},
  });
}

class DVAIAgentRequest {
  final String goal;
  final DVJsonObject context;
  final List<String> tools;

  const DVAIAgentRequest({
    required this.goal,
    this.context = const <String, DVJsonValue>{},
    this.tools = const <String>[],
  });
}

class DVAIAgentResult {
  final String output;
  final DVJsonObject data;
  final List<String> usedTools;

  const DVAIAgentResult({
    required this.output,
    this.data = const <String, DVJsonValue>{},
    this.usedTools = const <String>[],
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

  const DVExportOptions({
    this.tenantId,
    this.policyFilter,
    this.chunkSize = 1000,
    this.metadata = const <String, String>{},
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
