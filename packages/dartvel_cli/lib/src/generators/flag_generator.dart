import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'annotation_args.dart';

/// A flag declared inside a `@DVFlags()` class.
class DiscoveredFlag {
  const DiscoveredFlag({
    required this.name,
    required this.type,
    required this.initializer,
    required this.owner,
    required this.expires,
    required this.settle,
    required this.doc,
    required this.importPath,
  });

  /// The field name, which is also the key the rule set names it by.
  final String name;

  /// `bool`, `String`, `int`, `double`, or a declared enum's name.
  final String type;

  /// The initializer as written: the default compiled into the build.
  final String initializer;
  final String owner;
  final DateTime expires;

  /// A `DVFlagSettle` member name other than the default, or null.
  final String? settle;
  final List<String> doc;

  /// A `package:` import for the declaring file.
  final String importPath;

  bool get isEnum => !_primitiveTypes.contains(type);
}

const Set<String> _primitiveTypes = <String>{'bool', 'String', 'int', 'double'};

/// Discovers `@DVFlags()` classes and generates the typed `Flags` accessors.
///
/// A flag named by a string can be misspelt, and a misspelt flag does not
/// throw — it misses, and answers its default for ever. So flags are declared
/// once, in Dart, and read through generated members the analyzer checks.
class FlagGenerator {
  // A doc comment or an `@pragma(...)` may sit between the annotation and the
  // class. The pragma is how a private generation input tells the analyzer it
  // is used, and a pattern that stopped at it would drop every flag in the
  // class from `Flags` without a word.
  static final RegExp _classRegex = RegExp(
    r'@DVFlags\s*\(\s*\)\s*(?:(?:///[^\n]*\n|@pragma\([^)]*\))\s*)*'
    r'(?:abstract\s+)?(?:final\s+)?class\s+([A-Za-z0-9_]+)[^{]*\{',
  );

  // The field straight after its annotation, with any pragmas between them.
  // Anchored at the start: the annotation must mark this field, not whatever
  // `static const` happens to come next.
  static final RegExp _fieldRegex = RegExp(
    r'^\s*(?:@pragma\([^)]*\)\s*)*'
    r'static\s+const\s+([A-Za-z0-9_<>?, ]+?)\s+([A-Za-z0-9_]+)\s*=\s*'
    r'([^;]+);',
  );

  /// Generates `lib/dartvel_client/flags.g.dart` and returns the build
  /// warnings: one `DV-FLAGS-004` per flag past its expiry at [now].
  ///
  /// Throws [StateError] for a declaration that cannot be generated, naming
  /// the flag and the reason — no expiry, a public `@DVFlags` class, or a type
  /// a flag cannot carry — rather than generating around it.
  static Future<List<String>> generate({
    required String root,
    required String pkgName,
    /// Accepted and not written anywhere. A build id in generated files
    /// rewrote every file on every build.
    String? buildId,
    DateTime? now,
  }) async {
    final DateTime at = now ?? DateTime.now().toUtc();
    final List<DiscoveredFlag> flags =
        await discover(root: root, pkgName: pkgName);

    final File output =
        File(p.join(root, 'lib', 'dartvel_client', 'flags.g.dart'));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(_render(flags));

    return <String>[
      for (final DiscoveredFlag flag in flags)
        if (flag.expires.isBefore(at))
          'DV-FLAGS-004: flag "${flag.name}" (owner ${flag.owner}) passed its '
              'expiry on ${_date(flag.expires)}; delete it, or extend '
              '`expires:` with the reason it is still needed',
    ];
  }

  /// Every flag declared in the project under [root], without writing
  /// anything: what `generate` writes and what `dartvel flags` reports.
  ///
  /// Throws [StateError] for a declaration that cannot be generated, the same
  /// refusals `generate` makes, and for a flag declared twice — a rule set
  /// names flags by key and could not say which of two it means.
  static Future<List<DiscoveredFlag>> discover({
    required String root,
    required String pkgName,
  }) async {
    final List<DiscoveredFlag> flags = <DiscoveredFlag>[];
    for (final File file in _dartFiles(root)) {
      final String source = await file.readAsString();
      if (!source.contains('@DVFlags')) continue;
      final String importPath = p
          .relative(file.path, from: root)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      _collect(source, file.path, importPath, flags);
    }

    final Set<String> seen = <String>{};
    for (final DiscoveredFlag flag in flags) {
      if (!seen.add(flag.name)) {
        throw StateError(
          'flag "${flag.name}" is declared twice; a rule set could not say '
          'which one it means',
        );
      }
    }
    return flags;
  }

  static void _collect(
    String source,
    String path,
    String importPath,
    List<DiscoveredFlag> into,
  ) {
    for (final RegExpMatch match in _classRegex.allMatches(source)) {
      final String className = match.group(1)!;
      if (!className.startsWith('_')) {
        throw StateError(
          '$path: @DVFlags class "$className" must be private (write '
          '`_$className`); Dartvel generation inputs are private, and '
          'application code reads the generated `Flags`',
        );
      }
      final int bodyStart = match.end;
      final int bodyEnd = _matchingBrace(source, bodyStart - 1);
      if (bodyEnd < 0) continue;
      _collectFields(
          source.substring(bodyStart, bodyEnd), path, importPath, into);
    }
  }

  static void _collectFields(
    String body,
    String path,
    String importPath,
    List<DiscoveredFlag> into,
  ) {
    int at = 0;
    while (true) {
      final int annotation = body.indexOf('@DVFlag', at);
      if (annotation < 0) return;
      // `@DVFlags` is the class annotation, not a field's.
      if (body.startsWith('@DVFlags', annotation)) {
        at = annotation + 8;
        continue;
      }
      final String rest = body.substring(annotation);
      final String? args = dvAnnotationArgs(rest, 'DVFlag');
      if (args == null) {
        throw StateError('$path: an @DVFlag annotation is not closed');
      }
      final int argsEnd = rest.indexOf(args) + args.length + 1;
      final String afterAnnotation = rest.substring(argsEnd);
      final RegExpMatch? field = _fieldRegex.firstMatch(afterAnnotation);
      if (field == null) {
        throw StateError(
          '$path: @DVFlag must mark a `static const` field with an '
          'initializer; the initializer is the default compiled into the build',
        );
      }

      final String type = field.group(1)!.replaceAll(' ', '');
      final String name = field.group(2)!;
      final String initializer = field.group(3)!.trim();

      if (!_primitiveTypes.contains(type) &&
          !RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(type)) {
        throw StateError(
          '$path: flag "$name" has type `$type`, which a flag cannot carry. '
          'Flags carry bool, String, int, double and declared enums; a '
          'structure is configuration, and belongs in Configuration',
        );
      }

      final Map<String, String> named = _namedArgs(args);
      final String? owner = _stringLiteral(named['owner']);
      if (owner == null || owner.isEmpty) {
        throw StateError(
          '$path: flag "$name" has no `owner:`; somebody has to be asked '
          'about it and somebody has to delete it',
        );
      }
      final String? expiresText = _stringLiteral(named['expires']);
      if (expiresText == null) {
        throw StateError(
          '$path: flag "$name" has no `expires:`. A flag is debt with an '
          "owner and a date on it; declare `expires: 'YYYY-MM-DD'`",
        );
      }
      final DateTime? expires = _parseDate(expiresText);
      if (expires == null) {
        throw StateError(
          '$path: flag "$name" has `expires: \'$expiresText\'`, which is not '
          'a YYYY-MM-DD date',
        );
      }
      String? settle;
      final String? settleArg = named['settle'];
      if (settleArg != null) {
        final RegExpMatch? m =
            RegExp(r'^DVFlagSettle\.([A-Za-z]+)$').firstMatch(settleArg.trim());
        if (m == null) {
          throw StateError(
            '$path: flag "$name" has `settle: $settleArg`; write '
            '`DVFlagSettle.onNextLaunch` or leave it out',
          );
        }
        settle = m.group(1) == 'immediately' ? null : m.group(1);
      }

      into.add(DiscoveredFlag(
        name: name,
        type: type,
        initializer: initializer,
        owner: owner,
        expires: expires,
        settle: settle,
        doc: _docBefore(body, annotation),
        importPath: importPath,
      ));
      at = annotation + argsEnd + field.end;
    }
  }

  /// The `///` lines immediately above [offset], in order.
  static List<String> _docBefore(String body, int offset) {
    final List<String> lines = body.substring(0, offset).split('\n');
    final List<String> doc = <String>[];
    // The last element is the indentation before the annotation itself.
    for (int i = lines.length - 2; i >= 0; i--) {
      final String line = lines[i].trim();
      if (!line.startsWith('///')) break;
      doc.insert(0, line);
    }
    return doc;
  }

  static Map<String, String> _namedArgs(String args) {
    final Map<String, String> out = <String, String>{};
    for (final String part in dvSplitArgs(args)) {
      final int colon = part.indexOf(':');
      if (colon < 0) continue;
      out[part.substring(0, colon).trim()] = part.substring(colon + 1).trim();
    }
    return out;
  }

  static String? _stringLiteral(String? text) {
    if (text == null) return null;
    final RegExpMatch? m =
        RegExp(r'''^(['"])(.*)\1$''').firstMatch(text.trim());
    return m?.group(2);
  }

  static DateTime? _parseDate(String text) {
    final RegExpMatch? m =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (m == null) return null;
    final DateTime date = DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    // DateTime rolls 2026-02-31 over into March rather than refusing it.
    if (_date(date) != text) return null;
    return date;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static int _matchingBrace(String source, int open) {
    int depth = 0;
    for (int i = open; i < source.length; i++) {
      final String c = source[i];
      if (c == "'" || c == '"') {
        final int end = source.indexOf(c, i + 1);
        if (end < 0) return -1;
        i = end;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String _render(List<DiscoveredFlag> flags) {
    final Map<String, String> aliases = <String, String>{};
    for (final DiscoveredFlag flag in flags) {
      if (flag.isEnum) {
        aliases.putIfAbsent(flag.importPath, () => 'f${aliases.length}');
      }
    }

    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: unused_import, unnecessary_import')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    for (final MapEntry<String, String> e in aliases.entries) {
      sb.writeln("import '${e.key}' as ${e.value};");
    }
    sb
      ..writeln()
      ..writeln('/// The flags this build declares, generated from `@DVFlags()`.')
      ..writeln('///')
      ..writeln('/// Read `Flags.name.value` anywhere, or `context.flag(Flags.name)`')
      ..writeln('/// in a build method to rebuild when the rules change.')
      ..writeln('abstract final class Flags {');

    for (final DiscoveredFlag flag in flags) {
      final String? alias = flag.isEnum ? aliases[flag.importPath] : null;
      final String type = alias == null ? flag.type : '$alias.${flag.type}';
      String defaultValue = flag.initializer;
      if (alias != null && defaultValue.startsWith('${flag.type}.')) {
        defaultValue = '$alias.$defaultValue';
      }
      if (flag.type == 'double' && RegExp(r'^-?\d+$').hasMatch(defaultValue)) {
        defaultValue = '$defaultValue.0';
      }
      for (final String line in flag.doc) {
        sb.writeln('  $line');
      }
      sb
        ..writeln('  static final DVFeatureFlag<$type> ${flag.name} = '
            'DVFeatureFlag<$type>(')
        ..writeln("    key: '${flag.name}',")
        ..writeln('    defaultValue: $defaultValue,')
        ..writeln("    owner: '${flag.owner.replaceAll("'", r"\'")}',")
        ..writeln('    expires: DateTime.utc(${flag.expires.year}, '
            '${flag.expires.month}, ${flag.expires.day}),');
      if (flag.settle != null) {
        sb.writeln('    settle: DVFlagSettle.${flag.settle},');
      }
      if (alias != null) {
        sb.writeln('    values: $type.values,');
      }
      sb
        ..writeln('  );')
        ..writeln();
    }

    sb.writeln('  /// Every flag above, so the runtime can notice a rule set '
        'naming one this');
    sb.writeln('  /// build does not declare, and `dartvel flags prune` can '
        'list what is due.');
    if (flags.isEmpty) {
      sb.writeln('  static final List<DVFeatureFlag<Object?>> all = '
          '<DVFeatureFlag<Object?>>[];');
    } else {
      sb.writeln('  static final List<DVFeatureFlag<Object?>> all = '
          '<DVFeatureFlag<Object?>>[');
      for (final DiscoveredFlag flag in flags) {
        sb.writeln('    ${flag.name},');
      }
      sb.writeln('  ];');
    }
    sb
      ..writeln('}')
      ..writeln()
      ..writeln('/// Declares this build\'s flags to the runtime.')
      ..writeln('void registerDartvelFlags() {')
      ..writeln('  DVFlags.declare(Flags.all);')
      ..writeln('}');
    return sb.toString();
  }

  static List<File> _dartFiles(String root) {
    const LocalFileSystem fs = LocalFileSystem();
    final List<File> files = <File>[];
    for (final entity in Glob('lib/**.dart')
        .listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is! File) continue;
      final String path = entity.path.replaceAll('\\', '/');
      if (path.contains('/lib/dartvel_client/')) continue;
      files.add(File(entity.path));
    }
    files.sort((File a, File b) => a.path.compareTo(b.path));
    return files;
  }
}
