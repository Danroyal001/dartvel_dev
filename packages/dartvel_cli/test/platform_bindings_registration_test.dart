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

Future<String> runtimeFor() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_reg_');
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
    dv: YamlMap(),
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  late String runtime;
  setUpAll(() async => runtime = await runtimeFor());

  test('every desktop and mobile platform is registered by name', () {
    for (final String binding in <String>[
      'DVLinuxBindings.register()',
      'DVWindowsBindings.register()',
      'DVMacosBindings.register()',
      'DVIosBindings.register()',
    ]) {
      expect(runtime, contains(binding), reason: binding);
    }
  });

  test('registration is part of configuring the runtime, not left to the app',
      () {
    // Inside configureDartvelRuntime(), which the generated router already
    // calls. A separate function the application had to remember is how this
    // was missing in the first place.
    final int configure = runtime.indexOf('void configureDartvelRuntime(');
    final int end = runtime.indexOf('\n}\n', configure);
    final String body = runtime.substring(configure, end);
    expect(body, contains('registerPlatformBindings'));
  });

  test('the web never sees it', () {
    // dart:ffi is not available there, and the conditional export already
    // resolves each class to a stub -- but the call must still be guarded so
    // a web build does not pay for four stubs' worth of code either.
    expect(runtime, contains('if (kIsWeb) return;'));
  });

  test('it dispatches on the running platform, once', () {
    // One switch over defaultTargetPlatform, not four ifs that could each be
    // true on a mis-detected host.
    expect(runtime, contains('switch (defaultTargetPlatform)'));
    expect(runtime, contains('TargetPlatform.linux'));
    expect(runtime, contains('TargetPlatform.windows'));
    expect(runtime, contains('TargetPlatform.macOS'));
    expect(runtime, contains('TargetPlatform.iOS'));
  });

  test('a platform whose libraries are missing is not a crash', () {
    // register() returns false on a headless container without X11; the
    // runtime says so and carries on, because an app that cannot copy to the
    // clipboard is still an app.
    expect(runtime, contains('debugPrint'));
    expect(runtime, isNot(contains('throw StateError(\'Native bindings')));
  });
}
