// The generated runtime registers the platform's native bindings.
//
// DVLinuxBindings, DVWindowsBindings, DVMacosBindings and DVIosBindings each
// have a register() that loads the libraries and wires clipboard, window,
// notifications and the rest onto DVNativeBridge. Nothing in a generated
// application called any of them: the only call sites were the framework's
// own tests. So DV.Platform.Clipboard.copy() on a Linux desktop threw "binding
// not registered" in every real app, and the platform matrix that reports
// those bindings as implemented was describing code no application reached.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> configFor() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_kiosk_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'reg_app',
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
    dv: YamlMap.wrap(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'display',
        'home': '/welcome',
        'exit': <String, Object?>{'method': 'adminAuth'},
        'policies': <String, Object?>{
          'customerDisplay': <String, Object?>{
            'home': '/customer-display',
            'routes': <String, Object?>{'allow': <String>['/customer-display/**']},
            'session': <String, Object?>{'idleTimeout': '60s', 'onIdle': 'reset'},
          },
          'staffTerminal': <String, Object?>{'home': '/staff'},
        },
      },
    }),
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'config.g.dart'))
      .readAsStringSync();
}

// Named policies are available to code as DVKioskPolicies.<name>, so a kiosk
// window opened at runtime uses a declared policy rather than an ad-hoc one.
// There is no policy that is not in the declaration: each is the kiosk
// section's own settings with the named entry's over them, parsed by the
// same parser dartvel doctor checks.
void main() {
  late String config;
  setUpAll(() async => config = await configFor());

  test('every declared policy is a member', () {
    expect(config, contains('class DVKioskPolicies'));
    expect(config, contains('static DVKioskPolicy get customerDisplay'));
    expect(config, contains('static DVKioskPolicy get staffTerminal'));
    expect(config, contains("static const List<String> names = <String>['customerDisplay', 'staffTerminal'];"));
  });

  test('a policy is the section with the named entry over it', () {
    final int start = config.indexOf('get customerDisplay');
    final String body = config.substring(start, config.indexOf('get staffTerminal'));
    expect(body, contains("'home': '/customer-display'"));
    expect(body, contains("'scope': 'display'"), reason: 'inherited from the section');
    expect(body, contains("'method': 'adminAuth'"), reason: 'inherited too');
    expect(body, contains("'onIdle': 'reset'"));
    expect(body, isNot(contains("'policies'")), reason: 'a policy does not carry its siblings');
  });

  test('with no policies declared there is still a class, and it is empty', () async {
    final String plain = await plainConfig();
    expect(plain, contains('class DVKioskPolicies'));
    expect(plain, contains('static const List<String> names = <String>[];'));
  });
}

Future<String> plainConfig() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_kiosk_plain_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );
  await ClientGenerator.generate(
    root: root.path, pagesDir: 'lib/pages', pkgName: 'plain_app', buildId: 'b',
    backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com', apiBasePath: '/api', envFiles: const <String>[],
    seoSiteName: 'app', seoTitle: 'app', seoDesc: 'app', seoImage: '', seoTwitter: '',
    defaultTransition: 'none', durationMs: 200, curve: 'linear', normalizeTrailing: true,
    notFoundRedirect: '/', plugins: const <String>[], webPrerender: false, ota: false, dv: YamlMap(),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'config.g.dart')).readAsStringSync();
}
