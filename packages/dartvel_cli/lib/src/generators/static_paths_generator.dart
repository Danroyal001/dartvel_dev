import 'dart:io';

import 'package:path/path.dart' as p;

/// A discovered source of static paths for a parameterized model route.
class StaticPathsProvider {
  const StaticPathsProvider({
    required this.functionName,
    required this.importPath,
    String? resolveExpression,
    this.route,
  }) : resolveExpression = resolveExpression ?? functionName;

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
/// something enumerates the values to generate for it. Either
/// `generatePublicPages: true` (the model's published records) or
/// `publicPathsResolver:` (an explicit function) says what those values are,
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
  static List<StaticPathsProvider> discover({
    required String root,
    required String pkgName,
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
      final content = file.readAsStringSync();

      final relative = p.relative(file.path, from: root).replaceAll(r'\', '/');
      final importPath =
          relative.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');

      if (content.contains('@DVModel') &&
          (content.contains('generatePublicPages') ||
              content.contains('publicPathsResolver'))) {
        for (final match in _modelRegex.allMatches(content)) {
          final args = match.group(1) ?? '';
          final resolver = _resolverArgRegex.firstMatch(args)?.group(1);
          final generates =
              RegExp(r'\bgeneratePublicPages\s*:\s*true\b').hasMatch(args);
          // A resolver is enough on its own: naming one is the statement that
          // this model's parameterized route should be generated.
          if (!generates && resolver == null) {
            continue;
          }
          final sourceClassName = match.group(2)!;
          final className = sourceClassName.startsWith('_')
              ? sourceClassName.substring(1)
              : sourceClassName;
          if (!sourceClassName.startsWith('_')) {
            throw StateError(
              'Dartvel model generation inputs must be private. Rename '
              '$sourceClassName to _$sourceClassName and reference the '
              'generated $className type from '
              'dartvel_client/dartvel_client.dart.',
            );
          }
          final fields = _fieldRegex
              .allMatches(content)
              .map(
                (field) => _ModelField(
                  type: field.group(1)!,
                  name: field.group(2)!,
                ),
              )
              .toList(growable: false);
          final publicPathField = _publicPathField(className, fields);
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
              route: '/${_pluralRouteSegment(className)}/:$publicPathField',
            ),
          );
        }
      }
    }

    return providers;
  }

  /// Renders the manifest source for [providers].
  static String render({
    required List<StaticPathsProvider> providers,
    required String buildId,
  }) {
    final buffer = StringBuffer()
      ..writeln('// GENERATED BY DARTVEL - DO NOT EDIT')
      ..writeln('// build: $buildId')
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
      ..writeln('Future<Map<String, List<String>>> resolveDartvelStaticPaths()'
          ' async {')
      ..writeln('  final resolved = <String, List<String>>{};')
      ..writeln('  for (final entry in dartvelStaticPaths) {')
      ..writeln('    resolved[entry.name] = await entry.resolve();')
      ..writeln('  }')
      ..writeln('  return resolved;')
      ..writeln('}');

    return buffer.toString();
  }

  /// Discovers providers and writes the manifest.
  static Future<List<StaticPathsProvider>> generate({
    required String root,
    required String pkgName,
    required String buildId,
  }) async {
    final providers = discover(root: root, pkgName: pkgName);

    final outputDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

    final output = File(p.join(outputDir.path, 'static_paths.g.dart'));
    output.writeAsStringSync(
      render(providers: providers, buildId: buildId),
    );

    return providers;
  }

  static String _publicPathField(String className, List<_ModelField> fields) {
    final stringFields = fields
        .where((field) => field.type == 'String')
        .map((field) => field.name)
        .toList(growable: false);
    if (stringFields.contains('slug')) return 'slug';
    if (stringFields.contains('id')) return 'id';
    if (stringFields.isNotEmpty) return stringFields.first;
    throw StateError(
      '@DVModel(generatePublicPages: true) on _$className requires a String '
      'slug, id, or other String field so Dartvel can generate a '
      'parameterized public page route.',
    );
  }

  static String _pluralRouteSegment(String className) {
    final buffer = StringBuffer();
    for (var index = 0; index < className.length; index += 1) {
      final char = className[index];
      final lower = char.toLowerCase();
      if (index > 0 && char != lower) buffer.write('-');
      buffer.write(lower);
    }
    final singular = buffer.toString();
    if (singular.endsWith('s')) return singular;
    if (singular.endsWith('y')) {
      return '${singular.substring(0, singular.length - 1)}ies';
    }
    return '${singular}s';
  }
}

class _ModelField {
  const _ModelField({
    required this.type,
    required this.name,
  });

  final String type;
  final String name;
}
