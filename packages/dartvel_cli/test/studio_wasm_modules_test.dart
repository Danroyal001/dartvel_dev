// Studio's code out of the public web root, for the WebAssembly app.
//
// dart2wasm with deferred loading writes a module per deferred import graph,
// and the build works out which modules each import needs
// (wasm_deferred.dart). Studio's screens are the `dartvel_studio` import of
// dartvel_flutter's studio_routes.dart; the modules only it needs are moved
// out with its dart2js parts. When nobody can say which modules are
// Studio's, the wasm app is dropped from the build rather than shipped with
// Studio inside it: every browser then runs dart2js, whose Studio parts are
// kept back.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/studio_parts.dart';
import 'package:dartvel_cli/src/build/wasm_deferred.dart';
import 'package:dartvel_cli/src/build/web_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group("which modules are Studio's", () {
    test('the ones only the Studio import needs', () {
      final List<String>? studio = dvStudioWasmModules(<String, List<String>>{
        'p0': <String>['main.dart_module1.wasm', 'main.dart_module2.wasm'],
        'dartvel_studio': <String>[
          'main.dart_module2.wasm', // shared with a page
          'main.dart_module3.wasm', // shared with the sign-in
          'main.dart_module4.wasm', // Studio's own
        ],
        'dartvel_studio_sign_in': <String>['main.dart_module3.wasm'],
      }, compiledIn: true);
      expect(studio, <String>['main.dart_module4.wasm']);
    });

    test('none when Studio is not compiled in', () {
      expect(
          dvStudioWasmModules(<String, List<String>>{
            'p0': <String>['main.dart_module1.wasm'],
          }, compiledIn: false),
          isEmpty);
    });

    test('unknown when Studio is compiled in and no module is known to be its',
        () {
      // Its code is in the wasm app somewhere; shipping that app would serve
      // it to everybody.
      expect(
          dvStudioWasmModules(<String, List<String>>{
            'p0': <String>['main.dart_module1.wasm'],
          }, compiledIn: true),
          isNull);
      expect(
          dvStudioWasmModules(<String, List<String>>{
            'p0': <String>['main.dart_module1.wasm'],
            'dartvel_studio': <String>['main.dart_module1.wasm'],
          }, compiledIn: true),
          isNull,
          reason: 'every module it loads is also public');
    });
  });

  group('a built site', () {
    late Directory temp;
    late String web;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('dv_studio_wasm_');
      web = p.join(temp.path, 'web');
      Directory(web).createSync();
      for (final String name in <String>[
        'main.dart.wasm',
        'main.dart.mjs',
        'main.dart_module1.wasm',
        'main.dart_module4.wasm',
        'main.dart.js',
      ]) {
        File(p.join(web, name)).writeAsStringSync(name);
      }
      File(p.join(web, 'flutter_bootstrap.js')).writeAsStringSync(
          '/* flutter.js */\n'
          '_flutter.buildConfig = {"engineRevision":"af7e796e16","builds":['
          '{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},'
          '{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};\n'
          '_flutter.loader.load({});\n');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test("Studio's modules move to where only a granted session is sent them",
        () {
      final String parts = p.join(temp.path, 'parts');
      Directory(parts).createSync();
      dvMoveStudioWasmModules(
          webRoot: web,
          partsRoot: parts,
          modules: <String>['main.dart_module4.wasm']);
      expect(File(p.join(web, 'main.dart_module4.wasm')).existsSync(), isFalse);
      expect(File(p.join(parts, 'main.dart_module4.wasm')).existsSync(), isTrue);
      expect(File(p.join(web, 'main.dart_module1.wasm')).existsSync(), isTrue);
    });

    test('dropping the wasm app leaves a dart2js site the loader can run', () {
      File(p.join(web, 'main.dart_module1.wasm.map')).writeAsStringSync('{}');
      dvDropWasmApp(web);
      final String bootstrap =
          File(p.join(web, 'flutter_bootstrap.js')).readAsStringSync();
      expect(dvBuildCompilesToWasm(bootstrap), isFalse);
      final Map<String, Object?> config = jsonDecode(RegExp(
              r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;')
          .firstMatch(bootstrap)!
          .group(1)!) as Map<String, Object?>;
      expect(config['builds'], <Object?>[
        <String, Object?>{
          'compileTarget': 'dart2js',
          'renderer': 'canvaskit',
          'mainJsPath': 'main.dart.js',
        },
      ]);
      for (final String gone in <String>[
        'main.dart.wasm',
        'main.dart.mjs',
        'main.dart_module1.wasm',
        'main.dart_module4.wasm',
        'main.dart_module1.wasm.map',
      ]) {
        expect(File(p.join(web, gone)).existsSync(), isFalse, reason: gone);
      }
      expect(File(p.join(web, 'main.dart.js')).existsSync(), isTrue);
    });
  });
}
