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
}
