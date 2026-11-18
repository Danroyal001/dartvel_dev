// Builds the inputs of the types oracle (not a mirrored file; see
// ../README.md), on the Dart VM running this script, with this checkout's
// `pkg/kernel` and `pkg/vm` from source:
//
//   <out>/types/types_test.dart  upstream's
//       test/transformations/type_flow/types_test.dart, unchanged but for
//       its `package:test` import, which points at types_test_shim.dart
//       (copied beside it), so the test's own body runs and every `expect`
//       prints a line;
//   <out>/types/types_test.txt   what it prints (all lines must be `ok`);
//   <out>/types/types.dill and lattice_cases.txt  from types_lattice.dart.
//
// Usage: dart build_types_inputs.dart <sdk root> <out dir>
import 'dart:io';

const List<String> sdkPackages = [
  'kernel',
  'front_end',
  'vm',
  '_fe_analyzer_shared',
  'meta',
];

const List<String> pubPackages = [
  'args-2.7.0',
  'collection-1.19.1',
  'crypto-3.0.7',
  'typed_data-1.4.0',
  'package_config-2.2.0',
  'path-1.9.1',
  'yaml-3.1.3',
  'source_span-1.10.2',
  'string_scanner-1.4.1',
  'term_glyph-1.2.2',
  'record_use-1.1.1',
  'pub_semver-2.2.0',
];

const String testImport = "import 'package:test/test.dart';";

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: build_types_inputs.dart <sdk root> <out dir>');
    exit(64);
  }
  final String sdk = Directory(arguments[0]).absolute.path;
  final Directory out = Directory('${arguments[1]}/types')
    ..createSync(recursive: true);
  final String pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';

  final File packageConfig = File('${out.path}/package_config.json');
  final List<String> entries = [
    for (final String name in sdkPackages)
      '{"name": "$name", "rootUri": "file://$sdk/pkg/$name/", '
          '"packageUri": "lib/"}',
    for (final String versioned in pubPackages)
      '{"name": "${versioned.substring(0, versioned.lastIndexOf('-'))}", '
          '"rootUri": "file://$pubCache/hosted/pub.dev/$versioned/", '
          '"packageUri": "lib/"}',
  ];
  packageConfig.writeAsStringSync(
    '{"configVersion": 2, "packages": [\n  ${entries.join(',\n  ')}\n]}\n',
  );

  final String oracle = '$sdk/pkg/vm/rust/oracle';
  File('$oracle/types_test_shim.dart').copySync(
    '${out.path}/types_test_shim.dart',
  );
  final String test = File(
    '$sdk/pkg/vm/test/transformations/type_flow/types_test.dart',
  ).readAsStringSync();
  if (testImport.allMatches(test).length != 1) {
    throw 'types_test.dart: its package:test import changed; '
        'update build_types_inputs.dart';
  }
  File('${out.path}/types_test.dart').writeAsStringSync(
    test.replaceFirst(testImport, "import 'types_test_shim.dart';"),
  );

  final String dart = Platform.resolvedExecutable;
  final ProcessResult result = await Process.run(dart, [
    '--packages=${packageConfig.path}',
    '${out.path}/types_test.dart',
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw 'types_test.dart: exit ${result.exitCode}';
  }
  final String printed = result.stdout as String;
  File('${out.path}/types_test.txt').writeAsStringSync(printed);
  final List<String> lines = printed.trimRight().split('\n');
  final int failures = lines.where((String l) => !l.startsWith('ok ')).length;
  stdout.writeln('types_test.dart: ${lines.length} expects, $failures failed');
  if (failures != 0) exit(1);

  final Process lattice = await Process.start(dart, [
    '--packages=${packageConfig.path}',
    '$oracle/types_lattice.dart',
    out.path,
  ], mode: ProcessStartMode.inheritStdio);
  final int exitCode = await lattice.exitCode;
  if (exitCode != 0) throw 'types_lattice.dart: exit $exitCode';
}
