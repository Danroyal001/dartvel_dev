/// Where the release pipeline reports its `DV-RELEASE-*` codes.
library;

import '../diagnostics/diagnostics.dart';
import '../observability/observability.dart';

/// Receives a diagnostic code and its message.
typedef DVReleaseDiagnosticSink = void Function(String code, String message);

/// One diagnostic raised while planning, gating, rolling out or rolling back.
final class DVReleaseFinding {
  DVReleaseFinding(this.code, this.message) : level = _registered(code).level;

  /// A `DV-RELEASE-*` code from the diagnostic registry.
  final String code;

  /// The registry's level for [code], so a finding cannot disagree with it.
  final String level;

  final String message;

  static DVDiagnostic _registered(String code) {
    final DVDiagnostic? diagnostic = DVDiagnostics.find(code);
    if (diagnostic == null) {
      throw ArgumentError.value(code, 'code', 'not a registered diagnostic');
    }
    return diagnostic;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'level': level,
    'message': message,
  };

  @override
  String toString() => '$code ($level): $message';
}

/// Logs [code] at the level the registry assigns it.
void dvLogReleaseDiagnostic(String code, String message) {
  final String level = DVDiagnostics.find(code)?.level ?? 'warning';
  DVObservability.log(
    '$code: $message',
    level: switch (level) {
      'debug' => DVLogLevel.debug,
      'info' => DVLogLevel.info,
      'error' => DVLogLevel.error,
      _ => DVLogLevel.warn,
    },
    code: code,
  );
}
