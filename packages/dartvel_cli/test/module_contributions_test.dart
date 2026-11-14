// What a mounted module brings to the application besides its pages and
// functions, read from the module's own pubspec so the application does not
// repeat it:
//
// - the third-party origins its scripts need, added to the page policy the
//   application declared (`dartvel.module.csp`);
// - a function run once the module is registered, in the client and in the
//   server, so a module that listens for something starts listening without
//   the application calling it (`dartvel.module.start`);
// - the settings the application gives it at the mount (`config:`), which
//   reach `DV.Modules.<id>.config`.
//
// And a module mounted as a dependency (`package:`) has its carried
// operations served like one mounted from a path, each handed the request it
// arrived on.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

const String _modulePubspec = '''
name: acme_pixel
dartvel:
  module:
    id: pixel
    surface: AcmePixel
    start: startAcmePixel
    csp:
      script-src: [https://cdn.pixel.example]
      connect-src: [https://collect.pixel.example]
    operations:
      collect:
        native: {compat: backend}
        web: {compat: backend}
        backend: real
''';

Directory workspace({
  String security = '',
  String mount = '',
  String modulePubspec = _modulePubspec,
  bool fromPackage = false,
}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_module_contrib_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
$security  modules:
    pixel:
${fromPackage ? '      package: acme_pixel' : '      source: { path: modules/acme_pixel }'}
      backendPolicy: public
$mount''');
  File(p.join(root.path, 'modules', 'acme_pixel', 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync(modulePubspec);
  if (fromPackage) {
    File(p.join(root.path, '.dart_tool', 'package_config.json'))
        .writeAsStringSync(jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'acme_pixel',
          'rootUri': '../modules/acme_pixel/',
          'packageUri': 'lib/',
        },
      ],
    }));
  }
  return root;
}

Future<String> routes(Directory root) async {
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shopfront',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  return File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
      .readAsStringSync();
}

Future<String> registration(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shopfront',
    buildId: 'b',
    modules: dvDiscoverModuleMounts(root.path),
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
    ota: false,
    dv: YamlMap(),
  );
  return File(p.join(
          root.path, 'lib', 'dartvel_client', 'modules_data.g.dart'))
      .readAsStringSync();
}

void main() {
  group('the origins a module needs', () {
    test('are read from the module\'s own pubspec', () {
      final DVModuleMount mount =
          dvDiscoverModuleMounts(workspace().path).single;
      expect(mount.problems, isEmpty);
      expect(mount.csp, <String, List<String>>{
        'script-src': <String>['https://cdn.pixel.example'],
        'connect-src': <String>['https://collect.pixel.example'],
      });
    });

    test('are added to the page policy the application declared', () async {
      final String source = await routes(workspace(
        security: '  security:\n'
            '    pageCsp: "default-src \'self\'; '
            'script-src \'self\' \'inline-scripts\'"\n',
      ));
      expect(
        source,
        contains("const String? dartvelPageContentSecurityPolicy = "
            "'default-src \\'self\\'; "
            "script-src \\'self\\' \\'inline-scripts\\' "
            "https://cdn.pixel.example; "
            "connect-src \\'self\\' https://collect.pixel.example';"),
      );
    });

    test('do not invent a policy for an application that declared none',
        () async {
      final String source = await routes(workspace());
      expect(source,
          contains('const String? dartvelPageContentSecurityPolicy = null;'));
    });

    test('are refused when they are not origins, naming the module', () {
      final DVModuleMount mount = dvDiscoverModuleMounts(workspace(
        modulePubspec: '''
name: acme_pixel
dartvel:
  module:
    id: pixel
    csp:
      script-src: ["'unsafe-inline'"]
''',
      ).path).single;
      expect(mount.csp, isEmpty);
      expect(mount.problems.join('\n'),
          allOf(contains('pixel'), contains("'unsafe-inline'")));
    });
  });

  group('a module\'s start function', () {
    test('is called with the module once it is registered', () async {
      final String source = await registration(workspace());
      expect(source,
          contains("import 'package:acme_pixel/acme_pixel.dart' as "));
      expect(
        RegExp(r"\w+\.startAcmePixel\(\s*dvModuleRegistry\.register\(\s*id: 'pixel'")
            .hasMatch(source),
        isTrue,
        reason: source,
      );
    });

    test('keeps the registration free of Flutter', () async {
      final String source = await registration(workspace());
      expect(source, isNot(contains('dartvel_flutter')));
      expect(source, isNot(contains('package:flutter/')));
    });

    test('is refused when it is not a function name', () {
      final DVModuleMount mount = dvDiscoverModuleMounts(workspace(
        modulePubspec: '''
name: acme_pixel
dartvel:
  module:
    id: pixel
    start: "print('x'); start"
''',
      ).path).single;
      expect(mount.start, isNull);
      expect(mount.problems.join('\n'), contains('start'));
    });

    test('a module without one is registered as before', () async {
      final String source = await registration(workspace(
        modulePubspec: 'name: acme_pixel\ndartvel:\n  module:\n    id: pixel\n',
      ));
      expect(source, contains("id: 'pixel'"));
      expect(source, isNot(contains('acme_pixel.dart')));
    });
  });

  group('the settings an application gives a module', () {
    test('reach DV.Modules.<id>.config', () async {
      final Directory root = workspace(
        mount: '      config:\n'
            '        pixelId: "1234567890"\n'
            '        consent: marketing\n'
            '        debug: true\n',
      );
      expect(dvDiscoverModuleMounts(root.path).single.config,
          <String, Object?>{
        'pixelId': '1234567890',
        'consent': 'marketing',
        'debug': true,
      });
      final String source = await registration(root);
      expect(source, contains("'config': <String, Object?>{"));
      expect(source, contains("'pixelId': '1234567890'"));
      expect(source, contains("'consent': 'marketing'"));
      expect(source, contains("'debug': true"));
    });

    test('are refused when they are not a map', () {
      final DVModuleMount mount = dvDiscoverModuleMounts(
              workspace(mount: '      config: yes-please\n').path)
          .single;
      expect(mount.problems.join('\n'), contains('config'));
    });
  });

  group('operations carried to the backend', () {
    test('are served for a module mounted as a dependency', () async {
      final String source = await routes(workspace(fromPackage: true));
      expect(source,
          contains("cfg.apiBasePath + '/_dv/modules/pixel/collect'"));
      expect(source,
          contains("import 'package:acme_pixel/src/carrier_backend.dart'"));
    });

    test('are handed the request they arrived on', () async {
      final String source = await routes(workspace());
      expect(
        source,
        contains('await core.DVModuleRpc.withRequest(req, () async => await '),
      );
    });
  });
}
