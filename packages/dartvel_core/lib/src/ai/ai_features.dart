/// AI features after they ship: a budget checked before the provider is
/// called, a declared fallback chain whose every step is reported, answers
/// cached under the prompt version and model, a context manifest that is
/// enforced rather than documented, and a record of which prompt version and
/// model produced every output.
///
/// None of it is a second system. Budgets are [DVMeters], the cache is a
/// [DVCacheAdapter] invalidated through [DVCacheTags], retrieved rows are
/// [DVSemanticRetrieval]'s, and prompts are [DVPrompts].
library dartvel_core.ai.features;

import '../observability/observability.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart';

/// A meter a feature's budget is counted on: `DVMeterRef.tenant('aiTokens')`.
///
/// Scoped to the current tenant, as every [DVMeters] recording is.
class DVMeterRef {
  const DVMeterRef.tenant(this.meter);

  final String meter;
}

/// One declared step down a feature's chain.
class DVAIFallback {
  const DVAIFallback.model(String this.model);

  const DVAIFallback._degrade() : model = null;

  /// Answer with nothing and say so: a typed state the UI renders.
  static const DVAIFallback degrade = DVAIFallback._degrade();

  /// The model to try, or null for [degrade].
  final String? model;

  bool get isDegrade => model == null;

  @override
  String toString() => isDegrade ? 'degrade' : 'model($model)';
}

/// An AI feature's operating declaration.
class DVAIFeature {
  const DVAIFeature({
    required this.prompt,
    this.budget,
    this.fallback = const <DVAIFallback>[],
    this.cacheTags = const <String>[],
    this.context = const <Type>[],
    this.contextFields = const <Type, List<String>>{},
    this.maxOutputTokens = 1024,
    this.evalThreshold = 1.0,
  });

  /// The id of the prompt the feature sends. Also the feature's id.
  final String prompt;

  final DVMeterRef? budget;

  /// Tried in order after the primary model, when its budget is spent or its
  /// provider fails. Empty means refuse at exhaustion and be unavailable on
  /// failure.
  final List<DVAIFallback> fallback;

  /// Tags for a cached answer, with `{input}` placeholders:
  /// `'ticket:{id}'`. With a cache configured, answers are cached whether or
  /// not tags are declared; tags are how a change drops them.
  final List<String> cacheTags;

  /// The models the feature reads. Nothing else can be added to its context.
  final List<Type> context;

  /// Narrows a model in [context] to these fields.
  final Map<Type, List<String>> contextFields;

  /// The most output a call may produce, which is what the budget check
  /// charges for before the call.
  final int maxOutputTokens;

  /// The share of golden transcripts that must pass (`DV-AIOPS-007`).
  final double evalThreshold;

  String get id => prompt;
}

/// What the application's models look like to a context manifest. Generated
/// from `@DVModel`, including its `@DVModel.sensitiveField()` fields.
class DVAIContextModel {
  const DVAIContextModel(
    this.type, {
    required this.name,
    required this.fields,
    this.sensitive = const <String>{},
  });

  final Type type;
  final String name;
  final Set<String> fields;
  final Set<String> sensitive;
}

/// What the caller's policy forbids a feature to read.
class DVAIContextPolicy {
  const DVAIContextPolicy({
    this.forbiddenModels = const <Type>{},
    this.forbiddenFields = const <Type, Set<String>>{},
  });

  final Set<Type> forbiddenModels;
  final Map<Type, Set<String>> forbiddenFields;
}

class _Readable {
  const _Readable(this.model, this.fields);

  final DVAIContextModel model;

  /// The fields the manifest reads: never a sensitive one.
  final Set<String> fields;
}

/// The rows one feature's prompt will see, admitted through its manifest.
///
/// Obtained from [DVAIFeatures.contextFor]; a context is bound to the feature
/// whose manifest built it.
class DVAIContext {
  DVAIContext._(this.feature, this._readable);

  final String feature;
  final Map<Type, _Readable> _readable;
  final List<Map<String, Object?>> _entries = <Map<String, Object?>>[];

  /// Adds one row of [model]: the fields the manifest reads, valued, and the
  /// model's sensitive fields named, never valued.
  void add(Type model, Map<String, Object?> row) {
    final _Readable? readable = _readable[model];
    if (readable == null) {
      throw DVAIOpsError(
        'DV-AIOPS-005',
        'feature "$feature" does not name $model in its context manifest; a '
            'feature reads the models it names and nothing else',
      );
    }
    final List<String> fields = readable.fields.toList()..sort();
    final List<String> withheld = readable.model.sensitive.toList()..sort();
    _entries.add(<String, Object?>{
      'model': readable.model.name,
      'fields': <String, Object?>{
        for (final String field in fields)
          if (row.containsKey(field)) field: _plain(row[field]),
      },
      if (withheld.isNotEmpty) 'withheld': withheld,
    });
  }

  void addAll(Type model, Iterable<Map<String, Object?>> rows) {
    for (final Map<String, Object?> row in rows) {
      add(model, row);
    }
  }

  /// Adds the rows semantic search retrieved, under the same manifest and
  /// the same exclusion as any other row.
  void addRetrieval(Type model, DVSemanticRetrieval<Object?> retrieval) =>
      addAll(model, retrieval.rows);

  List<Map<String, Object?>> get _rows => _entries;
}

Object? _plain(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        '${e.key}': _plain(e.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final Object? item in value) _plain(item)];
  }
  return '$value';
}

/// Why a step down the chain was taken.
enum DVAIFallbackReason { budget, providerFailure }

class DVAIFallbackStep {
  const DVAIFallbackStep({
    required this.from,
    required this.to,
    required this.reason,
  });

  /// The model given up on.
  final String from;

  /// The model tried next, or `degrade`.
  final String to;
  final DVAIFallbackReason reason;
}

/// What produced an output, and what happened on the way.
class DVAIRunRecord {
  const DVAIRunRecord({
    required this.feature,
    required this.tenant,
    required this.promptId,
    required this.promptVersion,
    required this.promptFingerprint,
    required this.promptSource,
    required this.inputHash,
    required this.outcome,
    required this.at,
    this.model,
    this.outputHash,
    this.fromCache = false,
    this.steps = const <DVAIFallbackStep>[],
  });

  final String feature;
  final String tenant;
  final String promptId;
  final int promptVersion;
  final String promptFingerprint;
  final DVPromptSource promptSource;

  /// SHA-256 of the prompt text as sent, after exclusion and redaction.
  final String inputHash;

  /// `answered`, `degraded`, `refused` or `unavailable`.
  final String outcome;
  final DateTime at;

  /// The model that answered, for an answer.
  final String? model;
  final String? outputHash;
  final bool fromCache;
  final List<DVAIFallbackStep> steps;
}

/// The most recent run records.
class DVAIRunLog {
  DVAIRunLog({this.capacity = 1000});

  final int capacity;
  final List<DVAIRunRecord> _records = <DVAIRunRecord>[];

  /// Called for every record, for a sink that keeps them longer.
  void Function(DVAIRunRecord record)? onRecord;

  List<DVAIRunRecord> get records => List<DVAIRunRecord>.unmodifiable(_records);

  void add(DVAIRunRecord record) {
    if (_records.length >= capacity) _records.removeAt(0);
    _records.add(record);
    onRecord?.call(record);
  }
}

/// What running a feature produced.
sealed class DVAIFeatureResult {
  const DVAIFeatureResult(this.steps);

  /// Every step down the fallback chain this run took.
  final List<DVAIFallbackStep> steps;
}

class DVAIAnswered extends DVAIFeatureResult {
  const DVAIAnswered({required this.output, required this.run, required List<DVAIFallbackStep> steps})
      : super(steps);

  /// A [DVJsonString] for a text prompt, a [DVJsonMap] for a structured one.
  final DVJsonValue output;
  final DVAIRunRecord run;
}

/// The declared degrade step was taken (`DV-AIOPS-003`).
class DVAIDegraded extends DVAIFeatureResult {
  const DVAIDegraded({required this.reason, required List<DVAIFallbackStep> steps})
      : super(steps);

  final String code = 'DV-AIOPS-003';
  final DVAIFallbackReason reason;
}

/// The budget was spent and nothing declared could answer within it
/// (`DV-AIOPS-002`). This is the default at exhaustion.
class DVAIRefused extends DVAIFeatureResult {
  const DVAIRefused({required this.meter, required List<DVAIFallbackStep> steps})
      : super(steps);

  final String code = 'DV-AIOPS-002';
  final String meter;
}

/// The provider failed and nothing declared could answer (`DV-AIOPS-004`).
class DVAIUnavailable extends DVAIFeatureResult {
  const DVAIUnavailable({required this.error, required List<DVAIFallbackStep> steps})
      : super(steps);

  final String code = 'DV-AIOPS-004';
  final Object error;
}

class _Declared {
  const _Declared(this.feature, this.readable, this.meter);

  final DVAIFeature feature;
  final Map<Type, _Readable> readable;
  final DVMeterDefinition? meter;
}

/// Runs declared AI features.
class DVAIFeatures {
  DVAIFeatures({
    required this.prompts,
    required DVAIAdapter adapter,
    required this.model,
    Map<String, DVAIAdapter> models = const <String, DVAIAdapter>{},
    this.meters,
    Map<String, DVMeterDefinition> meterDefinitions =
        const <String, DVMeterDefinition>{},
    this.cache,
    this.tags = const DVCacheTags(),
    this.cacheTtl,
    List<DVAIContextModel> contextModels = const <DVAIContextModel>[],
    this.policy = const DVAIContextPolicy(),
    DVAIRunLog? runs,
    DVLogger? logger,
    DVTracer? tracer,
    DateTime Function()? clock,
  })  : _adapter = adapter,
        _models = Map<String, DVAIAdapter>.of(models),
        _meterDefinitions = Map<String, DVMeterDefinition>.of(meterDefinitions),
        _contextModels = <Type, DVAIContextModel>{
          for (final DVAIContextModel m in contextModels) m.type: m,
        },
        runs = runs ?? DVAIRunLog(),
        _logger = logger,
        _tracer = tracer,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final DVPrompts prompts;

  /// The primary model's name, as run records and cache keys carry it.
  final String model;
  final DVMeters? meters;
  final DVCacheAdapter? cache;
  final DVCacheTags tags;
  final Duration? cacheTtl;
  final DVAIContextPolicy policy;
  final DVAIRunLog runs;

  final DVAIAdapter _adapter;
  final Map<String, DVAIAdapter> _models;
  final Map<String, DVMeterDefinition> _meterDefinitions;
  final Map<Type, DVAIContextModel> _contextModels;
  final DVLogger? _logger;
  final DVTracer? _tracer;
  final DateTime Function() _clock;
  final Map<String, _Declared> _features = <String, _Declared>{};

  DVLogger get _log => _logger ?? DVObservability.logger;
  DVTracer get _trace => _tracer ?? DVObservability.tracer;

  /// Where these features report. An evaluation of them reports here too, so
  /// a refused gate lands beside the runs it scored.
  DVLogger get logger => _log;

  /// The token estimate budgets are charged with: four characters a token.
  static int estimateTokens(String text) =>
      DVSemanticMetering.estimateTokens(text);

  static final RegExp _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

  DVAIFeature? feature(String id) => _features[id]?.feature;

  /// Declares [feature], refusing a declaration that cannot be honoured.
  void register(DVAIFeature feature) {
    final DVPromptTemplate? template = prompts.template(feature.prompt);
    if (template == null) {
      throw ArgumentError.value(
          feature.prompt, 'prompt', 'no prompt is registered with this id');
    }
    if (_features.containsKey(feature.id)) {
      throw ArgumentError.value(feature.id, 'feature', 'is already registered');
    }
    if (feature.maxOutputTokens < 1) {
      throw ArgumentError.value(
          feature.maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    if (!(feature.evalThreshold >= 0 && feature.evalThreshold <= 1)) {
      throw ArgumentError.value(
          feature.evalThreshold, 'evalThreshold', 'is a share between 0 and 1');
    }

    DVMeterDefinition? meter;
    final DVMeterRef? budget = feature.budget;
    if (budget != null) {
      if (meters == null) {
        throw ArgumentError.value(budget.meter, 'budget',
            'no DVMeters is configured to count it on');
      }
      meter = _meterDefinitions[budget.meter] ??
          (throw ArgumentError.value(
              budget.meter, 'budget', 'names no configured meter'));
    }

    for (int i = 0; i < feature.fallback.length; i++) {
      final DVAIFallback step = feature.fallback[i];
      if (step.isDegrade) {
        if (i != feature.fallback.length - 1) {
          throw ArgumentError.value(feature.fallback, 'fallback',
              'degrade answers every time, so a step after it never runs');
        }
        continue;
      }
      if (step.model != model && !_models.containsKey(step.model)) {
        throw ArgumentError.value(
            step.model, 'fallback', 'names a model with no adapter');
      }
    }

    for (final String tag in feature.cacheTags) {
      for (final RegExpMatch match in _placeholder.allMatches(tag)) {
        if (!template.input.containsKey(match.group(1))) {
          throw ArgumentError.value(tag, 'cacheTags',
              'names {${match.group(1)}}, which the prompt does not take');
        }
      }
    }

    for (final Type named in feature.contextFields.keys) {
      if (!feature.context.contains(named)) {
        throw ArgumentError.value(named, 'contextFields',
            'narrows a model the manifest does not name');
      }
    }
    final Map<Type, _Readable> readable = <Type, _Readable>{};
    for (final Type type in feature.context) {
      final DVAIContextModel descriptor = _contextModels[type] ??
          (throw ArgumentError.value(
              type, 'context', 'has no model descriptor configured'));
      if (policy.forbiddenModels.contains(type)) {
        throw DVAIOpsError(
          'DV-AIOPS-005',
          'feature "${feature.id}" names ${descriptor.name}, which the policy '
              'forbids it to read',
        );
      }
      final List<String>? narrowed = feature.contextFields[type];
      final Set<String> fields;
      if (narrowed == null) {
        fields = descriptor.fields.difference(descriptor.sensitive);
      } else {
        for (final String field in narrowed) {
          if (!descriptor.fields.contains(field)) {
            throw ArgumentError.value(field, 'contextFields',
                'is not a field of ${descriptor.name}');
          }
          if (descriptor.sensitive.contains(field)) {
            throw DVAIOpsError(
              'DV-AIOPS-005',
              'feature "${feature.id}" names ${descriptor.name}.$field, a '
                  'sensitive field; a sensitive field is described, never '
                  'valued',
            );
          }
        }
        fields = narrowed.toSet();
      }
      final Set<String> forbidden = (policy.forbiddenFields[type] ??
              const <String>{})
          .intersection(fields);
      if (forbidden.isNotEmpty) {
        throw DVAIOpsError(
          'DV-AIOPS-005',
          'feature "${feature.id}" reads ${descriptor.name}.'
              '${(forbidden.toList()..sort()).join(', ')}, which the policy '
              'forbids; narrow the manifest with contextFields',
        );
      }
      readable[type] = _Readable(descriptor, fields);
    }

    _features[feature.id] = _Declared(feature, readable, meter);
  }

  /// A context admitting exactly what [feature]'s manifest reads.
  DVAIContext contextFor(String feature) {
    final _Declared declared = _features[feature] ??
        (throw ArgumentError.value(feature, 'feature', 'is not registered'));
    return DVAIContext._(feature, declared.readable);
  }

  /// Runs [featureId] on [input], with [context] from [contextFor].
  ///
  /// [idempotencyKey] defaults to the ambient
  /// [DVMeters.currentIdempotencyKey] and is required for a budgeted feature:
  /// usage recorded without one would be counted again on every retry.
  ///
  /// [bypassCache] neither reads nor writes the cache. An evaluation uses it,
  /// because an answer read from the cache a golden was captured into is the
  /// golden compared with itself.
  Future<DVAIFeatureResult> run(
    String featureId, {
    required Map<String, Object?> input,
    DVAIContext? context,
    String? idempotencyKey,
    bool bypassCache = false,
  }) async {
    final _Declared declared = _features[featureId] ??
        (throw ArgumentError.value(featureId, 'feature', 'is not registered'));
    final DVAIFeature feature = declared.feature;
    if (context != null && context.feature != featureId) {
      throw DVAIOpsError(
        'DV-AIOPS-005',
        'a context built under the manifest of "${context.feature}" was '
            'passed to "$featureId", whose manifest did not admit it',
      );
    }
    _checkInput(prompts.template(feature.prompt)!.input, input);

    final DVMeterDefinition? meter = declared.meter;
    final String? key = (idempotencyKey ?? DVMeters.currentIdempotencyKey)?.trim();
    if (meter != null && (key == null || key.isEmpty)) {
      throw StateError(
        'Feature "$featureId" is budgeted on "${meter.name}" and was run with '
        'no idempotency key and no DVMeters.withIdempotencyKey scope. The '
        'provider is not called: its usage could not be recorded once.',
      );
    }

    final DVResolvedPrompt resolved = await prompts.resolve(feature.prompt);
    final DVPromptVersion prompt = resolved.version;
    final List<String> cacheTags = <String>[
      for (final String tag in feature.cacheTags)
        tag.replaceAllMapped(_placeholder, (Match m) => '${input[m.group(1)]}'),
    ];
    final String rendered = dvRedactSecrets(_render(prompt, input, context));
    final String inputHash = sha256.convert(utf8.encode(rendered)).toString();
    final String tenant = const DVTenants().currentTenant;

    DVAIRunRecord recordRun(String outcome,
        {String? model,
        String? outputHash,
        bool fromCache = false,
        required List<DVAIFallbackStep> steps}) {
      final DVAIRunRecord record = DVAIRunRecord(
        feature: featureId,
        tenant: tenant,
        promptId: prompt.id,
        promptVersion: prompt.version,
        promptFingerprint: prompt.fingerprint,
        promptSource: resolved.source,
        inputHash: inputHash,
        outcome: outcome,
        at: _clock(),
        model: model,
        outputHash: outputHash,
        fromCache: fromCache,
        steps: List<DVAIFallbackStep>.unmodifiable(steps),
      );
      runs.add(record);
      return record;
    }

    final DVSpan span = _trace.startSpan('ai.feature $featureId');
    span
      ..setAttribute('ai.feature', featureId)
      ..setAttribute('ai.prompt.id', prompt.id)
      ..setAttribute('ai.prompt.version', '${prompt.version}')
      ..setAttribute('ai.prompt.fingerprint', prompt.fingerprint)
      ..setAttribute('ai.prompt.source', resolved.source.name);

    final List<DVAIFallbackStep> steps = <DVAIFallbackStep>[];
    final List<DVAIFallback> chain = <DVAIFallback>[
      DVAIFallback.model(model),
      ...feature.fallback,
    ];
    String current = model;
    DVAIFallbackReason? reason;
    Object? failure;
    bool budgetReported = false;

    try {
      for (int i = 0; i < chain.length; i++) {
        final DVAIFallback step = chain[i];
        if (i > 0) {
          final String to = step.isDegrade ? 'degrade' : step.model!;
          steps.add(DVAIFallbackStep(from: current, to: to, reason: reason!));
          _log.log(
            'DV-AIOPS-003: feature "$featureId" stepped from $current to $to '
            '(${reason.name})',
            level: DVLogLevel.info,
            code: 'DV-AIOPS-003',
            context: <String, Object?>{
              'feature': featureId,
              'from': current,
              'to': to,
              'reason': reason.name,
              'tenant': tenant,
            },
          );
          if (!step.isDegrade) current = step.model!;
        }

        if (step.isDegrade) {
          recordRun('degraded', steps: steps);
          span.setAttribute('ai.outcome', 'degraded');
          return DVAIDegraded(reason: reason!, steps: List.unmodifiable(steps));
        }

        final String stepModel = step.model!;
        final DVAIAdapter adapter =
            stepModel == model ? _adapter : _models[stepModel]!;
        // The model is in the key: a fallback's answer is never served as
        // the primary's, which would be a silent substitution by the cache.
        final String cacheKey = 'dvai:$tenant:${prompt.id}@${prompt.version}'
            '#${prompt.fingerprint}:$stepModel:$inputHash';

        if (!bypassCache && cache != null) {
          final DVJsonValue? hit = await _readCache(cacheKey);
          if (hit != null) {
            span
              ..setAttribute('ai.model', stepModel)
              ..setAttribute('ai.cache', 'hit')
              ..setAttribute('ai.outcome', 'answered');
            return DVAIAnswered(
              output: hit,
              steps: List.unmodifiable(steps),
              run: recordRun('answered',
                  model: stepModel,
                  outputHash: _hashOutput(hit),
                  fromCache: true,
                  steps: steps),
            );
          }
        }

        if (meter != null) {
          // Before the call, for the most the call can cost: a budget
          // checked afterwards has already been spent.
          final int worstCase =
              estimateTokens(rendered) + feature.maxOutputTokens;
          final DVMeterOutcome admission =
              await meters!.admits(meter, worstCase);
          if (admission.applied != null && !budgetReported) {
            budgetReported = true;
            _log.log(
              'DV-AIOPS-002: feature "$featureId" is over its token budget on '
              '"${meter.name}"; ${admission.applied!.name} was taken',
              level: DVLogLevel.warn,
              code: 'DV-AIOPS-002',
              context: <String, Object?>{
                'feature': featureId,
                'meter': meter.name,
                'tenant': tenant,
                'behaviour': admission.applied!.name,
                'limit': admission.limit,
                'used': admission.total,
                'requested': worstCase,
              },
            );
          }
          if (!admission.admitted) {
            reason = DVAIFallbackReason.budget;
            continue;
          }
        }

        final DVJsonValue output;
        try {
          output = prompt.schema.isEmpty
              ? DVJsonString(await adapter.chat(rendered, provider: stepModel))
              : DVJsonMap(await adapter.structuredOutput(rendered, prompt.schema));
        } on Exception catch (error) {
          // An Exception is the provider's: an outage, a rejection, a
          // refusal. An Error is a bug and is not fallen back from.
          reason = DVAIFallbackReason.providerFailure;
          failure = error;
          continue;
        }

        final String outputText = jsonEncode(DVJsonCodec.toJson(output));
        if (meter != null) {
          final DVMeterOutcome recorded = await meters!.record(
            meter,
            estimateTokens(rendered) + estimateTokens(outputText),
            idempotencyKey: '$key:ai:$featureId',
          );
          if (!recorded.admitted) {
            _log.log(
              'DV-AIOPS-002: feature "$featureId" answered and its usage was '
              'refused by "${meter.name}": another call took the budget '
              'between the check and the recording',
              level: DVLogLevel.warn,
              code: 'DV-AIOPS-002',
              context: <String, Object?>{
                'feature': featureId,
                'meter': meter.name,
                'tenant': tenant,
                'behaviour': recorded.applied?.name,
                'recorded': false,
              },
            );
          }
        }

        if (!bypassCache && cache != null) {
          tags.tag(cacheKey, cacheTags);
          await cache!.write(
            cacheKey,
            jsonEncode(<String, Object?>{
              'tags': cacheTags,
              'output': DVJsonCodec.toJson(output),
            }),
            cacheTtl,
          );
        }

        span
          ..setAttribute('ai.model', stepModel)
          ..setAttribute('ai.cache', cache == null || bypassCache ? 'off' : 'miss')
          ..setAttribute('ai.outcome', 'answered');
        return DVAIAnswered(
          output: output,
          steps: List.unmodifiable(steps),
          run: recordRun('answered',
              model: stepModel, outputHash: _hashOutput(output), steps: steps),
        );
      }

      if (reason == DVAIFallbackReason.budget) {
        recordRun('refused', steps: steps);
        span.setAttribute('ai.outcome', 'refused');
        return DVAIRefused(meter: meter!.name, steps: List.unmodifiable(steps));
      }

      final Object error = failure!;
      _log.log(
        'DV-AIOPS-004: feature "$featureId" is unavailable: the provider '
        'failed and ${feature.fallback.isEmpty ? 'no fallback is declared' : 'every declared fallback failed'}',
        level: DVLogLevel.error,
        code: 'DV-AIOPS-004',
        context: <String, Object?>{
          'feature': featureId,
          'tenant': tenant,
          'models': <String>[
            for (final DVAIFallback s in chain)
              if (!s.isDegrade) s.model!,
          ],
          // The type and status only. A provider's message or body can quote
          // the prompt back, and the prompt is not the log's to keep.
          'errorType': '${error.runtimeType}',
          if (error is DVAIProviderException) 'provider': error.provider,
          if (error is DVAIProviderException && error.statusCode != null)
            'status': error.statusCode,
        },
      );
      recordRun('unavailable', steps: steps);
      span
        ..status = DVSpanStatus.error
        ..setAttribute('ai.outcome', 'unavailable')
        ..setAttribute('error.type', '${error.runtimeType}');
      return DVAIUnavailable(error: error, steps: List.unmodifiable(steps));
    } on Object catch (error) {
      span
        ..status = DVSpanStatus.error
        ..setAttribute('error.type', '${error.runtimeType}');
      rethrow;
    } finally {
      span.end();
    }
  }

  Future<DVJsonValue?> _readCache(String key) async {
    final Object? raw = await cache!.read(key);
    if (raw is! String) return null;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;
    for (final Object? tag in (decoded['tags'] as List<Object?>?) ?? const <Object?>[]) {
      // Revalidating a tag forgets its keys; an entry one of whose tags no
      // longer holds it is stale however it got past the delete.
      if (!tags.keysForTag('$tag').contains(key)) {
        await cache!.remove(key);
        return null;
      }
    }
    return DVJsonCodec.fromJson(decoded['output']);
  }

  static String _hashOutput(DVJsonValue output) => sha256
      .convert(utf8.encode(jsonEncode(dvCanonicalJson(DVJsonCodec.toJson(output)))))
      .toString();

  static String _render(DVPromptVersion prompt, Map<String, Object?> input,
      DVAIContext? context) {
    final StringBuffer text = StringBuffer(prompt.system)
      ..writeln()
      ..writeln()
      ..writeln('Input:')
      ..write(jsonEncode(dvCanonicalJson(_plain(input))));
    final List<Map<String, Object?>> rows =
        context?._rows ?? const <Map<String, Object?>>[];
    if (rows.isNotEmpty) {
      text
        ..writeln()
        ..writeln()
        ..writeln('Context:')
        ..write(jsonEncode(dvCanonicalJson(rows)));
    }
    return text.toString();
  }

  static void _checkInput(
      Map<String, Type> declared, Map<String, Object?> input) {
    for (final String name in input.keys) {
      if (!declared.containsKey(name)) {
        throw ArgumentError.value(
            name, 'input', 'is not an input the prompt declares');
      }
    }
    for (final MapEntry<String, Type> entry in declared.entries) {
      if (!input.containsKey(entry.key)) {
        throw ArgumentError.value(
            entry.key, 'input', 'is declared by the prompt and was not given');
      }
      if (!_isA(input[entry.key], entry.value)) {
        throw ArgumentError.value(input[entry.key], entry.key,
            'is not a ${entry.value}, which the prompt declares');
      }
    }
  }

  static bool _isA(Object? value, Type type) => switch (type) {
        const (String) => value is String,
        const (int) => value is int,
        const (double) => value is double,
        const (num) => value is num,
        const (bool) => value is bool,
        const (DateTime) => value is DateTime,
        _ => value != null && value.runtimeType == type,
      };
}
