// dartvel.memory reaches the running application.
//
// DV.Memory.allocate applies configured defaults and ceilings -- but only the
// ones it was given. A pubspec whose 128MB television ceiling is parsed by
// doctor and never handed to the runtime is a number that looks enforced and
// is not.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page =
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n";

Future<String> generatedFor(YamlMap dv) async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_memory_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(
    p.join(root.path, 'lib', 'dartvel_client'),
  ).createSync(recursive: true);
  File(
    p.join(root.path, 'lib', 'pages', 'index.page.dart'),
  ).writeAsStringSync(_page);
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'mem_app',
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
    dv: dv,
  );
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  test(
    'a declared memory section is installed at startup, as declared',
    () async {
      final String out = await generatedFor(
        YamlMap.wrap(<String, Object?>{
          'memory': <String, Object?>{
            'budget': '4GB',
            'targets': <String, Object?>{
              'tizen': <String, Object?>{'budget': '128MB', 'segment': '32MB'},
            },
          },
        }),
      );
      expect(out, contains('DVMemory.configure('));
      expect(out, contains('DVMemoryConfig.parse('));
      expect(out, contains("'budget': '128MB'"));
      expect(out, contains("'segment': '32MB'"));
    },
  );

  test('a device-profile memory override is installed too', () async {
    final String out = await generatedFor(
      YamlMap.wrap(<String, Object?>{
        'deviceProfiles': <String, Object?>{
          'lobby': <String, Object?>{
            'platform': 'sony-elinux',
            'memory': <String, Object?>{'budget': '64MB'},
          },
        },
      }),
    );
    expect(out, contains('DVMemory.configure('));
    expect(out, contains("'lobby'"));
    expect(out, contains("'64MB'"));
  });

  test('a project that declares no memory configures nothing', () async {
    final String out = await generatedFor(YamlMap());
    expect(out, isNot(contains('DVMemory.configure(')));
  });
}
