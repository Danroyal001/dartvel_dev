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
  // An app root that wraps the project's own @DVFunctionalWidget (the app's
  // theme shell, say) names a class that only exists in widgets.g.dart. The
  // entry inlined that body without importing it, so `DV.run(args)` failed to
  // compile with "Method not found" (found on Dartvel Authenticator).
  test('a host root may use the project\'s own functional widgets', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    File(p.join(root.path, 'lib/app.dart')).writeAsStringSync('''
import 'dartvel_client/dartvel_client.dart';
@DVAppRoot()
Widget _root(BuildContext context, DVAppParts parts) => ShellApp(router: parts.router);
@DVFunctionalWidget()
Widget _shellApp(BuildContext context, {required RouterConfig<Object> router}) =>
    MaterialApp.router(routerConfig: router);
''');
    await _routerFor(root);
    final output = File(
      p.join(root.path, 'lib/dartvel_client/application.g.dart'),
    ).readAsStringSync();
    expect(output, contains('ShellApp(router: parts.router)'));
    expect(output, contains("import 'widgets.g.dart';"));
    expect(
      File(p.join(root.path, 'lib/dartvel_client/widgets.g.dart'))
          .readAsStringSync(),
      contains('ShellApp'),
    );
  });
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
  // A functional widget's body is copied with its file's imports, the barrel
  // among them, whose DV is now the generated one. The generator's own import
  // of the runtime brought a second DV, and every widget that used DV stopped
  // compiling: 'DV' is imported from both.
  test('inlined source resolves DV through its own imports only', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    Directory(p.join(root.path, 'lib/components')).createSync();
    File(p.join(root.path, 'lib/components/copy.dart')).writeAsStringSync('''
import '../dartvel_client/dartvel_client.dart';
@DVFunctionalWidget()
Widget _copyButton(BuildContext context) =>
    DVText('Copy').modifier(DVModifier().onTap(() => DV.Clipboard.copy('x')));
''');
    await _routerFor(root);
    final widgets = File(p.join(root.path, 'lib/dartvel_client/widgets.g.dart'))
        .readAsStringSync();
    final runtimeImports = RegExp(
      r"^import 'package:dartvel_flutter/dartvel_flutter\.dart'([^;]*);",
      multiLine: true,
    ).allMatches(widgets).map((m) => m.group(1)!).toList();
    expect(runtimeImports, isNotEmpty);
    for (final clause in runtimeImports) {
      expect(clause, matches(RegExp(r'hide .*\bDV\b')), reason: clause);
    }
    expect(widgets, contains("dartvel_client/dartvel_client.dart'"));
  });
  // The lowered boot body sat inside `abstract final class DV`, so a name
  // the application declares and DV also has -- Session, Auth, Cache --
  // resolved to DV's static instead (found on the SigmaDev site's `Session`).
  test('boot bodies are lowered outside the DV class', () async {
    final root = await _project();
    addTearDown(() => root.deleteSync(recursive: true));
    _page(root, 'index.dart', '@DVPage() Widget _index() => DVText("Home");');
    File(p.join(root.path, 'lib/boot.dart')).writeAsStringSync('''
import 'dartvel_client/dartvel_client.dart';
@DVBoot()
void _start(DVBoot boot) { DV.log('boot ran'); }
''');
    await _routerFor(root);
    final output = File(p.join(root.path, 'lib/dartvel_client/application.g.dart')).readAsStringSync();
    final int classStart = output.indexOf('abstract final class DV');
    expect(output.indexOf("DV.log('boot ran')"), greaterThanOrEqualTo(0));
    expect(output.indexOf("DV.log('boot ran')"), lessThan(classStart));
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
