// A web-server build writes what each route loads, for the server to name in
// the head it sends.
//
// The static build writes each page's preloads into that page's own HTML. A
// web-server build has one shell for every route, so a list written into it
// would be one route's list served for all of them: the manifest is keyed by
// route pattern instead, and the shell is left exactly as it was.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/route_prefetch.dart'
    show dvCapturedImagesPathFor;
import 'package:dartvel_cli/src/build/web_server_prefetch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String mainJs = 'var init={deferredLibraryParts:{p0:[0],p1:[0,1],p2:[2],'
    'p3:[]},deferredPartUris:["main.dart.js_1.part.js",'
    '"main.dart.js_2.part.js","main.dart.js_3.part.js"]};';

const String router = '''
class DocsPageGeneratedPage extends DartvelPage {
  static Future<void> loadLibrary() {
    return _libraryFuture ??= p1.loadLibrary();
  }
}

class ProductPageGeneratedPage extends DartvelPage {
  static Future<void> loadLibrary() {
    return _libraryFuture ??= p2.loadLibrary();
  }
}

class IndexPageGeneratedPage extends DartvelPage {
  static Future<void> loadLibrary() {
    return _libraryFuture ??= p3.loadLibrary();
  }
}

GoRouter createDartvelRouter() {
  DVRoutePreloaders.register(
    '/docs',
    DocsPageGeneratedPage.loadLibrary,
  );
  DVRoutePreloaders.register(
    '/products/:id',
    ProductPageGeneratedPage.loadLibrary,
  );
  DVRoutePreloaders.register(
    '/',
    IndexPageGeneratedPage.loadLibrary,
  );
}
''';

const String shell = '<!doctype html><html><head><base href="/">'
    '<title>Site</title></head><body>'
    '<img src="dartvel-splash.png" alt=""></body></html>';

void main() {
  late Directory project;
  late Directory web;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_ws_prefetch_');
    web = Directory(p.join(project.path, 'build', 'web'))
      ..createSync(recursive: true);
    File(p.join(web.path, 'main.dart.js')).writeAsStringSync(mainJs);
    File(p.join(web.path, 'index.html')).writeAsStringSync(shell);
    File(dvCapturedImagesPathFor(project.path, '/docs'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(<Object?>[
        <String, Object?>{'url': 'dartvel-splash.png', 'as': 'image'},
        <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
      ]));
  });

  tearDown(() => project.deleteSync(recursive: true));

  int write() => dvWriteWebServerPrefetch(
        projectRoot: project.path,
        webRoot: web.path,
        routerSource: router,
        routes: <String>['/', '/docs', '/products/:id'],
      );

  Map<String, Object?> routes() => (jsonDecode(
        File(p.join(web.path, 'dartvel_prefetch.json')).readAsStringSync(),
      ) as Map<String, Object?>)['routes']! as Map<String, Object?>;

  test('each route pattern gets its own parts and images', () {
    write();
    expect(routes()['/docs'], <String, Object?>{
      'scripts': <String>['main.dart.js_1.part.js', 'main.dart.js_2.part.js'],
      // The splash is the shell's own, requested on every route: not /docs'.
      'images': <Object?>[
        <String, Object?>{'url': 'assets/assets/hero.png', 'as': 'fetch'},
      ],
    });
  });

  test('a parameterised route is keyed by its pattern', () {
    // The server matches /products/5 to /products/:id and reads this entry.
    // A static build has no page for it; this is what the server can serve
    // that the file writer cannot.
    write();
    expect((routes()['/products/:id']! as Map<String, Object?>)['scripts'],
        <String>['main.dart.js_3.part.js']);
  });

  test('the shell is left exactly as it was', () {
    write();
    expect(File(p.join(web.path, 'index.html')).readAsStringSync(), shell);
    expect(Directory(p.join(web.path, 'docs')).existsSync(), isFalse);
  });

  test('says how many routes name something', () {
    expect(write(), 2);
  });
}
