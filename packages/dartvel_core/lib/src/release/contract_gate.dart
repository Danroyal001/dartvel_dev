/// The contract step: gated by the protocol window, not by a timer.
///
/// A contract stops keeping the old shape current, and a later release drops
/// it. It is refused while any protocol version inside the window still reads
/// what it drops (`DV-RELEASE-005`), and while the release being replaced
/// still reads the old shape -- a contract that runs while the previous
/// release serves takes the column that release reads. Neither refusal can be
/// overridden: a dropped column is not restored by saying sorry, and rollback
/// of data is deliberately not offered.
///
/// The decision itself is [DVContractDecision], and Schema Evolution's tracker
/// asks it too, so the gate and the tracker cannot answer the same question
/// two ways.
library;

import '../protocol/contract.dart';
import 'release_diagnostics.dart';
import 'release_gates.dart';
import 'release_record.dart';

/// Part of the protocol shape a contract step removes.
final class DVContractDrop {
  /// A field of a model.
  const DVContractDrop.field(this.model, String this.field);

  /// A whole model.
  const DVContractDrop.model(this.model) : field = null;

  final String model;
  final String? field;

  bool readBy(DVProtocolContract contract) {
    final DVProtocolModel? m = contract.model(model);
    if (m == null) return false;
    return field == null || m.field(field!) != null;
  }

  @override
  String toString() => field == null ? model : '$model.$field';
}

/// The release a contract would replace, and the phase it was built for.
typedef DVContractReplacing = ({
  String release,
  DVReleaseMigrationPhase? builtFor,
});

/// Whether a contract may run.
///
/// One decision behind two codes: `DV-RELEASE-005` from [DVContractStepGate]
/// and `DV-SCHEMA-005` from Schema Evolution's tracker. Each caller supplies
/// what it knows -- the gate reads the window from the protocol lock, the
/// tracker is given the versions seen calling -- and neither keeps its own
/// copy of the rule.
final class DVContractDecision {
  const DVContractDecision._({
    required this.windowed,
    required this.readers,
    required this.replacing,
  });

  /// Decides.
  ///
  /// [windowed] is every protocol version inside the window, or null when
  /// nobody said; null is refused rather than read as "no clients".
  /// [readsOldShape] says whether a version still reads what the contract
  /// drops. [replacing] is the release the contract would replace, or null on
  /// a first deploy.
  factory DVContractDecision.evaluate({
    required Iterable<int>? windowed,
    required bool Function(int protocol) readsOldShape,
    required DVContractReplacing? replacing,
  }) {
    final List<int>? sorted = windowed == null
        ? null
        : (windowed.toSet().toList()..sort());
    return DVContractDecision._(
      windowed: sorted == null ? null : List<int>.unmodifiable(sorted),
      readers: List<int>.unmodifiable(<int>[
        for (final int protocol in sorted ?? const <int>[])
          if (readsOldShape(protocol)) protocol,
      ]),
      replacing: replacing,
    );
  }

  /// Whether a release built for [phase] still reads the old shape: anything
  /// before the read switch, and a release that names no phase at all.
  static bool builtToReadOldShape(DVReleaseMigrationPhase? phase) =>
      phase == null || phase.index < DVReleaseMigrationPhase.readSwitched.index;

  /// The protocol versions inside the window, sorted; null when not known.
  final List<int>? windowed;

  /// The windowed versions that still read what the contract drops.
  final List<int> readers;

  final DVContractReplacing? replacing;

  bool get windowKnown => windowed != null;

  /// The release being replaced still reads the old shape.
  bool get replacingReadsOldShape {
    final DVContractReplacing? r = replacing;
    return r != null && builtToReadOldShape(r.builtFor);
  }

  bool get allowed => windowKnown && readers.isEmpty && !replacingReadsOldShape;
}

/// Refuses a contract step while anything still reads what it drops.
final class DVContractStepGate implements DVReleaseGate {
  DVContractStepGate({
    required this.migration,
    required this.drops,
    required this.lock,
    this.window = const DVProtocolWindow(),
    String? name,
    DVReleaseDiagnosticSink? onDiagnostic,
  }) : name = name ?? 'contract:$migration',
       _diagnose = onDiagnostic ?? dvLogReleaseDiagnostic {
    if (drops.isEmpty) {
      throw ArgumentError.value(
        drops,
        'drops',
        'a contract step that drops nothing from the protocol shape has '
            'nothing to check; name what it drops',
      );
    }
  }

  /// The expand/contract migration being contracted.
  final String migration;
  final List<DVContractDrop> drops;

  /// The protocol lock of the release that runs the contract.
  final DVProtocolLock lock;
  final DVProtocolWindow window;
  final DVReleaseDiagnosticSink _diagnose;

  @override
  final String name;

  @override
  Set<DVReleasePhase> get phases => const <DVReleasePhase>{
    DVReleasePhase.beforeDeploy,
  };

  List<DVContractDrop> _readBy(int protocol) {
    final DVProtocolContract contract = lock.release(protocol)!.contract;
    return <DVContractDrop>[
      for (final DVContractDrop drop in drops)
        if (drop.readBy(contract)) drop,
    ];
  }

  @override
  DVGateOutcome evaluate(DVReleaseGateContext context) {
    final int? locked = lock.current?.protocol;
    if (locked != context.candidate.protocolVersion) {
      return DVGateOutcome.hold(
        name,
        'the protocol lock is at ${locked ?? 'no version'} and release '
        '${context.candidate.id} records protocol '
        '${context.candidate.protocolVersion}; the window cannot be read for it',
        overridable: false,
      );
    }

    final DVReleaseRecord? previous = context.previous;
    final DVContractDecision decision = DVContractDecision.evaluate(
      windowed: window.served(lock, now: context.now),
      readsOldShape: (int protocol) => _readBy(protocol).isNotEmpty,
      replacing: previous == null
          ? null
          : (release: previous.id, builtFor: previous.schema[migration]),
    );
    final List<int> served = decision.windowed!;

    if (decision.readers.isNotEmpty) {
      const String code = 'DV-RELEASE-005';
      final List<String> readers = <String>[
        for (final int protocol in decision.readers)
          'protocol $protocol reads ${_readBy(protocol).join(', ')}',
      ];
      final String message =
          'contract of $migration refused: ${readers.join('; ')}, inside the '
          'window $served';
      _diagnose(code, message);
      return DVGateOutcome.hold(
        name,
        message,
        code: code,
        overridable: false,
        evidence: <String, Object?>{'served': served, 'readers': readers},
      );
    }

    if (decision.replacingReadsOldShape) {
      final DVContractReplacing replacing = decision.replacing!;
      return DVGateOutcome.hold(
        name,
        'contract of $migration refused: ${replacing.release}, the release '
        'being replaced, was built for '
        '${replacing.builtFor?.name ?? 'the shape before it'} and still reads '
        'what the contract drops',
        overridable: false,
      );
    }
    return DVGateOutcome.pass(
      name,
      evidence: <String, Object?>{'served': served},
    );
  }
}
