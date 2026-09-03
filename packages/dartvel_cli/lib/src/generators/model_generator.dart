import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Sort key for a field with no `@DVModel.pageOrder(n)`, so every ordered
/// field lands ahead of every unordered one regardless of the value used.
const int _unorderedPageField = 1 << 30;

class ModelGenerator {
  static Future<void> generate({
    required String root,
    required String pkgName,
    required String buildId,
  }) async {
    final String searchTuningSrc = _searchTuningSource(root);
    final modelsDir = Directory(p.join(root, 'lib', 'models'));
    final fs = const LocalFileSystem();
    // Always '/': a glob separator is not a host path separator, and a
    // backslash is glob's escape character. p.join here matched nothing on
    // Windows, so models.g.dart came out empty and every model type was
    // undefined hundreds of lines away.
    final glob = Glob('lib/models/**.dart');
    final files = <File>[];
    if (modelsDir.existsSync()) {
      for (final entity in glob.listFileSystemSync(
        fs,
        root: root,
        followLinks: false,
      )) {
        if (entity is File) {
          files.add(File(entity.path));
        }
      }
    }

    final sb = StringBuffer();
    // The public pages' specs, for the backend that cannot import this file.
    final List<String> pageSpecs = <String>[];
    sb.writeln("import 'dart:async';");
    sb.writeln("import 'dart:convert' as convert;");
    sb.writeln("import 'dart:core';");
    sb.writeln("import 'dart:core' as core;");
    sb.writeln("import 'dart:math' as math;");
    sb.writeln();
    sb.writeln("import 'package:flutter/widgets.dart';");
    sb.writeln("import 'package:dartvel_core/dartvel.dart';");
    sb.writeln("import 'package:dartvel_flutter/dartvel_flutter.dart';");
    sb.writeln();
    sb.writeln('/// Reads a numeric column. The generated columns have TEXT');
    sb.writeln('/// affinity, which coerces bound numbers to strings.');
    sb.writeln('num _dvAsNum(Object? value) =>');
    sb.writeln('    value is num ? value : num.parse(value.toString());');
    sb.writeln();
    sb.writeln('/// Reads a timestamp. JSON has no date type, so a value that');
    sb.writeln('/// has been through jsonEncode arrives as the ISO string');
    sb.writeln('/// [toJson] wrote; one that has not is still a DateTime.');
    sb.writeln('DateTime _dvAsDateTime(Object? value) => value is DateTime');
    sb.writeln('    ? value');
    sb.writeln('    : value is num');
    sb.writeln('        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())');
    sb.writeln('        : DateTime.parse(value.toString());');

    final classesGenerated = <String>[];

    for (final file in files) {
      final content = await file.readAsString();
      // Scan for @DVModel(...) classes.
      final classMatches = RegExp(
        r'@DVModel\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
        dotAll: true,
      ).allMatches(content);
      for (final match in classMatches) {
        final modelArgs = match.group(1) ?? '';
        final sourceClassName = match.group(2)!;
        if (!sourceClassName.startsWith('_')) {
          throw StateError(
            'Dartvel model generation inputs must be private. Rename '
            '$sourceClassName to _$sourceClassName and reference the generated '
            '$sourceClassName type from dartvel_client/dartvel_client.dart.',
          );
        }
        final className = sourceClassName.substring(1);
        final constructorPrefix = RegExp(
          '\\bconst\\s+${RegExp.escape(sourceClassName)}\\s*\\(',
        ).hasMatch(content)
            ? 'const '
            : '';
        final isSearchableModel = modelArgs.contains(
          RegExp(r'\bsearchable\s*:\s*true\b'),
        );
        // Page-generation options feed the generated Model.Page component and
        // public static-path metadata.
        final pageDataModeMatch = RegExp(
          r'\bpageDataMode\s*:\s*DVModelPageDataMode\.([A-Za-z0-9_]+)',
        ).firstMatch(modelArgs);
        final pageDataMode = pageDataModeMatch?.group(1) ?? 'auto';
        final generatesPublicPages = modelArgs.contains(
          RegExp(r'\bgeneratePublicPages\s*:\s*true\b'),
        );
        final tableName = '${className.toLowerCase()}s';
        classesGenerated.add(className);

        // Parse fields
        // We find all fields of format: final Type name;
        final fieldRegex = RegExp(
          r'final\s+(.+?)\s+([A-Za-z0-9_]+)\s*;',
          dotAll: true,
        );
        final fields = <Map<String, String>>[];
        for (final m in fieldRegex.allMatches(content)) {
          fields.add({'type': m.group(1)!, 'name': m.group(2)!});
        }
        final searchableFields = <Map<String, String>>[];
        // Canonical form is @DVModel.searchableField(); the bare @DVSearchable
        // spelling is still accepted while it remains deprecated.
        final searchableFieldRegex = RegExp(
          r'@(?:DVModel\.searchableField|DVSearchable)\s*\(\s*\)\s*'
          r'final\s+(.+?)\s+([A-Za-z0-9_]+)\s*;',
          dotAll: true,
        );
        for (final m in searchableFieldRegex.allMatches(content)) {
          searchableFields.add({'type': m.group(1)!, 'name': m.group(2)!});
        }
        // Fields marked @DVModel.sensitiveField(...): excluded from public
        // serialization and generated display by default. The deprecated
        // @DVSensitiveModelField spelling is still accepted.
        final sensitiveFieldNames = <String>{};
        // Fields opted back into generated forms with
        // @DVModel.sensitiveField(showInForms: true). There is no generated
        // admin view yet, so showInAdmin has nothing to gate.
        final sensitiveFormFields = <String>{};
        final sensitiveFieldRegex = RegExp(
          r'@(?:DVModel\.sensitiveField|DVSensitiveModelField)\s*\(([^)]*)\)\s*'
          r'final\s+.+?\s+([A-Za-z0-9_]+)\s*;',
          dotAll: true,
        );
        for (final m in sensitiveFieldRegex.allMatches(content)) {
          final args = m.group(1)!;
          final name = m.group(2)!;
          sensitiveFieldNames.add(name);
          if (RegExp(r'\bshowInForms\s*:\s*true\b').hasMatch(args)) {
            sensitiveFormFields.add(name);
          }
        }

        // Generated model pages compose fields semantically rather than
        // dumping them in declaration order. These field annotations override
        // what the composition would otherwise infer, and live under the
        // DVModel parent like @DVModel.sensitiveField() rather than standing
        // alone.
        String? singleAnnotatedField(String constructor) {
          final match = RegExp(
            '@DVModel\\.$constructor\\s*\\(\\s*\\)\\s*final\\s+.+?\\s+'
            '([A-Za-z0-9_]+)\\s*;',
            dotAll: true,
          ).firstMatch(content);
          return match?.group(1);
        }

        final featuredImageField = singleAnnotatedField('featuredImage');
        final pageTitleField = singleAnnotatedField('pageTitle');
        final mainContentField = singleAnnotatedField('mainContent');

        final hiddenPageFields = <String>{};
        for (final m in RegExp(
          r'@DVModel\.hideFromPage\s*\(\s*\)\s*final\s+.+?\s+([A-Za-z0-9_]+)\s*;',
          dotAll: true,
        ).allMatches(content)) {
          hiddenPageFields.add(m.group(1)!);
        }

        final pageFieldOrder = <String, int>{};
        for (final m in RegExp(
          r'@DVModel\.pageOrder\s*\(\s*(-?\d+)\s*\)\s*final\s+.+?\s+'
          r'([A-Za-z0-9_]+)\s*;',
          dotAll: true,
        ).allMatches(content)) {
          pageFieldOrder[m.group(2)!] = int.parse(m.group(1)!);
        }

        // Inference for anything not annotated. The featured image is the
        // first DVImage field; the title is the first `title`/`name` string,
        // else the first string. Main content cannot be resolved here — the
        // spec picks the longest non-empty text, which is only known at render
        // time — so the generator emits the candidates and the page chooses.
        bool isPageVisible(String name) =>
            !sensitiveFieldNames.contains(name) &&
            !hiddenPageFields.contains(name);

        String baseType(String type) =>
            type.endsWith('?') ? type.substring(0, type.length - 1) : type;

        String? firstOf(Iterable<String> names) {
          for (final name in names) {
            return name;
          }
          return null;
        }

        final resolvedFeaturedImage = featuredImageField ??
            firstOf(
              fields
                  .where((Map<String, String> f) =>
                      baseType(f['type']!) == 'DVImage' &&
                      isPageVisible(f['name']!))
                  .map((Map<String, String> f) => f['name']!),
            );

        final stringFields = fields
            .where((Map<String, String> f) =>
                baseType(f['type']!) == 'String' && isPageVisible(f['name']!))
            .map((Map<String, String> f) => f['name']!)
            .toList();

        final resolvedPageTitle = pageTitleField ??
            firstOf(stringFields.where((String name) {
              final lower = name.toLowerCase();
              return lower == 'title' || lower == 'name';
            })) ??
            firstOf(stringFields);

        // Candidates the page picks the longest value from, when no field is
        // annotated @DVModel.mainContent().
        final mainContentCandidates = mainContentField != null
            ? <String>[mainContentField]
            : stringFields
                .where((String name) => name != resolvedPageTitle)
                .toList();

        // Everything else, in @DVModel.pageOrder(n) order first and declaration
        // after, with the fields already placed above removed.
        final placedFields = <String>{
          if (resolvedFeaturedImage != null) resolvedFeaturedImage,
          if (resolvedPageTitle != null) resolvedPageTitle,
          ...mainContentCandidates,
        };
        final remainingPageFields = fields
            .map((Map<String, String> f) => f['name']!)
            .where((String name) =>
                isPageVisible(name) && !placedFields.contains(name))
            .toList();
        // Sorted on (order, declaration index) rather than order alone:
        // List.sort is not stable, so comparing equal would let unannotated
        // fields drift out of declaration order between runs.
        final declarationIndex = <String, int>{
          for (var i = 0; i < remainingPageFields.length; i++)
            remainingPageFields[i]: i,
        };
        remainingPageFields.sort((String a, String b) {
          final orderA = pageFieldOrder[a] ?? _unorderedPageField;
          final orderB = pageFieldOrder[b] ?? _unorderedPageField;
          if (orderA != orderB) return orderA.compareTo(orderB);
          return declarationIndex[a]!.compareTo(declarationIndex[b]!);
        });

        // Generate the public runtime model. The annotated source class is a
        // private schema input; application code uses this generated class.
        sb.writeln();
        sb.writeln('/// Generated public model for [$sourceClassName].');
        sb.writeln('class $className {');
        for (final field in fields) {
          final type = field['type']!;
          final name = field['name']!;
          sb.writeln('  final $type $name;');
        }
        sb.writeln();
        sb.writeln('  $constructorPrefix$className({');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('    required this.$name,');
        }
        sb.writeln('  });');
        sb.writeln();
        sb.writeln(
          '  /// How generated pages for this model resolve their data, as',
        );
        sb.writeln('  /// declared by @DVModel(pageDataMode:).');
        sb.writeln(
          '  static const DVModelPageDataMode pageDataMode = DVModelPageDataMode.$pageDataMode;',
        );
        sb.writeln();
        sb.writeln(
          '  /// Whether @DVModel(generatePublicPages:) requested public',
        );
        sb.writeln('  /// pages and static paths for this model.');
        sb.writeln(
          '  static const bool generatePublicPages = $generatesPublicPages;',
        );
        sb.writeln();
        sb.writeln(
          '  /// Field names marked @DVModel.sensitiveField(), excluded from',
        );
        sb.writeln('  /// public serialization and generated display.');
        sb.writeln(
          '  static const Set<String> sensitiveFields = <String>{${sensitiveFieldNames.map((n) => "'$n'").join(', ')}};',
        );
        sb.writeln();
        sb.writeln('  /// Generated form component for [$className].');
        sb.writeln('  ///');
        sb.writeln('  /// Pass [onSubmit] to receive the edited model; without');
        sb.writeln('  /// it the form has no one to hand a value to and shows');
        sb.writeln('  /// no controls.');
        sb.writeln(
          '  static Widget Form($className model, [void Function($className)? onSubmit]) {',
        );
        sb.writeln('    return DVForm<$className>(model, onSubmit);');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Generated lazy list component for [$className].');
        sb.writeln('  static Widget List(');
        sb.writeln('    Iterable<$className> models, {');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln('  }) {');
        sb.writeln('    final itemBuilder = builder ?? Card;');
        sb.writeln(
          '    return DVBox.builder<$className>(models, itemBuilder);',
        );
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Generated grid table component for [$className].');
        // A real table, not a grid of cards. This used to emit
        // DVBox.builder(...).grid(columns: 2): no header, no rows, nothing to
        // arrow between, and nothing a screen reader could announce as
        // tabular -- while the spec promises sorting, keyboard navigation and
        // accessibility from it.
        sb.writeln('  /// A sortable, keyboard-navigable table of [models].');
        sb.writeln('  ///');
        sb.writeln('  /// One column per non-sensitive field. Pass [builder]');
        sb.writeln('  /// to fall back to a card grid instead.');
        sb.writeln('  static Widget Table(');
        sb.writeln('    Iterable<$className> models, {');
        sb.writeln('    int columns = 2,');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln('  }) {');
        sb.writeln('    if (builder != null) {');
        sb.writeln(
          '      return DVBox.builder<$className>(models, builder).grid(columns: columns);',
        );
        sb.writeln('    }');
        sb.writeln(
            '    return DVTable<$className>(');
        sb.writeln('      models.toList(growable: false),');
        sb.writeln('      columns: <DVTableColumn<$className>>[');
        for (final field in fields) {
          final name = field['name']!;
          // A sensitive field is excluded from tables by the same rule that
          // keeps it out of logs and AI context; putting it in a column would
          // be the widest possible exposure.
          if (sensitiveFieldNames.contains(name)) continue;
          final type = baseType(field['type']!);
          final label = _columnLabel(name);
          sb.writeln('        DVTableColumn<$className>(');
          sb.writeln("          label: '$label',");
          sb.writeln(
              '          value: (model) => model.$name.toString(),');
          // Only where the field has an order, and compared in its own type.
          // Comparing through toString sorts 10 before 9 and 2026-01 before
          // 2025-12: it looks like it works and orders nothing meaningfully,
          // which is worse than not offering the control.
          final String? comparator = switch (type) {
            'int' || 'double' || 'num' => 'a.$name.compareTo(b.$name)',
            'String' => 'a.$name.compareTo(b.$name)',
            'DateTime' => 'a.$name.compareTo(b.$name)',
            'bool' =>
              '(a.$name ? 1 : 0).compareTo(b.$name ? 1 : 0)',
            _ => null,
          };
          if (comparator != null) {
            final bool nullable = field['type']!.trim().endsWith('?');
            if (nullable) {
              // A null sorts last rather than throwing. A table that crashes
              // on a column with one empty cell is a table nobody can sort.
              sb.writeln('          compare: (a, b) => a.$name == null');
              sb.writeln('              ? (b.$name == null ? 0 : 1)');
              sb.writeln('              : b.$name == null');
              sb.writeln('                  ? -1');
              sb.writeln('                  : a.$name!.compareTo(b.$name!),');
            } else {
              sb.writeln('          compare: (a, b) => $comparator,');
            }
          }
          sb.writeln('        ),');
        }
        sb.writeln('      ],');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Generated page component for [$className].');
        sb.writeln('  // ignore: constant_identifier_names');
        sb.writeln(
          '  static const ${className}PageComponent Page = ${className}PageComponent._();',
        );
        if (generatesPublicPages) {
          final publicPathField = _publicPathField(fields);
          final publishedField = _publishedField(fields);
          pageSpecs.add(
            '  DVModelPageSpec(\n'
            "    model: '$className',\n"
            "    route: '/${_pluralRouteSegment(className)}/:$publicPathField',\n"
            "    param: '$publicPathField',\n"
            "    table: '$tableName',\n"
            "    keyField: '$publicPathField',\n"
            "    titleField: ${resolvedPageTitle == null ? 'null' : "'$resolvedPageTitle'"},\n"
            "    contentFields: <String>[${mainContentCandidates.map((String n) => "'$n'").join(', ')}],\n"
            "    imageField: ${resolvedFeaturedImage == null ? 'null' : "'$resolvedFeaturedImage'"},\n"
            "    publishedField: ${publishedField == null ? 'null' : "'$publishedField'"},\n"
            '  ),',
          );
          sb.writeln();
          sb.writeln(
            '  static FutureOr<Iterable<String>> Function()? _publicStaticPathsResolver;',
          );
          sb.writeln();
          sb.writeln(
            '  /// Registers the published-record path resolver used by static',
          );
          sb.writeln(
              '  /// generation for @DVModel(generatePublicPages: true).');
          sb.writeln(
            '  static void usePublicStaticPathsResolver(',
          );
          sb.writeln(
            '    FutureOr<Iterable<String>> Function() resolver,',
          );
          sb.writeln('  ) {');
          sb.writeln('    _publicStaticPathsResolver = resolver;');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln(
            '  /// Resolves public page path values for generated static paths.',
          );
          sb.writeln(
              '  static Future<core.List<String>> publicStaticPaths() async {');
          sb.writeln('    final resolver = _publicStaticPathsResolver;');
          sb.writeln('    if (resolver != null) {');
          sb.writeln(
              '    final values = await Future<Iterable<String>>.value(');
          sb.writeln('      resolver(),');
          sb.writeln('    );');
          sb.writeln('    return values.toList(growable: false);');
          sb.writeln('    }');
          sb.writeln(
            "    final rows = await DV.Database.query('select * from $tableName');",
          );
          sb.writeln('    return rows');
          sb.writeln('        .map(${className}Parser.fromJson)');
          if (publishedField != null) {
            sb.writeln('        .where((model) => model.$publishedField)');
          }
          sb.writeln('        .map((model) => model.$publicPathField)');
          sb.writeln('        .toList(growable: false);');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln(
            '  /// Route generated for public [$className] pages.',
          );
          sb.writeln(
            "  static const String publicPageRoute = '/${_pluralRouteSegment(className)}/:$publicPathField';",
          );
          sb.writeln(
            "  /// The path parameter [publicPageRoute] carries.",
          );
          sb.writeln(
            "  static const String publicPageParam = '$publicPathField';",
          );
          sb.writeln();
          sb.writeln('  /// The page at [publicPageRoute], ready to route to.');
          sb.writeln('  ///');
          sb.writeln('  /// generatePublicPages promised public pages and');
          sb.writeln('  /// produced only a list of paths: nothing generated a');
          sb.writeln('  /// route, so every one of those paths led to the');
          sb.writeln("  /// application's own not-found page. This is what the");
          sb.writeln('  /// generated router renders for them.');
          sb.writeln('  static Widget publicPage(String $publicPathField) {');
          sb.writeln('    return Page.fromId(');
          sb.writeln('      $publicPathField,');
          sb.writeln('      findById: (String value) async {');
          sb.writeln('        final found = await find(value);');
          sb.writeln('        if (found == null) {');
          sb.writeln("          throw StateError('No $className for \"'");
          sb.writeln("              '\$value\".');");
          sb.writeln('        }');
          sb.writeln('        return found;');
          sb.writeln('      },');
          sb.writeln('    );');
          sb.writeln('  }');
        }
        sb.writeln();
        sb.writeln('  /// Generated card component for [$className].');
        sb.writeln('  static Widget Card($className model) {');
        sb.writeln('    return DVBox.list([');
        for (final field in fields) {
          final name = field['name']!;
          if (sensitiveFieldNames.contains(name)) continue;
          final type = baseType(field['type']!);
          if (type == 'DVImage') {
            sb.writeln('      DVImageView(model.$name),');
          } else {
            sb.writeln('      DVText(model.$name.toString()),');
          }
        }
        sb.writeln('    ]).modifier(const DVModifier().card());');
        sb.writeln('  }');
        sb.writeln();

        // Semantic page composition, in the order NEW_SPEC.md defines:
        // featured image, title, main content, then the remaining fields.
        sb.writeln('  /// Field a generated page renders as its featured');
        sb.writeln('  /// image, or null when the model has none.');
        sb.writeln(
          '  static const String? featuredImageField = '
          '${resolvedFeaturedImage == null ? 'null' : "'$resolvedFeaturedImage'"};',
        );
        sb.writeln('  /// Field a generated page renders as its title.');
        sb.writeln(
          '  static const String? pageTitleField = '
          '${resolvedPageTitle == null ? 'null' : "'$resolvedPageTitle'"};',
        );
        sb.writeln('  /// Fields a generated page may render as its main');
        sb.writeln('  /// content; the longest non-empty one wins.');
        // core-prefixed: the class already declares a static `List` component,
        // which shadows the type inside the class body.
        sb.writeln(
          '  static const core.List<String> mainContentFields = <String>'
          '[${mainContentCandidates.map((String n) => "'$n'").join(', ')}];',
        );
        sb.writeln('  /// Fields excluded from generated pages by');
        sb.writeln('  /// @DVModel.hideFromPage().');
        sb.writeln(
          '  static const Set<String> hiddenPageFields = <String>'
          '{${hiddenPageFields.map((String n) => "'$n'").join(', ')}};',
        );
        sb.writeln();
        sb.writeln('  /// Renders the semantic page body for [$className].');
        sb.writeln('  static Widget PageBody($className model) {');
        sb.writeln('    return DVBox.list([');
        if (resolvedFeaturedImage != null) {
          sb.writeln('      DVImageView(model.$resolvedFeaturedImage),');
        }
        if (resolvedPageTitle != null) {
          sb.writeln(
            '      DVText(model.$resolvedPageTitle.toString())'
            '.modifier(const DVModifier().fontSize(24)),',
          );
        }
        if (mainContentCandidates.isNotEmpty) {
          // The spec picks the largest text block, which depends on the
          // record's values, so the choice happens here rather than at
          // generation time.
          sb.writeln('      DVText(_mainContentOf(model)),');
        }
        for (final name in remainingPageFields) {
          final type = baseType(
            fields.firstWhere(
              (Map<String, String> f) => f['name'] == name,
            )['type']!,
          );
          if (type == 'DVImage') {
            sb.writeln('      DVImageView(model.$name),');
          } else {
            sb.writeln('      DVText(model.$name.toString()),');
          }
        }
        sb.writeln('    ]);');
        sb.writeln('  }');
        if (mainContentCandidates.isNotEmpty) {
          sb.writeln();
          sb.writeln('  /// The longest non-empty main-content candidate.');
          sb.writeln('  static String _mainContentOf($className model) {');
          sb.writeln('    final candidates = <String>[');
          for (final name in mainContentCandidates) {
            final isNullable = fields
                .firstWhere(
                  (Map<String, String> f) => f['name'] == name,
                )['type']!
                .endsWith('?');
            // `?.` on a non-nullable field is a warning, so the null handling
            // is emitted only where the field can actually be null.
            sb.writeln(
              isNullable
                  ? "      model.$name ?? '',"
                  : '      model.$name,',
            );
          }
          sb.writeln('    ];');
          // Explicitly typed rather than `var`: generated code is held to the
          // same lint rules as hand-written code.
          sb.writeln('    String longest = \'\';');
          sb.writeln('    for (final candidate in candidates) {');
          sb.writeln('      if (candidate.length > longest.length) {');
          sb.writeln('        longest = candidate;');
          sb.writeln('      }');
          sb.writeln('    }');
          sb.writeln('    return longest;');
          sb.writeln('  }');
        }

        // Persistence and model sync. The key column is the same field public
        // pages use; falling back to the first field keeps keyless models
        // usable for append-only data.
        final keyField = fields.isEmpty
            ? null
            : (() {
                try {
                  return _publicPathField(fields);
                } on StateError {
                  return fields.first['name']!;
                }
              })();
        if (keyField != null) {
          final columnList =
              fields.map((Map<String, String> f) => f['name']!).join(', ');
          final placeholderList =
              fields.map((Map<String, String> f) => '?').join(', ');
          String toParam(Map<String, String> f) {
            final base = f['type']!.replaceAll('?', '');
            final name = f['name']!;
            // SQLite stores booleans as integers and DateTimes as text; the
            // conversion happens here so _fromRow can reverse it.
            if (base == 'bool') return 'model.$name == true ? 1 : 0';
            if (base == 'DateTime') {
              return f['type']!.endsWith('?')
                  ? 'model.$name?.toIso8601String()'
                  : 'model.$name.toIso8601String()';
            }
            return 'model.$name';
          }

          sb.writeln();
          sb.writeln('  /// Typed change stream for [$className].');
          sb.writeln(
            '  static Stream<DVModelChange<$className>> get changes =>',
          );
          sb.writeln('      DVModelSync.changes<$className>();');
          sb.writeln();
          sb.writeln('  /// Reads a row back into a [$className].');
          sb.writeln(
            '  static $className _fromRow(Map<String, Object?> row) {',
          );
          sb.writeln('    return $className(');
          for (final field in fields) {
            final name = field['name']!;
            final type = field['type']!;
            final base = type.replaceAll('?', '');
            final nullable = type.endsWith('?');
            String read;
            if (base == 'bool') {
              // The generated columns have TEXT affinity, which coerces a
              // bound integer to the string '1'; accept every stored form.
              const truthy =
                  "== 1 || row['NAME'] == true || row['NAME'] == '1' || row['NAME'] == 'true'";
              final check = "row['$name'] ${truthy.replaceAll('NAME', name)}";
              read = nullable
                  ? "row['$name'] == null ? null : ($check)"
                  : check;
            } else if (base == 'int') {
              read = nullable
                  ? "row['$name'] == null ? null : _dvAsNum(row['$name']).toInt()"
                  : "_dvAsNum(row['$name']).toInt()";
            } else if (base == 'double') {
              read = nullable
                  ? "row['$name'] == null ? null : _dvAsNum(row['$name']).toDouble()"
                  : "_dvAsNum(row['$name']).toDouble()";
            } else if (base == 'DateTime') {
              read = nullable
                  ? "row['$name'] == null ? null : DateTime.parse(row['$name']! as String)"
                  : "DateTime.parse(row['$name']! as String)";
            } else {
              read = "row['$name'] as $type";
            }
            sb.writeln('      $name: $read,');
          }
          sb.writeln('    );');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// Every stored [$className].');
          sb.writeln('  static Future<core.List<$className>> all() async {');
          sb.writeln(
            "    final rows = await const DVDatabase().query('SELECT * FROM $tableName');",
          );
          sb.writeln(
            '    return rows.map(_fromRow).toList(growable: false);',
          );
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// The stored [$className] whose $keyField matches,');
          sb.writeln('  /// or null.');
          sb.writeln('  static Future<$className?> find(String $keyField) async {');
          sb.writeln(
            "    final rows = await const DVDatabase().query('SELECT * FROM $tableName WHERE $keyField = ?', <Object?>[$keyField]);",
          );
          sb.writeln('    return rows.isEmpty ? null : _fromRow(rows.first);');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// Upserts [model] and publishes the change.');
          sb.writeln('  static Future<$className> save($className model) async {');
          sb.writeln('    const db = DVDatabase();');
          sb.writeln(
            "    final existing = await db.query('SELECT ${fields.first['name']} FROM $tableName WHERE $keyField = ?', <Object?>[model.$keyField]);",
          );
          sb.writeln(
            "    await db.execute('DELETE FROM $tableName WHERE $keyField = ?', <Object?>[model.$keyField]);",
          );
          sb.writeln(
            "    await db.execute('INSERT INTO $tableName ($columnList) VALUES ($placeholderList)', <Object?>[${fields.map(toParam).join(', ')}]);",
          );
          sb.writeln('    await DVModelSync.publish<$className>(');
          sb.writeln('      model,');
          sb.writeln('      kind: existing.isEmpty');
          sb.writeln('          ? DVModelChangeKind.created');
          sb.writeln('          : DVModelChangeKind.updated,');
          sb.writeln('    );');
          sb.writeln('    return model;');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// Removes [model] and publishes the deletion.');
          sb.writeln('  static Future<void> destroy($className model) async {');
          sb.writeln(
            "    await const DVDatabase().execute('DELETE FROM $tableName WHERE $keyField = ?', <Object?>[model.$keyField]);",
          );
          sb.writeln(
            '    await DVModelSync.publish<$className>(model, kind: DVModelChangeKind.deleted);',
          );
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// Generated CRUD admin for [$className].');
          sb.writeln('  ///');
          sb.writeln('  /// One call rather than a generated screen: the model');
          sb.writeln('  /// supplies list, blank, save, delete and its own');
          sb.writeln('  /// form, and DVModelAdmin is the screen around them.');
          sb.writeln('  static Widget Admin() {');
          sb.writeln('    return DVModelAdmin<$className>(');
          sb.writeln("      title: '$className',");
          sb.writeln('      load: all,');
          sb.writeln('      save: save,');
          sb.writeln('      destroy: destroy,');
          // The registered factory is the same blank the form falls back to,
          // so New and an empty form agree on what a new record looks like.
          sb.writeln(
            '      blank: () => createDVModel<$className>()!,',
          );
          sb.writeln(
            "      label: ($className model) => '\${model.$keyField}',",
          );
          sb.writeln(
            '      form: ($className model, void Function($className) onSubmit) =>',
          );
          sb.writeln('          Form(model, onSubmit),');
          sb.writeln('    );');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  /// Calls [callback] with every stored [$className]');
          sb.writeln('  /// now and again after each change, per the spec\'s');
          sb.writeln('  /// `Model.watch((models) { ... })`.');
          sb.writeln(
            '  static Future<DVModelWatch> watch(void Function(core.List<$className>) callback) async {',
          );
          sb.writeln('    Future<void> emit() async => callback(await all());');
          sb.writeln('    await emit();');
          sb.writeln(
            '    final subscription = DVModelSync.changes<$className>().listen((_) { emit(); });',
          );
          sb.writeln('    return DVModelWatch(subscription);');
          sb.writeln('  }');
        }
        sb.writeln('}');

        sb.writeln();
        sb.writeln(
          '/// Generated model-aware page component for [$className].',
        );
        sb.writeln('class ${className}PageComponent {');
        sb.writeln('  const ${className}PageComponent._();');
        sb.writeln();
        sb.writeln(
          '  /// Renders a collection page for already-loaded models.',
        );
        sb.writeln('  Widget call(');
        sb.writeln('    Iterable<$className> models, {');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln('  }) {');
        sb.writeln('    return DVBox.list([');
        sb.writeln("      const DVText('$className'),");
        sb.writeln('      $className.List(models, builder: builder),');
        sb.writeln('    ]);');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Renders a detail page for an already-loaded model.');
        sb.writeln('  Widget sync(');
        sb.writeln('    $className model, {');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln('  }) {');
        // A page renders the semantic composition; Card stays the compact
        // representation used inside lists and tables.
        sb.writeln('    final render = builder ?? $className.PageBody;');
        sb.writeln('    return render(model);');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Renders a detail page from a future.');
        sb.writeln('  Widget async(');
        sb.writeln('    Future<$className> model, {');
        sb.writeln('    $className? initialData,');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln(
          "    Widget loading = const DVText('Loading $className...'),",
        );
        sb.writeln('    Widget Function(String message)? errorBuilder,');
        sb.writeln('  }) {');
        sb.writeln('    return FutureBuilder<$className>(');
        sb.writeln('      future: model,');
        sb.writeln('      initialData: initialData,');
        sb.writeln('      builder: (context, snapshot) {');
        sb.writeln('        if (snapshot.hasError) {');
        sb.writeln('          final message = snapshot.error.toString();');
        sb.writeln(
          '          return errorBuilder?.call(message) ?? DVText(message);',
        );
        sb.writeln('        }');
        sb.writeln('        final value = snapshot.data;');
        sb.writeln('        if (value == null) return loading;');
        sb.writeln('        return sync(value, builder: builder);');
        sb.writeln('      },');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Renders a detail page from a Dartvel signal.');
        sb.writeln('  Widget signal(');
        sb.writeln('    DVSignal<$className> model, {');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln('  }) {');
        sb.writeln('    return sync(model.value, builder: builder);');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// Resolves and renders a detail page by id.');
        sb.writeln('  Widget fromId(');
        sb.writeln('    String id, {');
        sb.writeln(
          '    required Future<$className> Function(String id) findById,',
        );
        sb.writeln(
          '    DVModelPageDataMode dataMode = $className.pageDataMode,',
        );
        sb.writeln('    $className? cachedModel,');
        sb.writeln('    Widget Function($className)? builder,');
        sb.writeln(
          "    Widget loading = const DVText('Loading $className...'),",
        );
        sb.writeln('    Widget Function(String message)? errorBuilder,');
        sb.writeln('  }) {');
        sb.writeln('    if (dataMode == DVModelPageDataMode.cached &&');
        sb.writeln('        cachedModel != null) {');
        sb.writeln('      return sync(cachedModel, builder: builder);');
        sb.writeln('    }');
        sb.writeln('    final initialData =');
        sb.writeln(
          '        dataMode == DVModelPageDataMode.staleWhileRevalidate',
        );
        sb.writeln('            ? cachedModel');
        sb.writeln('            : null;');
        sb.writeln('    return async(');
        sb.writeln('      findById(id),');
        sb.writeln('      initialData: initialData,');
        sb.writeln('      builder: builder,');
        sb.writeln('      loading: loading,');
        sb.writeln('      errorBuilder: errorBuilder,');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');

        // Generate extension
        sb.writeln();
        sb.writeln('/// Dartvel generated extension for [$className]');
        sb.writeln('extension ${className}DartvelExtension on $className {');

        // toJson
        sb.writeln('  /// Serializes [$className] to a JSON map.');
        sb.writeln('  Map<String, Object?> toJson() => {');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln("    '$name': ${_jsonValue(field)},");
        }
        sb.writeln('  };');

        // toPublicJson (excludes @DVModel.sensitiveField() fields)
        sb.writeln();
        sb.writeln(
          '  /// Serializes [$className] for client/public output, omitting',
        );
        sb.writeln('  /// @DVModel.sensitiveField() fields.');
        sb.writeln('  Map<String, Object?> toPublicJson() => {');
        for (final field in fields) {
          final name = field['name']!;
          if (sensitiveFieldNames.contains(name)) continue;
          sb.writeln("    '$name': ${_jsonValue(field)},");
        }
        sb.writeln('  };');

        // copyWith
        sb.writeln();
        sb.writeln(
          '  /// Returns a copy of [$className] with the given fields replaced.',
        );
        // An already-nullable field is already optional here; appending a
        // second `?` is a syntax error, not a more optional parameter.
        final params = fields.map((f) {
          final type = f['type']!;
          return '${type.endsWith('?') ? type : '$type?'} ${f['name']}';
        }).join(', ');
        sb.writeln('  $className copyWith({$params}) {');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('      $name: $name ?? this.$name,');
        }
        sb.writeln('    );');
        sb.writeln('  }');

        // Instance persistence, per the spec's `await user.sync()`.
        if (fields.isNotEmpty) {
          sb.writeln();
          sb.writeln('  /// Upserts this model and publishes the change.');
          sb.writeln('  Future<$className> save() => $className.save(this);');
          sb.writeln();
          sb.writeln('  /// Removes this model and publishes the deletion.');
          sb.writeln('  Future<void> destroy() => $className.destroy(this);');
          sb.writeln();
          sb.writeln('  /// Persists this model and announces it as synced,');
          sb.writeln('  /// so other watchers converge on this state.');
          sb.writeln('  Future<$className> sync() async {');
          sb.writeln('    await $className.save(this);');
          sb.writeln(
            '    await DVModelSync.publish<$className>(this, kind: DVModelChangeKind.synced);',
          );
          sb.writeln('    return this;');
          sb.writeln('  }');
        }

        // Database metadata
        sb.writeln();
        sb.writeln('  /// Database table name for [$className].');
        sb.writeln("  String get tableName => '$tableName';");
        sb.writeln();
        sb.writeln('  /// SQL statement to create the [$className] table.');
        final cols = fields.map((f) => "${f['name']} TEXT").join(', ');
        sb.writeln(
          "  String get createTableSql => 'CREATE TABLE IF NOT EXISTS $tableName ($cols)';",
        );

        sb.writeln('}');

        // Helper fromJson
        sb.writeln();
        sb.writeln('/// Helper class for parsing [$className] from JSON.');
        sb.writeln('class ${className}Parser {');
        sb.writeln('  /// Parses [$className] from a JSON map.');
        sb.writeln('  static $className fromJson(Map<String, Object?> json) {');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('      $name: ${_fromJsonValue(field)},');
        }
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');

        sb.writeln();
        sb.writeln('/// Generated typed test factory for [$className].');
        sb.writeln('class ${className}Factory {');
        sb.writeln('  /// Varies the identifying fields between calls.');
        sb.writeln('  ///');
        sb.writeln('  /// Without it every create() returned the same');
        sb.writeln('  /// identifier, so a test making two records silently');
        sb.writeln('  /// got one -- and the failure read as an assertion');
        sb.writeln('  /// about the wrong record rather than about the');
        sb.writeln('  /// factory.');
        sb.writeln('  static int _sequence = 0;');
        sb.writeln();
        sb.writeln('  /// Rewinds the sequence, so a test is repeatable.');
        sb.writeln('  ///');
        sb.writeln('  /// Otherwise the identifiers depend on how many tests');
        sb.writeln('  /// ran before this one, which makes a golden or a');
        sb.writeln('  /// snapshot assertion unrepeatable.');
        sb.writeln('  static void resetSequence() {');
        sb.writeln('    _sequence = 0;');
        sb.writeln('  }');
        sb.writeln();
        for (final field in fields) {
          final type = field['type']!;
          final name = field['name']!;
          final nullableType = type.endsWith('?') ? type : '$type?';
          sb.writeln('  final $nullableType $name;');
        }
        sb.writeln();
        sb.writeln('  const ${className}Factory({');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('    this.$name,');
        }
        sb.writeln('  });');
        sb.writeln();
        sb.writeln('  ${className}Factory copyWith({');
        for (final field in fields) {
          final type = field['type']!;
          final name = field['name']!;
          final nullableType = type.endsWith('?') ? type : '$type?';
          sb.writeln('    $nullableType $name,');
        }
        sb.writeln('  }) {');
        sb.writeln('    return ${className}Factory(');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('      $name: $name ?? this.$name,');
        }
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  ${className}Factory admin() {');
        sb.writeln('    return copyWith(');
        for (final field in fields) {
          final type = field['type']!;
          final name = field['name']!;
          final value = _factoryAdminValue(type, name);
          if (value != null) {
            sb.writeln('      $name: $value,');
          }
        }
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  $className create() {');
        sb.writeln('    final n = ++_sequence;');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final type = field['type']!;
          final name = field['name']!;
          final defaultValue = _factoryDefaultValue(
            type: type,
            name: name,
            className: className,
            sequenced: true,
          );
          sb.writeln('      $name: $name ?? $defaultValue,');
        }
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln('  /// [count] models, each with its own identifier.');
        sb.writeln('  ///');
        sb.writeln('  /// Every list-shaped test needs this, and writing the');
        sb.writeln('  /// loop by hand is where people reach for a shared');
        sb.writeln('  /// instance and reintroduce the duplicate-id bug.');
        sb.writeln('  List<$className> createMany(int count) {');
        sb.writeln(
            '    return List<$className>.generate(count, (_) => create());');
        sb.writeln('  }');
        sb.writeln('}');

        // Generated form controls helper
        sb.writeln();
        sb.writeln('/// Generated form controls for [$className]');
        sb.writeln('class ${className}FormControls extends DVFormControls {');
        sb.writeln('  final $className? ${className.toLowerCase()};');
        sb.writeln('  ${className}FormControls({');
        sb.writeln('    this.${className.toLowerCase()},');
        sb.writeln('    super.onSubmit,');
        sb.writeln('    super.onReset,');
        sb.writeln('  }) : super(${className.toLowerCase()});');

        for (final field in fields) {
          final name = field['name']!;
          final type = field['type']!;
          // A sensitive field stays out of generated forms unless it was
          // opted back in with @DVModel.sensitiveField(showInForms: true).
          if (sensitiveFieldNames.contains(name) &&
              !sensitiveFormFields.contains(name)) {
            continue;
          }
          var defaultVal = 'null';
          if (type == 'String') {
            defaultVal = "''";
          } else if (type == 'int') {
            defaultVal = '0';
          } else if (type == 'double') {
            defaultVal = '0.0';
          } else if (type == 'bool') {
            defaultVal = 'false';
          }

          // No default means the getter can return null, whatever the field
          // was declared as. Keeping the field's own type there made the
          // whole generated client fail to compile for a DateTime.
          final hasDefault = defaultVal != 'null';
          final getterType =
              hasDefault || type.endsWith('?') ? type : '$type?';
          sb.writeln();
          sb.writeln(
            '  $getterType get $name => ${className.toLowerCase()}?.$name'
            '${hasDefault ? ' ?? $defaultVal' : ''};',
          );
          if (type.replaceAll('?', '') == 'String') {
            // A nullable string has no text to validate until it has one;
            // calling trim() on it unconditionally does not compile.
            final subject = getterType.endsWith('?') ? '($name ?? \'\')' : name;
            final validation = name.toLowerCase().contains('email')
                ? '$subject.isNotEmpty && $subject.contains(\'@\')'
                : '$subject.trim().isNotEmpty';
            sb.writeln('  bool get ${name}IsValid => $validation;');
          }
        }
        sb.writeln('}');
        sb.writeln();
        // A plain function, not a lazy final: a lazy runs once per isolate,
        // which makes re-registration after a test reset silently a no-op.
        sb.writeln('void _register$className() {');
        // A transport cannot carry a model without a codec; registering it
        // here means cross-client sync works without app wiring.
        sb.writeln('  DVModelSync.registerCodec<$className>(');
        sb.writeln("    name: '$className',");
        sb.writeln('    encode: ($className model) => model.toJson(),');
        sb.writeln('    decode: ${className}Parser.fromJson,');
        sb.writeln('  );');
        sb.writeln(
          '  registerFormControlsFactory<$className>((model, {onSubmit, onReset}) {',
        );
        sb.writeln('    return ${className}FormControls(');
        sb.writeln('      ${className.toLowerCase()}: model as $className?,');
        sb.writeln('      onSubmit: onSubmit,');
        sb.writeln('      onReset: onReset,');
        sb.writeln('    );');
        sb.writeln('  });');
        sb.writeln(
          // Not const, even when the constructor is: the defaults include
          // expressions such as DateTime.fromMillisecondsSinceEpoch that no
          // const invocation can hold. A non-const call to a const
          // constructor is always legal; the reverse is not.
          '  registerDVModelFactory<$className>(() => $className(',
        );
        for (final field in fields) {
          final name = field['name']!;
          final type = field['type']!;
          final defaultValue = _factoryDefaultValue(
            type: type,
            name: name,
            className: className,
          );
          sb.writeln('    $name: $defaultValue,');
        }
        sb.writeln('  ));');
        sb.writeln(
          '  registerDVModelSerializer<$className>((model) => model.toJson());',
        );
        // The way back: without it a DVForm can render a model but not
        // return an edited one.
        sb.writeln(
          '  registerDVModelDeserializer<$className>(${className}Parser.fromJson);',
        );

        // GraphQL: the generated API surface for this model. Sensitive fields
        // stay out of the type, the resolvers, and the mutation arguments —
        // GraphQL is a public API, so it reads through toPublicJson.
        if (keyField != null) {
          String sdlType(Map<String, String> f) {
            final base = f['type']!.replaceAll('?', '');
            final nullable = f['type']!.endsWith('?');
            final scalar = switch (base) {
              'int' => 'Int',
              'double' || 'num' => 'Float',
              'bool' => 'Boolean',
              _ => 'String',
            };
            return nullable ? scalar : '$scalar!';
          }

          final publicFields = fields
              .where((Map<String, String> f) =>
                  !sensitiveFieldNames.contains(f['name']))
              .toList();
          final singular =
              className[0].toLowerCase() + className.substring(1);

          sb.writeln('  DVGraphQL.registerType(DVGraphQLObjectType(');
          sb.writeln("    '$className',");
          sb.writeln('    const <DVGraphQLField>[');
          for (final f in publicFields) {
            sb.writeln(
              "      DVGraphQLField('${f['name']}', '${sdlType(f)}'),",
            );
          }
          sb.writeln('    ],');
          sb.writeln('  ));');
          sb.writeln('  DVGraphQL.registerQuery(DVGraphQLField(');
          sb.writeln("    '$tableName',");
          sb.writeln("    '[$className!]!',");
          sb.writeln('    resolve: (args, parent) async =>');
          sb.writeln('        (await $className.all())');
          sb.writeln(
            '            .map(($className m) => m.toPublicJson())',
          );
          sb.writeln('            .toList(),');
          sb.writeln('  ));');
          sb.writeln('  DVGraphQL.registerQuery(DVGraphQLField(');
          sb.writeln("    '$singular',");
          sb.writeln("    '$className',");
          sb.writeln("    args: const <String, String>{'$keyField': 'String!'},");
          sb.writeln('    resolve: (args, parent) async =>');
          sb.writeln(
            "        (await $className.find(args['$keyField'] as String))",
          );
          sb.writeln('            ?.toPublicJson(),');
          sb.writeln('  ));');

          // save<Model>: public fields as arguments; sensitive fields take
          // their generated defaults rather than crossing the API.
          final constructorArgs = fields.map((Map<String, String> f) {
            final name = f['name']!;
            final type = f['type']!;
            if (sensitiveFieldNames.contains(name)) {
              final fallback = _factoryDefaultValue(
                type: type,
                name: name,
                className: className,
              );
              return '$name: $fallback';
            }
            return "$name: args['$name'] as $type";
          }).join(', ');
          sb.writeln('  DVGraphQL.registerMutation(DVGraphQLField(');
          sb.writeln("    'save$className',");
          sb.writeln("    '$className!',");
          sb.writeln('    args: const <String, String>{');
          for (final f in publicFields) {
            sb.writeln("      '${f['name']}': '${sdlType(f)}',");
          }
          sb.writeln('    },');
          sb.writeln('    resolve: (args, parent) async =>');
          // Runtime argument values: never const, whatever the source
          // class's constructor is.
          sb.writeln(
            '        (await $className.save($className($constructorArgs)))',
          );
          sb.writeln('            .toPublicJson(),');
          sb.writeln('  ));');
          sb.writeln('  DVGraphQL.registerMutation(DVGraphQLField(');
          sb.writeln("    'delete$className',");
          sb.writeln("    'Boolean!',");
          sb.writeln("    args: const <String, String>{'$keyField': 'String!'},");
          sb.writeln('    resolve: (args, parent) async {');
          sb.writeln(
            "      final model = await $className.find(args['$keyField'] as String);",
          );
          sb.writeln('      if (model == null) return false;');
          sb.writeln('      await $className.destroy(model);');
          sb.writeln('      return true;');
          sb.writeln('    },');
          sb.writeln('  ));');
        }
        sb.writeln('}');

        sb.writeln();
        sb.writeln('/// Generated bulk import helpers for [$className].');
        sb.writeln('class ${className}Import {');
        sb.writeln('  static DVImportResult<$className> csv(String content) {');
        sb.writeln('    final lines = const convert.LineSplitter()');
        sb.writeln('        .convert(content)');
        sb.writeln('        .where((line) => line.trim().isNotEmpty)');
        sb.writeln('        .toList(growable: false);');
        sb.writeln('    if (lines.isEmpty) {');
        sb.writeln(
          '      return const DVImportResult<$className>(items: <$className>[]);',
        );
        sb.writeln('    }');
        sb.writeln('    final headers = _splitCsvLine(lines.first);');
        sb.writeln('    final items = <$className>[];');
        sb.writeln('    final errors = <DVImportRowError>[];');
        sb.writeln(
          '    for (int index = 1; index < lines.length; index += 1) {',
        );
        sb.writeln('      final values = _splitCsvLine(lines[index]);');
        sb.writeln('      final row = <String, Object?>{};');
        sb.writeln('      for (int i = 0; i < headers.length; i += 1) {');
        sb.writeln(
          "        row[headers[i]] = i < values.length ? values[i] : '';",
        );
        sb.writeln('      }');
        sb.writeln('      try {');
        sb.writeln('        items.add(${className}Parser.fromJson(row));');
        sb.writeln('      } on Object catch (error) {');
        sb.writeln('        errors.add(DVImportRowError(');
        sb.writeln('          row: index + 1,');
        sb.writeln('          message: error.toString(),');
        sb.writeln('        ));');
        sb.writeln('      }');
        sb.writeln('    }');
        sb.writeln(
          '    return DVImportResult<$className>(items: items, errors: errors);',
        );
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static Future<List<DVJobEnvelope<DVImportChunk>>> resumableCsv(',
        );
        sb.writeln('    String content, {');
        sb.writeln("    String queue = 'imports',");
        sb.writeln('    int chunkSize = 500,');
        sb.writeln('  }) async {');
        sb.writeln(
          '    final chunks = dvChunkImportRows(content, chunkSize: chunkSize, hasHeader: true);',
        );
        sb.writeln('    final jobs = <DVJobEnvelope<DVImportChunk>>[];');
        sb.writeln('    for (final chunk in chunks) {');
        sb.writeln(
          '      jobs.add(await const DVQueues().dispatch<DVImportChunk>(',
        );
        sb.writeln('        DVImportChunk(');
        sb.writeln("          model: '$className',");
        sb.writeln("          format: 'csv',");
        sb.writeln('          startRow: chunk.startRow,');
        sb.writeln('          rows: chunk.rows,');
        sb.writeln('          header: chunk.header,');
        sb.writeln('        ),');
        sb.writeln('        queue: queue,');
        sb.writeln('      ));');
        sb.writeln('    }');
        sb.writeln('    return jobs;');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static DVImportResult<$className> ndjson(String content) {',
        );
        sb.writeln('    final lines = const convert.LineSplitter()');
        sb.writeln('        .convert(content)');
        sb.writeln('        .where((line) => line.trim().isNotEmpty)');
        sb.writeln('        .toList(growable: false);');
        sb.writeln('    final items = <$className>[];');
        sb.writeln('    final errors = <DVImportRowError>[];');
        sb.writeln(
          '    for (int index = 0; index < lines.length; index += 1) {',
        );
        sb.writeln('      try {');
        sb.writeln('        final decoded = convert.jsonDecode(lines[index]);');
        sb.writeln('        if (decoded is! Map<Object?, Object?>) {');
        sb.writeln(
          "          throw const FormatException('NDJSON row must be a JSON object.');",
        );
        sb.writeln('        }');
        sb.writeln(
          '        items.add(${className}Parser.fromJson(Map<String, Object?>.from(decoded)));',
        );
        sb.writeln('      } on Object catch (error) {');
        sb.writeln('        errors.add(DVImportRowError(');
        sb.writeln('          row: index + 1,');
        sb.writeln('          message: error.toString(),');
        sb.writeln('        ));');
        sb.writeln('      }');
        sb.writeln('    }');
        sb.writeln(
          '    return DVImportResult<$className>(items: items, errors: errors);',
        );
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static Future<List<DVJobEnvelope<DVImportChunk>>> resumableNdjson(',
        );
        sb.writeln('    String content, {');
        sb.writeln("    String queue = 'imports',");
        sb.writeln('    int chunkSize = 500,');
        sb.writeln('  }) async {');
        sb.writeln(
          '    final chunks = dvChunkImportRows(content, chunkSize: chunkSize, hasHeader: false);',
        );
        sb.writeln('    final jobs = <DVJobEnvelope<DVImportChunk>>[];');
        sb.writeln('    for (final chunk in chunks) {');
        sb.writeln(
          '      jobs.add(await const DVQueues().dispatch<DVImportChunk>(',
        );
        sb.writeln('        DVImportChunk(');
        sb.writeln("          model: '$className',");
        sb.writeln("          format: 'ndjson',");
        sb.writeln('          startRow: chunk.startRow,');
        sb.writeln('          rows: chunk.rows,');
        sb.writeln('          header: chunk.header,');
        sb.writeln('        ),');
        sb.writeln('        queue: queue,');
        sb.writeln('      ));');
        sb.writeln('    }');
        sb.writeln('    return jobs;');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static DVImportResult<$className> excel(String content) {',
        );
        sb.writeln('    final lines = const convert.LineSplitter()');
        sb.writeln('        .convert(content)');
        sb.writeln('        .where((line) => line.trim().isNotEmpty)');
        sb.writeln('        .toList(growable: false);');
        sb.writeln('    if (lines.isEmpty) {');
        sb.writeln(
          '      return const DVImportResult<$className>(items: <$className>[]);',
        );
        sb.writeln('    }');
        sb.writeln("    final headers = lines.first.split('\\t');");
        sb.writeln('    final items = <$className>[];');
        sb.writeln('    final errors = <DVImportRowError>[];');
        sb.writeln(
          '    for (int index = 1; index < lines.length; index += 1) {',
        );
        sb.writeln("      final values = lines[index].split('\\t');");
        sb.writeln('      final row = <String, Object?>{};');
        sb.writeln('      for (int i = 0; i < headers.length; i += 1) {');
        sb.writeln(
          "        row[headers[i]] = i < values.length ? values[i] : '';",
        );
        sb.writeln('      }');
        sb.writeln('      try {');
        sb.writeln('        items.add(${className}Parser.fromJson(row));');
        sb.writeln('      } on Object catch (error) {');
        sb.writeln('        errors.add(DVImportRowError(');
        sb.writeln('          row: index + 1,');
        sb.writeln('          message: error.toString(),');
        sb.writeln('        ));');
        sb.writeln('      }');
        sb.writeln('    }');
        sb.writeln(
          '    return DVImportResult<$className>(items: items, errors: errors);',
        );
        sb.writeln('  }');
        sb.writeln('}');
        sb.writeln();
        sb.writeln('/// Generated export helpers for [$className].');
        sb.writeln('class ${className}Export {');
        sb.writeln(
          '  static DVExportResult csv(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.csv\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) {',
        );
        sb.writeln('    final exportItems = options.apply(items);');
        sb.writeln('    final buffer = StringBuffer();');
        // An export is a file that leaves the system, so sensitive columns are
        // written only when the caller asks for them.
        final publicFieldNames = fields
            .map((Map<String, String> f) => f['name']!)
            .where((String name) => !sensitiveFieldNames.contains(name))
            .toList();
        final allFieldNames =
            fields.map((Map<String, String> f) => f['name']!).toList();
        if (sensitiveFieldNames.isEmpty) {
          sb.writeln("    buffer.writeln('${allFieldNames.join(',')}');");
        } else {
          sb.writeln(
            '    final includeSensitive = options.includeSensitiveFields;',
          );
          sb.writeln(
            "    buffer.writeln(includeSensitive ? '${allFieldNames.join(',')}'"
            " : '${publicFieldNames.join(',')}');",
          );
        }
        sb.writeln('    for (final item in exportItems) {');
        sb.writeln('      buffer.writeln([');
        for (final field in fields) {
          final name = field['name']!;
          final guard =
              sensitiveFieldNames.contains(name) ? 'if (includeSensitive) ' : '';
          sb.writeln('        ${guard}_escapeCsvValue(item.$name),');
        }
        sb.writeln("      ].join(','));");
        sb.writeln('    }');
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'text/csv; charset=utf-8',");
        sb.writeln('      bytes: convert.utf8.encode(buffer.toString()),');
        sb.writeln('      metadata: options.exportMetadata(),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static DVExportResult json(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.json\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) {',
        );
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'application/json; charset=utf-8',");
        // toPublicJson drops sensitive fields; toJson is the internal form and
        // is reached only when the caller explicitly asks for it.
        final exportJsonCall = sensitiveFieldNames.isEmpty
            ? 'item.toJson()'
            : '(options.includeSensitiveFields ? item.toJson() '
                ': item.toPublicJson())';
        sb.writeln(
          '      bytes: convert.utf8.encode(convert.jsonEncode(options.apply(items).map((item) => $exportJsonCall).toList(growable: false))),',
        );
        sb.writeln('      metadata: options.exportMetadata(),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static DVExportResult ndjson(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.ndjson\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) {',
        );
        sb.writeln('    final exportItems = options.apply(items);');
        sb.writeln('    final buffer = StringBuffer();');
        sb.writeln('    for (final item in exportItems) {');
        sb.writeln(
          '      buffer.writeln(convert.jsonEncode($exportJsonCall));',
        );
        sb.writeln('    }');
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'application/x-ndjson; charset=utf-8',");
        sb.writeln('      bytes: convert.utf8.encode(buffer.toString()),');
        sb.writeln('      metadata: options.exportMetadata(),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static Stream<DVExportResult> streamCsv(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.csv\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) async* {',
        );
        sb.writeln(
          '    final exportItems = options.apply(items).toList(growable: false);',
        );
        sb.writeln('    if (options.chunkSize < 1) {');
        sb.writeln(
          "      throw ArgumentError.value(options.chunkSize, 'chunkSize', 'chunkSize must be positive.');",
        );
        sb.writeln('    }');
        sb.writeln(
          '    for (int index = 0; index < exportItems.length; index += options.chunkSize) {',
        );
        sb.writeln(
          '      final end = math.min(index + options.chunkSize, exportItems.length);',
        );
        sb.writeln('      yield csv(');
        sb.writeln('        exportItems.sublist(index, end),');
        sb.writeln(
          "        fileName: fileName.replaceFirst('.csv', '.part\${(index ~/ options.chunkSize) + 1}.csv'),",
        );
        sb.writeln('        options: options,');
        sb.writeln('      );');
        sb.writeln('    }');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static Stream<DVExportResult> streamNdjson(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.ndjson\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) async* {',
        );
        sb.writeln(
          '    final exportItems = options.apply(items).toList(growable: false);',
        );
        sb.writeln('    if (options.chunkSize < 1) {');
        sb.writeln(
          "      throw ArgumentError.value(options.chunkSize, 'chunkSize', 'chunkSize must be positive.');",
        );
        sb.writeln('    }');
        sb.writeln(
          '    for (int index = 0; index < exportItems.length; index += options.chunkSize) {',
        );
        sb.writeln(
          '      final end = math.min(index + options.chunkSize, exportItems.length);',
        );
        sb.writeln('      yield ndjson(');
        sb.writeln('        exportItems.sublist(index, end),');
        sb.writeln(
          "        fileName: fileName.replaceFirst('.ndjson', '.part\${(index ~/ options.chunkSize) + 1}.ndjson'),",
        );
        sb.writeln('        options: options,');
        sb.writeln('      );');
        sb.writeln('    }');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          '  static DVExportResult excel(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.xls\', DVExportOptions<$className> options = const DVExportOptions<$className>()}) {',
        );
        sb.writeln('    final exportItems = options.apply(items);');
        sb.writeln('    final buffer = StringBuffer();');
        sb.writeln("    buffer.writeln('<?xml version=\"1.0\"?>');");
        sb.writeln(
          "    buffer.writeln('<?mso-application progid=\"Excel.Sheet\"?>');",
        );
        sb.writeln(
          "    buffer.writeln('<Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\">');",
        );
        sb.writeln("    buffer.writeln('<Worksheet ss:Name=\"$className\">');");
        sb.writeln("    buffer.writeln('<Table>');");
        if (sensitiveFieldNames.isNotEmpty) {
          sb.writeln(
            '    final includeSensitive = options.includeSensitiveFields;',
          );
        }
        sb.writeln("    buffer.writeln('<Row>');");
        for (final field in fields) {
          final name = field['name']!;
          final sensitive = sensitiveFieldNames.contains(name);
          if (sensitive) sb.writeln('    if (includeSensitive) {');
          sb.writeln(
            "    ${sensitive ? '  ' : ''}buffer.writeln('<Cell><Data ss:Type=\"String\">$name</Data></Cell>');",
          );
          if (sensitive) sb.writeln('    }');
        }
        sb.writeln("    buffer.writeln('</Row>');");
        sb.writeln('    for (final item in exportItems) {');
        sb.writeln("      buffer.writeln('<Row>');");
        for (final field in fields) {
          final name = field['name']!;
          final sensitive = sensitiveFieldNames.contains(name);
          if (sensitive) sb.writeln('      if (includeSensitive) {');
          sb.writeln(
            "      ${sensitive ? '  ' : ''}buffer.writeln('<Cell><Data ss:Type=\"String\">\${_escapeExcelCell(item.$name)}</Data></Cell>');",
          );
          if (sensitive) sb.writeln('      }');
        }
        sb.writeln("      buffer.writeln('</Row>');");
        sb.writeln('    }');
        sb.writeln("    buffer.writeln('</Table>');");
        sb.writeln("    buffer.writeln('</Worksheet>');");
        sb.writeln("    buffer.writeln('</Workbook>');");
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln(
          "      contentType: 'application/vnd.ms-excel; charset=utf-8',",
        );
        sb.writeln('      bytes: convert.utf8.encode(buffer.toString()),');
        sb.writeln('      metadata: options.exportMetadata(),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');
        sb.writeln();
        sb.writeln('/// Generated reporting helpers for [$className].');
        sb.writeln('class ${className}Report {');
        sb.writeln(
          '  static DVReportResult monthly(Iterable<$className> items, {DateTime? month}) {',
        );
        sb.writeln('    final selectedMonth = month ?? DateTime.now();');
        sb.writeln('    return DVReportResult(');
        sb.writeln("      name: '${className.toLowerCase()}.monthly',");
        sb.writeln('      generatedAt: DateTime.now().toUtc(),');
        sb.writeln('      metrics: <String, Object?>{');
        sb.writeln("        'month': selectedMonth.month,");
        sb.writeln("        'year': selectedMonth.year,");
        sb.writeln("        'count': items.length,");
        sb.writeln('      },');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          "  static DVScheduledReport scheduleMonthly({String cron = '0 0 1 * *', String queue = 'reports', DateTime? scheduledAt, DateTime? periodStart, DateTime? periodEnd, Map<String, String> metadata = const <String, String>{}}) {",
        );
        sb.writeln('    final report = DVScheduledReport(');
        sb.writeln("      name: '${className.toLowerCase()}.monthly',");
        sb.writeln("      model: '$className',");
        sb.writeln("      report: 'monthly',");
        sb.writeln('      cron: cron,');
        sb.writeln('      queue: queue,');
        sb.writeln('      scheduledAt: scheduledAt ?? DateTime.now().toUtc(),');
        sb.writeln('      periodStart: periodStart,');
        sb.writeln('      periodEnd: periodEnd,');
        sb.writeln('      metadata: metadata,');
        sb.writeln('    );');
        sb.writeln('    // Parsed here, so an unusable cron fails where the');
        sb.writeln('    // schedule is declared rather than silently never');
        sb.writeln('    // running in a worker nobody is watching.');
        sb.writeln('    report.schedule;');
        sb.writeln('    return report;');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
          "  static Future<DVJobEnvelope<DVScheduledReport>> dispatchMonthly({String cron = '0 0 1 * *', String queue = 'reports', int priority = 0, int maxAttempts = 3, Duration backoff = const Duration(seconds: 30), DateTime? scheduledAt, DateTime? periodStart, DateTime? periodEnd, Map<String, String> metadata = const <String, String>{}}) {",
        );
        sb.writeln('    return const DVQueues().dispatch<DVScheduledReport>(');
        sb.writeln('      scheduleMonthly(');
        sb.writeln('        cron: cron,');
        sb.writeln('        queue: queue,');
        sb.writeln('        scheduledAt: scheduledAt,');
        sb.writeln('        periodStart: periodStart,');
        sb.writeln('        periodEnd: periodEnd,');
        sb.writeln('        metadata: metadata,');
        sb.writeln('      ),');
        sb.writeln('      queue: queue,');
        sb.writeln('      priority: priority,');
        sb.writeln('      maxAttempts: maxAttempts,');
        sb.writeln('      backoff: backoff,');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');

        if (isSearchableModel || searchableFields.isNotEmpty) {
          final effectiveSearchableFields =
              searchableFields.isEmpty ? fields : searchableFields;
          sb.writeln();
          sb.writeln('/// Generated search facets for [$className].');
          sb.writeln('class ${className}SearchFacets {');
          for (final field in effectiveSearchableFields) {
            final type = field['type']!;
            final name = field['name']!;
            sb.writeln('  final List<$type>? $name;');
          }
          sb.writeln();
          sb.writeln('  const ${className}SearchFacets({');
          for (final field in effectiveSearchableFields) {
            final name = field['name']!;
            sb.writeln('    this.$name,');
          }
          sb.writeln('  });');
          sb.writeln('}');
          sb.writeln();
          sb.writeln('/// Generated typed search facade for [$className].');
          sb.writeln('class ${className}Search {');
          sb.writeln(
            '  /// Ranking configured under `dartvel.search` in pubspec.yaml.',
          );
          sb.writeln(
            '  ///',
          );
          sb.writeln(
            '  /// Pass it to a provider that post-processes matches, so the',
          );
          sb.writeln(
            '  /// configuration lives in one place rather than at each call.',
          );
          sb.writeln('  static const DVSearchTuning tuning = $searchTuningSrc;');
          sb.writeln();
          sb.writeln(
            '  static DVSearchProvider<$className, ${className}SearchFacets> _provider = const DVUnconfiguredSearchProvider<$className, ${className}SearchFacets>();',
          );
          sb.writeln();
          sb.writeln(
            '  static void useProvider(DVSearchProvider<$className, ${className}SearchFacets> provider) {',
          );
          sb.writeln('    _provider = provider;');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  static Future<DVSearchResultPage<$className>> query(');
          sb.writeln('    String value, {');
          sb.writeln('    ${className}SearchFacets? facets,');
          sb.writeln('    int page = 1,');
          sb.writeln('    int perPage = 20,');
          sb.writeln('  }) {');
          sb.writeln('    return _provider.query(');
          sb.writeln('      value,');
          sb.writeln('      facets: facets,');
          sb.writeln('      page: page,');
          sb.writeln('      perPage: perPage,');
          sb.writeln('    );');
          sb.writeln('  }');
          sb.writeln('}');
        }
      }
    }

    // The per-model registration blocks are lazy top-level finals, which
    // nothing evaluates on its own — form factories, codecs and GraphQL
    // resolvers would silently never register. This function forces them and
    // is called from the generated configureDartvelRuntime().
    sb.writeln();
    sb.writeln('/// Runs every generated model registration: form');
    sb.writeln('/// factories, codecs, sync codecs and GraphQL resolvers.');
    sb.writeln('/// Idempotent — registries overwrite by key — and');
    sb.writeln('/// repeatable after a test reset.');
    sb.writeln('void registerDartvelModels() {');
    for (final className in classesGenerated) {
      sb.writeln('  _register$className();');
    }
    sb.writeln('}');

    if (classesGenerated.isNotEmpty) {
      sb.writeln();
      sb.writeln('List<String> _splitCsvLine(String line) {');
      sb.writeln("  return line.split(',').map((value) {");
      sb.writeln('    final trimmed = value.trim();');
      sb.writeln(
        "    if (trimmed.length >= 2 && trimmed.startsWith('\"') && trimmed.endsWith('\"')) {",
      );
      sb.writeln('      return trimmed.substring(1, trimmed.length - 1);');
      sb.writeln('    }');
      sb.writeln('    return trimmed;');
      sb.writeln('  }).toList(growable: false);');
      sb.writeln('}');
      sb.writeln();
      sb.writeln('String _escapeCsvValue(Object? value) {');
      sb.writeln("  final text = value?.toString() ?? '';");
      sb.writeln(
        "  if (text.contains(',') || text.contains('\"') || text.contains('\\n')) {",
      );
      sb.writeln(r'''    return '"${text.replaceAll('"', '""')}"';''');
      sb.writeln('  }');
      sb.writeln('  return text;');
      sb.writeln('}');
      sb.writeln();
      sb.writeln('String _escapeExcelCell(Object? value) {');
      sb.writeln("  final text = value?.toString() ?? '';");
      sb.writeln('  return text');
      sb.writeln("      .replaceAll('&', '&amp;')");
      sb.writeln("      .replaceAll('<', '&lt;')");
      sb.writeln("      .replaceAll('>', '&gt;')");
      sb.writeln("      .replaceAll('\"', '&quot;')");
      sb.writeln("      .replaceAll(\"'\", '&apos;');");
      sb.writeln('}');
      sb.writeln();
    }

    final clientDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    if (!clientDir.existsSync()) {
      clientDir.createSync(recursive: true);
    }
    final generatedHeader =
        // unnecessary_nullable_for_final_variable_declarations: page metadata
        // is declared `String?` for every model, so it reads as unnecessary on
        // the models that happen to resolve a value.
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n// ignore_for_file: directives_ordering, non_constant_identifier_names, unused_element, use_super_parameters, unnecessary_nullable_for_final_variable_declarations, unnecessary_import\n// Build ID: $buildId\n';
    // The no-models stub must still define registerDartvelModels(): the
    // generated dartvel_runtime.dart imports and calls it unconditionally,
    // so an app with no @DVModel inputs otherwise generates a client that
    // does not compile.
    final content = classesGenerated.isEmpty
        ? '${generatedHeader}library dartvel_client_models;\n\n'
            '/// This application declares no @DVModel inputs; the generated\n'
            '/// runtime calls this unconditionally.\n'
            'void registerDartvelModels() {}\n'
        : '$generatedHeader\n${sb.toString()}';
    File(p.join(clientDir.path, 'models.g.dart')).writeAsStringSync(content);

    // Pure Dart, no Flutter: what the backend renders a public page from.
    File(p.join(clientDir.path, 'model_pages.g.dart')).writeAsStringSync(
      '${generatedHeader}library dartvel_client_model_pages;\n\n'
      "import 'package:dartvel_core/dartvel.dart' show DVModelPageSpec;\n\n"
      '/// Where each public model page\'s rows are and which fields carry its\n'
      '/// title, content, image and published flag. The backend resolves a\n'
      '/// page\'s data from these on request.\n'
      'const List<DVModelPageSpec> dartvelModelPages = <DVModelPageSpec>[\n'
      '${pageSpecs.join('\n')}${pageSpecs.isEmpty ? '' : '\n'}'
      '];\n',
    );
  }

  /// A default value for [name].
  ///
  /// [sequenced] is only true inside a factory's create(), which declares an
  /// `n`. The registry and fallback callers build a single instance with no
  /// sequence in scope, and emitting `$n` there produced generated code that
  /// did not compile: "Undefined name 'n'".
  static String _factoryDefaultValue({
    required String type,
    required String name,
    required String className,
    bool sequenced = false,
  }) {
    final String seq = sequenced ? r'$n' : '1';
    final baseType = type.replaceAll('?', '');
    final lowerName = name.toLowerCase();
    if (type.endsWith('?')) return 'null';
    if (baseType == 'String') {
      // Identifying and unique fields carry the sequence; descriptive ones do
      // not. An email has a unique constraint in most schemas, so two records
      // sharing one fail to insert -- while varying a display name only makes
      // test expectations read strangely.
      if (lowerName == 'id' || lowerName.endsWith('id')) {
        // The field name is baked in here; only the sequence is interpolated
        // in the generated code. Escaping both put a literal ${name} into the
        // output, where it resolved to the factory's own nullable `name`
        // field and every id came out as "null_1".
        return "'${name}_$seq'";
      }
      if (lowerName.contains('email')) return "'user$seq@example.com'";
      if (lowerName.contains('slug') || lowerName.contains('username')) {
        return "'$name-$seq'";
      }
      if (lowerName.contains('name')) return "'Test User'";
      if (lowerName.contains('status')) return "'active'";
      if (lowerName.contains('role')) return "'user'";
      return "'test_$name'";
    }
    if (baseType == 'int') return '1';
    if (baseType == 'double') return '1.0';
    if (baseType == 'num') return '1';
    if (baseType == 'bool') return 'true';
    if (baseType == 'DateTime') {
      return 'DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)';
    }
    if (baseType == 'DVImage') {
      // An asset rather than a URL: a test factory should not have a default
      // that makes a network request when something renders it.
      return "const DVImage.asset('assets/test_$name.png')";
    }
    if (baseType == 'List<String>') return "const <String>['test']";
    if (baseType == 'List<int>') return 'const <int>[1]';
    if (baseType == 'List<double>') return 'const <double>[1.0]';
    if (baseType == 'List<num>') return 'const <num>[1]';
    if (baseType == 'List<bool>') return 'const <bool>[true]';
    if (baseType == 'Map<String,String>' || baseType == 'Map<String, String>') {
      return "const <String, String>{'test': 'value'}";
    }
    if (baseType == 'Map<String,int>' || baseType == 'Map<String, int>') {
      return "const <String, int>{'test': 1}";
    }
    if (baseType == 'Map<String,double>' || baseType == 'Map<String, double>') {
      return "const <String, double>{'test': 1.0}";
    }
    if (baseType == 'Map<String,bool>' || baseType == 'Map<String, bool>') {
      return "const <String, bool>{'test': true}";
    }
    throw StateError(
      'Cannot generate ${className}Factory default for required field '
      '$className.$name of type $type. Make the field nullable or add an '
      'explicit value with ${className}Factory($name: ...).',
    );
  }

  /// How a field is written into a JSON map.
  ///
  /// A `DateTime` is not JSON: leaving one in the map makes `jsonEncode` throw
  /// on the whole model, so it goes out as the ISO string [_fromJsonValue]
  /// reads back.
  static String _jsonValue(Map<String, String> field) {
    final name = field['name']!;
    final type = field['type']!;
    final nullable = type.endsWith('?');
    if (type.replaceAll('?', '') != 'DateTime') return name;
    return nullable ? '$name?.toIso8601String()' : '$name.toIso8601String()';
  }

  /// How a field is read back out of a JSON map.
  ///
  /// Casting is not enough: a decoded map holds strings and numbers, so a
  /// straight `as DateTime` or `as int` throws on exactly the values
  /// `toJson` produced.
  static String _fromJsonValue(Map<String, String> field) {
    final name = field['name']!;
    final type = field['type']!;
    final base = type.replaceAll('?', '');
    final nullable = type.endsWith('?');
    final read = switch (base) {
      'DateTime' => "_dvAsDateTime(json['$name'])",
      'int' => "_dvAsNum(json['$name']).toInt()",
      'double' => "_dvAsNum(json['$name']).toDouble()",
      'num' => "_dvAsNum(json['$name'])",
      _ => "json['$name'] as $type",
    };
    // A plain cast already carries the `?`; a coercion helper does not, so
    // only those need the null guard.
    if (!nullable || !read.startsWith('_dv')) return read;
    return "json['$name'] == null ? null : $read";
  }

  static String? _factoryAdminValue(String type, String name) {
    final baseType = type.replaceAll('?', '');
    final lowerName = name.toLowerCase();
    if (baseType == 'String') {
      if (lowerName.contains('email')) return "'admin@example.com'";
      if (lowerName.contains('name')) return "'Admin User'";
      if (lowerName.contains('role')) return "'admin'";
      if (lowerName.contains('status')) return "'active'";
    }
    if (baseType == 'bool' &&
        (lowerName.contains('admin') || lowerName.contains('active'))) {
      return 'true';
    }
    return null;
  }

  static String _publicPathField(List<Map<String, String>> fields) {
    final stringFields = fields
        .where((field) => field['type'] == 'String')
        .map((field) => field['name']!)
        .toList(growable: false);
    if (stringFields.contains('slug')) return 'slug';
    if (stringFields.contains('id')) return 'id';
    if (stringFields.isNotEmpty) return stringFields.first;
    throw StateError(
      '@DVModel(generatePublicPages: true) requires a String slug, id, or '
      'other String field so Dartvel can generate a parameterized public '
      'page route.',
    );
  }

  static String? _publishedField(List<Map<String, String>> fields) {
    final boolFields = fields
        .where((field) => field['type'] == 'bool')
        .map((field) => field['name']!)
        .toList(growable: false);
    if (boolFields.contains('published')) return 'published';
    if (boolFields.contains('isPublished')) return 'isPublished';
    return null;
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

  /// Renders `dartvel.search` from pubspec.yaml as a const DVSearchTuning.
  ///
  /// Ranking is configuration, not code, so it belongs in one declared place
  /// rather than repeated at every provider construction.
  static String _searchTuningSource(String root) {
    Object? search;
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      if (loaded is YamlMap) {
        final Object? dartvel = loaded['dartvel'];
        if (dartvel is YamlMap) search = dartvel['search'];
      }
    }

    final StringBuffer synonyms = StringBuffer();
    bool typoTolerance = true;
    String pre = '<mark>';
    String post = '</mark>';

    if (search is YamlMap) {
      final Object? declared = search['synonyms'];
      if (declared is YamlMap) {
        for (final MapEntry<Object?, Object?> entry in declared.entries) {
          final Object? values = entry.value;
          if (values is! YamlList) continue;
          synonyms.write(
            "    '${_escapeDart('${entry.key}')}': <String>["
            '${values.map((Object? v) => "'${_escapeDart('$v')}'").join(', ')}'
            '],\n',
          );
        }
      }
      if (search['typoTolerance'] == false) typoTolerance = false;
      if (search['highlightPre'] is String) {
        pre = search['highlightPre'] as String;
      }
      if (search['highlightPost'] is String) {
        post = search['highlightPost'] as String;
      }
    }

    final String synonymsSrc = synonyms.isEmpty
        ? 'const <String, List<String>>{}'
        : '<String, List<String>>{\n$synonyms  }';

    return 'DVSearchTuning(\n'
        '    synonyms: $synonymsSrc,\n'
        '    typoTolerance: $typoTolerance,\n'
        "    highlightPre: '${_escapeDart(pre)}',\n"
        "    highlightPost: '${_escapeDart(post)}',\n"
        '  )';
  }

  /// pubspec is project input, so a quote or backslash in a configured value
  /// would otherwise close the generated literal and break a file far from the
  /// line that caused it.
  static String _escapeDart(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(r"'", r"\'")
      .replaceAll(r'$', r'\$');

}


/// A field name as a column heading.
///
/// `createdAt` reads as "Created at" rather than as the identifier, because a
/// table header is shown to a reader and announced to a screen reader.
String _columnLabel(String field) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < field.length; i += 1) {
    final String c = field[i];
    if (i > 0 && c.toUpperCase() == c && c.toLowerCase() != c) {
      out.write(' ');
      out.write(c.toLowerCase());
    } else {
      out.write(i == 0 ? c.toUpperCase() : c);
    }
  }
  return out.toString().replaceAll('_', ' ');
}
