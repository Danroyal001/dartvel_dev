/// Code splitting for the WebAssembly build.
///
/// Every Dartvel page is a deferred library. dart2js splits each into parts
/// that load when the page is first shown. dart2wasm compiles every one of
/// them into the single main.dart.wasm unless it is passed
/// `--enable-deferred-loading`, and `flutter build web` (Flutter 3.47) has no
/// option that reaches it. The build therefore reruns the exact dart2wasm
/// command Flutter ran -- read from Flutter's verbose log, so every define
/// and flag Flutter chose is kept -- with deferred loading on and a map of
/// which module each deferred import needs.
///
/// flutter.js instantiates the app without a module loader, and the first
/// `loadLibrary()` would throw. [dvWithDeferredModuleLoader] gives
/// main.dart.mjs a default one that fetches a module from beside itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

/// The deferred-loading map the build asks dart2wasm for, kept in the web
/// output only until the build has read it.
const String dvWasmDeferredMapFile = 'main.dart.wasm.deferred.json';

/// The dart2wasm command line in a `flutter build web --wasm -v` log, or
/// null when there is none.
///
/// Flutter logs each process it runs as `executing: <arguments joined by
/// spaces>`, so an argument containing a space cannot be told apart; the
/// caller checks the result names files that exist before running it.
List<String>? dvDart2WasmCommand(String verboseLog) {
  List<String>? found;
  for (final String line in const LineSplitter().convert(verboseLog)) {
    final int at = line.indexOf('executing: ');
    if (at < 0) continue;
    final List<String> command = line
        .substring(at + 'executing: '.length)
        .trim()
        .split(RegExp(r'\s+'));
    if (command.length > 3 &&
        command[1] == 'compile' &&
        command[2] == 'wasm') {
      found = command;
    }
  }
  return found;
}

/// [command] with deferred loading on, writing `main.dart.wasm`, its modules
/// and the deferred map to [outputDirectory] instead of Flutter's build
/// directory. Flutter's dependency file and recorded uses are left out: they
/// describe Flutter's own build, and a second writer would mislead its next
/// incremental one.
List<String> dvDeferredWasmCommand(
  List<String> command, {
  required String outputDirectory,
  required String deferredMap,
}) {
  final List<String> result = <String>[];
  for (int index = 0; index < command.length; index++) {
    final String argument = command[index];
    if (argument.startsWith('--extra-compiler-option=--depfile=') ||
        argument.startsWith('--recorded-uses=') ||
        argument == '--enable-deferred-loading' ||
        argument.startsWith('--extra-compiler-option=--deferred-map=')) {
      continue;
    }
    if (argument == '-o' && index + 1 < command.length) {
      index++;
      continue;
    }
    result.add(argument);
  }
  final String entry = result.removeLast();
  return <String>[
    ...result,
    '--enable-deferred-loading',
    '--extra-compiler-option=--deferred-map=$deferredMap',
    '-o',
    '$outputDirectory/main.dart.wasm',
    entry,
  ];
}

const String _instantiate =
    'async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {';

const String _defaultLoader =
    '\n    // Dartvel: flutter.js passes no module loader; fetch each deferred'
    '\n    // module from beside this file.'
    '\n    loadDeferredModules ??= (names, load) => Promise.all(names.map('
    'async (name) => load(name, await fetch(new URL(name, import.meta.url)))));';

/// [mjs] (a dart2wasm `main.dart.mjs`) with a default deferred-module loader,
/// or null when it does not have the `instantiate` this knows how to patch.
String? dvWithDeferredModuleLoader(String mjs) {
  if (mjs.contains('loadDeferredModules ??=')) return mjs;
  final int at = mjs.indexOf(_instantiate);
  if (at < 0) return null;
  final int end = at + _instantiate.length;
  return '${mjs.substring(0, end)}$_defaultLoader${mjs.substring(end)}';
}

/// Takes the WebAssembly app out of the site in [webRoot], leaving the
/// dart2js and CanvasKit app every browser can run: the dart2wasm entry
/// leaves the build config flutter.js chooses from, and its files go.
///
/// For a build that must not ship the wasm app as it stands -- one whose
/// Studio modules cannot be told apart from public ones.
void dvDropWasmApp(String webRoot) {
  final File bootstrap = File(p.join(webRoot, 'flutter_bootstrap.js'));
  if (bootstrap.existsSync()) {
    final String source = bootstrap.readAsStringSync();
    final RegExp configLine =
        RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;');
    final RegExpMatch? match = configLine.firstMatch(source);
    if (match != null) {
      final Object? config = jsonDecode(match.group(1)!);
      if (config is Map && config['builds'] is List) {
        final Map<Object?, Object?> kept = <Object?, Object?>{
          ...config,
          'builds': <Object?>[
            for (final Object? build in config['builds'] as List)
              if (build is Map && build['compileTarget'] != 'dart2wasm') build,
          ],
        };
        bootstrap.writeAsStringSync(source.replaceRange(match.start, match.end,
            '_flutter.buildConfig = ${jsonEncode(kept)};'));
      }
    }
  }
  final Directory web = Directory(webRoot);
  if (!web.existsSync()) return;
  for (final FileSystemEntity entity in web.listSync()) {
    if (entity is! File) continue;
    final String name = p.basename(entity.path);
    if (name == 'main.dart.wasm' ||
        name == 'main.dart.mjs' ||
        name == 'main.dart.wasm.map' ||
        name == dvWasmDeferredMapFile ||
        RegExp(r'^main\.dart_module\d+\.wasm$').hasMatch(name)) {
      entity.deleteSync();
    }
  }
}

/// What [dvSplitWasmModules] did.
class DVWasmSplit {
  const DVWasmSplit({this.modules = 0, this.problem});

  /// How many deferred modules the site now has beside main.dart.wasm.
  final int modules;

  /// Why the site was left as one module, or null when it was split.
  final String? problem;
}

/// Runs [executable] with [arguments] and returns its exit code.
typedef DVWasmCompilerRun = Future<int> Function(
    String executable, List<String> arguments);

/// Recompiles the wasm app in [webRoot] with deferred loading, from the
/// dart2wasm command in Flutter's [verboseLog], working in [workRoot].
///
/// On success the site's main.dart.wasm and main.dart.mjs are replaced, the
/// modules are written beside them, and the deferred map is left as
/// [dvWasmDeferredMapFile] for the build to read. On any failure the site is
/// left exactly as Flutter wrote it, one module, and the reason is returned:
/// a site that works without splitting beats one that is half replaced.
Future<DVWasmSplit> dvSplitWasmModules({
  required String webRoot,
  required String workRoot,
  required String verboseLog,
  required DVWasmCompilerRun run,
}) async {
  final Directory work = Directory(workRoot);
  final File flutterWasm = File(p.join(webRoot, 'main.dart.wasm'));
  if (!flutterWasm.existsSync()) {
    return const DVWasmSplit(problem: 'The build wrote no main.dart.wasm.');
  }
  // Which one-module app the split in [work] was made from: Flutter's own
  // build cache skips dart2wasm when nothing changed and logs no command,
  // and then the last split is this app's split.
  final String flutterHash =
      sha256.convert(flutterWasm.readAsBytesSync()).toString();
  final File source = File(p.join(work.path, 'flutter-main.dart.wasm.sha256'));
  final List<String>? command = dvDart2WasmCommand(verboseLog);
  if (command == null) {
    if (source.existsSync() && source.readAsStringSync() == flutterHash) {
      return _installSplit(webRoot, work);
    }
    return const DVWasmSplit(
        problem: "Flutter's log names no dart2wasm command to rerun with "
            'deferred loading.');
  }
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);
  final String map = p.join(work.path, 'deferred_map.json');
  final List<String> deferred = dvDeferredWasmCommand(command,
      outputDirectory: work.path, deferredMap: map);
  final int exit = await run(deferred.first, deferred.sublist(1));
  if (exit != 0) {
    return DVWasmSplit(
        problem: 'dart2wasm with --enable-deferred-loading exited $exit.');
  }
  final DVWasmSplit split = _installSplit(webRoot, work);
  if (split.problem == null) source.writeAsStringSync(flutterHash);
  return split;
}

/// Copies the split in [work] over the one-module app in [webRoot].
DVWasmSplit _installSplit(String webRoot, Directory work) {
  final String map = p.join(work.path, 'deferred_map.json');
  final File wasm = File(p.join(work.path, 'main.dart.wasm'));
  final File mjs = File(p.join(work.path, 'main.dart.mjs'));
  if (!wasm.existsSync() || !mjs.existsSync() || !File(map).existsSync()) {
    return const DVWasmSplit(
        problem: 'dart2wasm with --enable-deferred-loading wrote no '
            'main.dart.wasm, main.dart.mjs or deferred map.');
  }
  final String? loader = dvWithDeferredModuleLoader(mjs.readAsStringSync());
  if (loader == null) {
    return const DVWasmSplit(
        problem: "This dart2wasm's main.dart.mjs has no instantiate() this "
            'build knows how to give a module loader.');
  }
  final List<File> modules = <File>[
    for (final FileSystemEntity entity in work.listSync())
      if (entity is File &&
          RegExp(r'^main\.dart_module\d+\.wasm$')
              .hasMatch(p.basename(entity.path)))
        entity,
  ];
  for (final File module in modules) {
    module.copySync(p.join(webRoot, p.basename(module.path)));
  }
  wasm.copySync(p.join(webRoot, 'main.dart.wasm'));
  File(p.join(webRoot, 'main.dart.mjs')).writeAsStringSync(loader);
  File(map).copySync(p.join(webRoot, dvWasmDeferredMapFile));
  return DVWasmSplit(modules: modules.length);
}
