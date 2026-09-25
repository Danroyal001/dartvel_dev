import 'dart:io';

// The record layer is the framework's, not an application's.
import 'package:dartvel_core/framework.dart' show DVRecordTable;
import 'package:dartvel_core/dartvel.dart'
    show
        DVDatabaseAdapter,
        DVHistory,
        DVLogLevel,
        DVPrivacy,
        DVPrivacyFinding,
        DVPrivacyModel,
        DVRetain,
        DVRetention,
        DVRetentionAction,
        DVSubject,
        MemoryDVDatabaseAdapter;
import 'package:path/path.dart' as p;

import 'annotation_args.dart';
import 'record_columns.dart';
import 'primary_constructors.dart';
import 'tenant_column.dart';

/// One model's privacy declaration, as written on its `@DVModel`.
class DVPrivacyModelDeclaration {
  DVPrivacyModelDeclaration._({
    required this.name,
    required this.source,
    required this.table,
    required this.key,
    required this.columns,
    required this.sensitive,
    required this.anonymizeOnErase,
    required this.subject,
    required this.retention,
    required this.retain,
    required this.history,
    required this.historySource,
  });

  /// The generated model's name: `Order` for `_Order`.
  final String name;

  /// Where it is declared, `lib/models/order.dart:3`.
  final String source;

  /// The table the generated model writes, and its columns.
  final String table;
  final List<String> columns;

  /// The column an erasure deletes rows by: `id`, else `slug`.
  final String? key;

  final Set<String> sensitive;
  final Set<String> anonymizeOnErase;
  final DVSubject? subject;
  final DVRetention? retention;
  final DVRetain? retain;

  /// The model's change log, which an erasure removes with the row, or null.
  final DVHistory? history;

  /// The Dart that constructs [history], as `privacy.g.dart` writes it.
  final String? historySource;

  /// How the rows reach their subject, as `dartvel privacy check` prints it.
  String? get subjectDescription {
    final DVSubject? s = subject;
    if (s == null) return null;
    if (identical(s, DVSubject.self)) return 'self';
    return s.parent == null ? s.column : '${s.column} -> ${s.parent}';
  }

  /// How long the rows are kept, as `dartvel privacy check` prints it.
  String? get retentionDescription {
    final DVRetention? r = retention;
    if (r == null) return null;
    if (r.isIndefinite) return 'indefinitely';
    return '${r.days} days from ${r.from}'
        '${r.then == DVRetentionAction.anonymize ? ', then anonymized' : ''}';
  }

  /// Why a row an erasure reaches is kept, when a field is held by law.
  String? get retainedBecause => retain?.because;

  /// Whether erasure, export or retention has anything to do with it.
  bool get declaresAnything =>
      subject != null || retention != null || sensitive.isNotEmpty;
}

/// Every `@DVModel` in a project, read for Data Compliance.
///
/// Read from the source, not from the generated client, because the
/// declarations are the generation input: `dartvel routes` writes the
/// registrations from this, and `dartvel privacy` walks the same list.
class DVPrivacyDeclarations {
  DVPrivacyDeclarations._(this.models)
      : findings = DVPrivacy.check(<DVPrivacyModel>[
          for (final DVPrivacyModelDeclaration d in models)
            if (d.declaresAnything && d.columns.isNotEmpty)
              _toModel(d, MemoryDVDatabaseAdapter(), checkOnly: true),
        ]);

  /// Every model, sorted by name, including those that declare nothing.
  final List<DVPrivacyModelDeclaration> models;

  /// `DV-PRIVACY-001` and `DV-PRIVACY-002`, from the declarations.
  final List<DVPrivacyFinding> findings;

  List<DVPrivacyFinding> get errors => <DVPrivacyFinding>[
        for (final DVPrivacyFinding f in findings)
          if (f.level == DVLogLevel.error) f,
      ];

  static final RegExp _modelPattern = RegExp(
    r'@DVModel\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
    dotAll: true,
  );

  static final RegExp _fieldPattern = RegExp(
    r'((?:@[A-Za-z_][A-Za-z0-9_.]*\s*(?:\([^)]*\))?\s*)*)'
    r'final\s+([A-Za-z0-9_<>, ?]+?)\s+([A-Za-z0-9_]+)\s*;',
  );

  /// Reads every model under `lib/` in [root].
  ///
  /// Throws [StateError] for a declaration that cannot be walked, naming the
  /// model: a subject field that is not declared, or that holds a model
  /// rather than an id; a path through a model that does not exist; a dated
  /// retention with no timestamp to measure from; a subject path on a model
  /// with no key to delete its rows by. Each would otherwise be a walk that
  /// reaches nothing and reports success. A sensitive field no path reaches
  /// is not thrown here but reported in [findings], so `dartvel privacy
  /// check` can list it beside everything else.
  static DVPrivacyDeclarations discover({required String root}) {
    final List<_Draft> drafts = <_Draft>[];
    for (final File file in _dartFiles(root)) {
      final String source = dvDesugarPrimaryConstructors(file.readAsStringSync());
      if (!source.contains('@DVModel')) continue;
      final String rel = p.relative(file.path, from: root).replaceAll('\\', '/');
      final String masked = dvMaskAnnotationArgs(source, 'DVModel');
      for (final RegExpMatch match in _modelPattern.allMatches(masked)) {
        final String declared = match.group(2)!;
        final String args =
            dvAnnotationArgs(source.substring(match.start), 'DVModel') ?? '';
        final int bodyStart = source.indexOf('{', match.end - 1);
        if (bodyStart < 0) continue;
        final int bodyEnd = _matchingBrace(source, bodyStart);
        if (bodyEnd < 0) continue;
        drafts.add(_Draft(
          declared: declared,
          name: declared.startsWith('_') ? declared.substring(1) : declared,
          source: '$rel:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
          args: _named(args),
          body: source.substring(bodyStart + 1, bodyEnd),
        ));
      }
    }
    final Set<String> names = <String>{
      for (final _Draft d in drafts) d.name,
    };
    final List<DVPrivacyModelDeclaration> models = <DVPrivacyModelDeclaration>[
      for (final _Draft d in drafts) _declaration(d, names),
    ]..sort((DVPrivacyModelDeclaration a, DVPrivacyModelDeclaration b) =>
        a.name.compareTo(b.name));
    return DVPrivacyDeclarations._(models);
  }

  static DVPrivacyModelDeclaration _declaration(_Draft d, Set<String> models) {
    Never refuse(String message) =>
        throw StateError('${d.name} (${d.source}): $message');

    final Map<String, String> types = <String, String>{};
    final Set<String> sensitive = <String>{};
    final Set<String> anonymize = <String>{};
    DVRetain? retain;
    for (final RegExpMatch f in _fieldPattern.allMatches(d.body)) {
      final String annotations = f.group(1) ?? '';
      final String name = f.group(3)!;
      types[name] = f.group(2)!.trim();
      final String? sensitiveArgs =
          dvAnnotationArgs(annotations, 'DVModel.sensitiveField');
      if (sensitiveArgs != null) {
        sensitive.add(name);
        if (RegExp(r'\bonErase\s*:\s*DVErase\.anonymize\b')
            .hasMatch(sensitiveArgs)) {
          anonymize.add(name);
        }
      }
      final String? retainArgs =
          dvAnnotationArgs(annotations, 'DVModel.retain');
      if (retainArgs != null) {
        if (retain != null) {
          refuse('more than one field declares @DVModel.retain; a row is '
              'kept for one reason, so declare the longest once');
        }
        final Map<String, String> named = _named(retainArgs);
        final int? years = int.tryParse(named['years'] ?? '');
        final String? because = _string(named['because']);
        if (years == null || years < 1 || because == null || because.isEmpty) {
          refuse('@DVModel.retain on $name needs years: and because:, the '
              'reason somebody will be given for keeping it');
        }
        retain = DVRetain(years: years, because: because);
      }
    }

    final bool tenantScoped =
        RegExp(r'\btenantScoped\s*:\s*true\b').hasMatch(d.args.values.join(' ')) ||
            d.args['tenantScoped']?.trim() == 'true';
    final List<String> columns = <String>[
      if (tenantScoped) dvTenantColumn,
      ...types.keys,
    ];
    final String? key = types.containsKey('id')
        ? 'id'
        : types.containsKey('slug')
            ? 'slug'
            : null;

    String column(String field, String what) {
      if (!types.containsKey(field)) {
        refuse('$what names $field, and ${d.name} declares no field $field');
      }
      return field;
    }

    DVSubject? subject;
    final String? subjectArg = d.args['subject']?.trim().replaceFirst(
          RegExp(r'^const\s+'),
          '',
        );
    if (subjectArg != null) {
      final RegExpMatch? symbol =
          RegExp(r'^#([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(subjectArg);
      final RegExpMatch? literalField = RegExp(
              r'''^DVSubject\.field\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*,?\s*\)$''')
          .firstMatch(subjectArg);
      final RegExpMatch? through = RegExp(
              r'''^DVSubject\.through\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*,\s*parent\s*:\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*,?\s*\)$''')
          .firstMatch(subjectArg);
      if (subjectArg == 'DVSubject.self') {
        subject = DVSubject.self;
      } else if (symbol != null || literalField != null) {
        final String field =
            column((symbol ?? literalField)!.group(1)!, 'subject:');
        final String type = types[field]!.replaceAll('?', '');
        if (!const <String>{'String', 'int', 'num'}.contains(type)) {
          refuse('its subject path is $field, a $type. The generated model '
              'does not store a $type field as the id of its row, so a walk '
              'over that column would match no row and an erasure would '
              'report success having reached nothing. Declare the id itself, '
              'such as `final String ${field}Id;`, and `subject: '
              '#${field}Id`.');
        }
        subject = DVSubject.field(field);
      } else if (through != null) {
        final String field = column(through.group(1)!, 'subject:');
        final String parent = through.group(2)!;
        if (!models.contains(parent)) {
          refuse('its subject path goes through $parent, which is not a '
              'declared model; declare it with @DVModel and its own subject');
        }
        subject = DVSubject.through(field, parent: parent);
      } else {
        refuse('subject: $subjectArg is not a subject path. Write '
            'DVSubject.self, #field, DVSubject.field(\'column\') or '
            'DVSubject.through(\'column\', parent: \'Model\')');
      }
    }

    DVRetention? retention;
    final String? retainArg =
        d.args['retain']?.trim().replaceFirst(RegExp(r'^const\s+'), '');
    if (retainArg != null) {
      if (retainArg == 'DVRetention.indefinite') {
        retention = DVRetention.indefinite;
      } else {
        // A value, not an annotation: no `@` for dvAnnotationArgs to find,
        // so the arguments are the text between its own parentheses.
        final RegExpMatch? call =
            RegExp(r'^DVRetention\.days\s*\(([\s\S]*)\)$').firstMatch(retainArg);
        if (call == null) {
          refuse('retain: $retainArg is not a retention. Write '
              'DVRetention.days(n) or DVRetention.indefinite');
        }
        final String inner = call.group(1)!;
        final List<String> parts = dvSplitArgs(inner);
        final int? days =
            parts.isEmpty ? null : int.tryParse(parts.first.trim());
        if (days == null || days < 1) {
          refuse('DVRetention.days needs a whole number of days first');
        }
        final Map<String, String> named = _named(inner);
        final String? declaredFrom = _string(named['from']);
        final String from = declaredFrom != null
            ? column(declaredFrom, 'DVRetention.days(from:)')
            : types.containsKey('createdAt')
                ? 'createdAt'
                : refuse('it keeps rows DVRetention.days($days) and has no '
                    'timestamp to measure that from. Add `from: \'field\'` '
                    'naming the field holding when the row was made, or a '
                    'createdAt field');
        final String? then = named['then']?.trim();
        final DVRetentionAction action = switch (then) {
          null ||
          'DVRetention.delete' ||
          'DVRetentionAction.delete' =>
            DVRetentionAction.delete,
          'DVRetention.anonymize' ||
          'DVRetentionAction.anonymize' =>
            DVRetentionAction.anonymize,
          _ => refuse('then: $then is not what a sweep can do; write '
              'DVRetention.delete or DVRetention.anonymize'),
        };
        retention = DVRetention.days(days, from: from, then: action);
      }
    }

    if ((subject != null || (retention != null && !retention.isIndefinite)) &&
        key == null) {
      refuse('it declares ${subject != null ? 'a subject path' : 'a retention'} '
          'and has no id field to delete its rows by. Declare `final String '
          'id;` (or a slug)');
    }
    if (identical(subject, DVSubject.self) && key == null) {
      refuse('DVSubject.self needs an id field: the row\'s id is the '
          'subject\'s');
    }

    // The generated model keeps its change log beside its table, so the
    // registration an erasure walks has to know it is there: without it the
    // row is deleted and every value it ever held stays in the log.
    final ({DVHistory history, String source})? history =
        dvHistoryArg(d.args['history'], refuse);

    return DVPrivacyModelDeclaration._(
      name: d.name,
      source: d.source,
      table: '${d.name.toLowerCase()}s',
      key: key,
      columns: columns,
      sensitive: sensitive,
      anonymizeOnErase: anonymize,
      subject: subject,
      retention: retention,
      retain: retain,
      history: history?.history,
      historySource: history?.source,
    );
  }

  /// Every declaring model as the privacy walk sees it, over [database].
  List<DVPrivacyModel> toPrivacyModels(DVDatabaseAdapter database) =>
      <DVPrivacyModel>[
        for (final DVPrivacyModelDeclaration d in models)
          if (d.declaresAnything) _toModel(d, database),
      ];

  static DVPrivacyModel _toModel(
    DVPrivacyModelDeclaration d,
    DVDatabaseAdapter database, {
    bool checkOnly = false,
  }) {
    final String key = d.key ??
        (checkOnly
            ? d.columns.first
            : throw StateError('${d.name} has no key to walk its rows by'));
    return DVPrivacyModel(
      name: d.name,
      table: DVRecordTable(
        table: d.table,
        key: key,
        columns: d.columns,
        sensitive: d.sensitive,
        history: d.history,
        database: database,
      ),
      subject: d.subject,
      anonymizeOnErase: d.anonymizeOnErase,
      retain: d.retain,
      retention: d.retention,
    );
  }

  /// `privacy.g.dart`: the registrations and the server's configuration.
  String render() {
    String lit(String s) =>
        "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
    String set(Iterable<String> values) =>
        '<String>{${values.map(lit).join(', ')}}';
    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: prefer_const_constructors')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      // The record layer, which is generated code's to name and not an
      // application's: erasure walks a model's table directly because a
      // subject's rows have to go whether or not the model is loadable.
      ..writeln("import 'package:dartvel_core/framework.dart';")
      ..writeln()
      ..writeln('/// Every model that declares a subject path, a retention or a')
      ..writeln('/// sensitive field, as the privacy walk sees it, over [database].')
      ..writeln('///')
      ..writeln('/// Generated from each `@DVModel(subject: ..., retain: ...)`.')
      ..writeln('List<DVPrivacyModel> dartvelPrivacyModels(DVDatabaseAdapter database) =>')
      ..writeln('    <DVPrivacyModel>[');
    for (final DVPrivacyModelDeclaration d in models) {
      if (!d.declaresAnything) continue;
      sb
        ..writeln('      DVPrivacyModel(')
        ..writeln('        name: ${lit(d.name)},')
        ..writeln('        table: DVRecordTable(')
        ..writeln('          table: ${lit(d.table)},')
        ..writeln('          key: ${lit(d.key ?? d.columns.first)},')
        ..writeln('          columns: const <String>[${d.columns.map(lit).join(', ')}],');
      if (d.sensitive.isNotEmpty) {
        sb.writeln('          sensitive: const ${set(d.sensitive)},');
      }
      if (d.historySource != null) {
        sb.writeln('          history: ${d.historySource},');
      }
      sb
        ..writeln('          database: database,')
        ..writeln('        ),');
      final DVSubject? s = d.subject;
      if (s != null) {
        sb.writeln('        subject: ${identical(s, DVSubject.self) ? 'DVSubject.self' : s.parent == null ? 'DVSubject.field(${lit(s.column!)})' : 'DVSubject.through(${lit(s.column!)}, parent: ${lit(s.parent!)})'},');
      }
      if (d.anonymizeOnErase.isNotEmpty) {
        sb.writeln('        anonymizeOnErase: ${set(d.anonymizeOnErase)},');
      }
      final DVRetain? r = d.retain;
      if (r != null) {
        sb.writeln('        retain: DVRetain(years: ${r.years}, because: ${lit(r.because)}),');
      }
      final DVRetention? t = d.retention;
      if (t != null) {
        sb.writeln(t.isIndefinite
            ? '        retention: DVRetention.indefinite,'
            : '        retention: DVRetention.days(${t.days}, from: ${lit(t.from!)}'
                '${t.then == DVRetentionAction.anonymize ? ', then: DVRetentionAction.anonymize' : ''}),');
      }
      sb.writeln('      ),');
    }
    sb
      ..writeln('    ];')
      ..writeln()
      ..writeln('/// Configures `DV.Privacy` over [database] from `DARTVEL_PRIVACY_KEY` in')
      ..writeln('/// [environment], and returns whether it did.')
      ..writeln('///')
      ..writeln('/// Called by the generated server. With the key unset nothing is configured')
      ..writeln('/// and `DV.Privacy` throws naming it; with the key set and no database the')
      ..writeln('/// server does not start, because an erasure with nothing to walk would')
      ..writeln('/// report success.')
      ..writeln('bool configureDartvelBackendPrivacy({')
      ..writeln('  required DVDatabaseAdapter? database,')
      ..writeln('  required Map<String, String> environment,')
      ..writeln('}) =>')
      ..writeln('    DVPrivacyRuntime.configureFromEnvironment(')
      ..writeln('      environment: environment,')
      ..writeln('      database: database,')
      ..writeln('      models: database == null')
      ..writeln('          ? const <DVPrivacyModel>[]')
      ..writeln('          : dartvelPrivacyModels(database),')
      ..writeln('    );');
    return sb.toString();
  }

  static Map<String, String> _named(String args) {
    final Map<String, String> out = <String, String>{};
    for (final String part in dvSplitArgs(args)) {
      final RegExpMatch? m =
          RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)([\s\S]*)$')
              .firstMatch(part);
      if (m == null) continue;
      out[m.group(1)!] = m.group(2)!.trim();
    }
    return out;
  }

  static String? _string(String? text) {
    if (text == null) return null;
    final RegExpMatch? m =
        RegExp(r'''^(['"])(.*)\1$''').firstMatch(text.trim());
    return m?.group(2);
  }

  static List<File> _dartFiles(String root) {
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return const <File>[];
    return lib
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !f.path.contains('dartvel_client'))
        .where((File f) => !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
  }

  static int _matchingBrace(String source, int open) {
    int depth = 0;
    for (int i = open; i < source.length; i++) {
      final String c = source[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}

class _Draft {
  _Draft({
    required this.declared,
    required this.name,
    required this.source,
    required this.args,
    required this.body,
  });

  final String declared;
  final String name;
  final String source;
  final Map<String, String> args;
  final String body;
}
