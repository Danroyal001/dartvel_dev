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
import 'package:dartvel_cli/src/templates/project_templates.dart';
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

  // Every generated file, joined: the runtime and the router live apart.
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

// A file association, a dartvel:// link or a second launch of a desktop
// application arrives as command-line arguments to a new process, and it
// is the generated runtime's job to take the single-instance lock, open
// them, and hand a later launch's arguments to the first -- not the
// application's to remember. What the tests hold to: main's arguments
// reach configureDartvelRuntime, which starts DVAppLaunch on desktop only,
// opens through the window manager as an external request, and ends a
// secondary process.
void main() {
  late String runtime;
  setUpAll(() async => runtime = await runtimeFor());

  String configureBody() {
    final int configure = runtime.indexOf('void configureDartvelRuntime(');
    expect(configure, greaterThan(-1));
    final int end = runtime.indexOf('\n}\n', configure);
    return runtime.substring(configure, end);
  }

  test('configureDartvelRuntime takes the launch arguments', () {
    expect(runtime, contains('void configureDartvelRuntime({List<String> arguments = const <String>[]})'));
  });

  test('the router hands them through', () {
    expect(runtime, contains('GoRouter createDartvelRouter({List<String> arguments = const <String>[]})'));
    expect(runtime, contains('configureDartvelRuntime(arguments: arguments)'));
  });

  test('it starts DVAppLaunch for this app, on desktop only', () {
    final String body = configureBody();
    expect(body, contains("startDartvelLaunch(arguments)"));
    final int start = runtime.indexOf('void startDartvelLaunch(');
    expect(start, greaterThan(-1));
    final String launch = runtime.substring(start, runtime.indexOf('\n}\n', start));
    expect(launch, contains('if (kIsWeb) return;'));
    expect(launch, contains('TargetPlatform.linux'));
    expect(launch, contains('TargetPlatform.windows'));
    expect(launch, contains('TargetPlatform.macOS'));
    expect(launch, contains("appId: 'reg_app'"));
    expect(launch, contains('DVAppLaunch.start('));
  });

  test('routes open as external requests, and a secondary process ends', () {
    final int start = runtime.indexOf('void startDartvelLaunch(');
    final String launch = runtime.substring(start, runtime.indexOf('\n}\n', start));
    expect(launch, contains('DVWindowOptions.external'));
    expect(launch, contains('exit(0)'));
  });

  test("the project template's main passes its arguments on", () {
    expect(ProjectTemplates.mainTemplate, contains('void main(List<String> arguments)'));
    expect(ProjectTemplates.mainTemplate, contains('createDartvelApp(arguments: arguments)'));
    expect(ProjectTemplates.mainTemplate, contains('createDartvelRouter(arguments: arguments)'));
  });
}
