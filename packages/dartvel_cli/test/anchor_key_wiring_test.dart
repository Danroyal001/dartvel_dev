// The application key reaching the shared window store.
//
// The store encrypts world anchor tokens under the application key and
// refuses them when it has no key store, which is right on a platform with no
// key custody and wrong everywhere else: an application nobody wired would
// refuse every anchor on a desktop that has a keyring. The store has no
// application id to name a key store by. The generated runtime does, and the
// key has to live under the same name `dartvel key` manages.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _runtimeFor(Map<String, Object?> dartvel) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_anchor_keys_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
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

  return File(p.join(root.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart')).readAsStringSync();
}

void main() {
  test('the runtime gives the shared store the platform key store for this application', () async {
    final String runtime = await _runtimeFor(const <String, Object?>{});

    expect(runtime, contains("DVWindowSharedStore.defaultAppKeys = () => dvAppKeyStoreFor('store_app');"));
    final RegExpMatch? import = RegExp(
      r"import 'package:dartvel_flutter/dartvel_flutter\.dart' show ([^;]*);",
    ).firstMatch(runtime);
    expect(import, isNotNull);
    final List<String> shown = import!.group(1)!.split(',').map((String s) => s.trim()).toList();
    expect(shown, containsAll(<String>['DVWindowSharedStore', 'dvAppKeyStoreFor']));
    expect(shown.where((String s) => s == 'DVWindowSharedStore'), hasLength(1),
        reason: 'a name shown twice is a warning, and flutter analyze fails on it');
  });

  test('before a replaced store is made, so tuning the store does not drop the key', () async {
    final String runtime = await _runtimeFor(const <String, Object?>{
      'windowing': <String, Object?>{
        'sharedState': <String, Object?>{'debounceMs': 200},
      },
    });

    final int keys = runtime.indexOf('DVWindowSharedStore.defaultAppKeys =');
    final int replaced = runtime.indexOf('DVWindowManager.useSharedStore(');
    expect(keys, isNonNegative);
    expect(replaced, isNonNegative);
    expect(keys, lessThan(replaced));
    final RegExpMatch import = RegExp(
      r"import 'package:dartvel_flutter/dartvel_flutter\.dart' show ([^;]*);",
    ).firstMatch(runtime)!;
    expect(import.group(1)!.split(',').map((String s) => s.trim()).where((String s) => s == 'DVWindowSharedStore'),
        hasLength(1));
  });
}
