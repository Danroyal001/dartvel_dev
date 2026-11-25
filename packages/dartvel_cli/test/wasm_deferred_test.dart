// Code splitting for the WebAssembly build.
//
// Every Dartvel page is a deferred library. Flutter 3.50's
// `--enable-wasm-deferred-loading` makes dart2wasm write each into modules
// of its own, beside main.dart.wasm. What it does not hand over is which
// modules each deferred import needs -- dart2wasm's `--deferred-map` cannot
// be reached through `flutter build web` -- and the build needs that twice:
// each page preloads its route's modules, and Studio's modules are kept out
// of the public files. So the build asks for source maps, reads which
// libraries each module holds, and matches them against dart2js's exact
// table of which parts each import loads. Then the maps go: they were never
// part of the site.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/wasm_deferred.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String app = '/app/lib/dartvel_client';
const String flutterPkg = '/sdk/flutter/packages/flutter/lib/src';

String wasmMap(List<String> sources) => jsonEncode(<String, Object?>{
      'version': 3,
      'sources': <String>[
        for (final String source in sources)
          source.startsWith('/') ? 'file://$source' : source,
        'org-dartlang-sdk:///lib/core/list.dart',
      ],
      'mappings': '',
    });

void main() {
  group('the libraries a source map names', () {
    test('wasm and dart2js name the same file the same way', () {
      // dart2wasm writes file: URIs; dart2js writes paths relative to the map.
      final Set<String> wasm = dvSourceMapLibraries(
          wasmMap(<String>['$app/pages/about_page.g.dart']),
          '/app/build/web/main.dart_module1.wasm.map');
      final Set<String> js = dvSourceMapLibraries(
          jsonEncode(<String, Object?>{
            'version': 3,
            'sources': <String>['../../lib/dartvel_client/pages/about_page.g.dart'],
          }),
          '/app/build/web/main.dart.js_1.part.js.map');
      expect(wasm, <String>{'$app/pages/about_page.g.dart'});
      expect(js, wasm);
    });

    test("the SDK's own sources are left out", () {
      // Every module has some; they say nothing about which page it is for.
      expect(
          dvSourceMapLibraries(wasmMap(const <String>[]), '/w/m.wasm.map'),
          isEmpty);
    });

    test('a map that will not parse names nothing', () {
      expect(dvSourceMapLibraries('not json', '/w/m.map'), isEmpty);
      expect(dvSourceMapLibraries('{"sources": 3}', '/w/m.map'), isEmpty);
    });
  });

  group('which modules each deferred import needs', () {
    // dart2js's exact table and what its parts hold.
    final Map<String, List<String>> jsParts = <String, List<String>>{
      'p0': <String>['main.dart.js_1.part.js', 'main.dart.js_2.part.js'],
      'p1': <String>['main.dart.js_3.part.js', 'main.dart.js_2.part.js'],
      'dartvel_studio': <String>['main.dart.js_4.part.js', 'main.dart.js_5.part.js'],
      'dartvel_studio_sign_in': <String>['main.dart.js_5.part.js'],
    };
    final Map<String, Set<String>> jsPartLibraries = <String, Set<String>>{
      'main.dart.js_1.part.js': <String>{'$app/pages/about_page.g.dart', '$flutterPkg/painting/edge_insets.dart'},
      'main.dart.js_2.part.js': <String>{'$app/components/card.dart'},
      'main.dart.js_3.part.js': <String>{'$app/pages/index_page.g.dart'},
      'main.dart.js_4.part.js': <String>{'/dv/studio/screens.dart'},
      'main.dart.js_5.part.js': <String>{'/dv/studio/sign_in.dart'},
    };
    final Set<String> jsMain = <String>{
      '$app/application.g.dart',
      '/dv/dartvel_flutter.dart',
    };

    Map<String, List<String>> infer(Map<String, Set<String>> wasmModules) =>
        dvInferWasmModules(
          jsParts: jsParts,
          jsPartLibraries: jsPartLibraries,
          jsMainLibraries: jsMain,
          wasmModuleLibraries: wasmModules,
        );

    test("a page's own module and the module it shares with another page",
        () {
      final Map<String, List<String>> byImport = infer(<String, Set<String>>{
        // Each holds code of libraries every page has too (the app, the
        // barrel); what tells them apart is what main.dart.js lacks.
        'main.dart_module1.wasm': <String>{'$app/pages/about_page.g.dart', '$app/application.g.dart', '/dv/dartvel_flutter.dart'},
        'main.dart_module2.wasm': <String>{'$app/components/card.dart'},
        'main.dart_module3.wasm': <String>{'$app/pages/index_page.g.dart', '/dv/dartvel_flutter.dart'},
        'main.dart_module5.wasm': <String>{'/dv/studio/screens.dart'},
        'main.dart_module6.wasm': <String>{'/dv/studio/sign_in.dart'},
      });
      expect(byImport['p0'], <String>['main.dart_module1.wasm', 'main.dart_module2.wasm']);
      expect(byImport['p1'], <String>['main.dart_module2.wasm', 'main.dart_module3.wasm']);
      expect(byImport['dartvel_studio'],
          <String>['main.dart_module5.wasm', 'main.dart_module6.wasm']);
      expect(byImport['dartvel_studio_sign_in'], <String>['main.dart_module6.wasm']);
    });

    test('modules are listed in number order, not name order', () {
      final Map<String, List<String>> byImport = infer(<String, Set<String>>{
        'main.dart_module10.wasm': <String>{'$app/components/card.dart'},
        'main.dart_module9.wasm': <String>{'$app/pages/about_page.g.dart'},
      });
      expect(byImport['p0'], <String>['main.dart_module9.wasm', 'main.dart_module10.wasm']);
    });

    test('a module of nothing but shared code is named by nobody', () {
      // dart2wasm's catch-all module for code nothing calls, and a module of
      // code dart2js kept in main.dart.js: no import is known to need it, so
      // no page preloads it and Studio does not claim it.
      final Map<String, List<String>> byImport = infer(<String, Set<String>>{
        'main.dart_module4.wasm': <String>{'/dv/core/media_source.dart'},
        'main.dart_module7.wasm': <String>{'$app/application.g.dart'},
        'main.dart_module8.wasm': const <String>{},
      });
      expect(byImport.values.expand((List<String> m) => m), isEmpty);
    });

    test('a library dart2js shook out does not stop the match', () {
      final Map<String, List<String>> byImport = infer(<String, Set<String>>{
        'main.dart_module1.wasm': <String>{'$app/pages/about_page.g.dart', '/dv/only_wasm_keeps_this.dart'},
      });
      expect(byImport['p0'], <String>['main.dart_module1.wasm']);
    });

    test('libraries no one import holds together are claimed by each import, '
        'never by none', () {
      // The compilers disagreeing: a module whose libraries dart2js put in
      // different imports' parts. Every one of those imports is said to need
      // it, so Studio never takes a module a page might load.
      final Map<String, List<String>> byImport = infer(<String, Set<String>>{
        'main.dart_module1.wasm': <String>{'$app/pages/index_page.g.dart', '/dv/studio/screens.dart'},
      });
      expect(byImport['p1'], <String>['main.dart_module1.wasm']);
      expect(byImport['dartvel_studio'], <String>['main.dart_module1.wasm']);
    });
  });

  // dart2js writes its maps in .dart_tool/flutter_build/<hash>/ and Flutter
  // copies them into build/web unchanged, so their relative paths start
  // three levels below the project, not two.
  group('a built site', () {
    late Directory temp;
    late String web;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('dv_wasm_deferred_');
      web = p.join(temp.path, 'build', 'web');
      Directory(web).createSync(recursive: true);
      void write(String name, String content) =>
          File(p.join(web, name)).writeAsStringSync(content);
      write('main.dart.js',
          'deferredLibraryParts:{p0:[0],p1:[1]},deferredPartUris:["main.dart.js_1.part.js","main.dart.js_2.part.js"]\n'
          '//# sourceMappingURL=main.dart.js.map');
      write('main.dart.js.map', jsonEncode(<String, Object?>{
        'version': 3,
        'sources': <String>['../../../lib/dartvel_client/application.g.dart'],
      }));
      write('main.dart.js_1.part.js', 'part one\n//# sourceMappingURL=main.dart.js_1.part.js.map\n');
      write('main.dart.js_1.part.js.map', jsonEncode(<String, Object?>{
        'version': 3,
        'sources': <String>['../../../lib/dartvel_client/pages/about_page.g.dart'],
      }));
      write('main.dart.js_2.part.js', 'part two\n//# sourceMappingURL=main.dart.js_2.part.js.map\n');
      write('main.dart.js_2.part.js.map', jsonEncode(<String, Object?>{
        'version': 3,
        'sources': <String>['../../../lib/dartvel_client/pages/index_page.g.dart'],
      }));
      for (final (int n, String page) in <(int, String)>[(1, 'about'), (3, 'index')]) {
        File(p.join(web, 'main.dart_module$n.wasm'))
            .writeAsBytesSync(dvWasmWithSourceMapUrl('main.dart_module$n.wasm.map'));
        write('main.dart_module$n.wasm.map',
            wasmMap(<String>['${temp.path}/lib/dartvel_client/pages/${page}_page.g.dart']));
      }
      File(p.join(web, 'main.dart.wasm'))
          .writeAsBytesSync(dvWasmWithSourceMapUrl('main.dart.wasm.map'));
      write('main.dart.wasm.map', wasmMap(const <String>[]));
      write('flutter.js.map', '{"version":3,"sources":[]}');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('names each import\'s modules from the files Flutter wrote', () {
      final DVWasmDeferredImports read = dvReadWasmDeferredImports(web);
      expect(read.problem, isNull);
      expect(read.byImport, <String, List<String>>{
        'p0': <String>['main.dart_module1.wasm'],
        'p1': <String>['main.dart_module3.wasm'],
      });
    });

    test('without the source maps it says so rather than guess', () {
      File(p.join(web, 'main.dart_module1.wasm.map')).deleteSync();
      final DVWasmDeferredImports read = dvReadWasmDeferredImports(web);
      expect(read.problem, contains('main.dart_module1.wasm'));
      expect(read.byImport, isEmpty);
    });

    test("the compiler's source maps leave the site, and nothing points at "
        'them', () {
      dvRemoveCompilerSourceMaps(web);
      final List<String> left = <String>[
        for (final FileSystemEntity entity in Directory(web).listSync())
          p.basename(entity.path),
      ]..sort();
      expect(left, <String>[
        'flutter.js.map', // Flutter ships it with every build, maps or not.
        'main.dart.js',
        'main.dart.js_1.part.js',
        'main.dart.js_2.part.js',
        'main.dart.wasm',
        'main.dart_module1.wasm',
        'main.dart_module3.wasm',
      ]);
      expect(File(p.join(web, 'main.dart.js')).readAsStringSync(),
          'deferredLibraryParts:{p0:[0],p1:[1]},deferredPartUris:["main.dart.js_1.part.js","main.dart.js_2.part.js"]');
      expect(File(p.join(web, 'main.dart.js_1.part.js')).readAsStringSync(),
          'part one\n');
      for (final String wasm in <String>['main.dart.wasm', 'main.dart_module1.wasm']) {
        expect(File(p.join(web, wasm)).readAsBytesSync(), dvEmptyWasmModule,
            reason: wasm);
      }
    });
  });

  group('a wasm file without its sourceMappingURL section', () {
    test('keeps every other section, byte for byte, and stays valid', () async {
      final Uint8List withUrl = dvWasmWithSourceMapUrl('main.dart.wasm.map',
          before: <int>[0, 4, 3, 0x61, 0x62, 0x63], // custom section "abc"
          after: <int>[0, 5, 4, 0x6e, 0x61, 0x6d, 0x65]); // custom section "name"
      final Uint8List stripped = dvWithoutWasmSourceMapUrl(withUrl);
      expect(stripped, <int>[
        ...dvEmptyWasmModule,
        0, 4, 3, 0x61, 0x62, 0x63,
        0, 5, 4, 0x6e, 0x61, 0x6d, 0x65,
      ]);
      final Directory temp = Directory.systemTemp.createTempSync('dv_wasm_strip_');
      addTearDown(() => temp.deleteSync(recursive: true));
      File(p.join(temp.path, 'm.wasm')).writeAsBytesSync(stripped);
      final ProcessResult run = await Process.run('node', <String>[
        '-e',
        'console.log(WebAssembly.validate(require("fs").readFileSync("m.wasm")))',
      ], workingDirectory: temp.path);
      expect(run.stdout.toString().trim(), 'true', reason: '${run.stderr}');
    });

    test('anything that is not a wasm file is left as it was', () {
      final Uint8List junk = Uint8List.fromList(utf8.encode('not wasm at all'));
      expect(dvWithoutWasmSourceMapUrl(junk), junk);
      final Uint8List truncated = Uint8List.fromList(
          <int>[...dvEmptyWasmModule, 0, 100, 1]);
      expect(dvWithoutWasmSourceMapUrl(truncated), truncated);
    });
  });
}

/// `\0asm` version 1, no sections.
const List<int> dvEmptyWasmModule = <int>[0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];

/// An empty wasm module with a `sourceMappingURL` custom section naming
/// [url], between the sections in [before] and [after].
Uint8List dvWasmWithSourceMapUrl(String url,
    {List<int> before = const <int>[], List<int> after = const <int>[]}) {
  const String name = 'sourceMappingURL';
  final List<int> payload = <int>[
    name.length,
    ...utf8.encode(name),
    url.length,
    ...utf8.encode(url),
  ];
  return Uint8List.fromList(<int>[
    ...dvEmptyWasmModule,
    ...before,
    0,
    payload.length,
    ...payload,
    ...after,
  ]);
}
