// Builds the inputs of the type-flow port's oracle (not a mirrored file; see
// ../README.md): this checkout's VM platform (kernel's
// oracle/compile_vm_platform.dart, as pkg/kernel/rust/oracle/build_corpus.dart
// builds it), then, for every testcase of
// pkg/vm/test/transformations/type_flow/summary_collector_test.dart, the
// kernel that test compiles and upstream's summaries printed from that
// kernel read back from its bytes (oracle/print_summaries.dart). Every tool
// runs from source, from this checkout, on the Dart VM running this script.
//
// Usage: dart build_inputs.dart <sdk root> <out dir>
//
// Packages that the SDK takes from DEPS come from the pub cache, at the
// versions in [pubPackages] (the same as the kernel oracle's).
import 'dart:io';

const List<String> sdkPackages = [
  'kernel',
  'front_end',
  'vm',
  '_fe_analyzer_shared',
  'meta',
  'build_integration',
  'vm_service',
  'expect',
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

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: build_inputs.dart <sdk root> <out dir>');
    exit(64);
  }
  final String sdk = Directory(arguments[0]).absolute.path;
  final Directory out = Directory(arguments[1])..createSync(recursive: true);
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

  final String dart = Platform.resolvedExecutable;
  final String platform = '${out.path}/vm_platform.dill';
  if (!File(platform).existsSync()) {
    await run(dart, [
      '--packages=${packageConfig.path}',
      '$sdk/pkg/kernel/rust/oracle/compile_vm_platform.dart',
      'dart:core',
      '-Ddart.vm.product=false',
      '-Ddart.vm.asan=false',
      '-Ddart.vm.msan=false',
      '-Ddart.vm.tsan=false',
      '-Ddart.isVM=true',
      '--single-root-scheme=org-dartlang-sdk',
      '--single-root-base=$sdk/',
      'org-dartlang-sdk:///sdk/lib/libraries.json',
      '${out.path}/unused-vm-platform.dill',
      platform,
      '${out.path}/vm_outline.dill',
    ]);
    for (final String name in ['unused-vm-platform.dill', 'vm_outline.dill']) {
      final File file = File('${out.path}/$name');
      if (file.existsSync()) file.deleteSync();
    }
  }

  final String printSummaries = generatePrintSummaries(sdk, out.path);
  await run(dart, [
    '--packages=${packageConfig.path}',
    printSummaries,
    platform,
    '$sdk/pkg/vm/testcases/transformations/type_flow/summary_collector',
    '${out.path}/summary_collector',
  ]);
}

Future<void> run(String executable, List<String> arguments) async {
  final Process process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln('${arguments[1]}: exit $exitCode');
    exit(exitCode);
  }
}

/// Writes `<out>/print_summaries.dart`: upstream's summary_collector_test.dart
/// up to its `class TestOptions`, unchanged but for the two imports this
/// checkout cannot resolve without dart2wasm and `package:test` (neither
/// is used by the part copied), followed by print_summaries_main.dart.
String generatePrintSummaries(String sdk, String out) {
  final List<String> test = File(
    '$sdk/pkg/vm/test/transformations/type_flow/summary_collector_test.dart',
  ).readAsLinesSync();
  final int end = test.indexWhere((String l) => l.startsWith('class TestOptions'));
  if (end < 0) throw 'summary_collector_test.dart: no class TestOptions';
  const Set<String> dropped = {
    "import 'package:test/test.dart';",
    "import '../../common_test_utils.dart';",
  };
  const List<String> added = [
    "import 'dart:typed_data';",
    "import 'package:kernel/binary/ast_from_binary.dart' show BinaryBuilder;",
    "import 'package:kernel/binary/ast_to_binary.dart' show BinaryPrinter, BytesSink;",
  ];
  final List<String> lines = [];
  int droppedCount = 0;
  for (final String line in test.sublist(0, end)) {
    if (dropped.contains(line)) {
      droppedCount++;
      continue;
    }
    lines.add(line);
    if (line == "import 'dart:io';") lines.addAll(added);
  }
  if (droppedCount != dropped.length) {
    throw 'summary_collector_test.dart: imports changed; update build_inputs.dart';
  }
  lines.addAll(
    File('$sdk/pkg/vm/rust/oracle/print_summaries_main.dart').readAsLinesSync(),
  );
  final String path = '$out/print_summaries.dart';
  File(path).writeAsStringSync('${lines.join('\n')}\n');
  return path;
}
