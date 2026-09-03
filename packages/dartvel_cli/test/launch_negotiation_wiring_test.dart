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

Future<String> runtimeFor({bool terminal = false}) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_launch_');
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
    dv: terminal ? YamlMap.wrap(<String, Object?>{'terminal': true}) : YamlMap(),
  );

  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

// Launch negotiation, wired into what main calls. A GUI-only build has no
// decision to make and links no terminal code; a build that opted into the
// terminal decides from the arguments and the display -- --tui starts in the
// terminal, no display with both backends asks -- and a terminal outcome
// hands the process to the terminal runner beside the GUI binary.
void main() {
  test('a GUI-only build negotiates nothing and links no terminal', () async {
    final String plain = await runtimeFor();
    expect(plain, contains('Future<void> negotiateDartvelLaunch(List<String> arguments)'));
    expect(plain, contains('DVRenderSurface.gui}'));
    expect(plain, isNot(contains('DVRenderSurface.terminal')));
    expect(plain, isNot(contains('resolveLaunchSurface(')), reason: 'no decision, no code that makes one');
    expect(plain, isNot(contains('DVLaunchOutcome.terminal')));
  });

  test('a build with the terminal linked resolves from the arguments and the display', () async {
    final String dual = await runtimeFor(terminal: true);
    expect(dual, contains('resolveLaunchSurface('));
    expect(dual, contains('DVRenderSurface.gui, DVRenderSurface.terminal}'));
    expect(dual, contains('displayAvailable: dvDisplayAvailable()'));
    expect(dual, contains('DVLaunchOutcome.terminal'));
    expect(dual, contains('DVLaunchOutcome.askToUseTerminal'));
    expect(dual, contains('dvTerminalFallbackPrompt'));
    expect(dual, contains('dvTerminalRunnerPathFor('));
  });

  test("the project template's main negotiates before it runs the app", () {
    expect(ProjectTemplates.mainTemplate, contains('await negotiateDartvelLaunch(arguments);'));
    final int negotiate = ProjectTemplates.mainTemplate.indexOf('negotiateDartvelLaunch');
    final int run = ProjectTemplates.mainTemplate.indexOf('runApp(');
    expect(negotiate, lessThan(run));
  });
}
