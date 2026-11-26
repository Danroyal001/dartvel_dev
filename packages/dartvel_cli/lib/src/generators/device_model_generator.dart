/// Models kept on the visitor's device:
/// `@DVModel(storage: DVModelStorage.device)`.
///
/// A settings object -- a text size, where voice mode sits, a voice
/// language -- is a model like any other: its fields, defaults and types are
/// declared once on a private primary-constructor class, and the generator
/// writes the public value class with equality, `copyWith` and a JSON codec.
/// What differs is where it lives: in `DVPreferenceStore` (`localStorage` in
/// a browser, a small file on a device), read before the first frame, with no
/// table, page, admin or sync.
///
/// A device model is declared anywhere under `lib/` except `lib/models/`.
/// Every database scanner (tables, migrations, admin, Studio, OpenAPI, pages)
/// reads `lib/models/`, and a settings object in there would be given a table
/// it never uses; one declared there is refused, naming the file.
///
/// The framework keeps its own settings the same way:
/// [dvFrameworkDeviceModels] lists its inputs, `tool/generate_framework_models.dart`
/// writes them, and a test fails when a checked-in output drifts.
library;

import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'annotation_args.dart';
import 'model_field_defaults.dart';
import 'model_generator.dart' show dvStudioEnumValues;
import 'primary_constructors.dart';

/// Whether the arguments of a `@DVModel(...)` ask for the device.
bool dvIsDeviceModelArgs(String args) =>
    RegExp(r'\bstorage\s*:\s*(?:DVModelStorage)?\.device\b').hasMatch(args);

const Set<String> _scalars = <String>{'String', 'bool', 'int', 'double', 'num', 'DateTime'};

final RegExp _modelPattern = RegExp(
  r'@DVModel\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
  dotAll: true,
);

/// The device models declared in [source], as generated code: the enums the
/// file declares (copied, as for database models), then each model's class
/// and parser. [classNames] receives the public name of each. Empty when the
/// file declares none.
String dvDeviceModelClasses(
  String source, {
  required String defaultKeyPrefix,
  String path = '',
  List<String>? classNames,
}) {
  final String content = dvDesugarPrimaryConstructors(source);
  final String masked = dvMaskAnnotationArgs(content, 'DVModel');
  final Map<String, List<String>> enums = dvStudioEnumValues(content);
  final StringBuffer out = StringBuffer();
  bool any = false;
  for (final RegExpMatch match in _modelPattern.allMatches(masked)) {
    final String args = dvAnnotationArgs(content.substring(match.start), 'DVModel') ?? '';
    if (!dvIsDeviceModelArgs(args)) continue;
    final String sourceName = match.group(2)!;
    if (!sourceName.startsWith('_')) {
      throw StateError('Dartvel: $sourceName${path.isEmpty ? '' : ' in $path'}: a model input must be private. '
          'Rename it _$sourceName and use the generated $sourceName.');
    }
    if (!any) {
      for (final String declaration in dvModelEnumDeclarations(source)) {
        final String enumName = RegExp(r'enum\s+([A-Za-z_$][\w$]*)').firstMatch(declaration)!.group(1)!;
        final String doc = _docOf(source, enumName, keyword: 'enum');
        out
          ..write(doc.isEmpty ? '' : doc.substring(0, doc.length - '///\n'.length))
          ..writeln(declaration)
          ..writeln();
      }
      any = true;
    }
    final String name = sourceName.substring(1);
    final String key = RegExp(r'''\bstorageKey\s*:\s*['"]([^'"]+)['"]''').firstMatch(args)?.group(1) ??
        '$defaultKeyPrefix.$name';
    final List<_Field> fields = <_Field>[
      for (final Map<String, String> field in dvModelFields(content, sourceName))
        _Field.read(name, field, enums.keys.toSet()),
    ];
    classNames?.add(name);
    _writeModel(out, name, key, fields, _docOf(source, sourceName));
  }
  return out.toString();
}

/// One file's device models as a complete library: [header] (the imports;
/// the body uses `convert.`, `DV` and `DVPreferenceStore`), then the classes.
String dvDeviceModelLibrary(String source, {required String defaultKeyPrefix, required String header, String path = ''}) =>
    '$header${dvDeviceModelClasses(source, defaultKeyPrefix: defaultKeyPrefix, path: path)}';

/// A device model the framework itself declares, and where its generated
/// code is checked in.
final class DVFrameworkDeviceModel {
  const DVFrameworkDeviceModel(this.input, this.output);

  /// The annotated input, from the repository root.
  final String input;

  /// The generated library beside it.
  final String output;
}

/// The framework's own device models.
const List<DVFrameworkDeviceModel> dvFrameworkDeviceModels = <DVFrameworkDeviceModel>[
  DVFrameworkDeviceModel(
    'packages/dartvel_flutter/lib/src/accessibility/accessibility_settings.dart',
    'packages/dartvel_flutter/lib/src/accessibility/accessibility_settings.g.dart',
  ),
  DVFrameworkDeviceModel(
    'packages/dartvel_flutter/lib/src/accessibility/voice_settings.dart',
    'packages/dartvel_flutter/lib/src/accessibility/voice_settings.g.dart',
  ),
  DVFrameworkDeviceModel(
    'packages/dartvel_flutter/lib/src/accessibility/former_settings.dart',
    'packages/dartvel_flutter/lib/src/accessibility/former_settings.g.dart',
  ),
];

/// The generated library for a framework device model whose input is [source].
String dvFrameworkDeviceModelSource(DVFrameworkDeviceModel model, String source) {
  final String inputName = p.basename(model.input);
  return dvDeviceModelLibrary(
    source,
    defaultKeyPrefix: 'dartvel',
    path: model.input,
    header: '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// Generated from $inputName by tool/generate_framework_models.dart, with the\n'
        '// same emitter as an application\'s @DVModel(storage: DVModelStorage.device).\n'
        '// ignore_for_file: directives_ordering, unused_element\n'
        "import 'dart:convert' as convert;\n"
        '\n'
        "import '../../dartvel_flutter.dart' show DV;\n"
        "import '../platform/storage/preference_store.dart';\n"
        '\n',
  );
}

/// Application device models: every `@DVModel(storage: DVModelStorage.device)`
/// under `lib/` outside `lib/models/` and the generated client, written to
/// `lib/dartvel_client/device_models.g.dart` with
/// `registerDartvelDeviceModels()`, which the runtime calls before the first
/// frame so `context.global<Model>()` works with no application code.
abstract final class DeviceModelGenerator {
  static Future<List<String>> generate({required String root, required String pkgName}) async {
    final List<File> files = <File>[];
    if (Directory(p.join(root, 'lib')).existsSync()) {
      for (final FileSystemEntity entity
          in Glob('lib/**.dart').listFileSystemSync(const LocalFileSystem(), root: root, followLinks: false)) {
        if (entity is! File) continue;
        final String rel = p.relative(entity.path, from: root).replaceAll(r'\', '/');
        if (rel.startsWith('lib/models/') || rel.startsWith('lib/dartvel_client/') || rel.endsWith('.g.dart')) continue;
        files.add(File(entity.path));
      }
    }
    files.sort((File a, File b) => a.path.compareTo(b.path));
    final List<String> names = <String>[];
    final StringBuffer body = StringBuffer();
    for (final File file in files) {
      final String text = file.readAsStringSync();
      if (!text.contains('@DVModel')) continue;
      body.write(dvDeviceModelClasses(text,
          defaultKeyPrefix: pkgName, path: p.relative(file.path, from: root), classNames: names));
    }
    final StringBuffer out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: directives_ordering, unused_element, unused_import')
      ..writeln('/// Models kept on the visitor\'s device: @DVModel(storage: DVModelStorage.device).')
      ..writeln('library dartvel_client_device_models;')
      ..writeln()
      ..writeln("import 'dart:convert' as convert;")
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln("import 'package:dartvel_flutter/dartvel_flutter.dart' show DV, DVPreferenceStore;")
      ..writeln()
      ..write(body);
    if (names.isEmpty) {
      out.writeln('/// This application declares no device models; the runtime calls this');
      out.writeln('/// unconditionally.');
      out.writeln('void registerDartvelDeviceModels() {}');
    } else {
      out.writeln('/// Reads every device model before the first frame, so');
      out.writeln('/// `context.global<Model>()` has its value from the start.');
      out.writeln('void registerDartvelDeviceModels() {');
      for (final String name in names) {
        out.writeln('  $name.kept;');
      }
      out.writeln('}');
    }
    final Directory client = Directory(p.join(root, 'lib', 'dartvel_client'))..createSync(recursive: true);
    File(p.join(client.path, 'device_models.g.dart')).writeAsStringSync(out.toString());
    return names;
  }
}

final class _Field {
  _Field(this.name, this.type, this.base, this.nullable, this.defaultValue, this.isEnum);

  factory _Field.read(String model, Map<String, String> field, Set<String> enums) {
    final String type = field['type']!.replaceAll(RegExp(r'\s+'), '');
    final String name = field['name']!;
    final bool nullable = type.endsWith('?');
    final String base = nullable ? type.substring(0, type.length - 1) : type;
    final bool isEnum = enums.contains(base);
    if (!isEnum && !_scalars.contains(base)) {
      throw StateError('Dartvel: $model.$name is a $type, which a model kept on the device cannot hold. '
          'Use String, bool, int, double, num, DateTime or an enum declared in the same file (nullable or not).');
    }
    final String? defaultValue = field['default']?.trim();
    if (!nullable && (defaultValue == null || defaultValue.isEmpty)) {
      throw StateError('Dartvel: $model.$name has no default. A model kept on the device starts from its '
          'defaults before anything is kept, so every field that is not nullable needs one: '
          'final $type $name = ...');
    }
    return _Field(name, type, base, nullable, defaultValue, isEnum);
  }

  final String name;
  final String type;
  final String base;
  final bool nullable;
  final String? defaultValue;
  final bool isEnum;

  String get parameter => defaultValue == null ? 'final $type $name,' : 'final $type $name = $defaultValue,';

  String get json {
    final String access = nullable ? '$name?' : name;
    if (isEnum) return "'$name': $access.name";
    if (base == 'DateTime') return "'$name': $access.toIso8601String()";
    return "'$name': $name";
  }

  /// [raw] read back as this field's type, or its default.
  String read(String raw) {
    final String fallback = 'defaults.$name';
    return switch (base) {
      'double' => '$raw is num ? $raw.toDouble() : $fallback',
      'DateTime' => '$raw is String ? (DateTime.tryParse($raw) ?? $fallback) : $fallback',
      _ when isEnum => '$raw is String ? ($base.values.asNameMap()[$raw] ?? $fallback) : $fallback',
      _ => '$raw is $base ? $raw : $fallback',
    };
  }
}

String _docOf(String source, String sourceName, {String keyword = 'class'}) {
  final int at = source.indexOf(RegExp('$keyword\\s+(const\\s+)?${RegExp.escape(sourceName)}\\b'));
  if (at < 0) return '';
  final List<String> before = source.substring(0, at).split('\n');
  final List<String> doc = <String>[];
  for (int i = before.length - 2; i >= 0; i--) {
    final String line = before[i].trim();
    if (line.startsWith('///')) {
      doc.insert(0, line);
    } else if (line.startsWith('@') || line.isEmpty && doc.isEmpty) {
      continue;
    } else {
      break;
    }
  }
  return doc.isEmpty ? '' : '${doc.join('\n')}\n///\n';
}

void _writeModel(StringBuffer out, String name, String key, List<_Field> fields, String doc) {
  final bool constant = fields.every((_Field f) => f.base != 'DateTime' || f.defaultValue == null);
  out
    ..write(doc)
    ..writeln('/// Kept on the visitor\'s device under `$key`: read it with [kept] (or')
    ..writeln('/// `context.global<$name>()` in a widget, which rebuilds on a change) and')
    ..writeln('/// write it with [keep].')
    ..writeln('class ${constant ? 'const ' : ''}$name({');
  for (final _Field field in fields) {
    out.writeln('  ${field.parameter}');
  }
  out
    ..writeln('}) {')
    ..writeln('  /// Where it is kept in [DVPreferenceStore].')
    ..writeln("  static const String storageKey = '$key';")
    ..writeln()
    ..writeln('  /// Every field at its default: what a visitor has before keeping anything.')
    ..writeln('  static ${constant ? 'const' : 'final'} $name defaults = $name();')
    ..writeln()
    ..writeln('  static bool _dvRegistered = false;')
    ..writeln()
    ..writeln('  /// The value kept on this device, or [defaults]. Read once, then from')
    ..writeln('  /// `DV.global<$name>()`, which [keep] and [forget] update.')
    ..writeln('  static $name get kept {')
    ..writeln('    if (!_dvRegistered) {')
    ..writeln('      _dvRegistered = true;')
    ..writeln('      DV.global<$name>(decode(DVPreferenceStore.instance.read(storageKey)));')
    ..writeln('    }')
    ..writeln('    return DV.global<$name>();')
    ..writeln('  }')
    ..writeln()
    ..writeln('  /// Whether anything is kept on this device yet.')
    ..writeln('  static bool get isKept => DVPreferenceStore.instance.read(storageKey) != null;')
    ..writeln()
    ..writeln('  /// Keeps this value for the next visit and makes it [kept], rebuilding')
    ..writeln('  /// every widget that reads `context.global<$name>()`.')
    ..writeln('  $name keep() {')
    ..writeln('    DVPreferenceStore.instance.write(storageKey, encode());')
    ..writeln('    _dvRegistered = true;')
    ..writeln('    DV.global<$name>(this);')
    ..writeln('    return this;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  /// Forgets what this device kept: [kept] is [defaults] again.')
    ..writeln('  static void forget() {')
    ..writeln('    DVPreferenceStore.instance.remove(storageKey);')
    ..writeln('    _dvRegistered = true;')
    ..writeln('    DV.global<$name>(defaults);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  /// The value in [stored] (what [encode] wrote). Missing, unreadable or')
    ..writeln('  /// wrong-typed fields are their defaults, so an old or broken value never')
    ..writeln('  /// stops a page.')
    ..writeln('  static $name decode(String? stored) {')
    ..writeln('    if (stored == null || stored.isEmpty) return defaults;')
    ..writeln('    final Object? decoded;')
    ..writeln('    try {')
    ..writeln('      decoded = convert.jsonDecode(stored);')
    ..writeln('    } on FormatException {')
    ..writeln('      return defaults;')
    ..writeln('    }')
    ..writeln('    if (decoded is! Map<String, Object?>) return defaults;')
    ..writeln('    return ${name}Parser.fromJson(decoded);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  /// The stored form: JSON text.')
    ..writeln('  String encode() => convert.jsonEncode(toJson());')
    ..writeln()
    ..writeln('  /// This value as JSON.')
    ..writeln('  Map<String, Object?> toJson() => <String, Object?>{');
  for (final _Field field in fields) {
    out.writeln('        ${field.json},');
  }
  out
    ..writeln('      };')
    ..writeln()
    ..writeln('  /// A copy with the given fields replaced.')
    ..writeln('  $name copyWith({${fields.map((_Field f) => '${f.base}? ${f.name}').join(', ')}}) => $name(');
  for (final _Field field in fields) {
    out.writeln('        ${field.name}: ${field.name} ?? this.${field.name},');
  }
  out
    ..writeln('      );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  bool operator ==(Object other) =>')
    ..writeln('      other is $name${fields.map((_Field f) => ' && other.${f.name} == ${f.name}').join()};')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  int get hashCode => Object.hashAll(<Object?>[${fields.map((_Field f) => f.name).join(', ')}]);')
    ..writeln()
    ..writeln('  @override')
    ..writeln("  String toString() => '$name(${fields.map((_Field f) => '${f.name}: \$${f.name}').join(', ')})';")
    ..writeln('}')
    ..writeln()
    ..writeln('/// Reads a [$name] from JSON.')
    ..writeln('class ${name}Parser {')
    ..writeln('  /// [json] as a [$name]: a field that is missing or of the wrong type is')
    ..writeln('  /// its default, and keys it does not know are ignored.')
    ..writeln('  static $name fromJson(Map<String, Object?> json) {')
    ..writeln('    ${constant ? 'const' : 'final'} $name defaults = $name.defaults;');
  for (final _Field field in fields) {
    out.writeln("    final Object? ${field.name} = json['${field.name}'];");
  }
  out.writeln('    return $name(');
  for (final _Field field in fields) {
    out.writeln('      ${field.name}: ${field.read(field.name)},');
  }
  out
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}
