/// Evaluating an AI feature against golden transcripts.
///
/// A transcript is the gate: deterministic, free to compare, and failing for a
/// reason a reader can see. A rubric model's score is recorded beside each
/// case and never decides one, because a gate that depends on a third party's
/// model version cannot tell a regression from that model changing.
library dartvel_core.ai.eval;

import 'dart:async';
import 'dart:convert';

import '../observability/observability.dart';
import 'ai.dart';
import 'ai_features.dart';
import 'prompts.dart';

/// One recorded input and the output it must produce, under one prompt
/// version.
class DVGoldenTranscript {
  const DVGoldenTranscript({
    required this.name,
    required this.feature,
    required this.promptVersion,
    required this.input,
    required this.expected,
    this.promptFingerprint,
  });

  final String name;
  final String feature;

  /// The version the expected output was produced by. A transcript is
  /// evidence about that version and no other.
  final int promptVersion;

  /// The fingerprint it was produced by, when captured; a stored version
  /// that reused the number with other text is then caught too.
  final String? promptFingerprint;
  final Map<String, Object?> input;
  final DVJsonValue expected;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'feature': feature,
        'promptVersion': promptVersion,
        if (promptFingerprint != null) 'promptFingerprint': promptFingerprint,
        'input': input,
        'expected': DVJsonCodec.toJson(expected),
      };

  factory DVGoldenTranscript.fromJson(Map<String, Object?> json) =>
      DVGoldenTranscript(
        name: json['name']! as String,
        feature: json['feature']! as String,
        promptVersion: json['promptVersion']! as int,
        promptFingerprint: json['promptFingerprint'] as String?,
        input: Map<String, Object?>.of(json['input']! as Map<String, Object?>),
        expected: DVJsonCodec.fromJson(json['expected']),
      );

  static String encodeFile(List<DVGoldenTranscript> transcripts) =>
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'format': 1,
            'transcripts': <Object?>[
              for (final DVGoldenTranscript t in transcripts) t.toJson(),
            ],
          })}\n';

  static List<DVGoldenTranscript> decodeFile(String source) {
    final Object? root = jsonDecode(source);
    if (root is! Map<String, Object?> || root['format'] != 1) {
      throw const FormatException('not a format 1 golden transcript file');
    }
    return <DVGoldenTranscript>[
      for (final Object? item in root['transcripts']! as List<Object?>)
        DVGoldenTranscript.fromJson(item! as Map<String, Object?>),
    ];
  }
}

enum DVAIEvalFailure {
  /// The feature answered something else.
  mismatch,

  /// The transcript was produced by a prompt version other than the one that
  /// answers now.
  staleVersion,

  /// The feature degraded, refused or was unavailable.
  notAnswered,
}

class DVAIEvalCase {
  const DVAIEvalCase({
    required this.name,
    required this.passed,
    required this.expected,
    this.failure,
    this.actual,
    this.model,
    this.rubricScore,
  });

  final String name;
  final bool passed;
  final DVAIEvalFailure? failure;
  final DVJsonValue expected;
  final DVJsonValue? actual;

  /// The model that answered.
  final String? model;

  /// Recorded, never deciding.
  final double? rubricScore;
}

class DVAIEvalGate {
  const DVAIEvalGate({required this.ok, required this.message, this.code});

  final bool ok;

  /// `DV-AIOPS-007` when the gate refuses.
  final String? code;
  final String message;
}

class DVAIEvalReport {
  const DVAIEvalReport({
    required this.feature,
    required this.promptVersion,
    required this.promptFingerprint,
    required this.threshold,
    required this.cases,
    required this.gate,
  });

  final String feature;
  final int promptVersion;
  final String promptFingerprint;
  final double threshold;
  final List<DVAIEvalCase> cases;
  final DVAIEvalGate gate;

  int get passed => cases.where((DVAIEvalCase c) => c.passed).length;

  double get score => cases.isEmpty ? 0 : passed / cases.length;
}

/// Scores an answer with a model. Recorded beside the case, never deciding.
typedef DVAIRubric = FutureOr<double> Function(
    DVGoldenTranscript transcript, DVJsonValue actual);

class DVAIEval {
  DVAIEval(this.features, {this.rubric, DVLogger? logger}) : _logger = logger;

  final DVAIFeatures features;
  final DVAIRubric? rubric;
  final DVLogger? _logger;

  DVLogger get _log => _logger ?? features.logger;

  static int _sequence = 0;

  /// Runs [feature] on each transcript and gates on the declared threshold.
  ///
  /// Never from the cache, and never passing with nothing to compare.
  Future<DVAIEvalReport> run(
      String feature, List<DVGoldenTranscript> transcripts) async {
    final DVAIFeature declared = features.feature(feature) ??
        (throw ArgumentError.value(feature, 'feature', 'is not registered'));
    for (final DVGoldenTranscript t in transcripts) {
      if (t.feature != feature) {
        throw ArgumentError.value(t.name, 'transcripts',
            'belongs to "${t.feature}", not "$feature"');
      }
    }
    final DVResolvedPrompt resolved =
        await features.prompts.resolve(declared.prompt);
    final int run = ++_sequence;

    final List<DVAIEvalCase> cases = <DVAIEvalCase>[];
    for (final DVGoldenTranscript t in transcripts) {
      cases.add(await _case(feature, t, run));
    }

    final double threshold = declared.evalThreshold;
    final int passed = cases.where((DVAIEvalCase c) => c.passed).length;
    final DVAIEvalGate gate;
    if (cases.isEmpty) {
      gate = const DVAIEvalGate(
        ok: false,
        code: 'DV-AIOPS-007',
        message: 'no golden transcripts were given; an evaluation of nothing '
            'is not a pass',
      );
    } else if (passed / cases.length < threshold) {
      gate = DVAIEvalGate(
        ok: false,
        code: 'DV-AIOPS-007',
        message: 'eval scored $passed of ${cases.length}, below the declared '
            'threshold of $threshold',
      );
    } else {
      gate = DVAIEvalGate(
          ok: true, message: 'eval scored $passed of ${cases.length}');
    }
    if (!gate.ok) {
      _log.log(
        'DV-AIOPS-007: feature "$feature" ${gate.message}',
        level: DVLogLevel.error,
        code: 'DV-AIOPS-007',
        context: <String, Object?>{
          'feature': feature,
          'passed': passed,
          'total': cases.length,
          'threshold': threshold,
          'promptVersion': resolved.version.version,
          'failed': <String>[
            for (final DVAIEvalCase c in cases)
              if (!c.passed) c.name,
          ],
        },
      );
    }
    return DVAIEvalReport(
      feature: feature,
      promptVersion: resolved.version.version,
      promptFingerprint: resolved.version.fingerprint,
      threshold: threshold,
      cases: List<DVAIEvalCase>.unmodifiable(cases),
      gate: gate,
    );
  }

  Future<DVAIEvalCase> _case(
      String feature, DVGoldenTranscript t, int run) async {
    final DVAIFeatureResult result = await features.run(
      feature,
      input: t.input,
      bypassCache: true,
      idempotencyKey: 'dartvel-eval:$feature:$run:${t.name}',
    );
    if (result is! DVAIAnswered) {
      return DVAIEvalCase(
          name: t.name,
          passed: false,
          failure: DVAIEvalFailure.notAnswered,
          expected: t.expected);
    }
    final double? score =
        rubric == null ? null : (await rubric!(t, result.output)).toDouble();
    final bool sameVersion = result.run.promptVersion == t.promptVersion &&
        (t.promptFingerprint == null ||
            t.promptFingerprint == result.run.promptFingerprint);
    if (!sameVersion) {
      return DVAIEvalCase(
        name: t.name,
        passed: false,
        failure: DVAIEvalFailure.staleVersion,
        expected: t.expected,
        actual: result.output,
        model: result.run.model,
        rubricScore: score,
      );
    }
    final bool matches = _canonical(result.output) == _canonical(t.expected);
    return DVAIEvalCase(
      name: t.name,
      passed: matches,
      failure: matches ? null : DVAIEvalFailure.mismatch,
      expected: t.expected,
      actual: result.output,
      model: result.run.model,
      rubricScore: score,
    );
  }

  /// Runs [feature] once, fresh, and returns what it produced as a
  /// transcript. Capturing is a deliberate act a person reviews; [run] never
  /// writes one.
  Future<DVGoldenTranscript> capture(
    String feature, {
    required String name,
    required Map<String, Object?> input,
  }) async {
    final DVAIFeatureResult result = await features.run(
      feature,
      input: input,
      bypassCache: true,
      idempotencyKey: 'dartvel-eval-capture:$feature:${++_sequence}:$name',
    );
    if (result is! DVAIAnswered) {
      throw StateError('feature "$feature" did not answer ($result); there is '
          'nothing to capture');
    }
    return DVGoldenTranscript(
      name: name,
      feature: feature,
      promptVersion: result.run.promptVersion,
      promptFingerprint: result.run.promptFingerprint,
      input: Map<String, Object?>.of(input),
      expected: result.output,
    );
  }

  static String _canonical(DVJsonValue value) =>
      jsonEncode(dvCanonicalJson(DVJsonCodec.toJson(value)));
}
