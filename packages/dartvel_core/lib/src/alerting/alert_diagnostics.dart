/// Where the alerting runtime reports its `DV-ALERT-*` codes by default.
library;

import '../diagnostics/diagnostics.dart';
import '../observability/observability.dart';

/// Logs [code] at the level the registry assigns it.
void dvLogAlertDiagnostic(String code, String message) {
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
