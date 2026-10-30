// Dart source: pkg/analyzer/lib/src/lint/registry.dart
//
// Verifies the metadata of every registered lint rule against the pinned
// Dart linter: `tools/oracle/bin/lints_metadata.dart` against
// `lints_dump --metadata`. A port of upstream dartr's
// tools/lints_metadata_differential.py; it writes the same files.
//
//   dart tools/lints_metadata_differential.dart --output target/lints/metadata
//       [--binary target/debug/lints_dump] [--packages <package_config.json>]
//
// The oracle runs with the package config of `--packages`, else
// DARTR_ORACLE_PACKAGE_CONFIG, else the oracle package that
// common/support.dart prepares against the Dart SDK source checkout
// (DARTR_DART_SDK_SOURCE, else third_party/dart-sdk). Exit code 0 when the
// metadata is equal, 1 when it differs or the run fails.

import 'dart:convert';
import 'dart:io';

import 'common/support.dart';

Future<void> main(List<String> arguments) async {
  var binary = '$root/target/debug/lints_dump';
  String? output;
  String? packages;
  for (var i = 0; i < arguments.length; i++) {
    var argument = arguments[i];
    String? inline;
    final equals = argument.indexOf('=');
    if (argument.startsWith('--') && equals > 0) {
      inline = argument.substring(equals + 1);
      argument = argument.substring(0, equals);
    }
    String value() {
      if (inline != null) return inline;
      if (i + 1 >= arguments.length) {
        stderr.writeln('argument $argument: expected one argument');
        exit(2);
      }
      return arguments[++i];
    }

    switch (argument) {
      case '--binary':
        binary = value();
      case '--output':
        output = value();
      case '--packages':
        packages = value();
      default:
        stderr.writeln('unrecognized arguments: $argument');
        exit(2);
    }
  }
  if (output == null) {
    stderr.writeln('the following arguments are required: --output');
    exit(2);
  }
  try {
    final differ = await _run(
      resolvePath(binary),
      resolvePath(output),
      packages == null ? null : resolvePath(packages),
    );
    exit(differ ? 1 : 0);
  } on ToolError catch (e) {
    stderr.writeln('lints_metadata_differential.dart: $e');
    exit(1);
  }
}

Future<bool> _run(String binary, String output, String? packages) async {
  Directory(output).createSync(recursive: true);
  packages ??= await oraclePackageConfig();
  if (!File(packages).existsSync()) {
    throw ToolError('No package config at $packages');
  }
  await pinnedDartVersion();
  final oracle = await runProcess(dartBinary(), [
    '--packages=${resolvePath(packages)}',
    '$root/tools/oracle/bin/lints_metadata.dart',
  ]);
  File('$output/oracle.json').writeAsStringSync(oracle.stdout);
  File('$output/oracle.stderr.log').writeAsStringSync(oracle.stderr);
  if (oracle.exitCode != 0) throw ToolError(oracle.stderr);
  final rust = await checkOutput(binary, ['--metadata']);
  File('$output/dartr.json').writeAsStringSync(rust);
  final expected = jsonDecode(oracle.stdout) as List;
  final actual = jsonDecode(rust) as List;
  final diffs = <Map<String, Object?>>[];
  if (expected.length != actual.length) {
    diffs.add({
      'count': {'oracle': expected.length, 'dartr': actual.length},
    });
  }
  for (var i = 0; i < expected.length && i < actual.length; i++) {
    if (!jsonEquals(expected[i], actual[i])) {
      diffs.add({'index': i, 'oracle': expected[i], 'dartr': actual[i]});
    }
  }
  File('$output/diffs.json').writeAsStringSync('${pyJson(diffs, indent: 2)}\n');
  final summary = {
    'rules': expected.length,
    'matched': expected.length - diffs.length,
    'differences': diffs.length,
  };
  File('$output/summary.json')
      .writeAsStringSync('${pyJson(summary, indent: 2)}\n');
  stdout.writeln(pyJson(summary, indent: 2));
  return diffs.isNotEmpty;
}
