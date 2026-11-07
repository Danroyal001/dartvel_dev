// Code splitting for the WebAssembly build.
//
// Every Dartvel page is a deferred library. dart2js splits each into parts a
// page loads when it is first shown; dart2wasm compiles all of them into one
// main.dart.wasm unless it is asked for `--enable-deferred-loading`, and
// `flutter build web` has no way to pass that. So the build reruns the exact
// dart2wasm command Flutter ran, with deferred loading on, and gives the
// loader the one thing flutter.js does not: a way to fetch a module.
import 'dart:io';

import 'package:dartvel_cli/src/build/wasm_deferred.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String dart = '/sdk/bin/dart';
const String buildDir = '/app/.dart_tool/flutter_build/3d0a';

/// The lines `flutter build web --wasm -v` prints around the dart2wasm run.
const String verboseLog = '''
[  +12 ms] Compiling lib/main.dart for the Web...
[  +13 ms] executing: $dart compile js --platform-binaries=/sdk/web --invoker=flutter_tool -Ddart.vm.product=true -o $buildDir/main.dart.js $buildDir/main.dart
[  +13 ms] executing: $dart compile wasm --packages=/app/.dart_tool/package_config.json --extra-compiler-option=--platform=/sdk/dart2wasm_platform.dill -Ddart.vm.profile=false -Ddart.vm.product=true --extra-compiler-option=--import-shared-memory -DFLUTTER_WEB_USE_SKWASM=true --extra-compiler-option=--depfile=$buildDir/dart2wasm.d --recorded-uses=$buildDir/recorded_uses_wasm.json -O2 --strip-wasm --no-source-maps --minify -o $buildDir/main.dart.wasm $buildDir/main.dart
[+184500 ms] Compiling lib/main.dart for the Web...  184.5s
''';

void main() {
  group('the dart2wasm command Flutter ran', () {
    test('is read from the verbose build log, and only the wasm one', () {
      final List<String>? command = dvDart2WasmCommand(verboseLog);
      expect(command, isNotNull);
      expect(command!.first, dart);
      expect(command.sublist(1, 3), <String>['compile', 'wasm']);
      expect(command.last, '$buildDir/main.dart');
      expect(command, contains('-DFLUTTER_WEB_USE_SKWASM=true'));
    });

    test('a log without one gives nothing to rerun', () {
      expect(dvDart2WasmCommand('[ +1 ms] Compiling lib/main.dart\n'), isNull);
    });
  });

  group('the rerun with deferred loading', () {
    final List<String> command = dvDart2WasmCommand(verboseLog)!;
    final List<String> deferred = dvDeferredWasmCommand(command,
        outputDirectory: '/out', deferredMap: '/out/map.json');

    test('asks for one module per deferred import graph and a map of them', () {
      expect(deferred, contains('--enable-deferred-loading'));
      expect(deferred,
          contains('--extra-compiler-option=--deferred-map=/out/map.json'));
    });

    test('writes beside Flutter rather than over its files', () {
      final int output = deferred.indexOf('-o');
      expect(deferred[output + 1], '/out/main.dart.wasm');
      // Flutter's dependency file and recorded uses describe Flutter's own
      // build; a second writer would make its next incremental build wrong.
      expect(deferred.where((String a) => a.contains('--depfile')), isEmpty);
      expect(deferred.where((String a) => a.contains('--recorded-uses')), isEmpty);
    });

    test('keeps everything else exactly as Flutter had it', () {
      for (final String argument in <String>[
        '--packages=/app/.dart_tool/package_config.json',
        '--extra-compiler-option=--import-shared-memory',
        '-DFLUTTER_WEB_USE_SKWASM=true',
        '-O2',
        '--minify',
      ]) {
        expect(deferred, contains(argument));
      }
      expect(deferred.last, '$buildDir/main.dart');
    });
  });

  group('the loader', () {
    // The anchor dart2wasm writes in main.dart.mjs.
    const String mjs = 'class CompiledApp {\n'
        '  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {\n'
        '    let dartInstance;\n';

    test('fetches a module beside main.dart.mjs when nothing else does', () {
      // flutter.js calls instantiate() with no loader, and the first
      // loadLibrary() would throw "No implementation of loadDeferredModules
      // provided" -- every Dartvel page is a deferred library.
      final String patched = dvWithDeferredModuleLoader(mjs)!;
      expect(patched, contains('loadDeferredModules ??='));
      expect(patched, contains('new URL(name, import.meta.url)'));
      // dart2wasm compiles what it is handed only if it is a Response or the
      // bytes; a pending fetch is neither, and every page failed to load.
      expect(patched, contains('await fetch('));
      expect(patched.indexOf('loadDeferredModules ??='),
          greaterThan(patched.indexOf('async instantiate(')));
    });

    test('patching twice changes nothing the second time', () {
      final String once = dvWithDeferredModuleLoader(mjs)!;
      expect(dvWithDeferredModuleLoader(once), once);
    });

    test('a runtime it does not recognise is reported, not guessed at', () {
      expect(dvWithDeferredModuleLoader('export function x() {}'), isNull);
    });
  });

  group('splitting a built site', () {
    late Directory temp;
    late String web;
    late String work;
    const String mjs = 'class CompiledApp {\n'
        '  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {\n'
        '  }\n}\n';

    setUp(() {
      temp = Directory.systemTemp.createTempSync('dv_wasm_split_');
      web = p.join(temp.path, 'build', 'web');
      work = p.join(temp.path, 'work');
      Directory(web).createSync(recursive: true);
      File(p.join(web, 'main.dart.wasm')).writeAsStringSync('one module');
      File(p.join(web, 'main.dart.mjs')).writeAsStringSync(mjs);
      File(p.join(web, 'main.dart.js')).writeAsStringSync('dart2js');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    /// A dart2wasm that writes what `--enable-deferred-loading` writes.
    Future<int> fakeCompiler(String executable, List<String> arguments) async {
      final String out =
          p.dirname(arguments[arguments.indexOf('-o') + 1]);
      Directory(out).createSync(recursive: true);
      File(p.join(out, 'main.dart.wasm')).writeAsStringSync('main module');
      File(p.join(out, 'main.dart_module1.wasm')).writeAsStringSync('page one');
      File(p.join(out, 'main.dart_module2.wasm')).writeAsStringSync('page two');
      File(p.join(out, 'main.dart.mjs')).writeAsStringSync(mjs);
      final String map = arguments
          .firstWhere((String a) => a.contains('--deferred-map='))
          .split('--deferred-map=')
          .last;
      File(map).writeAsStringSync('{}');
      return 0;
    }

    test('the site gets the modules, a loader and the map, and keeps dart2js',
        () async {
      final DVWasmSplit split = await dvSplitWasmModules(
          webRoot: web, workRoot: work, verboseLog: verboseLog, run: fakeCompiler);
      expect(split.problem, isNull);
      expect(split.modules, 2);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'main module');
      expect(File(p.join(web, 'main.dart_module1.wasm')).existsSync(), isTrue);
      expect(File(p.join(web, 'main.dart.mjs')).readAsStringSync(),
          contains('loadDeferredModules ??='));
      expect(File(p.join(web, dvWasmDeferredMapFile)).existsSync(), isTrue);
      expect(File(p.join(web, 'main.dart.js')).readAsStringSync(), 'dart2js');
    });

    test('a compiler that fails leaves the one-module build as it was', () async {
      final DVWasmSplit split = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: verboseLog,
          run: (String executable, List<String> arguments) async => 1);
      expect(split.problem, isNotNull);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'one module');
      expect(File(p.join(web, 'main.dart.mjs')).readAsStringSync(), mjs);
      expect(File(p.join(web, dvWasmDeferredMapFile)).existsSync(), isFalse);
    });

    test('a dart2wasm Flutter skipped as up to date reuses the last split',
        () async {
      // Flutter's own build cache skips dart2wasm when nothing changed, and
      // then logs no command. The app is the one split last time, so the
      // split is reused; any other app is not.
      final DVWasmSplit first = await dvSplitWasmModules(
          webRoot: web, workRoot: work, verboseLog: verboseLog, run: fakeCompiler);
      expect(first.problem, isNull);

      // The next build: Flutter writes the same one-module app again.
      File(p.join(web, 'main.dart.wasm')).writeAsStringSync('one module');
      File(p.join(web, 'main.dart.mjs')).writeAsStringSync(mjs);
      File(p.join(web, 'main.dart_module1.wasm')).deleteSync();
      bool ran = false;
      final DVWasmSplit again = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: 'no executing line',
          run: (String executable, List<String> arguments) async {
            ran = true;
            return 0;
          });
      expect(ran, isFalse);
      expect(again.problem, isNull);
      expect(again.modules, 2);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'main module');
      expect(File(p.join(web, 'main.dart_module1.wasm')).existsSync(), isTrue);

      // A different app is not given the old split.
      File(p.join(web, 'main.dart.wasm')).writeAsStringSync('another app');
      final DVWasmSplit other = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: 'no executing line',
          run: (String executable, List<String> arguments) async => 0);
      expect(other.problem, isNotNull);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'another app');
    });

    // The deferred compile used to start only once `flutter build web` had
    // finished, so a wasm build paid for dart2wasm twice, one after the
    // other. It now starts the moment Flutter logs its dart2wasm command and
    // runs beside Flutter's own; the split then uses that compile.
    test('a compile begun while Flutter was still building is used, not run '
        'again', () async {
      int runs = 0;
      Future<int> counted(String executable, List<String> arguments) {
        runs++;
        return fakeCompiler(executable, arguments);
      }

      final Future<int> early = dvCompileDeferredWasm(
          command: dvDart2WasmCommand(verboseLog)!, workRoot: work, run: counted);
      expect(runs, 1, reason: 'started at once, not when awaited');
      final DVWasmSplit split = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: verboseLog,
          run: counted,
          compiling: early);
      expect(runs, 1);
      expect(split.problem, isNull);
      expect(split.modules, 2);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'main module');
    });

    test('an early compile that failed leaves the one-module build as it was',
        () async {
      final DVWasmSplit split = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: verboseLog,
          run: fakeCompiler,
          compiling: Future<int>.value(1));
      expect(split.problem, isNotNull);
      expect(File(p.join(web, 'main.dart.wasm')).readAsStringSync(),
          'one module');
    });

    test('no dart2wasm command in the log is said, not run blind', () async {
      bool ran = false;
      final DVWasmSplit split = await dvSplitWasmModules(
          webRoot: web,
          workRoot: work,
          verboseLog: 'nothing here',
          run: (String executable, List<String> arguments) async {
            ran = true;
            return 0;
          });
      expect(ran, isFalse);
      expect(split.problem, isNotNull);
    });
  });
}
