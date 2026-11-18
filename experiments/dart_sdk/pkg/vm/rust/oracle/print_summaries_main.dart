// The driver of upstream's side of the summary oracle (not a mirrored file;
// see ../README.md). build_inputs.dart appends it to upstream's own
// pkg/vm/test/transformations/type_flow/summary_collector_test.dart, copied
// unchanged up to its `class TestOptions` except for two imports
// (`package:test`, whose `fail` and `test` are not used below, and
// `../../common_test_utils.dart`, which needs dart2wasm), so the summaries
// below are printed by the test's own `PrintSummaries`.
//
// For every testcase it compiles the program as the test's
// `compileTestCaseToKernelProgram` does (VmTarget, the platform as SDK
// summary, the main library renamed `#lib`), writes that kernel to
// `<out>/<name>.dill`, then prints the summaries twice: from the component
// in memory (what the test checks) and from a component read back from the
// bytes just written (what the Rust port reads). Both must equal the
// testcase's `.expect` file, so the `.dill` carries everything the test's
// output depends on.
//
// Usage: (generated file) <platform.dill> <testcases dir> <out dir>

Future<Component> compileForOracle(Uri source, Uri platform) async {
  final options = new CompilerOptions()
    ..target = new VmTarget(new TargetFlags())
    ..sdkSummary = platform
    ..environmentDefines = <String, String>{}
    ..explicitExperimentalFlags = parseExperimentalFlags(
      parseExperimentalArguments(null),
      onError: (String message) {
        throw message;
      },
    )
    ..onDiagnostic = (CfeDiagnosticMessage message) {
      throw "Compilation error: ${message.plainTextFormatted.join('\n')}";
    };
  final Component component = (await kernelForProgram(
    source,
    options,
  ))!.component!;
  component.mainMethod!.enclosingLibrary.name = '#lib';
  return component;
}

String summariesOf(Component component) {
  final Target target = new VmTarget(new TargetFlags());
  final Library library = component.mainMethod!.enclosingLibrary;
  final CoreTypes coreTypes = new CoreTypes(component);
  final ClosedWorldClassHierarchy hierarchy =
      new ClassHierarchy(component, coreTypes) as ClosedWorldClassHierarchy;
  final typeEnvironment = new TypeEnvironment(coreTypes, hierarchy);
  return new PrintSummaries(
    target,
    typeEnvironment,
    coreTypes,
    hierarchy,
  ).print(library);
}

Future<void> main(List<String> arguments) async {
  final Uri platform = Uri.base.resolveUri(new Uri.file(arguments[0]));
  final Directory testcases = new Directory(arguments[1]);
  final Directory out = new Directory(arguments[2])
    ..createSync(recursive: true);
  final List<File> sources =
      testcases
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  int failures = 0;
  for (final File source in sources) {
    if (new File('${source.path}.options').existsSync()) {
      // None today; the test would pass their experiment flags.
      throw 'unsupported: ${source.path}.options';
    }
    final String name = source.uri.pathSegments.last.replaceAll('.dart', '');
    final Component component = await compileForOracle(source.uri, platform);
    final BytesSink sink = new BytesSink();
    new BinaryPrinter(sink).writeComponentFile(component);
    final Uint8List bytes = sink.builder.takeBytes();
    new File('${out.path}/$name.dill').writeAsBytesSync(bytes);

    final Component readBack = new Component();
    new BinaryBuilder(bytes).readComponent(readBack);
    final String fromDill = summariesOf(readBack);
    final String inMemory = summariesOf(component);
    new File('${out.path}/$name.upstream.txt').writeAsStringSync(fromDill);

    final File expectFile = new File('${source.path}.expect');
    final String expected = expectFile.existsSync()
        ? expectFile.readAsStringSync()
        : '';
    final bool memoryOk = inMemory == expected;
    final bool dillOk = fromDill == expected;
    print('$name: in memory ${memoryOk ? 'matches' : 'DIFFERS'}, '
        'from .dill ${dillOk ? 'matches' : 'DIFFERS'}');
    if (!memoryOk || !dillOk) failures++;
  }
  print('${sources.length - failures} of ${sources.length} testcases: '
      'upstream reproduces the .expect file from memory and from the .dill');
  if (failures != 0) exit(1);
}
