// A page's declared middleware reaches the router it was declared for.
//
// NEW_SPEC.md opens the Middleware section with the page form:
//
//     @DVUseMiddleware([DVMiddlewares.auth, ...])
//     @DVPage()
//     Widget _checkoutPage(BuildContext context) => Checkout.Page();
//
// and the router generator had never heard of the annotation. The only
// reader anywhere was the backend generator's spelling check, which walks
// every file under lib/ and so did validate the names on a page -- against
// the sets written for an HTTP chain. So a page declaring auth got a green
// build, a whitelisted key, and a route anybody could open.
//
// These assert on the generated router rather than on the parser. A correct
// parser with nothing calling it is the mistake this repository has already
// made twice, most recently with @DVPage(policy:).
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'generated_router.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'middleware_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Middleware App',
    seoTitle: 'Middleware App',
    seoDesc: 'Middleware App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

Future<Directory> _project() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_page_middleware_',
  );
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  return root;
}

void _page(Directory root, String name, String source) {
  File(p.join(root.path, 'lib', 'pages', name)).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$source
''');
}

void main() {
  test('pure application generates its root without an app argument', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    await _routerFor(root);
    final entry = File(
      p.join(root.path, 'lib/dartvel_client/application.g.dart'),
    );
    expect(entry.existsSync(), isTrue);
    final output = entry.readAsStringSync();
    expect(output, contains('MaterialApp.router('));
    expect(output, contains('createDartvelRouter(arguments: args)'));
    expect(output, contains('run([List<String> args'));
    expect(output, isNot(contains('run(Widget')));
    // It imported a launch.g.dart nothing writes, so the one-line main of
    // every pure application failed to compile.
    for (final m in RegExp(r"import '([\w.]+\.dart)'").allMatches(output)) {
      expect(
        File(p.join(root.path, 'lib/dartvel_client', m.group(1)!)).existsSync(),
        isTrue,
        reason: '${m.group(1)} is imported and was not generated',
      );
    }
    expect(
      File(p.join(root.path, 'lib/dartvel_client/dartvel_client.dart'))
          .readAsStringSync(),
      contains("export 'application.g.dart'"),
    );
  });
  test(
    'boot hooks and optional host root are lowered in stable order',
    () async {
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
      File(p.join(root.path, 'lib/boot.dart')).writeAsStringSync('''
import 'dartvel_client/dartvel_client.dart';
@DVBoot()
void _first(DVBoot boot) { DV.log('first'); }
@DVBoot(entries: {DVEntryKind.app})
Future<void> _second(DVBoot boot) async => DV.log('second');
@DVAppRoot()
Widget _root(BuildContext context, DVAppParts parts) => MaterialApp.router(routerConfig: parts.router);
''');
      await _routerFor(root);
      final output = File(
        p.join(root.path, 'lib/dartvel_client/application.g.dart'),
      ).readAsStringSync();
      expect(output, contains("DV.log('first')"));
      expect(output, contains("DV.log('second')"));
      expect(
        output.indexOf("DV.log('first')"),
        lessThan(output.indexOf("DV.log('second')")),
      );
      expect(output, contains('routerConfig: parts.router'));
    },
  );
  // The barrel hides the runtime's DV and exports the generated one, so every
  // public static the runtime has must be on the generated class too, with
  // its type. A forwarder written `static get Auth => runtime.DV.Auth` is
  // dynamic: `DV.Auth.signIn(...)` still compiles with any arguments, and
  // `DV.global<Clock>()` stops being checked at all -- a typo is a runtime
  // NoSuchMethodError in a release build instead of a compile error.
  test('the generated DV forwards every runtime member, typed', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    await _routerFor(root);
    final output = File(
      p.join(root.path, 'lib/dartvel_client/application.g.dart'),
    ).readAsStringSync();
    final facade = output.substring(output.indexOf('abstract final class DV'));

    final runtime = File('../dartvel_flutter/lib/dartvel_flutter.dart')
        .readAsStringSync();
    final start = runtime.indexOf('\nclass DV {');
    final body = runtime.substring(start, runtime.indexOf('\n}\n', start));
    final names = <String>{
      for (final m in RegExp(
        r'^  static (?:const |final )?(?:[\w<>?, ]+?\s+)?(?:get |set )?([A-Za-z$][\w$]*)\s*(?:[<(=;]|=>)',
        multiLine: true,
      ).allMatches(body))
        if (!m.group(1)!.startsWith('_')) m.group(1)!,
    // container is Riverpod's, the framework's own: not application surface.
    }..removeAll(<String>{'run', 'Function', 'container'});
    expect(names, containsAll(<String>['Auth', 'global', 'transaction', r'$', 'log']));

    for (final name in names) {
      expect(
        RegExp('[^\\w\$]${RegExp.escape(name)}(?![\\w\$])').hasMatch(facade),
        isTrue,
        reason: 'DV.$name is not forwarded',
      );
    }
    // Nothing forwarded untyped.
    expect(facade, isNot(contains('static get ')));
    expect(facade, contains('static T global<T>('));
    expect(facade, contains('static Future<T> transaction<T>('));
    expect(facade, contains('static DVAuth get Auth'));
    expect(facade, contains("@Deprecated("));
  });
  test('a host root that drops the router is refused', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'lib/boot.dart')).writeAsStringSync(
      '@DVAppRoot() Widget _root(BuildContext context, DVAppParts parts) => MaterialApp();',
    );
    await expectLater(
      _routerFor(root),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('DV-RUN-006'),
        ),
      ),
    );
  });
}
