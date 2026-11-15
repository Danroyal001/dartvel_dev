// Builds the round-trip oracle's corpus (not a mirrored file; see
// ../README.md): this checkout's VM platform, and kernel for each program in
// tests/kernel_corpus and each input of the type-flow analysis's tests,
// compiled plain and with --aot. Every tool runs from source, from this
// checkout, on the Dart VM running this script.
//
// Usage: dart build_corpus.dart <sdk root> <out dir> [--no-type-flow-inputs]
//
// Packages that the SDK takes from DEPS come from the pub cache, at the
// versions in [pubPackages].
import 'dart:io';

const List<String> sdkPackages = [
  'kernel',
  'front_end',
  'vm',
  '_fe_analyzer_shared',
  'meta',
  'build_integration',
  'vm_service',
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
  if (arguments.length < 2) {
    stderr.writeln(
      'usage: build_corpus.dart <sdk root> <out dir> [--no-type-flow-inputs]',
    );
    exit(64);
  }
  final String sdk = Directory(arguments[0]).absolute.path;
  final Directory out = Directory(arguments[1])..createSync(recursive: true);
  final bool typeFlowInputs = !arguments.contains('--no-type-flow-inputs');
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
      '$sdk/pkg/front_end/tool/compile_platform.dart',
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
    // Only the full platform is part of the corpus.
    for (final String name in ['unused-vm-platform.dill', 'vm_outline.dill']) {
      final File file = File('${out.path}/$name');
      if (file.existsSync()) file.deleteSync();
    }
  }

  final List<File> programs = [
    ...dartFiles('$sdk/pkg/kernel/rust/tests/kernel_corpus'),
    if (typeFlowInputs)
      ...dartFiles('$sdk/pkg/vm/testcases/transformations/type_flow/transformer'),
  ];
  for (final File program in programs) {
    final String name = program.uri.pathSegments.last.replaceAll('.dart', '');
    for (final bool aot in [false, true]) {
      final String output = '${out.path}/$name${aot ? '-aot' : ''}.dill';
      if (File(output).existsSync()) continue;
      await run(dart, [
        '--packages=${packageConfig.path}',
        '$sdk/pkg/vm/bin/gen_kernel.dart',
        '--platform=$platform',
        if (aot) '--aot',
        '--output=$output',
        program.path,
      ], allowFailure: true);
    }
  }
}

List<File> dartFiles(String directory) {
  final List<File> files = Directory(directory)
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

Future<void> run(
  String executable,
  List<String> arguments, {
  bool allowFailure = false,
}) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    stderr.writeln('${arguments.last}: exit ${result.exitCode}');
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    if (!allowFailure) exit(result.exitCode);
  }
}
