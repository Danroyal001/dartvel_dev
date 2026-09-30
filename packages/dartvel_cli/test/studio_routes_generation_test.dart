// Studio is routes of the application's own router.
//
// The generator mounts dvStudioRoutes at dartvel.admin's mount, compiled in
// only when a build says it serves Studio (`-Ddartvel.studio=true`, which
// `dartvel build web-server` passes): a static build, a phone build or a
// desktop build tree-shakes the branch and carries none of Studio. An
// application that turns Studio off does not have the routes generated at
// all.
import 'dart:io';

import 'package:dartvel_cli/src/build/admin_mount.dart' show dvStudioDefine;
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> routerSource(String dartvelYaml) async {
  final root = await Directory.systemTemp.createTemp('dartvel_studio_routes_');
  try {
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
        .writeAsStringSync('''
import 'package:flutter/widgets.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _home(BuildContext context) => const Text('home');
''');
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);

    await ClientGenerator.generate(
      root: root.path,
      pagesDir: 'lib/pages',
      pkgName: 'shop',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 8080,
      devBackendHost: 'http://127.0.0.1:8080',
      prodBackendHost: 'https://example.com',
      apiBasePath: '/api',
      envFiles: const <String>[],
      seoSiteName: 'app',
      seoTitle: 'app',
      seoDesc: 'app',
      seoImage: '',
      seoTwitter: '',
      defaultTransition: 'none',
      durationMs: 200,
      curve: 'linear',
      normalizeTrailing: true,
      notFoundRedirect: '',
      plugins: const <String>[],
      webPrerender: false,
      ota: false,
      dv: dartvelYaml.isEmpty ? YamlMap() : loadYaml(dartvelYaml) as YamlMap,
    );

    return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

void main() {
  test('the define a build passes to compile Studio in', () {
    expect(dvStudioDefine, 'dartvel.studio');
  });

  test("Studio's routes are the application's, at the default mount, compiled "
      'in only by a build that serves Studio', () async {
    final String router = await routerSource('');
    expect(
        router,
        contains("if (const bool.fromEnvironment('dartvel.studio'))\n"
            "      ...dvStudioRoutes(mount: '/__studio', title: 'Studio · shop', view: dartvelPagePreview),"));
  });

  test('a moved mount moves the routes', () async {
    final String router = await routerSource('admin:\n  path: /ops/desk/\n');
    expect(router,
        contains("...dvStudioRoutes(mount: '/ops/desk', title: 'Studio · shop', view: dartvelPagePreview),"));
  });

  test('an application that turns Studio off has none of it generated',
      () async {
    final String router = await routerSource('admin:\n  enabled: false\n');
    expect(router, isNot(contains('dvStudioRoutes')));
    expect(router, isNot(contains('dartvel.studio')));
  });

  test('a documentation site behind Studio is where its sign-in returns to',
      () async {
    // The docs site with access: studio sends a signed-out reader to
    // Studio's sign-in; signing in has to bring them back to the page they
    // were reading, not to Studio.
    final String router = await routerSource(
        'docs:\n  enabled: true\n  path: /handbook\n  access: studio\n');
    expect(
        router,
        contains("...dvStudioRoutes(mount: '/__studio', title: 'Studio · shop', "
            "signInReturns: <String>['/handbook'], view: dartvelPagePreview),"));
    final String public = await routerSource(
        'docs:\n  enabled: true\n  path: /handbook\n  access: public\n');
    expect(public, isNot(contains('signInReturns')));
  });

  test("the route and Studio's canvas build a page through one function, "
      'so the canvas draws the page exactly as the route does', () async {
    final String router = await routerSource('');
    // Studio is handed the application's page views.
    expect(router, contains('view: dartvelPagePreview'));
    expect(
        router,
        contains('Widget? dartvelPagePreview(String path, '
            '{Widget? content, bool layout = true})'));
    // One view per page, which both the route and the preview call.
    final RegExpMatch? view =
        RegExp(r'Widget (_dvView\w+)\(Map<String, String> params, '
                r'Map<String, String> query, Widget body, \{bool layout = true\}\)')
            .firstMatch(router);
    expect(view, isNotNull, reason: 'no page view function');
    final String name = view!.group(1)!;
    final int calls = RegExp('${RegExp.escape(name)}\\(').allMatches(router).length;
    expect(calls, 3, reason: 'declared once, called by the route and the preview');
    // The route still lets a stored document take its page over.
    expect(router, contains("$name(params, query, DVStudioPageRoute('/', fallback: page))"));
    // The preview draws the page itself, or what Studio is editing, in it.
    expect(router, contains('$name(const <String, String>{}, '
        'const <String, String>{}, content ?? const '));
  });

  test('a page made in Studio is drawn in the site''s frame, on the site and '
      'on the canvas', () async {
    final String router = await routerSource('');
    expect(router,
        contains('DVStudioPageRoute(state.uri.path, frame: _dartvelStoredFrame)'));
    expect(router,
        contains('Widget _dartvelStoredFrame(Widget document, {bool layout = true})'));
    // An address the application has no page at: Studio's document, framed.
    expect(router,
        contains('_ => content == null ? null : _dartvelStoredFrame(content, layout: layout)'));
  });
}
