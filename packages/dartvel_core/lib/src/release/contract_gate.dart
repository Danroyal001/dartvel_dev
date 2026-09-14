/// The contract step: gated by the protocol window, not by a timer.
///
/// A contract drops the old shape. It is refused while any protocol version
/// inside the window still reads what it drops (`DV-RELEASE-005`), and while
/// the release being replaced still reads the old shape -- a contract that
/// runs while the previous release serves takes the column that release reads.
/// Neither refusal can be overridden: a dropped column is not restored by
/// saying sorry, and rollback of data is deliberately not offered.
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

    final List<int> served = window.served(lock, now: context.now).toList()
      ..sort();
    final List<String> readers = <String>[];
    for (final int protocol in served) {
      final DVProtocolContract contract = lock.release(protocol)!.contract;
      final List<DVContractDrop> read = <DVContractDrop>[
        for (final DVContractDrop drop in drops)
          if (drop.readBy(contract)) drop,
      ];
      if (read.isNotEmpty) readers.add('protocol $protocol reads ${read.join(', ')}');
    }
    if (readers.isNotEmpty) {
      const String code = 'DV-RELEASE-005';
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

    final DVReleaseRecord? previous = context.previous;
    if (previous != null) {
      final DVReleaseMigrationPhase? phase = previous.schema[migration];
      if (phase == null ||
          phase.index < DVReleaseMigrationPhase.readSwitched.index) {
        return DVGateOutcome.hold(
          name,
          'contract of $migration refused: ${previous.id}, the release being '
          'replaced, was built for ${phase?.name ?? 'the shape before it'} and '
          'still reads what the contract drops',
          overridable: false,
        );
      }
    }
    return DVGateOutcome.pass(
      name,
      evidence: <String, Object?>{'served': served},
    );
  }
}
