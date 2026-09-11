// `@DVHomeWidget` on a widget class.
//
// The specification puts the annotation on "any widget, whether
// Flutter-native, `DVClassWidget`, or `DVFunctionalWidget`", and only the
// function shape was ever generated. A class carrying the annotation was
// read as the class it extends, so the developer was told to rename
// `StatelessWidget`, and the widget they had written produced no entry in
// the generated list, no route, no Android provider and no WidgetKit
// extension.
//
// A class is generated differently from a function and the difference is not
// cosmetic. A function is lowered into a widget class the generator writes,
// which is why the input is private and the public name is Dartvel's. A
// class is already a widget: there is nothing to generate from it, so the
// generated route reaches the developer's own class where it lives, and the
// class has to be public for the route to name it -- the same rule, and the
// same reason, as a `@DVPage` class input.
import 'dart:io';

import 'package:dartvel_cli/src/build/home_widget_check.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

const String _classWidget = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget(title: 'Steps today')
class StepCounterWidget extends StatelessWidget {
  const StepCounterWidget({super.key});

  @override
  Widget build(BuildContext context) => const DVText('1,204 steps');
}
''';

Directory? lastRoot;

Future<void> generate(Map<String, String> widgets) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_hwc_');
  lastRoot = root;
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shopfront\n');
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
  // The route that shows a home widget inside the application is a page, and
  // `dartvel build web` audits every page for a level-1 heading. With no bar
  // the widget's title named nothing, so every application with a home widget
  // failed its own web build on the preview page.
  group('the preview page names itself', () {
    const String heading =
        "DVText('Steps today').modifier(const DVModifier().semanticHeading(1))";

    test('with a level-1 heading of its title, when it has no bar', () async {
      await generate(<String, String>{'widgets/step_counter.dart': _classWidget});

      expect(read('router.g.dart'), contains(heading));
    });

    test('and not a second one when the bar already carries the title',
        () async {
      await generate(<String, String>{
        'widgets/step_counter.dart': _classWidget.replaceFirst(
            "@DVHomeWidget(title: 'Steps today')",
            "@DVHomeWidget(title: 'Steps today', showAppBar: true)"),
      });

      final String router = read('router.g.dart');
      expect(router, contains('showAppBar: true'));
      expect(router, isNot(contains(heading)));
    });
  });

  test('a widget class is a home widget, with the identifier of its own name',
      () async {
    await generate(<String, String>{'widgets/step_counter.dart': _classWidget});

    final String source = read('home_widgets.g.dart');
    expect(source, contains("id: 'step-counter'"));
    expect(source, contains("name: 'StepCounterWidget'"));
    expect(source, contains("route: '${dvHomeWidgetRoute('step-counter')}'"));
    // The identifier that came out before was derived from the superclass.
    expect(source, isNot(contains('stateless')));
  });

  test('the route it names builds the class the developer wrote', () async {
    await generate(<String, String>{'widgets/step_counter.dart': _classWidget});

    final String router = read('router.g.dart');
    expect(router, contains("path: '${dvHomeWidgetRoute('step-counter')}'"));
    // Reached where it lives, since there is nothing to generate from a
    // class that is already a widget. A bare `StepCounterWidget()` in the
    // router would not resolve to anything: the router imports the
    // generated widgets, not the application's own files.
    expect(router, contains('StepCounterWidget()'));
    expect(router, contains("import 'package:shopfront/widgets/step_counter.dart'"));
  });

  test('the shell properties reach the page, as they do for a function',
      () async {
    // "Home widgets act like DVPage and support the same shell properties."
    // The class shape goes through the same parser; a second one would agree
    // on title and drift on the rest.
    await generate(<String, String>{'widgets/step_counter.dart': _classWidget});

    expect(read('router.g.dart'), contains("title: 'Steps today'"));
    expect(read('router.g.dart'), contains('DVPageShell('));
  });

  test('the build check sees the same widget the generator does', () async {
    // They are two walks over the same files. When they disagree the build
    // reports one set of widgets and packages another -- named in a
    // DV-WIDGET-001 refusal no provider was ever written for, or generated
    // into an artifact the notice said they had been left out of.
    await generate(<String, String>{'widgets/step_counter.dart': _classWidget});

    expect(DVHomeWidgetCheck.declaredIn(lastRoot!.path), <String>[
      'step-counter',
    ]);
  });

  test('a private widget class is refused, and the message says why',
      () async {
    // A private class cannot be named from the generated router at all, so
    // the honest answer is a refusal rather than a widget that vanishes. The
    // message has to name the class the developer wrote: the old one named
    // the class it extended, which sent people to rename StatelessWidget.
    Object? thrown;
    try {
      await generate(<String, String>{
        'widgets/step_counter.dart':
            _classWidget.replaceAll('StepCounterWidget', '_StepCounterWidget'),
      });
    } on Object catch (error) {
      thrown = error;
    }

    expect(thrown, isA<StateError>());
    expect('$thrown', contains('_StepCounterWidget'));
    expect('$thrown', isNot(contains('StatelessWidget')));
  });

  test('a public widget function is still refused', () async {
    // The two shapes have opposite rules and both are load-bearing. A
    // function is lowered into a class Dartvel writes, so a public input
    // would leave two names for one widget with the application free to use
    // the wrong one.
    Object? thrown;
    try {
      await generate(<String, String>{
        'widgets/step_counter.dart': '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget()
@DVFunctionalWidget()
Widget stepCounterWidget(BuildContext context) => const DVText('1,204');
''',
      });
    } on Object catch (error) {
      thrown = error;
    }

    expect(thrown, isA<StateError>());
  });
}
