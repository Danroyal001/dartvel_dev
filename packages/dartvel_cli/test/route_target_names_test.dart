// A route's typed target is a lowerCamelCase name, and the name it used to
// have still works for one more release.
//
// `/next_shift` generated `DVRoutes.next_shift`, which Dart's own style lint
// rejects -- and a Flutter project's CI runs `flutter analyze`, where an info
// is a failure. So a Dartvel app with an underscore in a page directory failed
// its own analyzer on code it never wrote.
//
// Renaming it silently would break every `DVRoutes.next_shift` already
// written, so the old name stays as a deprecated alias for the new one.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> routerFor(Map<String, String> pages) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_route_names_');
  addTearDown(() => root.deleteSync(recursive: true));

  for (final MapEntry<String, String> page in pages.entries) {
    File(p.join(root.path, 'lib', 'pages', page.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(page.value);
  }
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'names_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
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
    notFoundRedirect: '/',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

String page(String name) => "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: '$name')\n"
    "Widget ${name}Page(BuildContext context) => const DVText('$name');\n";

/// The declaration of [member] inside `class DVRoutes`, and the lines
/// directly above it.
String declarationOf(String router, String member) {
  final int start = router.indexOf('class DVRoutes {');
  final String routes = router.substring(start, router.indexOf('\n}', start));
  final List<String> lines = routes.split('\n');
  final int at = lines.indexWhere((String l) =>
      RegExp('static (const|DVRouteTarget) $member\\b').hasMatch(l));
  expect(at, isNonNegative, reason: 'DVRoutes has no $member:\n$routes');
  return lines.sublist(at < 2 ? 0 : at - 2, at + 1).join('\n');
}

void main() {
  test('an underscore in a route becomes a lowerCamelCase target', () async {
    final String router = await routerFor(<String, String>{
      'next_shift.dart': page('nextShift'),
    });

    expect(declarationOf(router, 'nextShift'),
        contains("static const nextShift = DVRouteTarget('/next_shift');"));
  });

  test('the old name is kept as a deprecated alias for the new one',
      () async {
    final String router = await routerFor(<String, String>{
      'next_shift.dart': page('nextShift'),
    });

    final String alias = declarationOf(router, 'next_shift');
    expect(alias, contains('static const next_shift = nextShift;'),
        reason: 'the same target, not a second copy that could drift');
    expect(alias, contains('@Deprecated('));
    // The alias is exactly the name the lint rejects; without this the
    // deprecation would keep the analyzer failing for another release.
    expect(alias, contains('// ignore: constant_identifier_names'));
  });

  test('a route with a parameter keeps its old name too', () async {
    final String router = await routerFor(<String, String>{
      'shift_log/[id].dart': page('shiftLog'),
    });

    expect(declarationOf(router, 'shiftLog'),
        contains('static DVRouteTarget shiftLog({required String id})'));
    final String alias = declarationOf(router, 'shift_log');
    expect(alias, contains('=> shiftLog(id: id);'));
    expect(alias, contains('// ignore: non_constant_identifier_names'));
  });

  test('a name with no underscore is unchanged and gets no alias', () async {
    final String router = await routerFor(<String, String>{
      'about.dart': page('about'),
    });

    expect(declarationOf(router, 'about'),
        contains("static const about = DVRouteTarget('/about');"));
    expect(router, isNot(contains('@Deprecated(')));
  });
}
