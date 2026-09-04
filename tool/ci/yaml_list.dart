/// Prints the entries of a top-level YAML list, one per line.
///
///     dart run tool/ci/yaml_list.dart config.yaml classes
///
/// For a CI step that has to walk what a config declares. Reading the YAML
/// rather than grepping it is the point: a class listed under a comment, or
/// indented differently, is still a class the generator was asked for, and a
/// grep that missed one would report a run as complete when it was not.
///
/// Dart because everything else in this repository's CI is.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

/// The verdict, as an exit code. Returned rather than exited on so the
/// whole of it is one function with one way out.
int _run(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: yaml_list.dart <file.yaml> <key>');
    return 2;
  }
  final File file = File(arguments.first);
  if (!file.existsSync()) {
    stderr.writeln('${arguments.first} is not there');
    return 1;
  }
  final Object? document = loadYaml(file.readAsStringSync());
  final Object? entries = document is Map ? document[arguments[1]] : null;
  if (entries is! List) return 0;
  for (final Object? entry in entries) {
    stdout.writeln('$entry');
  }
  return 0;
}
