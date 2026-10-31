import 'dart:io';

import 'package:oracles/oracles.dart';

const _usage = '''
Usage: dart bin/compare.dart <dumpA> <dumpB>

Compares every output file of two dumps byte for byte.
Exit 0: identical. Exit 1: differences, listed. Exit 64: bad usage.''';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final Comparison result;
  try {
    result = compareDumps(args[0], args[1]);
  } on ArgumentError catch (e) {
    stderr.writeln('${e.message}: ${e.invalidValue}');
    exitCode = 64;
    return;
  }
  for (final note in result.notes) {
    stdout.writeln('note: $note');
  }
  if (result.identical) {
    stdout.writeln('identical');
    return;
  }
  for (final difference in result.differences) {
    stdout.writeln(difference);
  }
  stdout.writeln('${result.differences.length} file(s) differ');
  exitCode = 1;
}
