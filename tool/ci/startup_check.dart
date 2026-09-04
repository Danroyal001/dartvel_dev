/// Checks that a running application measured its own startup.
///
///     dart tool/ci/startup_check.dart /tmp/diag/linux-live.json
///
/// The four phases are the contract: configure, generated, bindings, first
/// frame. A build that publishes the file and marks none of them has a
/// measurement surface that compiles and reports nothing, which reads as
/// "startup is instant" rather than as "startup was never timed".
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

/// The verdict, as an exit code. Returned rather than exited on so the
/// whole of it is one function with one way out.
int _run(List<String> arguments) {
  final String path =
      arguments.isEmpty ? '/tmp/diag/linux-live.json' : arguments.first;
  final File file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('::error::$path is not there');
    return 1;
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  final Map<String, Object?> live =
      decoded is Map<String, Object?> ? decoded : const <String, Object?>{};
  final Object? measured = live['startup'];
  final Map<String, Object?> startup =
      measured is Map<String, Object?> ? measured : const <String, Object?>{};
  final Object? raw = startup['phases'];
  final List<String> phases = <String>[
    if (raw is List)
      for (final Object? phase in raw)
        if (phase is Map) '${phase['name']}',
  ];

  stdout.writeln('startup phases: $phases total: ${startup['totalMicros']}');

  int failures = 0;
  for (final String expected in const <String>[
    'configure',
    'generated',
    'bindings',
    'first frame',
  ]) {
    if (!phases.contains(expected)) {
      stdout.writeln('::error::startup never marked "$expected"');
      failures++;
    }
  }
  final Object? total = startup['totalMicros'];
  if (total == null || total == 0) {
    stdout.writeln('::error::startup measured nothing');
    failures++;
  }
  return failures == 0 ? 0 : 1;
}
