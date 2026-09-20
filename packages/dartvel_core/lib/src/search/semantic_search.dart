/// Semantic search and embeddings: retrieval over an application's own
/// records by meaning rather than by words.
///
/// This is the runtime the specification's `# Semantic Search and Embeddings`
/// describes. It is built on what already exists rather than beside it:
/// embedding runs as jobs on [DVQueues], an embedder can wrap any
/// [DVAIAdapter], keyword and hybrid modes use a [DVSearchProvider], costs go
/// through [DVMeters], and tenant scope is [DVTenants]'s.
///
/// Three rules shape everything here, and each is a failure that looks like a
/// working search:
///
/// - A vector query returns the k nearest, so a filter applied afterwards
///   empties a page rather than narrowing it. Scope goes into the query, and
///   what cannot is post-filtered with refill, up to a bound that is
///   reported when it is reached.
/// - Vectors from two embedders are not comparable. An index is a generation
///   named after its embedder and chunking; a new embedder builds a new
///   generation, and queries keep answering from the old one, embedded with
///   the old model, until the new one is complete.
/// - A record whose embedding job failed is never found, and nobody can
///   report a result they never saw, so a dead-lettered job is reported.
library dartvel_core.search.semantic_search;

import '../observability/observability.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../dartvel.dart';

/// How a query is answered.
///
/// `keyword` is the default everywhere a default exists: it is what the
/// generated index already does, costs nothing per query, and a default that
/// changed would change the meaning of every existing call.
enum DVSearchMode { keyword, semantic, hybrid }

// --- embedders -----------------------------------------------------------------

/// Turns text into a vector.
///
/// [id] and [dimensions] identify the model, and are part of every index
/// built with it: two embedders with different ids never share an index.
abstract class DVEmbedder {
  /// The model, as the provider names it: `openai/text-embedding-3-small`.
  String get id;

  /// The length of every vector [embed] returns.
  int get dimensions;

  Future<List<double>> embed(String text);
}

/// An embedder whose vector was not the length it was declared with.
///
/// Refused rather than stored: vectors of two lengths in one index cannot be
/// compared, and a provider that silently changed a model's output size
/// would otherwise corrupt the index one write at a time.
class DVSemanticDimensionError implements Exception {
  DVSemanticDimensionError({
    required this.embedder,
    required this.expected,
    required this.actual,
  });

  final String embedder;
  final int expected;
  final int actual;

  @override
  String toString() => 'The embedder $embedder was declared with $expected '
      'dimensions and returned a vector of $actual. Declare the dimensions '
      'the model produces; vectors of different lengths cannot share an '
      'index.';
}

/// An embedder over any [DVAIAdapter]'s `embed`.
///
/// The model is named here rather than read from the adapter, because the
/// adapter's default model is exactly the kind of default this section
/// refuses: an index built without deciding which model built it.
class DVAIEmbedder implements DVEmbedder {
  DVAIEmbedder(this.adapter, {required this.id, required this.dimensions}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must name the embedding model');
    }
    if (dimensions < 1) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
  }

  final DVAIAdapter adapter;

  @override
  final String id;

  @override
  final int dimensions;

  @override
  Future<List<double>> embed(String text) async {
    final List<double> vector = await adapter.embed(text);
    if (vector.length != dimensions) {
      throw DVSemanticDimensionError(
          embedder: id, expected: dimensions, actual: vector.length);
    }
    return vector;
  }
}

// --- chunking ------------------------------------------------------------------

/// A piece of a field, and where in the field it starts.
class DVTextChunk {
  const DVTextChunk(this.offset, this.text);

  final int offset;
  final String text;
}

/// How long fields are split before embedding.
///
/// Part of an index's identity: the same corpus chunked two ways is two sets
/// of vectors, and changing it builds a new generation like changing the
/// embedder does.
class DVChunking {
  const DVChunking({this.maxCharacters = 800, this.overlap = 100});

  final int maxCharacters;
  final int overlap;

  String get id => 'chars-$maxCharacters-$overlap';

  List<DVTextChunk> split(String text) {
    if (maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters', 'must be positive');
    }
    if (overlap < 0 || overlap >= maxCharacters) {
      throw ArgumentError.value(
          overlap, 'overlap', 'must be at least 0 and below maxCharacters');
    }
    if (text.isEmpty) return const <DVTextChunk>[];
    if (text.length <= maxCharacters) return <DVTextChunk>[DVTextChunk(0, text)];

    final List<DVTextChunk> chunks = <DVTextChunk>[];
    int start = 0;
    while (start < text.length) {
      int end = math.min(start + maxCharacters, text.length);
      if (end < text.length) {
        // Break on whitespace when there is some in the back half, so a chunk
        // does not end in the middle of a word it then fails to match.
        final int space = text.lastIndexOf(RegExp(r'\s'), end);
        if (space > start + maxCharacters ~/ 2) end = space;
      }
      chunks.add(DVTextChunk(start, text.substring(start, end)));
      if (end >= text.length) break;
      start = math.max(end - overlap, start + 1);
    }
    return chunks;
  }
}

// --- vector storage ------------------------------------------------------------

/// One embedded chunk of one record.
class DVVectorEntry {
  const DVVectorEntry({
    required this.recordId,
    required this.chunk,
    required this.offset,
    required this.text,
    required this.vector,
    this.field = '',
    this.tenant,
    this.attributes = const <String, String>{},
  });

  final String recordId;

  /// The chunk's position among the record's chunks.
  final int chunk;

  /// Where the chunk starts in its field.
  final int offset;
  final String text;
  final String field;
  final List<double> vector;

  /// The record's tenant, for a tenant-scoped index.
  final String? tenant;

  /// Values a query may filter on, pushed down where the adapter can.
  final Map<String, String> attributes;
}

/// What a vector query is restricted to before it ranks anything.
class DVVectorFilter {
  const DVVectorFilter({this.tenant, this.equals = const <String, String>{}});

  final String? tenant;
  final Map<String, String> equals;

  bool matches(DVVectorEntry entry) {
    if (tenant != null && entry.tenant != tenant) return false;
    for (final MapEntry<String, String> condition in equals.entries) {
      if (entry.attributes[condition.key] != condition.value) return false;
    }
    return true;
  }
}

class DVVectorMatch {
  const DVVectorMatch(this.entry, this.score);

  final DVVectorEntry entry;

  /// Cosine similarity, higher is nearer.
  final double score;
}

/// Where vectors live: pgvector, or a search service that stores them.
abstract class DVVectorAdapter {
  /// Whether [nearest] applies its filter before ranking.
  ///
  /// An adapter that cannot is refused for a tenant-scoped index
  /// (`DV-SEMANTIC-002`), because filtering after ranking returns another
  /// tenant's nearest rows or none of the caller's.
  bool get canFilter;

  /// Stores a record's chunks, replacing any it had.
  Future<void> upsert(String index, List<DVVectorEntry> entries);

  Future<void> removeRecord(String index, String recordId);

  Future<List<DVVectorMatch>> nearest(
    String index,
    List<double> vector, {
    required int k,
    DVVectorFilter? filter,
  });

  Future<void> dropIndex(String index);

  /// Small durable values the index keeps about itself: which generation is
  /// active, which records a backfill has done, which job carried which
  /// record.
  Future<String?> readMeta(String key);

  Future<void> writeMeta(String key, String? value);
}

/// The reference adapter: exact cosine search in memory.
///
/// For development and tests. Deliberately not a vector store to deploy — the
/// specification leaves those to pgvector and the search services, since a
/// hand-rolled index would be the slowest and least-tested part of the
/// framework.
class DVInMemoryVectorAdapter implements DVVectorAdapter {
  DVInMemoryVectorAdapter({this.canFilter = true});

  @override
  final bool canFilter;

  final Map<String, List<DVVectorEntry>> _indexes =
      <String, List<DVVectorEntry>>{};
  final Map<String, int> _dimensions = <String, int>{};
  final Map<String, String> _meta = <String, String>{};

  @override
  Future<void> upsert(String index, List<DVVectorEntry> entries) async {
    if (entries.isEmpty) return;
    final int length = _dimensions[index] ?? entries.first.vector.length;
    for (final DVVectorEntry entry in entries) {
      if (entry.vector.length != length) {
        throw ArgumentError.value(
          entry.vector.length,
          'vector',
          'index "$index" holds vectors of $length dimensions; a vector of '
              '${entry.vector.length} cannot be compared with them',
        );
      }
    }
    _dimensions[index] = length;
    final List<DVVectorEntry> stored =
        _indexes.putIfAbsent(index, () => <DVVectorEntry>[]);
    final Set<String> replaced = <String>{
      for (final DVVectorEntry entry in entries) entry.recordId,
    };
    stored
      ..removeWhere((DVVectorEntry e) => replaced.contains(e.recordId))
      ..addAll(entries);
  }

  @override
  Future<void> removeRecord(String index, String recordId) async {
    _indexes[index]?.removeWhere((DVVectorEntry e) => e.recordId == recordId);
  }

  @override
  Future<List<DVVectorMatch>> nearest(
    String index,
    List<double> vector, {
    required int k,
    DVVectorFilter? filter,
  }) async {
    final List<DVVectorEntry> stored = _indexes[index] ?? const <DVVectorEntry>[];
    if (stored.isEmpty || k < 1) return const <DVVectorMatch>[];
    final int? length = _dimensions[index];
    if (length != null && vector.length != length) {
      throw ArgumentError.value(vector.length, 'vector',
          'index "$index" holds vectors of $length dimensions');
    }
    final Iterable<DVVectorEntry> candidates = canFilter && filter != null
        ? stored.where(filter.matches)
        : stored;
    final List<DVVectorMatch> ranked = <DVVectorMatch>[
      for (final DVVectorEntry entry in candidates)
        DVVectorMatch(entry, _cosine(vector, entry.vector)),
    ]..sort((DVVectorMatch a, DVVectorMatch b) => b.score.compareTo(a.score));
    return ranked.length <= k ? ranked : ranked.sublist(0, k);
  }

  @override
  Future<void> dropIndex(String index) async {
    _indexes.remove(index);
    _dimensions.remove(index);
  }

  @override
  Future<String?> readMeta(String key) async => _meta[key];

  @override
  Future<void> writeMeta(String key, String? value) async {
    if (value == null) {
      _meta.remove(key);
    } else {
      _meta[key] = value;
    }
  }

  static double _cosine(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}

// --- errors --------------------------------------------------------------------

/// A declaration the index refuses to run with.
class DVSemanticConfigError implements Exception {
  DVSemanticConfigError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// A query asked of an index that is being rebuilt, with no embedder for the
/// generation still answering.
///
/// Embedding the query with the new model and comparing it with the old
/// model's vectors would return noise ranked as confidently as a result, so
/// the query is refused instead.
class DVSemanticRebuildError implements Exception {
  DVSemanticRebuildError({
    required this.index,
    required this.serving,
    required this.building,
  });

  final String index;
  final String serving;
  final String building;

  @override
  String toString() => 'The semantic index "$index" is being rebuilt: '
      'queries answer from $serving until $building is complete, and no '
      'embedder for $serving was given. Pass the previous embedder in '
      'previousEmbedders so queries can be embedded the way that index was.';
}

/// A tenant's embedding budget is spent (`DV-SEMANTIC-007`).
///
/// A refusal rather than a quiet fallback to keyword search, which would
/// return something different from yesterday with nothing to say why.
class DVSemanticBudgetExceeded implements Exception {
  DVSemanticBudgetExceeded({required this.tenant, required this.meter});

  final String code = 'DV-SEMANTIC-007';
  final String tenant;
  final String meter;

  @override
  String toString() => '$code: the embedding budget on "$meter" is spent for '
      'tenant "$tenant", so the search was refused rather than answered some '
      'other way.';
}

// --- metering ------------------------------------------------------------------

/// Records embedding costs against a meter, and refuses past its limit.
class DVSemanticMetering {
  const DVSemanticMetering({required this.meters, required this.tokens});

  final DVMeters meters;

  /// A counter of tokens, whose limit and behaviour at the limit decide when
  /// embedding is refused.
  final DVMeterDefinition tokens;

  /// A rough token count: providers bill tokens, and four characters is the
  /// usual approximation when the tokenizer is not at hand.
  static int estimateTokens(String text) => math.max(1, (text.length / 4).ceil());

  /// Charges for embedding [text] under [key], or throws
  /// [DVSemanticBudgetExceeded] before anything is embedded.
  Future<void> charge(String text, {required String key}) async {
    final DVMeterOutcome outcome =
        await meters.record(tokens, estimateTokens(text), idempotencyKey: key);
    if (!outcome.admitted) {
      final String tenant = const DVTenants().currentTenant;
      DVObservability.log(
        'Embedding refused: the budget on ${tokens.name} is spent.',
        level: DVLogLevel.warn,
        code: 'DV-SEMANTIC-007',
        context: <String, Object?>{'meter': tokens.name, 'tenant': tenant},
      );
      throw DVSemanticBudgetExceeded(tenant: tenant, meter: tokens.name);
    }
  }
}

// --- results -------------------------------------------------------------------

class DVSemanticHit<T> {
  const DVSemanticHit({
    required this.record,
    required this.score,
    this.chunk,
    this.field,
    this.matchedBy = const <DVSearchMode>{},
  });

  final T record;
  final double score;

  /// The chunk that matched, for a semantic match.
  final DVTextChunk? chunk;

  /// The field [chunk] is from.
  final String? field;

  /// Which rankings found it: keyword, semantic, or both in hybrid mode.
  final Set<DVSearchMode> matchedBy;
}

class DVSemanticPage<T> {
  const DVSemanticPage({
    required this.hits,
    this.bounded = false,
    this.generation,
  });

  final List<DVSemanticHit<T>> hits;

  /// True when the refill bound was reached with fewer results than asked
  /// for (`DV-SEMANTIC-005`): the page is short because the search stopped,
  /// not because there was nothing more.
  final bool bounded;

  /// The index generation that answered a semantic query.
  final String? generation;

  List<T> get items => <T>[for (final DVSemanticHit<T> hit in hits) hit.record];
}

/// What an AI feature is handed: rows the caller may see, without sensitive
/// fields, and the chunks that matched.
class DVSemanticRetrieval<T> {
  const DVSemanticRetrieval({
    required this.hits,
    required this.rows,
    this.bounded = false,
  });

  final List<DVSemanticHit<T>> hits;
  final List<Map<String, Object?>> rows;
  final bool bounded;
}

class DVSemanticBackfill {
  const DVSemanticBackfill({
    required this.generation,
    required this.processed,
    required this.total,
    required this.completed,
  });

  final String generation;

  /// How many of the given records are now embedded in [generation].
  final int processed;
  final int total;

  /// Whether [generation] now answers queries.
  final bool completed;
}

/// The job a write enqueues. Public because a durable queue adapter has to
/// be able to rebuild it.
class DVSemanticJob {
  const DVSemanticJob({
    required this.index,
    required this.recordId,
    this.remove = false,
  });

  final String index;
  final String recordId;
  final bool remove;
}

// --- the index -----------------------------------------------------------------

/// Semantic search over one model.
class DVSemanticIndex<T> {
  DVSemanticIndex({
    required this.name,
    required DVEmbedder? embedder,
    required this.vectors,
    required this.idOf,
    required this.fields,
    required this.load,
    this.tenantOf,
    this.attributesOf,
    this.canSee,
    this.keyword,
    this.toJson,
    this.previousEmbedders = const <DVEmbedder>[],
    this.chunking = const DVChunking(),
    this.sensitiveFields = const <String>{},
    this.queues = const DVQueues(),
    this.queue = 'semantic',
    this.maxAttempts = 3,
    this.refillMultiple = 4,
    this.metering,
  }) : embedder = _requireEmbedder(name, embedder) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'name at least one field');
    }
    final Set<String> sensitiveSemantic =
        fields.keys.toSet().intersection(sensitiveFields);
    if (sensitiveSemantic.isNotEmpty) {
      throw ArgumentError.value(
        sensitiveSemantic.join(', '),
        'fields',
        'a sensitive field cannot be embedded: its text would reach the '
            'vector store and every result that matches it',
      );
    }
    if ((tenantOf != null || canSee != null) && !vectors.canFilter) {
      throw DVSemanticConfigError(
        'DV-SEMANTIC-002',
        'the vector adapter for "$name" cannot filter, and the model is '
            '${tenantOf != null ? 'tenant' : 'policy'}-scoped. A vector query '
            'returns the k nearest, so a filter applied afterwards shows one '
            'caller another\'s rows or none of their own. Use an adapter that '
            'filters in the query.',
      );
    }
    if (refillMultiple < 1) {
      throw ArgumentError.value(refillMultiple, 'refillMultiple', 'must be positive');
    }
    _registry[name] = this;
    queues.register<DVSemanticJob>(_runJob);
  }

  /// The model's name, which prefixes every generation's name.
  final String name;
  final DVEmbedder embedder;
  final DVVectorAdapter vectors;
  final String Function(T record) idOf;

  /// The semantic fields, by name.
  final Map<String, String Function(T record)> fields;

  /// Loads a record by id, so a result is always the record as it is now.
  final Future<T?> Function(String id) load;

  /// The record's tenant. Non-null makes the index tenant-scoped.
  final String? Function(T record)? tenantOf;

  /// Values a query may filter on.
  final Map<String, String> Function(T record)? attributesOf;

  /// The policy check a result must pass — the same one `find` uses, so a
  /// search can never return a row a lookup would refuse.
  final FutureOr<bool> Function(T record)? canSee;

  /// The keyword index, for keyword and hybrid modes.
  final DVSearchProvider<T, Object?>? keyword;

  /// The record as data, for [retrieve].
  final Map<String, Object?> Function(T record)? toJson;

  /// Embedders of earlier generations, so a rebuilding index can keep
  /// answering from the generation still active.
  final List<DVEmbedder> previousEmbedders;
  final DVChunking chunking;
  final Set<String> sensitiveFields;
  final DVQueues queues;
  final String queue;
  final int maxAttempts;

  /// How far past the requested page a refill may look, as a multiple of it.
  final int refillMultiple;
  final DVSemanticMetering? metering;

  static final Map<String, DVSemanticIndex<Object?>> _registry =
      <String, DVSemanticIndex<Object?>>{};

  /// Forgets every registered index. Tests use this.
  static void resetRegistry() => _registry.clear();

  static DVEmbedder _requireEmbedder(String name, DVEmbedder? embedder) {
    if (embedder == null) {
      throw DVSemanticConfigError(
        'DV-SEMANTIC-001',
        'semantic search on "$name" has no embedder. There is no default: '
            'vectors from two models are not comparable, and a default would '
            'pick one for an application that had not decided.',
      );
    }
    return embedder;
  }

  static Future<void> _runJob(DVSemanticJob job) async {
    final DVSemanticIndex<Object?>? index = _registry[job.index];
    if (index == null) {
      throw StateError('No semantic index named "${job.index}" is registered '
          'in this process; the job will be retried.');
    }
    await index._process(job);
  }

  // --- generations ---------------------------------------------------------

  /// The generation this index's embedder and chunking build.
  String get generation =>
      '$name@${embedder.id}#${embedder.dimensions}#${chunking.id}';

  String get _activeKey => 'semantic:active:$name';

  String? _active;
  Future<void>? _opening;
  final Set<String> _reported = <String>{};
  int _querySequence = 0;

  Future<void> _open() => _opening ??= _readActive();

  Future<void> _readActive() async {
    final String? stored = await vectors.readMeta(_activeKey);
    if (stored == null) {
      await vectors.writeMeta(_activeKey, generation);
      _active = generation;
      return;
    }
    _active = stored;
    if (stored != generation && _reported.add('003:$generation')) {
      DVObservability.log(
        'The embedder or chunking for "$name" changed: $generation is being '
        'built alongside, and queries answer from $stored until it is '
        'complete.',
        level: DVLogLevel.info,
        code: 'DV-SEMANTIC-003',
        context: <String, Object?>{
          'index': name,
          'serving': stored,
          'building': generation,
        },
      );
    }
  }

  bool get _rebuilding => _active != null && _active != generation;

  List<String> get _liveGenerations =>
      <String>[_active!, if (_rebuilding) generation];

  DVEmbedder? _embedderFor(String gen) {
    for (final DVEmbedder candidate in <DVEmbedder>[
      embedder,
      ...previousEmbedders,
    ]) {
      if (gen.startsWith('$name@${candidate.id}#${candidate.dimensions}#')) {
        return candidate;
      }
    }
    return null;
  }

  // --- writes --------------------------------------------------------------

  /// Enqueues [record] for embedding. Nothing is embedded inline: an
  /// embedder is a rate-limited network call, and a save that waits on one
  /// is a timeout during somebody else's outage.
  Future<void> indexed(T record) =>
      _dispatch(DVSemanticJob(index: name, recordId: idOf(record)));

  /// Enqueues removal of a record's vectors.
  Future<void> removed(String recordId) =>
      _dispatch(DVSemanticJob(index: name, recordId: recordId, remove: true));

  Future<void> _dispatch(DVSemanticJob job) async {
    final DVJobEnvelope<DVSemanticJob> envelope = await queues
        .dispatch<DVSemanticJob>(job, queue: queue, maxAttempts: maxAttempts);
    // Kept beside the vectors rather than read back from the job: a
    // dead-lettered envelope's payload is the queue's to unwrap, and the
    // record it was for is what absentRecords has to name.
    await vectors.writeMeta('semantic:job:${envelope.id}', '$name\n${job.recordId}');
  }

  Future<void> _process(DVSemanticJob job) async {
    await _open();
    if (job.remove) {
      for (final String gen in _liveGenerations) {
        await vectors.removeRecord(gen, job.recordId);
      }
      return;
    }
    final T? record = await load(job.recordId);
    for (final String gen in _liveGenerations) {
      if (record == null) {
        await vectors.removeRecord(gen, job.recordId);
        continue;
      }
      final DVEmbedder? using = _embedderFor(gen);
      if (using == null) continue;
      await _write(gen, record, using);
    }
  }

  Future<void> _write(String gen, T record, DVEmbedder using) async {
    final String id = idOf(record);
    final String? tenant = tenantOf?.call(record);
    final Map<String, String> attributes =
        attributesOf?.call(record) ?? const <String, String>{};
    final List<DVVectorEntry> entries = <DVVectorEntry>[];
    int position = 0;
    for (final MapEntry<String, String Function(T)> field in fields.entries) {
      for (final DVTextChunk chunk in chunking.split(field.value(record))) {
        // A stable key per chunk's content, so a retried job is charged once.
        await metering?.charge(chunk.text,
            key: 'semantic:index:$gen:$id:${field.key}:${chunk.offset}:'
                '${chunk.text.hashCode}');
        final List<double> vector = await using.embed(chunk.text);
        if (vector.length != using.dimensions) {
          throw DVSemanticDimensionError(
              embedder: using.id,
              expected: using.dimensions,
              actual: vector.length);
        }
        entries.add(DVVectorEntry(
          recordId: id,
          chunk: position++,
          offset: chunk.offset,
          text: chunk.text,
          field: field.key,
          vector: vector,
          tenant: tenant,
          attributes: attributes,
        ));
      }
    }
    if (entries.isEmpty) {
      await vectors.removeRecord(gen, id);
    } else {
      await vectors.upsert(gen, entries);
    }
  }

  /// Records whose embedding job dead-lettered, and so are absent from the
  /// index (`DV-SEMANTIC-004`, reported once per record).
  Future<List<String>> absentRecords() async {
    final List<String> absent = <String>[];
    for (final DVJobEnvelope<DVJobPayload> envelope
        in await queues.deadLetters(queue)) {
      final String? carried =
          await vectors.readMeta('semantic:job:${envelope.id}');
      if (carried == null) continue;
      final List<String> parts = carried.split('\n');
      if (parts.length != 2 || parts[0] != name) continue;
      final String recordId = parts[1];
      if (absent.contains(recordId)) continue;
      absent.add(recordId);
      if (_reported.add('004:$recordId')) {
        DVObservability.log(
          'The embedding job for "$recordId" in "$name" failed permanently; '
          'the record is absent from the index.',
          level: DVLogLevel.warn,
          code: 'DV-SEMANTIC-004',
          context: <String, Object?>{
            'index': name,
            'record': recordId,
            'error': envelope.lastError,
          },
        );
      }
    }
    return absent;
  }

  // --- backfill ------------------------------------------------------------

  /// Embeds [records] into this index's generation, skipping records a
  /// previous run already did, so a failure part-way resumes rather than
  /// re-embedding — and re-paying for — the records before it.
  ///
  /// With [complete], once every record is done the generation becomes the
  /// one queries answer from and the previous generation is dropped.
  Future<DVSemanticBackfill> backfill(
    Iterable<T> records, {
    bool complete = false,
  }) async {
    await _open();
    final String gen = generation;
    int processed = 0;
    int total = 0;
    for (final T record in records) {
      total++;
      final String doneKey = 'semantic:done:$gen:${idOf(record)}';
      if (await vectors.readMeta(doneKey) == null) {
        await _write(gen, record, embedder);
        await vectors.writeMeta(doneKey, '1');
      }
      processed++;
    }
    bool completed = false;
    if (complete && processed == total) {
      final String? previous = _active;
      await vectors.writeMeta(_activeKey, gen);
      _active = gen;
      if (previous != null && previous != gen) {
        await vectors.dropIndex(previous);
      }
      completed = true;
    }
    return DVSemanticBackfill(
      generation: gen,
      processed: processed,
      total: total,
      completed: completed || !_rebuilding,
    );
  }

  // --- queries -------------------------------------------------------------

  /// Searches the index. [where] holds conditions on [attributesOf]'s values,
  /// pushed into the vector query where the adapter can filter.
  Future<DVSemanticPage<T>> query(
    String text, {
    DVSearchMode mode = DVSearchMode.keyword,
    int limit = 10,
    Map<String, String> where = const <String, String>{},
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'must be positive');
    if (where.isNotEmpty && attributesOf == null) {
      throw ArgumentError.value(
          where, 'where', 'conditions need attributesOf on the index');
    }
    switch (mode) {
      case DVSearchMode.keyword:
        return DVSemanticPage<T>(hits: await _keywordHits(text, limit, where));
      case DVSearchMode.semantic:
        return _semantic(text, limit, where);
      case DVSearchMode.hybrid:
        return _hybrid(text, limit, where);
    }
  }

  /// The rows an AI feature needs, filtered by the caller's own policies and
  /// without sensitive fields.
  Future<DVSemanticRetrieval<T>> retrieve(
    String question, {
    int limit = 8,
    DVSearchMode mode = DVSearchMode.semantic,
    Map<String, String> where = const <String, String>{},
  }) async {
    final Map<String, Object?> Function(T)? asData = toJson;
    if (asData == null) {
      throw StateError('retrieve needs toJson on the index "$name"');
    }
    final DVSemanticPage<T> page =
        await query(question, mode: mode, limit: limit, where: where);
    return DVSemanticRetrieval<T>(
      hits: page.hits,
      bounded: page.bounded,
      rows: <Map<String, Object?>>[
        for (final DVSemanticHit<T> hit in page.hits)
          <String, Object?>{
            for (final MapEntry<String, Object?> entry
                in asData(hit.record).entries)
              if (!sensitiveFields.contains(entry.key)) entry.key: entry.value,
          },
      ],
    );
  }

  String? get _tenant =>
      tenantOf == null ? null : const DVTenants().currentTenant;

  /// Whether the caller may see [record]. Every result passes this, whatever
  /// an adapter was asked to push down, so a filter an adapter ignored cannot
  /// reach a page.
  Future<bool> _admit(
      T record, String? tenant, Map<String, String> where) async {
    final String? Function(T)? scope = tenantOf;
    if (scope != null && scope(record) != tenant) return false;
    if (where.isNotEmpty) {
      final Map<String, String> attributes =
          attributesOf?.call(record) ?? const <String, String>{};
      for (final MapEntry<String, String> condition in where.entries) {
        if (attributes[condition.key] != condition.value) return false;
      }
    }
    final FutureOr<bool> Function(T)? policy = canSee;
    if (policy != null && !await policy(record)) return false;
    return true;
  }

  Future<List<DVSemanticHit<T>>> _keywordHits(
      String text, int limit, Map<String, String> where) async {
    final DVSearchProvider<T, Object?>? provider = keyword;
    if (provider == null) {
      throw StateError('keyword search on "$name" needs a keyword provider');
    }
    final String? tenant = _tenant;
    final DVSearchResultPage<T> page =
        await provider.query(text, perPage: limit * refillMultiple);
    final List<DVSemanticHit<T>> hits = <DVSemanticHit<T>>[];
    int rank = 0;
    for (final T record in page.items) {
      rank++;
      if (!await _admit(record, tenant, where)) continue;
      hits.add(DVSemanticHit<T>(
        record: record,
        score: 1 / rank,
        matchedBy: const <DVSearchMode>{DVSearchMode.keyword},
      ));
      if (hits.length == limit) break;
    }
    return hits;
  }

  Future<DVSemanticPage<T>> _semantic(
      String text, int limit, Map<String, String> where) async {
    await _open();
    final String serving = _active!;
    final DVEmbedder? using = _embedderFor(serving);
    if (using == null) {
      throw DVSemanticRebuildError(
          index: name, serving: serving, building: generation);
    }
    final String? tenant = _tenant;
    await metering?.charge(text,
        key: 'semantic:query:$name:${DateTime.now().microsecondsSinceEpoch}:'
            '${_querySequence++}');
    final List<double> vector = await using.embed(text);
    if (vector.length != using.dimensions) {
      throw DVSemanticDimensionError(
          embedder: using.id, expected: using.dimensions, actual: vector.length);
    }

    final DVVectorFilter? filter = vectors.canFilter
        ? DVVectorFilter(tenant: tenant, equals: where)
        : null;
    final int bound = limit * refillMultiple;
    final Set<String> seen = <String>{};
    final List<DVSemanticHit<T>> hits = <DVSemanticHit<T>>[];
    int k = limit;
    bool bounded = false;
    while (true) {
      final List<DVVectorMatch> matches =
          await vectors.nearest(serving, vector, k: k, filter: filter);
      final bool exhausted = matches.length < k;
      for (final DVVectorMatch match in matches) {
        // Matches arrive nearest first, so a record's first chunk seen is its
        // best: one row per record however many of its chunks matched.
        if (!seen.add(match.entry.recordId)) continue;
        final T? record = await load(match.entry.recordId);
        if (record == null) continue;
        if (!await _admit(record, tenant, where)) continue;
        hits.add(DVSemanticHit<T>(
          record: record,
          score: match.score,
          chunk: DVTextChunk(match.entry.offset, match.entry.text),
          field: match.entry.field.isEmpty ? null : match.entry.field,
          matchedBy: const <DVSearchMode>{DVSearchMode.semantic},
        ));
        if (hits.length == limit) break;
      }
      if (hits.length >= limit || exhausted) break;
      if (k >= bound) {
        bounded = true;
        break;
      }
      k = math.min(k * 2, bound);
    }
    if (bounded) {
      DVObservability.log(
        'Semantic search on "$name" reached its refill bound with '
        '${hits.length} of $limit results.',
        level: DVLogLevel.info,
        code: 'DV-SEMANTIC-005',
        context: <String, Object?>{
          'index': name,
          'returned': hits.length,
          'limit': limit,
          'bound': bound,
        },
      );
    }
    return DVSemanticPage<T>(hits: hits, bounded: bounded, generation: serving);
  }

  Future<DVSemanticPage<T>> _hybrid(
      String text, int limit, Map<String, String> where) async {
    final List<DVSemanticHit<T>> byKeyword =
        await _keywordHits(text, limit * 2, where);
    final DVSemanticPage<T> bySemantic = await _semantic(text, limit * 2, where);

    // Reciprocal rank fusion: the two rankings combined by position rather
    // than by score, since a keyword score and a cosine are not on one scale.
    const double k = 60;
    final Map<String, double> scores = <String, double>{};
    final Map<String, DVSemanticHit<T>> first = <String, DVSemanticHit<T>>{};
    final Map<String, Set<DVSearchMode>> found = <String, Set<DVSearchMode>>{};
    void rank(List<DVSemanticHit<T>> hits, DVSearchMode mode) {
      for (int i = 0; i < hits.length; i++) {
        final String id = idOf(hits[i].record);
        scores[id] = (scores[id] ?? 0) + 1 / (k + i + 1);
        (found[id] ??= <DVSearchMode>{}).add(mode);
        // Prefer the semantic hit, which carries the matched chunk.
        if (mode == DVSearchMode.semantic || !first.containsKey(id)) {
          first[id] = hits[i];
        }
      }
    }

    rank(byKeyword, DVSearchMode.keyword);
    rank(bySemantic.hits, DVSearchMode.semantic);
    final List<String> ordered = scores.keys.toList()
      ..sort((String a, String b) => scores[b]!.compareTo(scores[a]!));
    return DVSemanticPage<T>(
      bounded: bySemantic.bounded,
      generation: bySemantic.generation,
      hits: <DVSemanticHit<T>>[
        for (final String id in ordered.take(limit))
          DVSemanticHit<T>(
            record: first[id]!.record,
            score: scores[id]!,
            chunk: first[id]!.chunk,
            field: first[id]!.field,
            matchedBy: found[id]!,
          ),
      ],
    );
  }
}
