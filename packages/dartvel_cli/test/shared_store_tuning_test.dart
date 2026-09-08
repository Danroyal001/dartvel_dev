// dartvel.windowing.sharedState, which the specification documents with four
// numbers and the build read none of.
//
// Two of them are constructor parameters on DVWindowSharedStore already, with
// defaults that happen to equal the documented values -- so a project that
// set spillThresholdKb: 64 got 32, and one that set debounceMs: 200 got 50.
// The setting was accepted, the build succeeded, and the number in the
// pubspec was decoration. That is the shape this repository keeps finding,
// and it is the reason the annotation check exists; this is the same failure
// one layer out, in configuration rather than annotations.
//
// The other two -- pollMs and sweepAfter -- have nothing behind them at all:
// there is no separate-process polling backend and no sweep of spilled
// files. They are named as absent rather than wired to a parameter that does
// not exist.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _runtimeFor(Map<String, Object?> dartvel) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_shared_store_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage()
Widget homePage(BuildContext context) => const SizedBox.shrink();
''');

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'store_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Store App',
    seoTitle: 'Store App',
    seoDesc: 'Store App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );

  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'),
  ).readAsStringSync();
}

Map<String, Object?> _windowing(Map<String, Object?> sharedState) =>
    <String, Object?>{
      'windowing': <String, Object?>{'sharedState': sharedState},
    };

void main() {
  test('a configured debounce and threshold reach the store', () async {
    final String runtime = await _runtimeFor(
      _windowing(<String, Object?>{'debounceMs': 200, 'spillThresholdKb': 64}),
    );

    expect(runtime, contains('DVWindowManager.useSharedStore'));
    expect(runtime, contains('debounce: Duration(milliseconds: 200)'));
    // Kilobytes in the pubspec, bytes in the constructor: the specification
    // writes Kb and the parameter is spillThresholdBytes, and a build that
    // passed 64 through would spill at 64 bytes.
    expect(runtime, contains('spillThresholdBytes: 65536'));
  });

  test('one of the two on its own still reaches it', () async {
    final String runtime =
        await _runtimeFor(_windowing(<String, Object?>{'debounceMs': 200}));

    expect(runtime, contains('debounce: Duration(milliseconds: 200)'));
    expect(runtime, isNot(contains('spillThresholdBytes:')));
  });

  test('a project that tunes nothing replaces nothing', () async {
    // The store is built lazily with its own defaults, and replacing it with
    // an identical one would be a line of generated code that exists to do
    // what not writing it does.
    final String runtime = await _runtimeFor(const <String, Object?>{});

    expect(runtime, isNot(contains('DVWindowManager.useSharedStore')));
  });

  test('a value that is not a number is ignored rather than emitted',
      () async {
    // It would reach generated source as Duration(milliseconds: fast), which
    // does not compile -- so a typo in a pubspec would break the build with
    // an error pointing at a generated file.
    final String runtime = await _runtimeFor(
      _windowing(<String, Object?>{'debounceMs': 'fast'}),
    );

    expect(runtime, isNot(contains('DVWindowManager.useSharedStore')));
  });
}
