import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../analysis/dart_source_lexer.dart';
import 'annotation_args.dart';

/// A meter declared with `@DVMeter` on a `static const` field.
class DiscoveredMeter {
  const DiscoveredMeter({
    required this.name,
    required this.kind,
    required this.arguments,
    required this.unit,
    required this.doc,
    required this.file,
    this.named = const <String, String>{},
  });

  /// The annotation's named arguments, as written.
  final Map<String, String> named;

  /// `entitlement`, the fixed quantity, or `none`.
  String get limit {
    final String? text = named['limit'];
    if (text == null) return 'none';
    final RegExpMatch? fixed =
        RegExp(r'^DVLimit\.fixed\((.*)\)$').firstMatch(text);
    if (fixed != null) return fixed.group(1)!.trim();
    return text.replaceFirst('DVLimit.', '');
  }

  /// The behaviour at the limit, or `-` when there is no limit.
  String get atLimit =>
      named['atLimit']?.replaceFirst('DVQuota.', '') ?? '-';

  /// How a gauge is billed: `average` unless declared.
  String get gaugeBilling =>
      named['gaugeBilling']?.replaceFirst('DVGaugeBilling.', '') ?? 'average';

  /// The field name, which is also the name usage is counted under.
  final String name;

  /// `counter` or `gauge`.
  final String kind;

  /// The annotation's arguments as written, copied into the generated code.
  final String arguments;

  /// The declared unit, for `dartvel meters list`.
  final String unit;
  final List<String> doc;

  /// The declaring file, relative to the project root.
  final String file;
}

/// Discovers `@DVMeter` declarations and generates the typed `Meters`
/// accessors, and refuses a meter recorded from client-reachable code
/// (`DV-METER-001`).
///
/// A meter named by a string can be misspelt, and a misspelt meter does not
/// throw: it is a second meter that counts and that nobody bills.
class MeterGenerator {
  // The field straight after its annotation. The type is optional because
  // the spec writes `static const apiCalls = DVMeter.counter;`.
  static final RegExp _fieldRegex = RegExp(
    r'^\s*(?:@pragma\([^)]*\)\s*)*'
    r'static\s+const\s+(?:DVMeterKind\s+)?([A-Za-z0-9_]+)\s*=\s*'
    r'(?:DVMeter|DVMeterKind)\.(counter|gauge)\s*;',
  );

  static final RegExp _classBefore =
      RegExp(r'class\s+(?:const\s+)?([A-Za-z0-9_]+)');

  /// Generates `lib/dartvel_client/meters.g.dart`.
  ///
  /// Throws [StateError] for a declaration that cannot be generated -- a
  /// public declaring class, a meter declared twice, a limit with no
  /// behaviour at it (`DV-METER-005`) -- and for a meter recorded from code
  /// outside [backendDir] (`DV-METER-001`), naming each file and line.
  static Future<void> generate({
    required String root,
    required String pkgName,
    required String backendDir,
  }) async {
    final List<DiscoveredMeter> meters = await discover(root: root);
    final List<String> clientRecordings =
        await _clientRecordings(root, backendDir, meters);
    if (clientRecordings.isNotEmpty) {
      throw StateError(
        'DV-METER-001: a meter is recorded from client-reachable code. A '
        'usage number the client reports is a number the customer controls; '
        'record it in a backend function, which already sees the call:\n'
        '${clientRecordings.map((String line) => '  $line').join('\n')}',
      );
    }
    final File output =
        File(p.join(root, 'lib', 'dartvel_client', 'meters.g.dart'));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(_render(meters));
  }

  /// Every meter declared in the project under [root], without writing
  /// anything: what [generate] writes and what `dartvel meters list` prints.
  static Future<List<DiscoveredMeter>> discover({required String root}) async {
    final List<DiscoveredMeter> meters = <DiscoveredMeter>[];
    for (final File file in _dartFiles(root)) {
      final String source = await file.readAsString();
      if (!source.contains('@DVMeter')) continue;
      final String relative =
          p.relative(file.path, from: root).replaceAll('\\', '/');
      _collect(source, relative, meters);
    }
    final Set<String> seen = <String>{};
    for (final DiscoveredMeter meter in meters) {
      if (!seen.add(meter.name)) {
        throw StateError(
          'meter "${meter.name}" is declared twice; usage recorded under the '
          'name could not say which one it is',
        );
      }
    }
    return meters;
  }

  static void _collect(
      String source, String path, List<DiscoveredMeter> into) {
    final DVDartSourceView view = dvDartSourceView(source);
    final RegExp annotation = RegExp(r'@DVMeter\s*\(');
    for (final RegExpMatch match in annotation.allMatches(view.masked)) {
      final String rest = source.substring(match.start);
      final String? args = dvAnnotationArgs(rest, 'DVMeter');
      final int line = dvDartLineOf(source, match.start);
      if (args == null) {
        throw StateError('$path:$line: an @DVMeter annotation is not closed');
      }
      final int argsEnd = rest.indexOf(args) + args.length + 1;
      final RegExpMatch? field =
          _fieldRegex.firstMatch(rest.substring(argsEnd));
      if (field == null) {
        throw StateError(
          '$path:$line: @DVMeter must mark `static const name = '
          'DVMeter.counter;` or `DVMeter.gauge`',
        );
      }
      final String name = field.group(1)!;

      final Iterable<RegExpMatch> classes =
          _classBefore.allMatches(view.masked.substring(0, match.start));
      final String? owner = classes.isEmpty ? null : classes.last.group(1);
      if (owner == null || !owner.startsWith('_')) {
        throw StateError(
          '$path:$line: meter "$name" is declared in '
          '${owner == null ? 'no class' : 'public class "$owner"'}. Declare '
          'it in a private class (`_$owner`); Dartvel generation inputs are '
          'private, and application code records through the generated '
          '`Meters`',
        );
      }

      final Map<String, String> named = _namedArgs(args);
      final String? unit = _stringLiteral(named['unit']);
      if (unit == null || unit.isEmpty) {
        throw StateError('$path:$line: meter "$name" has no `unit:`');
      }
      if (named.containsKey('limit') && !named.containsKey('atLimit')) {
        throw StateError(
          'DV-METER-005: $path:$line: meter "$name" declares a limit and no '
          'behaviour at the limit. Add atLimit: DVQuota.block, '
          'DVQuota.throttle or DVQuota.allowAndBill -- there is no default, '
          "because each is somebody's correct answer",
        );
      }

      into.add(DiscoveredMeter(
        name: name,
        kind: field.group(2)!,
        arguments: args.trim(),
        unit: unit,
        doc: _docBefore(source, match.start),
        file: path,
        named: named,
      ));
    }
  }

  /// Recordings in code the client bundle can reach: `lib/` minus the
  /// backend directory and generated output. Read with the lexer, so a
  /// recording in a string or a comment is not one.
  static Future<List<String>> _clientRecordings(
    String root,
    String backendDir,
    List<DiscoveredMeter> meters,
  ) async {
    final String backend =
        '${backendDir.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '')}/';
    final Set<String> names = <String>{
      for (final DiscoveredMeter meter in meters) meter.name,
    };
    final RegExp generated =
        RegExp(r'\bMeters\s*\.\s*([A-Za-z0-9_]+)\s*\.\s*record\s*\(');
    final RegExp direct =
        RegExp(r'\bDVMeters\s*\.\s*current\s*\.\s*record\s*\(');
    final List<String> found = <String>[];
    for (final File file in _dartFiles(root)) {
      final String relative =
          p.relative(file.path, from: root).replaceAll('\\', '/');
      if (relative.startsWith(backend)) continue;
      final String source = await file.readAsString();
      if (!source.contains('record')) continue;
      final String masked = dvDartSourceView(source).masked;
      for (final RegExpMatch match in generated.allMatches(masked)) {
        final String name = match.group(1)!;
        if (!names.contains(name)) continue;
        found.add('$relative:${dvDartLineOf(source, match.start)}: '
            'Meters.$name.record');
      }
      for (final RegExpMatch match in direct.allMatches(masked)) {
        found.add('$relative:${dvDartLineOf(source, match.start)}: '
            'DVMeters.current.record');
      }
    }
    return found;
  }

  static String _render(List<DiscoveredMeter> meters) {
    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: unused_import, unnecessary_import')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln()
      ..writeln('/// The meters this build declares, generated from `@DVMeter`.')
      ..writeln('///')
      ..writeln('/// Record from backend code: `Meters.apiCalls.record(1)`. The '
          'tenant is')
      ..writeln('/// the current one and the idempotency key the request\'s or '
          'job\'s.')
      ..writeln('abstract final class Meters {');
    for (final DiscoveredMeter meter in meters) {
      for (final String line in meter.doc) {
        sb.writeln('  $line');
      }
      sb
        ..writeln('  static final DVMeterDefinition ${meter.name} =')
        ..writeln('      const DVMeter(${meter.arguments})')
        ..writeln("          .definition('${meter.name}', "
            'kind: DVMeterKind.${meter.kind});')
        ..writeln();
    }
    sb
      ..writeln('  /// Every meter above, for the period close and '
          '`dartvel meters`.')
      ..writeln('  static final List<DVMeterDefinition> all = '
          '<DVMeterDefinition>[');
    for (final DiscoveredMeter meter in meters) {
      sb.writeln('    ${meter.name},');
    }
    sb
      ..writeln('  ];')
      ..writeln('}');
    return sb.toString();
  }

  /// The `///` lines immediately above [offset], in order.
  static List<String> _docBefore(String source, int offset) {
    final List<String> lines = source.substring(0, offset).split('\n');
    final List<String> doc = <String>[];
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
