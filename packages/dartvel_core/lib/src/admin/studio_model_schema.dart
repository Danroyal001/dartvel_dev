/// A data model's definition, as Studio designs one.
///
/// A model is described by one [DVStudioModelSpec] wherever it came from.
/// The generator writes one for every `@DVModel` it compiles; Studio stores
/// one for every model somebody designs there, in the application's own
/// database, and serves its records without a rebuild. Writing a stored
/// model out to source produces the `@DVModel` that compiles back to the
/// same spec -- the same table, key, fields and rules -- so moving a model
/// from Studio into code keeps its records where they are.
library;

import '../annotations/model_access.dart';
import '../database/records.dart';
import 'studio_api.dart';

/// The collection model definitions designed in Studio are kept in.
const String dvStudioModelsTable = 'dartvel_models';

/// A stored model definition: its name, and the spec as JSON.
const DVRecordShape dvStudioModelsShape = DVRecordShape(
  collection: dvStudioModelsTable,
  key: 'name',
  fields: <String, DVFieldType>{
    'name': DVFieldType.text,
    'document': DVFieldType.text,
  },
);

/// The first line of a model file Studio wrote. Studio rewrites a file that
/// still starts with it, and leaves any other file alone: a model somebody
/// has taken over by hand is theirs.
const String dvStudioModelSourceMarker =
    '// Written by Dartvel Studio from the data model it stores.';

/// The value types a field designed in Studio can hold.
///
/// The ones the record layer stores and the Studio form edits, and nothing
/// that would compile to a type the generated model cannot read back.
const List<String> dvStudioFieldTypes = <String>[
  'String',
  'int',
  'double',
  'bool',
  'DateTime',
  'List<String>',
  'Map<String, Object?>',
];

/// The table the generator gives a model named [model]: `Article` is
/// `articles`. A model designed in Studio uses the same one, so the model it
/// is written out to reads the records it already has.
String dvStudioTableFor(String model) => '${model.toLowerCase()}s';

/// `ArticleTag` is `article_tag`: the file a model is written to.
String dvStudioSnakeCase(String name) => name
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (Match m) => '${m[1]}_${m[2]}',
    )
    .toLowerCase();

final RegExp _modelName = RegExp(r'^[A-Z][A-Za-z0-9]{0,63}$');
final RegExp _fieldName = RegExp(r'^[a-z][A-Za-z0-9]{0,63}$');

/// Names a field cannot take: Dart keywords a generated model would not
/// compile with, and the columns the record layer keeps for itself.
const Set<String> _reservedFieldNames = <String>{
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
  'class', 'const', 'continue', 'default', 'deferred', 'do', 'dynamic',
  'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory',
  'false', 'final', 'finally', 'for', 'get', 'if', 'implements', 'import',
  'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null', 'of',
  'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set',
  'static', 'super', 'switch', 'this', 'throw', 'true', 'try', 'type',
  'typedef', 'var', 'void', 'when', 'while', 'with', 'yield', 'hashCode',
  'runtimeType', 'toString', 'noSuchMethod', 'version', 'deleted',
};

/// Model names a definition cannot take, because the framework or Flutter
/// already means something by them.
const Set<String> _reservedModelNames = <String>{
  'DV', 'Object', 'String', 'List', 'Map', 'Set', 'Widget', 'State',
  'Page', 'Route', 'Model', 'Record', 'Type', 'Function', 'Future',
  'Stream', 'Iterable', 'Null', 'Never', 'Enum',
};

/// The base type of a field type, with no `?`.
String dvStudioBaseType(String type) => type.replaceAll('?', '').trim();

/// Why [spec] cannot be stored as a model designed in Studio, or an empty
/// list when it can. [others] is every other model the application has, by
/// the name Studio lists it under.
List<String> dvStudioDefinitionProblems(
  DVStudioModelSpec spec, {
  required Map<String, DVStudioModelSpec> others,
}) {
  final List<String> problems = <String>[];
  final String name = spec.model;
  if (!_modelName.hasMatch(name)) {
    problems.add(
      'A data model is named in PascalCase, starting with a capital letter: '
      'Article, BlogPost.',
    );
  } else if (_reservedModelNames.contains(name) || name.startsWith('DV')) {
    problems.add('$name is a name Dartvel already uses. Choose another.');
  }
  if (spec.table != dvStudioTableFor(name)) {
    problems.add('$name keeps its records in ${dvStudioTableFor(name)}.');
  }
  if (spec.fields.isEmpty) {
    problems.add('A data model needs at least one field.');
  }
  final Set<String> seen = <String>{};
  for (final DVStudioFieldSpec field in spec.fields) {
    final String label = field.name.isEmpty ? 'A field' : field.name;
    if (!_fieldName.hasMatch(field.name)) {
      problems.add(
        '$label: a field is named in camelCase, starting with a lowercase '
        'letter: title, publishedAt.',
      );
    } else if (_reservedFieldNames.contains(field.name)) {
      problems.add('${field.name} is a word Dart or Dartvel keeps for itself.');
    }
    if (!seen.add(field.name)) {
      problems.add('There are two fields named ${field.name}.');
    }
    final String base = dvStudioBaseType(field.type);
    final List<String>? options = field.options;
    if (options != null) {
      if (!_modelName.hasMatch(base) || base == name) {
        problems.add(
          '$label: a field with choices names its choice type in PascalCase, '
          'as ${name}Status.',
        );
      }
      if (options.isEmpty) problems.add('$label: list at least one choice.');
      for (final String option in options) {
        if (!_fieldName.hasMatch(option) ||
            _reservedFieldNames.contains(option)) {
          problems.add(
            '$label: the choice "$option" has to be one camelCase word, '
            'as draft or inReview.',
          );
        }
      }
      if (options.toSet().length != options.length) {
        problems.add('$label lists the same choice twice.');
      }
    } else if (!dvStudioFieldTypes.contains(base)) {
      problems.add(
        '$label: ${field.type} is not a type Studio can store. Choose one of '
        '${dvStudioFieldTypes.join(', ')}.',
      );
    }
    final String? relation = field.relation;
    if (relation != null) {
      final DVStudioModelSpec? target =
          relation == name ? spec : others[relation];
      if (target == null) {
        problems.add('$label refers to $relation, and there is no such model.');
      } else {
        if (base != 'String' && base != 'int') {
          problems.add('$label holds a key of $relation, so it is a String.');
        }
        // The generator finds a relation by its name, `authorId` holding an
        // Author's id, so a model written out keeps its relations only if
        // the field is named that way.
        final String stem = '${relation[0].toLowerCase()}${relation.substring(1)}';
        if (!RegExp('^$stem(Id|Slug|Key)\$').hasMatch(field.name)) {
          problems.add(
            '$label refers to $relation, so it is named ${stem}Id, '
            '${stem}Slug or ${stem}Key.',
          );
        }
      }
    }
    if (field.sensitive) {
      problems.add(
        '$label: a sensitive field is declared in code, where its encryption '
        'and who may read it are decided.',
      );
    }
    if (field.min != null && field.max != null && field.min! > field.max!) {
      problems.add('$label: the smallest value is larger than the largest.');
    }
    if (field.minLength != null &&
        field.maxLength != null &&
        field.minLength! > field.maxLength!) {
      problems.add('$label: the shortest length is longer than the longest.');
    }
    if ((field.min != null || field.max != null) &&
        !const <String>{'int', 'double', 'num'}.contains(base)) {
      problems.add('$label: only a number has a smallest or largest value.');
    }
    if ((field.minLength != null ||
            field.maxLength != null ||
            field.pattern != null) &&
        base != 'String') {
      problems.add('$label: only text has a length or a pattern.');
    }
    if (field.pattern != null) {
      final String pattern = field.pattern!;
      try {
        RegExp(pattern);
      } on FormatException catch (error) {
        problems.add('$label: the pattern is not valid: ${error.message}');
      }
      // A pattern is run against whatever a caller of the data API sends.
      // One that repeats a repetition -- (a+)+ -- can take the server
      // exponential time on a string built to make it, so it is refused
      // here rather than discovered there.
      if (pattern.length > dvStudioPatternLimit) {
        problems.add(
          '$label: a pattern is at most $dvStudioPatternLimit characters.',
        );
      } else if (_nestedRepeat.hasMatch(pattern)) {
        problems.add(
          '$label: the pattern repeats something that already repeats, which '
          'can take the server a very long time to check. Simplify it.',
        );
      }
    }
  }
  final DVStudioFieldSpec? key =
      spec.fields.where((DVStudioFieldSpec f) => f.name == spec.key).firstOrNull;
  if (key == null) {
    problems.add('The key, ${spec.key}, has to be one of the fields.');
  } else {
    if (key.type != 'String') {
      problems.add(
        'The key, ${key.name}, is a String that is never empty: records are '
        'found by it.',
      );
    }
    // The key the generator would choose, so the model written out finds its
    // records by the same field.
    final List<String> texts = <String>[
      for (final DVStudioFieldSpec f in spec.fields)
        if (f.type == 'String') f.name,
    ];
    final String? generated = texts.contains('slug')
        ? 'slug'
        : texts.contains('id')
            ? 'id'
            : texts.firstOrNull;
    if (generated != null && generated != spec.key && key.type == 'String') {
      problems.add(
        'A model with a $generated field is found by its $generated. Make '
        '$generated the key, or rename it.',
      );
    }
  }
  for (final DVStudioIndexSpec index in spec.indexes) {
    if (index.fields.isEmpty) problems.add('An index names no field.');
    for (final String field in index.fields) {
      if (!seen.contains(field)) {
        problems.add('An index names $field, which is not a field.');
      }
    }
  }
  return problems;
}

/// The longest pattern a field designed in Studio may have.
const int dvStudioPatternLimit = 200;

/// The longest text a pattern is run against.
const int dvStudioPatternInputLimit = 10000;

/// A group holding a repetition, itself repeated: `(a+)+`, `(\w*)*`,
/// `(x+){2,}`.
final RegExp _nestedRepeat = RegExp(r'\([^()]*[+*][^()]*\)\s*[+*{]');

/// Why [value] breaks [field]'s rules, or null. [value] is what the record
/// layer stores: text as text, a number as a number.
String? dvStudioValueProblem(DVStudioFieldSpec field, Object? value) {
  if (value == null) return null;
  final String label = field.name;
  if (field.min != null || field.max != null) {
    final num? number = value is num ? value : num.tryParse('$value');
    if (number != null) {
      if (field.min != null && number < field.min!) {
        return '$label has to be at least ${_number(field.min!)}.';
      }
      if (field.max != null && number > field.max!) {
        return '$label has to be at most ${_number(field.max!)}.';
      }
    }
  }
  if (value is String) {
    final int length = value.runes.length;
    if (field.minLength != null && length < field.minLength!) {
      return '$label has to be at least ${field.minLength} characters.';
    }
    if (field.maxLength != null && length > field.maxLength!) {
      return '$label has to be at most ${field.maxLength} characters.';
    }
    final String? pattern = field.pattern;
    if (pattern != null && value.length > dvStudioPatternInputLimit) {
      return '$label is too long to check against its pattern.';
    }
    if (pattern != null) {
      final RegExp? expression = _pattern(pattern);
      if (expression != null) {
        final RegExpMatch? match = expression.firstMatch(value);
        if (match == null || match.start != 0 || match.end != value.length) {
          return '$label does not match the pattern $pattern.';
        }
      }
    }
  }
  return null;
}

RegExp? _pattern(String pattern) {
  try {
    return RegExp(pattern);
  } on FormatException {
    return null;
  }
}

String _number(num value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';

/// Every index [spec] asks for: each unique field on its own, then its
/// declared indexes. Named for the table and fields, so asking twice is
/// asking for the same index.
List<({String name, List<String> fields, bool unique})> dvStudioIndexesOf(
  DVStudioModelSpec spec,
) =>
    <({String name, List<String> fields, bool unique})>[
      for (final DVStudioFieldSpec field in spec.fields)
        if (field.unique && field.name != spec.key)
          (
            name: '${spec.table}_${field.name}_unique',
            fields: <String>[field.name],
            unique: true,
          ),
      for (final DVStudioIndexSpec index in spec.indexes)
        (
          name: '${spec.table}_${index.fields.join('_')}_${index.unique ? 'unique' : 'idx'}',
          fields: index.fields,
          unique: index.unique,
        ),
    ];

/// The `@DVModel` [spec] compiles back from, as a file in `lib/models`.
///
/// Every rule the definition carries is written as the annotation that
/// declares it, so the generator reads the same spec back: the key first,
/// choices as an enum, validation as `@DVModel.validate`, uniqueness as
/// `@DVModel.uniqueField`, indexes and access on the model.
String dvStudioModelDartSource(DVStudioModelSpec spec) {
  String quote(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
  final StringBuffer out = StringBuffer()
    ..writeln(dvStudioModelSourceMarker)
    ..writeln('// Studio rewrites this file while that line is first. Delete the')
    ..writeln('// line to take the model over by hand; Studio then leaves it be.')
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln();
  final Set<String> enums = <String>{};
  for (final DVStudioFieldSpec field in spec.fields) {
    final List<String>? options = field.options;
    if (options == null) continue;
    final String type = dvStudioBaseType(field.type);
    if (!enums.add(type)) continue;
    out
      ..writeln('enum $type { ${options.join(', ')} }')
      ..writeln();
  }
  final List<String> arguments = <String>[
    // A designed model has no page of its own until one is designed for it.
    'generatePublicPages: false',
    if (!spec.versioned) 'version: false',
    if (spec.softDelete) 'softDelete: true',
    if (spec.access case final DVModelAccess access)
      'access: DVModelAccess('
          'view: DVAccess.${access.view.name}, '
          'create: DVAccess.${access.create.name}, '
          'update: DVAccess.${access.update.name}, '
          'delete: DVAccess.${access.delete.name})',
    if (spec.indexes.isNotEmpty)
      'indexes: <DVIndex>[${<String>[
        for (final DVStudioIndexSpec index in spec.indexes)
          'DVIndex(<String>[${index.fields.map(quote).join(', ')}]'
              '${index.unique ? ', unique: true' : ''})',
      ].join(', ')}]',
  ];
  out
    ..writeln('@DVModel(')
    ..writeln(<String>[for (final String a in arguments) '  $a,'].join('\n'))
    ..writeln(')')
    ..writeln("@pragma('vm:entry-point')")
    ..writeln('class const _${spec.model}({');
  final List<DVStudioFieldSpec> ordered = <DVStudioFieldSpec>[
    ...spec.fields.where((DVStudioFieldSpec f) => f.name == spec.key),
    ...spec.fields.where((DVStudioFieldSpec f) => f.name != spec.key),
  ];
  for (final DVStudioFieldSpec field in ordered) {
    final List<String> rules = <String>[
      if (field.min != null) 'min: ${_number(field.min!)}',
      if (field.max != null) 'max: ${_number(field.max!)}',
      if (field.minLength != null) 'minLength: ${field.minLength}',
      if (field.maxLength != null) 'maxLength: ${field.maxLength}',
      if (field.pattern != null) 'pattern: ${quote(field.pattern!)}',
    ];
    if (field.unique) out.writeln('  @DVModel.uniqueField()');
    if (rules.isNotEmpty) {
      out.writeln('  @DVModel.validate(${rules.join(', ')})');
    }
    final String type = field.type;
    out.writeln(
      field.nullable
          ? '  final $type ${field.name},'
          : '  required final $type ${field.name},',
    );
  }
  out.writeln('});');
  return out.toString();
}

/// A value a data model's rules refuse: the model, the field and why.
class DVModelRuleError implements Exception {
  const DVModelRuleError(this.model, this.field, this.message);

  final String model;
  final String field;

  /// Said as Studio says it: `title has to be at least 3 characters.`
  final String message;

  @override
  String toString() => '$model: $message';
}

/// Refuses [values] that break a rule of [fields] with a [DVModelRuleError].
///
/// What a generated model's `save()` asks before it writes, so a record
/// saved in code meets the same rules as one written through Studio or the
/// data API. Uniqueness is the database's to hold, through the index the
/// field asks for, and Studio's write checks it too.
void dvCheckModelRules(
  String model,
  List<DVStudioFieldSpec> fields,
  Map<String, Object?> values,
) {
  for (final DVStudioFieldSpec field in fields) {
    final String? problem = dvStudioValueProblem(field, values[field.name]);
    if (problem != null) throw DVModelRuleError(model, field.name, problem);
  }
}
