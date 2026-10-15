// dartvel.hosts in the generated client: a const table and the call that
// installs it, only when hosts are declared, and a configuration with
// problems refused before anything is written.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _routerFor(Map<String, Object?> dartvel) async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_hosts_client_',
  );
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
    pkgName: 'hosts_app',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Example',
    seoTitle: 'Example',
    seoDesc: 'Example',
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
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}

void main() {
  test('declared hosts become a const table installed at set-up', () async {
    final String router = await _routerFor(<String, Object?>{
      'seo': <String, Object?>{'siteUrl': 'https://example.com'},
      'hosts': <String, Object?>{
        'example.com': null,
        'docs.example.com': <String, Object?>{
          'mount': '/docs',
          'siteUrl': 'https://docs.example.com',
          'name': "Example's Docs",
        },
        '*.apps.example.com': <String, Object?>{
          'mount': '/apps/{label}',
          'siteUrl': 'https://{label}.apps.example.com',
        },
      },
    });
    expect(
      router,
      contains('const DVHosts dartvelHosts = DVHosts(<DVHostEntry>['),
    );
    expect(router, contains("pattern: 'example.com'"));
    expect(router, contains("siteUrl: 'https://example.com'"));
    expect(router, contains("mount: '/docs'"));
    expect(router, contains(r"name: 'Example\'s Docs'"));
    expect(router, contains("pattern: '*.apps.example.com'"));
    expect(router, contains("mount: '/apps/{label}'"));
    expect(router, contains('dvUseHosts(dartvelHosts);'));
  });

  test('without hosts nothing is generated for them', () async {
    final String router = await _routerFor(const <String, Object?>{});
    expect(router, isNot(contains('dartvelHosts')));
    expect(router, isNot(contains('dvUseHosts')));
  });

  test('a configuration with problems fails generation, saying why', () async {
    await expectLater(
      _routerFor(<String, Object?>{
        'hosts': <String, Object?>{
          'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
          'example.org': <String, Object?>{'siteUrl': 'https://example.org'},
        },
      }),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('primary'),
        ),
      ),
    );
  });
}
