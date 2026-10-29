/// Converts every `.dart` file under the given directories to the `.dv`
/// dialect and back, and reports what did not come back byte for byte.
///
///   dart run bin/roundtrip.dart ../../packages ~/src/flutter/packages/flutter
///   dart run bin/roundtrip.dart --failures failures.tsv ../../packages
library;

import 'dart:io';

import 'package:dv_dialect/corpus.dart';

void main(List<String> args) {
  String? failuresOut;
  final roots = <Directory>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--failures' && i + 1 < args.length) {
      failuresOut = args[++i];
    } else {
      roots.add(Directory(args[i]));
    }
  }
  if (roots.isEmpty || roots.any((root) => !root.existsSync())) {
    stderr.writeln('usage: roundtrip.dart [--failures FILE] DIR...');
    exitCode = 64;
    return;
  }

  final report = roundTripCorpus(roots);
  String percent(double share) => '${(share * 100).toStringAsFixed(2)}%';
  stdout
    ..writeln(
      'files:         ${report.files} standard Dart '
      '(${report.notStandard} not standard Dart, left out)',
    )
    ..writeln(
      'round-tripped: ${report.identical} '
      '(${percent(report.identicalShare)}) byte for byte',
    )
    ..writeln(
      'semicolons:    ${report.removed} of ${report.semicolons} '
      'optional (${percent(report.removedShare)})',
    )
    ..writeln('failures:      ${report.failures.length}');
  for (final failure in report.failures.take(20)) {
    stdout.writeln('  ${failure.path}:${failure.line}');
  }
  if (failuresOut != null) {
    File(failuresOut).writeAsStringSync(
      [
        for (final failure in report.failures)
          '${failure.path}\t${failure.line}',
      ].join('\n'),
    );
    stdout.writeln('Wrote $failuresOut');
  }
}
