// The generated list of home widgets reaches something that reads it.
//
// `home_widgets.g.dart` has always carried `dartvelHomeWidgets`, the
// application's own @DVHomeWidget declarations, and the barrel has always
// exported it. Nothing read it. Not the runtime, and not the build either,
// which walks the source files again for itself.
//
// So the one list in the process that knows which widget ids exist was
// unreachable from the call that needs it. DVHomeWidgets.publish takes a
// bare string, and every way of misspelling it is silent on the device: the
// write lands under a key no widget asks for and the home screen goes on
// showing its placeholder.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

const String _widget = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget()
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) => const DVText('1,204');
''';

Future<String> _runtimeFor({required bool withWidget}) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_hwd_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shopfront\n');
  if (withWidget) {
    File(p.join(root.path, 'lib', 'widgets', 'step_counter.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_widget);
  }

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

  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'))
      .readAsStringSync();
}

void main() {
  test('configuring the runtime hands the declarations to DVHomeWidgets',
      () async {
    final String runtime = await _runtimeFor(withWidget: true);
    final int configure = runtime.indexOf('void configureDartvelRuntime(');
    expect(configure, greaterThan(-1));
    final String body =
        runtime.substring(configure, runtime.indexOf('\n}\n', configure));

    expect(body, contains('DVHomeWidgets.declare(dartvelHomeWidgets)'));
  });

  test('an application with no widgets still declares its empty list',
      () async {
    // Unconditionally, for the reason the file is written unconditionally: a
    // call the generator only sometimes emits is a second thing to get
    // wrong, and an empty list is what "this application has none" looks
    // like everywhere else.
    final String runtime = await _runtimeFor(withWidget: false);

    expect(runtime, contains('DVHomeWidgets.declare(dartvelHomeWidgets)'));
  });

  test('the list is imported from where it is generated', () async {
    // The runtime imports the generated siblings it needs by name. Without
    // this one the call names an identifier that does not resolve, and the
    // application fails to compile in a file the developer is told not to
    // edit.
    final String runtime = await _runtimeFor(withWidget: true);

    expect(runtime,
        contains("import 'home_widgets.g.dart' show dartvelHomeWidgets;"));
  });
}
