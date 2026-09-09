// The generated runtime asks what link this launch carried, on mobile too.
//
// A home widget's tap is a deep link, and on Android and iOS the whole chain
// existed except its last step. `dartvel build` writes the capture -- the
// Activity's intent on one side, two AppDelegate overrides on the other --
// and both platforms register `deepLinks.initial` to read it back. Nothing
// called it. The generated launch path takes the single-instance lock and
// opens what argv named, which is a desktop shape, so it returned
// immediately on every other platform and the captured link sat there.
//
// The symptom is the reason this is worth a test: the application came up.
// It came up at its own starting route rather than at the widget's page,
// which is a shortcut rather than a widget, and reads as working.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _runtimeFor() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_launch_link_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'link_app',
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

  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  late String runtime;
  setUpAll(() async => runtime = await _runtimeFor());

  String launchBody() {
    final int start = runtime.indexOf('void startDartvelLaunch(');
    expect(start, greaterThan(-1));
    return runtime.substring(start, runtime.indexOf('\n}\n', start));
  }

  test('a non-desktop launch reads the link before it gives up', () {
    final String body = launchBody();
    final int mobile = body.indexOf('DVAppLaunch.openLaunchLink(');
    final int desktopOnly = body.indexOf('if (!desktop)');

    expect(mobile, greaterThan(-1),
        reason: 'nothing on Android or iOS ever asks what launched the app');
    // Before the early return, or it is written and unreachable -- which is
    // the same as not being there, with a line in the file saying otherwise.
    expect(mobile, greaterThan(desktopOnly));
    expect(body.substring(desktopOnly, mobile), isNot(contains('return;')));
  });

  test('it reads the link through the binding both platforms register', () {
    // `deepLinks.initial` is the name Android's JNI bindings and the iOS FFI
    // bindings both register. A different name here is a call that answers
    // null for ever on a launch that really did carry a URL.
    expect(launchBody(), contains("'deepLinks.initial'"));
  });

  test('a missing binding does not take the launch down', () {
    // invoke, not require: require throws for an unregistered name, and this
    // runs on every platform the application is built for. A crash at
    // startup would be the cost of a widget nobody on that platform has.
    expect(launchBody(), contains("DVNativeBridge.invoke<String>('deepLinks.initial')"));
  });

  test('it navigates in place rather than opening a window', () {
    // The desktop path opens an external window, which is right for a second
    // launch of a desktop application and wrong here: a phone has one window
    // and the widget's page belongs in it.
    final String body = launchBody();
    // Bounded at the desktop path, which is where the external window
    // belongs and where an unbounded slice would find one.
    final String branch = body.substring(
      body.indexOf('DVAppLaunch.openLaunchLink('),
      body.indexOf('DVAppLaunch.start('),
    );

    expect(branch, contains('DV.Navigation.navigate(DVRouteTarget(route))'));
    expect(branch, isNot(contains('DVWindowOptions.external')));
  });

  test('it waits for a router before navigating', () {
    // DV.Navigation throws when no router is attached, and this runs from the
    // router's own constructor -- before runApp, before the attach. Reaching
    // for it there would be a StateError on first launch on a phone.
    expect(launchBody(), contains('addPostFrameCallback'));
  });
}
