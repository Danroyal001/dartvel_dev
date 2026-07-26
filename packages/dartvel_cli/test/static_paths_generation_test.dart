import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_cli/src/generators/static_paths_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a throwaway project containing [files] under `lib/`.
Future<Directory> _project(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('dartvel_static_paths_');
  files.forEach((relative, contents) {
    final file = File(p.join(root.path, 'lib', relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

void main() {
  group('discover', () {
    test('finds an annotated provider', () async {
      final root = await _project({
        'paths/product_paths.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVStaticPaths()
Future<List<String>> productPaths() async => <String>['a', 'b'];
''',
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );
        expect(found, hasLength(1));
        expect(found.single.functionName, 'productPaths');
        expect(found.single.importPath, 'package:shop/paths/product_paths.dart');
        expect(found.single.route, isNull);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('captures an explicit route argument', () async {
      final root = await _project({
        'paths/blog.dart': '''
@DVStaticPaths(route: '/blog/:slug')
Future<List<String>> blogPaths() async => <String>['hello'];
''',
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'site',
        );
        expect(found.single.route, '/blog/:slug');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('finds several providers across files, deterministically', () async {
      // Generated output must be stable, or every regenerate churns the diff.
      final root = await _project({
        'paths/b_paths.dart':
            "@DVStaticPaths()\nFuture<List<String>> bPaths() async => [];\n",
        'paths/a_paths.dart':
            "@DVStaticPaths()\nFuture<List<String>> aPaths() async => [];\n",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'site',
        );
        expect(found.map((e) => e.functionName), <String>['aPaths', 'bPaths']);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('accepts a non-Future return type', () async {
      final root = await _project({
        'paths/sync_paths.dart':
            "@DVStaticPaths()\nList<String> syncPaths() => <String>['x'];\n",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'site',
        );
        expect(found.single.functionName, 'syncPaths');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('ignores generated output', () async {
      // Rediscovering its own emitted references would compound on every run.
      final root = await _project({
        'dartvel_client/static_paths.g.dart':
            "@DVStaticPaths()\nFuture<List<String>> ghost() async => [];\n",
        'models.g.dart':
            "@DVStaticPaths()\nFuture<List<String>> alsoGhost() async => [];\n",
      });
      try {
        expect(
          StaticPathsGenerator.discover(root: root.path, pkgName: 'site'),
          isEmpty,
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('returns nothing when the project has no lib directory', () async {
      final root = await Directory.systemTemp.createTemp('dartvel_empty_');
      try {
        expect(
          StaticPathsGenerator.discover(root: root.path, pkgName: 'site'),
          isEmpty,
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  group('render', () {
    test('emits an entry and import per provider', () {
      final source = StaticPathsGenerator.render(
        providers: const [
          StaticPathsProvider(
            functionName: 'productPaths',
            importPath: 'package:shop/paths/product_paths.dart',
            route: '/products/:slug',
          ),
        ],
        buildId: 'test-build',
      );

      expect(source, contains("import 'package:shop/paths/product_paths.dart';"));
      expect(source, contains("name: 'productPaths',"));
      expect(source, contains("route: '/products/:slug',"));
      expect(source, contains('resolve: productPaths,'));
      expect(source, contains('resolveDartvelStaticPaths'));
    });

    test('emits a null route when none was declared', () {
      final source = StaticPathsGenerator.render(
        providers: const [
          StaticPathsProvider(
            functionName: 'productPaths',
            importPath: 'package:shop/p.dart',
          ),
        ],
        buildId: 'b',
      );
      expect(source, contains('route: null,'));
    });

    test('emits a valid empty manifest when nothing is annotated', () {
      final source = StaticPathsGenerator.render(
        providers: const [],
        buildId: 'b',
      );
      expect(source, contains('dartvelStaticPaths = <DVStaticPathsEntry>[\n];'));
      expect(source, isNot(contains('import ')));
    });

    test('does not duplicate an import shared by two providers', () {
      final source = StaticPathsGenerator.render(
        providers: const [
          StaticPathsProvider(functionName: 'a', importPath: 'package:s/p.dart'),
          StaticPathsProvider(functionName: 'b', importPath: 'package:s/p.dart'),
        ],
        buildId: 'b',
      );
      expect("import 'package:s/p.dart';".allMatches(source).length, 1);
    });
  });

  group('generate', () {
    test('writes the manifest into the generated client directory', () async {
      final root = await _project({
        'paths/product_paths.dart':
            "@DVStaticPaths()\nFuture<List<String>> productPaths() async => [];\n",
      });
      try {
        final providers = await StaticPathsGenerator.generate(
          root: root.path,
          pkgName: 'shop',
          buildId: 'test-build',
        );
        expect(providers, hasLength(1));

        final output = File(
          p.join(root.path, 'lib', 'dartvel_client', 'static_paths.g.dart'),
        );
        expect(output.existsSync(), isTrue);
        expect(output.readAsStringSync(), contains('productPaths'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  group('page options metadata', () {
    test('declared pageDataMode and generatePublicPages reach the model',
        () async {
      // These annotation parameters compile but no renderer consumes them yet.
      // Emitting them keeps the declared intent observable instead of
      // silently discarding it.
      final root = await Directory.systemTemp.createTemp('dartvel_page_opts_');
      try {
        Directory(p.join(root.path, 'lib', 'models'))
            .createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'dartvel_client'))
            .createSync(recursive: true);
        File(p.join(root.path, 'lib', 'models', 'product.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  pageDataMode: DVModelPageDataMode.staleWhileRevalidate,
  generatePublicPages: true,
)
class _Product {
  final String slug;
  const _Product({required this.slug});
}
''');

        await ModelGenerator.generate(
          root: root.path,
          pkgName: 'shop',
          buildId: 'test-build',
        );

        final content = File(
          p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
        ).readAsStringSync();

        expect(
          content,
          contains('pageDataMode = '
              'DVModelPageDataMode.staleWhileRevalidate;'),
        );
        expect(content, contains('generatePublicPages = true;'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('defaults to auto and no public pages when unspecified', () async {
      final root = await Directory.systemTemp.createTemp('dartvel_page_def_');
      try {
        Directory(p.join(root.path, 'lib', 'models'))
            .createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'dartvel_client'))
            .createSync(recursive: true);
        File(p.join(root.path, 'lib', 'models', 'note.dart'))
            .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String body;
  const _Note({required this.body});
}
''');

        await ModelGenerator.generate(
          root: root.path,
          pkgName: 'notes',
          buildId: 'test-build',
        );

        final content = File(
          p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
        ).readAsStringSync();

        expect(content, contains('pageDataMode = DVModelPageDataMode.auto;'));
        expect(content, contains('generatePublicPages = false;'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}
