// Every link gets a preview, and a guarded route's preview is safe: the
// generated router marks it guarded with its public title, and registers no
// builder that would render the page itself on a hover.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('a guarded page previews its title only; an open page previews itself',
      () async {
    final Directory root = await Directory.systemTemp.createTemp('dartvel_guarded_preview_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'pages', 'admin.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Admin console', policy: DVPolicies.viewAdmin)
Widget _adminPage(BuildContext context) => const SizedBox.shrink();
''');
    File(p.join(root.path, 'lib', 'pages', 'about.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'About')
Widget _aboutPage(BuildContext context) => const SizedBox.shrink();
''');
    await ClientGenerator.generate(
      root: root.path, pagesDir: 'lib/pages', pkgName: 'preview_app', buildId: 'b',
      backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
      prodBackendHost: 'https://api.example.test', apiBasePath: '/api', envFiles: const <String>[],
      seoSiteName: 'Preview App', seoTitle: 'Preview App', seoDesc: 'Preview App', seoImage: '',
      seoTwitter: '', defaultTransition: 'fade', durationMs: 200, curve: 'easeInOut',
      normalizeTrailing: true, notFoundRedirect: '', plugins: const <String>[], ota: false,
      dv: YamlMap.wrap(<String, Object?>{}),
    );
    final String router =
        File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart')).readAsStringSync();

    expect(router, contains("DVRoutePreviews.registerGuarded(\n    '/admin',\n    title: 'Admin console',\n  );"));
    final RegExp adminBuilder = RegExp(r"DVRoutePreviews\.register\(\s*'/admin',");
    expect(adminBuilder.hasMatch(router), isFalse,
        reason: 'a guarded page must not register a builder that renders it');
    expect(RegExp(r"DVRoutePreviews\.register\(\s*'/about',").hasMatch(router), isTrue);
  });
}
