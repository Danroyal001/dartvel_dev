// @DVPage(mfa: ...) read by the router generator, and the step-up the
// generated runtime installs.
//
// DVPageMfa decides and the second-factor page presents -- both tested in
// dartvel_flutter -- and none of it matters unless the generated router asks:
// a page declaring a second factor whose route has no redirect opens for a
// password-only session with a green build. The whole generated client
// compiling is generated_client_analyzes_test's; this pins the connections
// only the generator makes, and the refusal of a declaration it cannot read.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _generate(Map<String, String> pages) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_mfa_router_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  pages.forEach((String name, String source) {
    File(p.join(root.path, 'lib', 'pages', name))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'bank_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Bank',
    seoTitle: 'Bank',
    seoDesc: 'Bank',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap.wrap(const <String, Object?>{}),
  );
  return root;
}

String _page(String name, String annotation) => '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$annotation
Widget ${name}Page(BuildContext context) => const SizedBox.shrink();
''';

String _read(Directory root, String file) =>
    File(p.join(root.path, 'lib', 'dartvel_client', file)).readAsStringSync();

/// The route block for [path] in the generated router.
String _route(String router, String path) {
  final int at = router.indexOf("path: '$path'");
  expect(at, isNot(-1), reason: 'no route for $path');
  final int end = router.indexOf('GoRoute(', at);
  return router.substring(at, end == -1 ? router.length : end);
}

void main() {
  test('a page declaring a second factor gets the gate, with its window, and '
      'the challenge route exists', () async {
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
      'billing.dart': _page('billing', '@DVPage(mfa: DVMfa.required)'),
      'payout.dart': _page('payout', '''
@DVPage(
  title: 'Payout',
  mfa: DVMfa.recent(Duration(minutes: 15)),
)'''),
    });
    final String router = _read(root, 'router.g.dart');
    expect(_route(router, '/billing'), contains('DVPageMfa.required(context, state)'));
    expect(_route(router, '/payout'),
        contains('DVPageMfa.recent(context, state, const Duration(milliseconds: 900000))'));
    expect(_route(router, '/'), isNot(contains('DVPageMfa')));
    expect(_route(router, '/second-factor'),
        contains("DV.Auth.SecondFactorPage(from: state.uri.queryParameters['from'])"));
  });

  test('an application with no page declaring a second factor gets no '
      'challenge route', () async {
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    });
    expect(_read(root, 'router.g.dart'), isNot(contains('/second-factor')));
  });

  test('the runtime installs the step-up challenge for refused calls', () async {
    final Directory root = await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    });
    final String runtime = _read(root, 'dartvel_runtime.dart');
    final int provider = runtime.indexOf('DVAuth.installDefaultProvider(');
    final int stepUp = runtime.indexOf('DVAuth.installStepUp();');
    expect(provider, isNot(-1));
    expect(stepUp, greaterThan(provider));
  });

  test('a page mfa the generator cannot read stops the build and names the '
      'file', () async {
    await expectLater(
      _generate(<String, String>{
        'vault.dart': _page('vault', '@DVPage(mfa: strictPolicy)'),
      }),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('vault.dart'), contains('mfa')))),
    );
  });
}
