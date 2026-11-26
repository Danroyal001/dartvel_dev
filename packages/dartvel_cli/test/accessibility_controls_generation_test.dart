// `dartvel.accessibility.controls` reaches the app: the generated root is
// wrapped in the accessibility frame and the controls are installed before
// the first frame, the default root gets a high-contrast theme, and the
// SSR-first head reads the visitor's settings before the first paint. A
// project that does not ask gets none of it.
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_core/dartvel.dart' show dvAccessibilityStorageKey;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _applicationFor(Directory root, Map<String, Object?> dartvel) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'a11y_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'A11y App',
    seoTitle: 'A11y App',
    seoDesc: 'A11y App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'application.g.dart')).readAsStringSync();
}

Directory _project({String? appRoot}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_a11y_controls_');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
  if (appRoot != null) File(p.join(root.path, 'lib', 'app.dart')).writeAsStringSync(appRoot);
  return root;
}

String _createApp(String out) {
  final int start = out.indexOf('Widget createDartvelApp(');
  return out.substring(start, out.indexOf('\n}\n', start));
}

void main() {
  test('off by default: the app is generated as it was', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final String app = _createApp(await _applicationFor(root, <String, Object?>{}));
    expect(app, isNot(contains('DVAccessibilityFrame')));
    expect(app, isNot(contains('DVAccessibilityControls')));
  });

  test('on: installed before the first frame, the root in the frame, a high-contrast theme', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final String app = _createApp(await _applicationFor(root, <String, Object?>{
      'accessibility': <String, Object?>{'controls': true},
    }));
    expect(app, contains("DVAccessibilityControls.instance.install(floatingButton: true, app: 'a11y_app')"));
    expect(app, contains('DVAccessibilityFrame(child: MaterialApp.router('));
    expect(app, contains('highContrastTheme: dvHighContrastTheme(dartvelDefaultTheme(.light))'));
    expect(app, contains('highContrastDarkTheme: dvHighContrastTheme(dartvelDefaultTheme(.dark))'));
    expect(app.indexOf('install('), lessThan(app.indexOf('DVAccessibilityFrame(')));
  });

  test('an app that places the button itself has no floating one, and its own root is framed', () async {
    final Directory root = _project(appRoot: '''
import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

@DVAppRoot()
Widget _root(BuildContext context, DVAppParts parts) => MaterialApp.router(routerConfig: parts.router);
''');
    addTearDown(() => root.deleteSync(recursive: true));
    final String app = _createApp(await _applicationFor(root, <String, Object?>{
      'accessibility': <String, Object?>{
        'controls': <String, Object?>{'floatingButton': false},
      },
    }));
    expect(app, contains('install(floatingButton: false'));
    expect(app, contains('DVAccessibilityFrame(child: Builder('));
  });

  test('a misspelt setting stops the build, naming it', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    await expectLater(
      _applicationFor(root, <String, Object?>{
        'accessibility': <String, Object?>{
          'controls': <String, Object?>{'floatingButon': false},
        },
      }),
      throwsA(predicate((Object error) => '$error'.contains('floatingButon'))),
    );
  });

  group('the SSR-first head', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dv_a11y_head_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('reads the stored settings only when the app opted in', () {
      final DVSplash off = DVSplash.fromConfig(const <String, Object?>{}, root: root.path);
      expect(off.accessibilityControls, isFalse);
      final DVSplash on = DVSplash.fromConfig(const <String, Object?>{
        'accessibility': <String, Object?>{'controls': true},
      }, root: root.path);
      expect(on.accessibilityControls, isTrue);
      const String shell = '<!DOCTYPE html><html><head><title>a</title></head><body></body></html>';
      expect(dvWebSplashApply(shell, off), isNot(contains(dvAccessibilityStorageKey)));
      expect(dvWebSplashApply(shell, on), contains(dvAccessibilityStorageKey));
    });
  });
}
