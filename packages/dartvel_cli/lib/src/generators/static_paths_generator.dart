import 'dart:io';

import 'annotation_args.dart';
import 'primary_constructors.dart';
import 'public_pages.dart';
import 'package:path/path.dart' as p;

/// A discovered source of static paths for a parameterized model route.
class StaticPathsProvider {
  const StaticPathsProvider({
    required this.functionName,
    required this.importPath,
    String? resolveExpression,
    this.route,
    this.generatesPage = false,
    this.className,
    this.param,
  }) : resolveExpression = resolveExpression ?? functionName;

  /// Whether the model asked Dartvel to generate the page itself.
  ///
  /// A data model has its pages made for it unless it opts out, so the router
  /// has to serve them. `publicPathsResolver:` means "here are the paths for
  /// the page I wrote", and generating a second route would shadow it.
  final bool generatesPage;

  /// The generated model class, where one owns this route.
  final String? className;

  /// The path parameter the route carries.
  final String? param;

  /// The annotated function's name.
  final String functionName;

  /// A `package:`-qualified import for the file declaring it.
  final String importPath;

  /// The callable expression used in generated output.
  final String resolveExpression;

  /// The route these paths belong to, when declared explicitly.
  final String? route;
}

/// Discovers static-path sources on `@DVModel` and emits a manifest the static
/// generator can enumerate.
///
/// Static routes are always generated; a parameterized route cannot be unless
/// something enumerates the values to generate for it. A data model's
/// published records do, for every model that did not opt out of pages, and
/// `publicPathsResolver:` (an explicit function) says what they are instead,
/// and this turns them into a typed list rather than leaving static generation
/// to guess.
class StaticPathsGenerator {
  /// Captures an explicit `publicPathsResolver:` argument on `@DVModel(...)`.
  static final _resolverArgRegex = RegExp(
    r'publicPathsResolver\s*:\s*([A-Za-z0-9_.]+)',
  );

  static final _modelRegex = RegExp(
    r'@DVModel\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
    dotAll: true,
  );

  static final _fieldRegex = RegExp(
    r'final\s+(.+?)\s+([A-Za-z0-9_]+)\s*;',
    dotAll: true,
  );

  /// Scans [root]'s `lib/` for providers.
  ///
  /// Every data model under `lib/models/` has a page unless it opts out or
  /// [DVPublicPages] skips it; [takenRoutes] are the routes the application's
  /// own pages serve, which a default page yields to.
  static List<StaticPathsProvider> discover({
    required String root,
    required String pkgName,
    Set<String> takenRoutes = const <String>{},
  }) {
    final libDir = Directory(p.join(root, 'lib'));
    if (!libDir.existsSync()) return const <StaticPathsProvider>[];

    final providers = <StaticPathsProvider>[];

    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        // Generated output must never be scanned back in, or a regenerate
        // would rediscover its own emitted references.
        .where((file) => !file.path.contains('dartvel_client'))
        .where((file) => !file.path.endsWith('.g.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final content = dvDesugarPrimaryConstructors(file.readAsStringSync());

      final relative = p.relative(file.path, from: root).replaceAll(r'\', '/');
      final importPath =
          relative.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');

      if (!content.contains('@DVModel')) continue;
      // Only a model the model generator reads gets a page by default: it is
      // the generated class that serves one. A model elsewhere in lib/ still
      // gets what it asks for by name.
      final bool isModelsFile = relative.startsWith('lib/models/');
      // Blanked annotation arguments: `[^)]*` stops at the first close
      // parenthesis and a string argument can contain one. The model
      // generator masks the same way, and the two disagreeing is a model
      // whose static paths are silently not generated.
      final masked = dvMaskAnnotationArgs(content, 'DVModel');
      final Set<String> sensitive = dvSensitiveFieldNames(content);
      for (final match in _modelRegex.allMatches(masked)) {
        // Out of the original, not the masked copy: the copy is only
        // there so the pattern can step over the annotation, and its
        // arguments are spaces. Offsets are the same in both.
        final args =
            dvAnnotationArgs(content.substring(match.start), 'DVModel') ?? '';
        final resolver = _resolverArgRegex.firstMatch(args)?.group(1);
        final sourceClassName = match.group(2)!;
        final className = sourceClassName.startsWith('_')
            ? sourceClassName.substring(1)
            : sourceClassName;
        final fields = _fieldRegex
            .allMatches(content)
            .map(
              (field) => (
                type: field.group(1)!,
                name: field.group(2)!,
              ),
            )
            .toList(growable: false);
        final DVPublicPages pages = DVPublicPages.of(
          className: className,
          modelArgs: args,
          fields: fields,
          sensitive: sensitive,
          takenRoutes: takenRoutes,
        );
        final bool generates =
            pages.generates && (isModelsFile || pages.explicit);
        // A resolver is enough on its own: naming one is the statement that
        // this model's parameterized route should be generated.
        if (!generates && resolver == null) continue;
        if (!sourceClassName.startsWith('_')) {
          throw StateError(
            'Dartvel model generation inputs must be private. Rename '
            '$sourceClassName to _$sourceClassName and reference the '
            'generated $className type from '
            'dartvel_client/dartvel_client.dart.',
          );
        }
        final String keyField = pages.keyField ??
            dvModelKeyField(fields) ??
            (throw StateError(
              '@DVModel(publicPathsResolver:) on _$className requires a '
              'String slug, id, or other String field so Dartvel can '
              'generate a parameterized public page route.',
            ));
        // The route is the model's own either way, so it is never written
        // out as a string. A route repeated in an annotation drifts the
        // moment the page file moves, which is what file-based routing
        // exists to prevent.
        providers.add(
          StaticPathsProvider(
            functionName: '${className}PublicStaticPaths',
            // A resolver lives in the model's own file; the default
            // enumeration lives on the generated model.
            importPath: resolver != null
                ? importPath
                : 'package:$pkgName/dartvel_client/dartvel_client.dart',
            resolveExpression: resolver ?? '$className.publicStaticPaths',
            route: '/${dvPluralRouteSegment(className)}/:$keyField',
            generatesPage: resolver == null,
            className: className,
            param: keyField,
          ),
        );
      }
    }

    return providers;
  }

  /// Renders the manifest source for [providers].
  static String render({
    required List<StaticPathsProvider> providers,
    /// Accepted and not written anywhere. A build id in generated files
    /// rewrote every file on every build.
    String? buildId,
  }) {
    final buffer = StringBuffer()
      ..writeln('// GENERATED BY DARTVEL - DO NOT EDIT')
      ..writeln('//')
      ..writeln('// Static paths for parameterized routes, discovered from')
      ..writeln('// @DVModel(generatePublicPages:) and')
      ..writeln('// @DVModel(publicPathsResolver:).')
      ..writeln();

    final imports = providers.map((p) => p.importPath).toSet().toList()..sort();
    for (final import in imports) {
      buffer.writeln("import '$import';");
    }
    if (imports.isNotEmpty) buffer.writeln();

    buffer
      ..writeln('/// A route whose parameter values are enumerated at build')
      ..writeln('/// time.')
      ..writeln('class DVStaticPathsEntry {')
      ..writeln('  const DVStaticPathsEntry({')
      ..writeln('    required this.name,')
      ..writeln('    required this.route,')
      ..writeln('    required this.resolve,')
      ..writeln('  });')
      ..writeln()
      ..writeln('  /// The provider function name.')
      ..writeln('  final String name;')
      ..writeln()
      ..writeln('  /// The route these paths belong to, if declared.')
      ..writeln('  final String? route;')
      ..writeln()
      ..writeln('  /// Produces the parameter values to generate.')
      ..writeln('  final Future<List<String>> Function() resolve;')
      ..writeln('}')
      ..writeln()
      ..writeln('/// Every discovered static-path provider.')
      ..writeln('const List<DVStaticPathsEntry> dartvelStaticPaths ='
          ' <DVStaticPathsEntry>[');

    for (final provider in providers) {
      final route = provider.route == null ? 'null' : "'${provider.route}'";
      buffer
        ..writeln('  DVStaticPathsEntry(')
        ..writeln("    name: '${provider.functionName}',")
        ..writeln('    route: $route,')
        ..writeln('    resolve: ${provider.resolveExpression},')
        ..writeln('  ),');
    }

    buffer
      ..writeln('];')
      ..writeln()
      ..writeln('/// Resolves every provider into the concrete paths to')
      ..writeln('/// generate, keyed by provider name.')
      ..writeln('///')
      ..writeln('/// A provider that throws is reported and skipped rather')
      ..writeln('/// than ending the resolution. They are independent: a')
      ..writeln('/// model whose pages need a database that is not reachable')
      ..writeln('/// at build time should not stop a resolver that reads a')
      ..writeln('/// file from producing its pages, and one exception')
      ..writeln('/// otherwise silently costs the site every generated page.')
      ..writeln('Future<Map<String, List<String>>> resolveDartvelStaticPaths({')
      ..writeln('  void Function(String provider, Object error)? onError,')
      ..writeln('}) async {')
      ..writeln('  final resolved = <String, List<String>>{};')
      ..writeln('  for (final entry in dartvelStaticPaths) {')
      ..writeln('    try {')
      ..writeln('      resolved[entry.name] = await entry.resolve();')
      ..writeln('    } on Object catch (error) {')
      ..writeln('      resolved[entry.name] = const <String>[];')
      ..writeln('      if (onError != null) onError(entry.name, error);')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln('  return resolved;')
      ..writeln('}');

    return buffer.toString();
  }

  /// Discovers providers and writes the manifest.
  static Future<List<StaticPathsProvider>> generate({
    required String root,
    required String pkgName,
    /// Accepted and not written anywhere. A build id in generated files
    /// rewrote every file on every build.
    String? buildId,
    Set<String> takenRoutes = const <String>{},
  }) async {
    final providers =
        discover(root: root, pkgName: pkgName, takenRoutes: takenRoutes);

    final outputDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

    final output = File(p.join(outputDir.path, 'static_paths.g.dart'));
    output.writeAsStringSync(
      render(providers: providers),
    );

    return providers;
  }
}
