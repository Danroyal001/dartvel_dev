// Studio's code is the application's deferred Studio library, and its parts
// are not public files.
//
// A web-server build compiles Studio into the application as a deferred
// library. The parts that belong to Studio's screens alone are taken out of
// the web root -- whose every file the binary hands to anybody -- and carried
// separately, to be served from memory to a session with the Studio grant.
// A part Studio shares with the sign-in or with a public page is public:
// somebody with no grant needs it.
import 'dart:io';

import 'package:dartvel_cli/src/build/studio_parts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  compiledInTests();

  late Directory root;
  late String web;
  late String parts;

  void write(String name, String body) =>
      File(p.join(web, name)).writeAsStringSync(body);

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_parts_');
    web = p.join(root.path, 'web');
    parts = p.join(root.path, 'studio');
    Directory(web).createSync();
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test("moves the parts only Studio's screens load out of the web root",
      () {
    write(
        'main.dart.js',
        'x.deferredLibraryParts:{p0:[0],dartvel_studio:[1,2],'
            'dartvel_studio_sign_in:[2,3]},deferredPartUris:['
            '"main.dart.js_1.part.js","main.dart.js_2.part.js",'
            '"main.dart.js_3.part.js","main.dart.js_4.part.js"],');
    for (int i = 1; i <= 4; i++) {
      write('main.dart.js_$i.part.js', '/* part $i */');
    }
    write('main.dart.js_2.part.js.map', '{}');

    final DVStudioPartsResult result =
        dvSplitStudioParts(webRoot: web, partsRoot: parts);

    expect(result.problem, isNull);
    expect(result.parts, <String>['main.dart.js_2.part.js']);
    // Gone from the web root, with its source map.
    expect(File(p.join(web, 'main.dart.js_2.part.js')).existsSync(), isFalse);
    expect(File(p.join(web, 'main.dart.js_2.part.js.map')).existsSync(),
        isFalse);
    expect(File(p.join(parts, 'main.dart.js_2.part.js')).readAsStringSync(),
        '/* part 2 */');
    // The page's part and the part the sign-in shares stay public.
    for (final String kept in <String>[
      'main.dart.js_1.part.js',
      'main.dart.js_3.part.js',
      'main.dart.js_4.part.js',
    ]) {
      expect(File(p.join(web, kept)).existsSync(), isTrue, reason: kept);
    }
  });

  test('a build whose Studio is not a deferred library of its own fails', () {
    // Studio compiled into main.dart.js is Studio handed to every visitor.
    write('main.dart.js',
        'deferredLibraryParts:{p0:[0]},deferredPartUris:["main.dart.js_1.part.js"]');
    write('main.dart.js_1.part.js', '/* page */');
    final DVStudioPartsResult result =
        dvSplitStudioParts(webRoot: web, partsRoot: parts);
    expect(result.problem, contains('not a deferred library'));
    expect(File(p.join(web, 'main.dart.js_1.part.js')).existsSync(), isTrue);
  });

  test('a build where Studio shares every part with public code fails', () {
    write(
        'main.dart.js',
        'deferredLibraryParts:{p0:[0],dartvel_studio:[0]},'
            'deferredPartUris:["main.dart.js_1.part.js"]');
    write('main.dart.js_1.part.js', '/* page and Studio */');
    final DVStudioPartsResult result =
        dvSplitStudioParts(webRoot: web, partsRoot: parts);
    expect(result.problem, contains('no part of their own'));
  });

  test('parts left by an earlier build are replaced, not added to', () {
    Directory(parts).createSync(recursive: true);
    File(p.join(parts, 'main.dart.js_9.part.js')).writeAsStringSync('old');
    write(
        'main.dart.js',
        'deferredLibraryParts:{dartvel_studio:[0]},'
            'deferredPartUris:["main.dart.js_1.part.js"]');
    write('main.dart.js_1.part.js', '/* Studio */');
    final DVStudioPartsResult result =
        dvSplitStudioParts(webRoot: web, partsRoot: parts);
    expect(result.problem, isNull);
    expect(
        Directory(parts)
            .listSync()
            .map((FileSystemEntity e) => p.basename(e.path))
            .toList(),
        <String>['main.dart.js_1.part.js']);
  });
}

void compiledInTests() {
  test('a static build whose Studio import was tree-shaken carries no Studio',
      () {
    // What dart2js wrote for Dartvel Preview, a static web build with no
    // Studio define: the router's Studio routes are behind a false constant,
    // so both of Studio's deferred imports own no part at all. The build
    // read the key's presence as Studio compiled in, and refused every
    // static `dartvel build web`.
    const String shaken =
        'deferredLibraryParts:{p0:[0,1],p1:[0,2],dartvel_studio:[],dartvel_studio_sign_in:[]},'
        'deferredPartUris:["main.dart.js_2.part.js","main.dart.js_1.part.js","main.dart.js_3.part.js"]';
    expect(dvStudioCompiledIn(shaken), isFalse);
  });

  test('a build with Studio\'s parts carries Studio', () {
    const String studio =
        'deferredLibraryParts:{p0:[0],dartvel_studio:[1,2]},'
        'deferredPartUris:["main.dart.js_1.part.js","main.dart.js_2.part.js","main.dart.js_3.part.js"]';
    expect(dvStudioCompiledIn(studio), isTrue);
  });

  test('a build with no deferred code carries no Studio', () {
    expect(dvStudioCompiledIn('main();'), isFalse);
  });
}
