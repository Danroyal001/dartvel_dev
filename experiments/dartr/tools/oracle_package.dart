// Prepares the pub package of a Dart oracle in tools/ and prints the path of
// its package config, for `dart --packages=<it>` and
// `dart compile exe --packages=<it>`:
//
//   dart tools/oracle_package.dart [oracle | diagnostics_oracle]
//
// The oracles depend on the analyzer, _fe_analyzer_shared and linter of the
// Dart SDK source checkout dartr ports: DARTR_DART_SDK_SOURCE, else
// third_party/dart-sdk. See `oraclePackageConfig` in common/support.dart.

import 'dart:io';

import 'common/support.dart';

Future<void> main(List<String> arguments) async {
  final name = arguments.isEmpty ? 'oracle' : arguments.first;
  if (arguments.length > 1 ||
      !File('$root/tools/$name/pubspec.yaml').existsSync()) {
    stderr.writeln(
      'usage: dart tools/oracle_package.dart [oracle | diagnostics_oracle]',
    );
    exit(64);
  }
  try {
    stdout.writeln(await oraclePackageConfig(name: name));
  } on ToolError catch (e) {
    stderr.writeln('oracle_package.dart: $e');
    exit(1);
  }
}
