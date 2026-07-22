import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('page and backend policy annotation arguments are accepted', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_policy_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);

      File(p.join(root.path, 'lib', 'pages', 'admin.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(policy: DVPolicies.viewAdmin)
Widget adminPage(BuildContext context) => const SizedBox.shrink();
''');
      Directory(p.join(root.path, 'lib', 'pages', 'blog'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'pages', 'blog', '[id].dart'))
          .writeAsStringSync('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage()
class BlogPage extends DartvelPage {
  const BlogPage({super.key});
}
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'refund.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: DVPolicies.refund)
Future<Map<String, bool>> handler() async => <String, bool>{'ok': true};
''');

      await ClientGenerator.generate(
        root: root.path,
        pagesDir: 'lib/pages',
        pkgName: 'policy_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        devBackendHost: 'http://localhost:3000',
        prodBackendHost: 'https://api.example.test',
        apiBasePath: '/api',
        envFiles: const <String>[],
        seoSiteName: 'Policy App',
        seoTitle: 'Policy App',
        seoDesc: 'Policy App',
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
        dv: YamlMap.wrap(<String, Object?>{}),
      );
      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'policy_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      expect(
        File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'))
            .existsSync(),
        isTrue,
      );
      final config = File(
        p.join(root.path, 'lib', 'dartvel_client', 'config.g.dart'),
      ).readAsStringSync();
      expect(config, contains('static const authProviders = <String>[];'));
      final ssg = File(p.join(root.path, '.dartvel', 'ssg_builder.dart'))
          .readAsStringSync();
      expect(ssg, contains('String key = "/blog/:id";'));
      expect(ssg, isNot(contains('var key')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('private annotated pages and widgets generate public wrappers',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_private_client_test_');
    try {
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'components'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'pages', 'index.dart'))
          .writeAsStringSync('''
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

part 'index.dartvel.g.dart';

@DVPage()
@DVFunctionalWidget()
Widget _indexPage(BuildContext context) => const SizedBox.shrink();
''');
      File(p.join(root.path, 'lib', 'components', 'cards.dart'))
          .writeAsStringSync('''
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

part 'cards.dartvel.g.dart';

@DVFunctionalWidget()
Widget _featureCard(String title) => DVText(title);
''');

      await ClientGenerator.generate(
        root: root.path,
        pagesDir: 'lib/pages',
        pkgName: 'private_client_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        devBackendHost: 'http://localhost:3000',
        prodBackendHost: 'https://api.example.test',
        apiBasePath: '/api',
        envFiles: const <String>[],
        seoSiteName: 'Private App',
        seoTitle: 'Private App',
        seoDesc: 'Private App',
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
        dv: YamlMap.wrap(<String, Object?>{}),
      );

      final router = File(
        p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
      ).readAsStringSync();
      final widgets = File(
        p.join(root.path, 'lib', 'dartvel_client', 'widgets.g.dart'),
      ).readAsStringSync();
      final pagePart = File(
        p.join(root.path, 'lib', 'pages', 'index.dartvel.g.dart'),
      ).readAsStringSync();
      final widgetPart = File(
        p.join(root.path, 'lib', 'components', 'cards.dartvel.g.dart'),
      ).readAsStringSync();

      expect(pagePart, contains('Widget IndexPage(BuildContext context)'));
      expect(pagePart, contains('return _indexPage(context);'));
      expect(widgetPart, contains('Widget FeatureCard(String title)'));
      expect(widgetPart, contains('return _featureCard(title);'));
      expect(router, contains('p0.IndexPage(context)'));
      expect(router, isNot(contains('p0._indexPage')));
      expect(widgets, contains('return w0.FeatureCard(title);'));
      expect(widgets, isNot(contains('w0._featureCard')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
