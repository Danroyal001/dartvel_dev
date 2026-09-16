// The request lifecycle the documentation lists is a reading of what the
// backend generator emits, kept beside the site rather than inside the
// generator. That is a second encoding of one order, and the way it goes
// wrong is silent: a stage moves in the generator and the site keeps printing
// a lifecycle that is perfectly plausible and no longer true.
//
// So this generates a real backend and holds the site to it, in both
// directions: every stage the site lists is in the handler, in that order,
// and every optional stage the handler has is one the site lists.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:dartvel_cli/src/docs/docs_site.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Map<String, String> _files = <String, String>{
  'pubspec.yaml': '''
name: stages_probe
publish_to: none
environment:
  sdk: ^3.9.0
''',
  'lib/backend/functions/checkout.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: DVPolicies.checkout)
@DVUseMiddleware([DVMiddlewares.tracing, DVMiddlewares.rateLimit, DVMiddlewares.bodyLimit])
Future<String> _checkout(DVContext context, String basketId) async =>
    basketId;
''',
  // Typed without the annotation. The generator decides a function is typed
  // from its signature, so this reads its body and checks CSRF like any
  // other -- and the site first listed it as a raw handler, because it went
  // by whether the annotation was there.
  'lib/backend/functions/sum.post.dart': '''
int sum(int a, int b) => a + b;
''',
  'lib/backend/functions/upload.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async => ResponseType.text('ok');
''',
  'lib/backend/functions/status.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _status() async => <String, Object?>{};
''',
};

/// The text in the generated handler that marks each stage.
Pattern _marker(String stage, String function) => switch (stage) {
  'tenant' => 'core.dvWithRequestTenant(',
  'tracing' => 'core.dvTraced(',
  'body' => 'req.body',
  'csrf' => '_dvValidateCsrf(',
  'policy' => '_dvAllowed(',
  'context' => 'core.DVContext(',
  // The generator calls a typed function through the library it lowered it
  // into (`bf0.dvBackendFn0()`) or the source's prefix (`f0.name(...)`).
  'function' => RegExp(
    'await (?:bf\\d+\\.dvBackendFn\\d+|f\\d+\\.$function|f\\d+\\.handler)\\(',
  ),
  _ when stage.startsWith('middleware:') =>
    "'${stage.substring('middleware:'.length)}'",
  _ => throw ArgumentError(stage),
};

List<String> _stagesIn(String html, String function) {
  final int start = html.indexOf('id="function-$function"');
  final int end = html.indexOf('<section', start + 1);
  return RegExp(r'<li class="stage" data-stage="([^"]+)"')
      .allMatches(html.substring(start, end == -1 ? html.length : end))
      .map((RegExpMatch m) => m.group(1)!)
      .toList();
}

/// The generated registration for [method] [path], up to the next one.
String _handler(String routes, String method, String path) {
  final int start = routes.indexOf("router.$method(cfg.apiBasePath + '$path'");
  expect(start, isNot(-1), reason: 'no $method $path registration');
  final int end = routes.indexOf('  router.', start + 1);
  return routes.substring(start, end == -1 ? routes.length : end);
}

void main() {
  late Directory root;
  late String routes;
  late String functions;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('dv_docs_stages_');
    _files.forEach((String relative, String contents) {
      final File file = File(
        p.joinAll(<String>[root.path, ...relative.split('/')]),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    });
    await BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'stages_probe',
      backendHost: '127.0.0.1',
      backendPort: 8787,
      apiBasePath: '/api',
    );
    routes = File(
      p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
    ).readAsStringSync();
    functions = (await DVDocsSite.build(
      root: root.path,
    )).files['functions.html']!;
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  for (final (String method, String path, String name)
      in <(String, String, String)>[
        ('post', '/checkout', 'checkout'),
        ('get', '/status', 'status'),
        ('post', '/sum', 'sum'),
        ('post', '/upload', 'upload'),
      ]) {
    test('$method $path: the stages listed run in the order listed', () {
      final String handler = _handler(routes, method, path);
      final List<String> stages = _stagesIn(functions, name);
      expect(stages, isNotEmpty);
      int previous = -1;
      for (final String stage in stages) {
        final int at = handler.indexOf(_marker(stage, name));
        expect(
          at,
          isNot(-1),
          reason: '$stage is listed and not in the handler',
        );
        expect(
          at,
          greaterThan(previous),
          reason: '$stage is listed after a stage the handler runs later',
        );
        previous = at;
      }
    });

    test('$method $path: every optional stage in the handler is listed', () {
      final String handler = _handler(routes, method, path);
      final List<String> stages = _stagesIn(functions, name);
      for (final String stage in <String>[
        'csrf',
        'tracing',
        'policy',
        'context',
        'middleware:rateLimit',
        'middleware:bodyLimit',
      ]) {
        if (handler.contains(_marker(stage, name))) {
          expect(
            stages,
            contains(stage),
            reason: 'the handler has $stage and the site does not say so',
          );
        }
      }
    });
  }
}
