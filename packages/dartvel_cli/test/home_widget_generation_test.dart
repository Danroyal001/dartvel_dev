// Home widgets, as far as Dart can carry them.
//
// The specification gives @DVHomeWidget to any widget and says home widgets
// act like a DVPage: they support the same shell properties, they can launch
// and navigate to pages within the app, a page can navigate back, and Dartvel
// generates a page that centres the widget's content.
//
// The annotation existed and nothing read it. A developer could write
// @DVHomeWidget() on a widget, build, run, and find no widget anywhere and no
// message saying why -- which is the worst shape a missing feature can take,
// because the code says it is there.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

const String _stepCounter = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget()
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) => const DVText('1,204 steps');
''';

Directory? lastRoot;

Future<void> generate({
  Map<String, String> widgets = const <String, String>{
    'widgets/step_counter.dart': _stepCounter,
  },
  String dartvelSection = '',
}) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_home_');
  lastRoot = root;
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
$dartvelSection
''');
  widgets.forEach((String name, String source) {
    File(p.join(root.path, 'lib', name))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  });

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
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );
}

String read(String name) =>
    File(p.join(lastRoot!.path, 'lib', 'dartvel_client', name))
        .readAsStringSync();

void main() {
  test('a home widget is in the generated list, by name and route', () async {
    await generate();

    final String source = read('home_widgets.g.dart');
    expect(source, contains('dartvelHomeWidgets'));
    expect(source, contains("id: 'step-counter'"));
    expect(source, contains("name: 'StepCounterWidget'"));
    expect(source, contains("route: '/widgets/step-counter'"));
  });

  test('the route it names is a route the application serves', () async {
    // "Home widgets act like DVPage": a route that is in a list and in no
    // router is a link that opens the not-found page.
    await generate();

    final String router = read('router.g.dart');
    expect(router, contains("path: '/widgets/step-counter'"));
    expect(router, contains('StepCounterWidget()'));
  });

  test('the generated page centres the widget, as the specification says',
      () async {
    await generate();

    expect(read('router.g.dart'), contains('Center('));
  });

  test('an application with no home widgets still generates a list', () async {
    // Empty rather than absent: the file is imported by the runtime, and a
    // conditional import is a second thing to get wrong.
    await generate(widgets: const <String, String>{});

    expect(read('home_widgets.g.dart'), contains('dartvelHomeWidgets'));
    expect(read('home_widgets.g.dart'), isNot(contains("id: '")));
  });

  test('a widget input must be private, like every other generation input',
      () async {
    expect(
      generate(widgets: <String, String>{
        'widgets/bad.dart': _stepCounter.replaceAll('_stepCounterWidget', 'stepCounterWidget'),
      }),
      throwsA(isA<StateError>()),
    );
  });

  test('an annotation with arguments still declares a widget', () async {
    // The scanners matched the literal `@DVHomeWidget()`, empty parentheses
    // and all. The moment the specification's "same shell properties" were
    // given to one -- @DVHomeWidget(title: 'Steps') -- the widget stopped
    // existing: no entry in the list, no route in the router, no provider on
    // the device and no message anywhere, with the annotation still sitting
    // in the file saying otherwise.
    await generate(widgets: <String, String>{
      'widgets/step_counter.dart': _shellful,
    });

    expect(read('home_widgets.g.dart'), contains("id: 'step-counter'"));
    expect(read('router.g.dart'), contains("path: '/widgets/step-counter'"));
  });

  test('the declared shell properties reach the generated page', () async {
    // "Home widgets act like DVPage and support the same shell properties."
    // A page gets its properties through DVPageShell; a home widget's page
    // was a bare Center, so every property was declared and then dropped --
    // a page that renders under the status bar and shows no title, which
    // reads as a styling problem rather than as a property nothing reads.
    await generate(widgets: <String, String>{
      'widgets/step_counter.dart': _shellful,
    });

    final String route = widgetRoute(read('router.g.dart'));
    expect(route, contains('DVPageShell('));
    expect(route, contains("title: 'Steps today'"));
    expect(route, contains('showAppBar: true'));
    // Still centred: the specification asks for a page that centres the
    // widget's content, and a shell around it does not replace that.
    expect(route, contains('Center('));
  });

  test('a property that differs from the default is the one carried', () async {
    // The failure this catches is a generator that writes a constant
    // `const DVPageScaffoldSpec()` for every widget: every assertion about
    // the common case passes, and an application that asked for no platform
    // shell gets a Material one.
    await generate(widgets: <String, String>{
      'widgets/step_counter.dart': _stepCounter.replaceFirst(
        '@DVHomeWidget()',
        '@DVHomeWidget(shell: DVPageShellMode.none, selectable: false)',
      ),
    });

    final String route = widgetRoute(read('router.g.dart'));
    expect(route, contains('shell: DVPageShellMode.none'));
    expect(route, contains('selectable: false'));
  });

  test('a widget that declared no properties still gets the page shell',
      () async {
    // The default is a page's default, because that is what "acts like
    // DVPage" means. Without the shell there is no safe area and no
    // selection, which is a page that looks built rather than one that is.
    await generate();

    final String route = widgetRoute(read('router.g.dart'));
    expect(route, contains('DVPageShell('));
    expect(route, contains('DVPageScaffoldSpec('));
  });

  test('a widget that builds its own Scaffold is not given a second one',
      () async {
    // Two Scaffolds is two backgrounds and two app bars. It renders, which
    // is the problem: it reads as a styling mistake in the widget rather
    // than as a page that wrapped something already wrapped. Pages have this
    // rule, and "the same shell properties" has to include it.
    await generate(widgets: <String, String>{
      'widgets/step_counter.dart': _stepCounter.replaceFirst(
        "const DVText('1,204 steps')",
        "Scaffold(body: const DVText('1,204 steps'))",
      ),
    });

    expect(widgetRoute(read('router.g.dart')), contains('scaffold: false'));
  });

  test('the title is what the platform calls it, and the id is the fallback',
      () async {
    // The identifier is a route segment -- step-counter -- and it was what
    // the launcher and the widget gallery showed. A widget called
    // "step-counter" among somebody's applications looks like a defect in
    // whichever one it came from.
    await generate(widgets: <String, String>{
      'widgets/step_counter.dart': _shellful,
    });

    expect(read('home_widgets.g.dart'), contains("title: 'Steps today'"));

    await generate();
    expect(read('home_widgets.g.dart'), isNot(contains('title:')));
  });
}

/// The same widget, with the shell properties a page has.
const String _shellful = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget(title: 'Steps today', showAppBar: true)
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) => const DVText('1,204 steps');
''';

/// The generated route for the step counter, and nothing either side of it.
///
/// The router holds the application's pages too, and a `title:` belonging to
/// one of those would satisfy an assertion about the widget's own shell
/// without the widget having one.
String widgetRoute(String router) {
  const String marker = "path: '/widgets/step-counter'";
  final int at = router.indexOf(marker);
  expect(at, isNot(-1), reason: 'the widget route is not in the router');
  final int end = router.indexOf('GoRoute(', at + marker.length);
  return router.substring(at, end == -1 ? router.length : end);
}
