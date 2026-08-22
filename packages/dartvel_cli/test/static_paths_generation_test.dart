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
    test('finds a model with an explicit paths resolver', () async {
      final root = await _project({
        'models/product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: productPaths)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  const _Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a', 'b'];
""",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );
        expect(found, hasLength(1));
        // The resolver is called directly, not through the generated model.
        expect(found.single.resolveExpression, 'productPaths');
        // And it is imported from the file that declares it.
        expect(found.single.importPath, 'package:shop/models/product.dart');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('derives the route from the model, never from a string', () async {
      // The whole reason this moved onto @DVModel: a route repeated in an
      // annotation drifts silently the moment the page file moves.
      final root = await _project({
        'models/product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: productPaths)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  const _Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a'];
""",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );
        expect(found.single.route, '/products/:slug');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a resolver alone is enough, without generatePublicPages', () async {
      // Naming a resolver is itself the statement that this route should be
      // generated; requiring a second flag would be ceremony.
      final root = await _project({
        'models/product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: productPaths)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  const _Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a'];
""",
      });
      try {
        expect(
          StaticPathsGenerator.discover(root: root.path, pkgName: 'shop'),
          hasLength(1),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a resolver overrides the default record enumeration', () async {
      // Both declared: the explicit resolver wins, because it was written down
      // on purpose and the enumeration is the default it replaces.
      final root = await _project({
        'models/product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true, publicPathsResolver: productPaths)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  const _Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a'];
""",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );
        expect(found, hasLength(1));
        expect(found.single.resolveExpression, 'productPaths');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('finds resolvers across files, deterministically', () async {
      final root = await _project({
        'models/b_product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: productPaths)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  const _Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a'];
""",
        'models/a_article.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: articlePaths)
@pragma('vm:entry-point')
class _Article {
  final String slug;
  const _Article({required this.slug});
}

Future<List<String>> articlePaths() async => <String>['x'];
""",
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );
        // Sorted by file path, so a regenerate never reorders the manifest.
        expect(found.map((e) => e.resolveExpression),
            <String>['articlePaths', 'productPaths']);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rejects public annotated models', () async {
      final root = await _project({
        'models/product.dart': """
import 'package:dartvel_core/dartvel.dart';

@DVModel(publicPathsResolver: productPaths)
class Product {
  final String slug;
  const Product({required this.slug});
}

Future<List<String>> productPaths() async => <String>['a'];
""",
      });
      try {
        expect(
          () => StaticPathsGenerator.discover(root: root.path, pkgName: 'shop'),
          throwsA(isA<StateError>()),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('ignores generated output', () async {
      // A regenerate must not rediscover its own emitted references.
      final root = await _project({
        'dartvel_client/models.g.dart': """
@DVModel(publicPathsResolver: productPaths)
class _Product {
  final String slug;
  const _Product({required this.slug});
}
""",
      });
      try {
        expect(
          StaticPathsGenerator.discover(root: root.path, pkgName: 'shop'),
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

    test('adds public model providers for generated model pages', () async {
      final root = await _project({
        'models/product.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true)
class _Product {
  final String slug;
  final String title;
  const _Product({required this.slug, required this.title});
}
''',
      });
      try {
        final found = StaticPathsGenerator.discover(
          root: root.path,
          pkgName: 'shop',
        );

        expect(found, hasLength(1));
        expect(found.single.functionName, 'ProductPublicStaticPaths');
        expect(found.single.resolveExpression, 'Product.publicStaticPaths');
        expect(
          found.single.importPath,
          'package:shop/dartvel_client/dartvel_client.dart',
        );
        expect(found.single.route, '/products/:slug');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rejects public annotated models for generated public pages',
        () async {
      final root = await _project({
        'models/product.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true)
class Product {
  final String slug;
  const Product({required this.slug});
}
''',
      });
      try {
        expect(
          () => StaticPathsGenerator.discover(
            root: root.path,
            pkgName: 'shop',
          ),
          throwsStateError,
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

      expect(
        source,
        contains("import 'package:shop/paths/product_paths.dart';"),
      );
      expect(source, contains("name: 'productPaths',"));
      expect(source, contains("route: '/products/:slug',"));
      expect(source, contains('resolve: productPaths,'));
      expect(source, contains('resolveDartvelStaticPaths'));
    });

    test('emits generated model resolve expressions', () {
      final source = StaticPathsGenerator.render(
        providers: const [
          StaticPathsProvider(
            functionName: 'ProductPublicStaticPaths',
            importPath: 'package:shop/dartvel_client/dartvel_client.dart',
            resolveExpression: 'Product.publicStaticPaths',
            route: '/products/:slug',
          ),
        ],
        buildId: 'test-build',
      );

      expect(
        source,
        contains("import 'package:shop/dartvel_client/dartvel_client.dart';"),
      );
      expect(source, contains("name: 'ProductPublicStaticPaths',"));
      expect(source, contains("route: '/products/:slug',"));
      expect(source, contains('resolve: Product.publicStaticPaths,'));
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
      expect(
        source,
        contains('dartvelStaticPaths = <DVStaticPathsEntry>[\n];'),
      );
      expect(source, isNot(contains('import ')));
    });

    test('does not duplicate an import shared by two providers', () {
      final source = StaticPathsGenerator.render(
        providers: const [
          StaticPathsProvider(
            functionName: 'a',
            importPath: 'package:s/p.dart',
          ),
          StaticPathsProvider(
            functionName: 'b',
            importPath: 'package:s/p.dart',
          ),
        ],
        buildId: 'b',
      );
      expect('import \'package:s/p.dart\';'.allMatches(source).length, 1);
    });
  });

  group('generate', () {
    test('writes the manifest into the generated client directory', () async {
      final root = await _project({
        'models/product.dart':
            '@DVModel(publicPathsResolver: productPaths)\n'
            "@pragma('vm:entry-point')\n"
            'class _Product {\n'
            '  final String slug;\n'
            '  const _Product({required this.slug});\n'
            '}\n'
            'Future<List<String>> productPaths() async => [];\n',
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
    test('declared pageDataMode drives generated page rendering', () async {
      final root = await Directory.systemTemp.createTemp('dartvel_page_opts_');
      try {
        Directory(
          p.join(root.path, 'lib', 'models'),
        ).createSync(recursive: true);
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        File(
          p.join(root.path, 'lib', 'models', 'product.dart'),
        ).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  pageDataMode: DVModelPageDataMode.staleWhileRevalidate,
  generatePublicPages: true,
)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  final bool published;
  const _Product({required this.slug, required this.published});
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
          contains(
            'pageDataMode = '
            'DVModelPageDataMode.staleWhileRevalidate;',
          ),
        );
        expect(content, contains('generatePublicPages = true;'));
        expect(content, contains('// ignore: constant_identifier_names'));
        expect(
          content,
          contains(
            'static const ProductPageComponent Page = '
            'ProductPageComponent._();',
          ),
        );
        expect(content, contains('class ProductPageComponent'));
        expect(content, contains('Widget fromId('));
        expect(content, contains('Product? cachedModel,'));
        expect(
          content,
          contains('dataMode == DVModelPageDataMode.staleWhileRevalidate'),
        );
        expect(
          content,
          contains(
            'static void usePublicStaticPathsResolver(',
          ),
        );
        expect(
            content,
            contains('static Future<core.List<String>> '
                'publicStaticPaths() async {'));
        expect(
          content,
          contains("DV.Database.query('select * from products')"),
        );
        expect(content, contains('.where((model) => model.published)'));
        expect(content, contains('.map((model) => model.slug)'));
        expect(
          content,
          contains("static const String publicPageRoute = '/products/:slug';"),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('defaults to auto and no public pages when unspecified', () async {
      final root = await Directory.systemTemp.createTemp('dartvel_page_def_');
      try {
        Directory(
          p.join(root.path, 'lib', 'models'),
        ).createSync(recursive: true);
        Directory(
          p.join(root.path, 'lib', 'dartvel_client'),
        ).createSync(recursive: true);
        File(p.join(root.path, 'lib', 'models', 'note.dart')).writeAsStringSync(
          '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String body;
  const _Note({required this.body});
}
''',
        );

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
