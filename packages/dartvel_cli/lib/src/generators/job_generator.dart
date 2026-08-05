import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// A discovered `@DVJob(...)` payload class.
class DiscoveredJob {
  /// The generated public name, without the leading underscore.
  final String name;
  final String queue;
  final int priority;
  final int maxAttempts;
  final int backoffSeconds;
  final List<Map<String, String>> fields;
  final bool hasConstConstructor;

  const DiscoveredJob({
    required this.name,
    required this.queue,
    required this.priority,
    required this.maxAttempts,
    required this.backoffSeconds,
    required this.fields,
    required this.hasConstConstructor,
  });
}

/// A discovered `@DVJob.handler()` function.
class DiscoveredJobHandler {
  /// The payload type the handler takes.
  final String payloadType;

  /// The handler's parameter name, used when re-emitting the body.
  final String parameterName;

  /// The generated public function name.
  final String publicName;

  /// The expression the private input's body evaluates to.
  final String expressionBody;

  /// Whether the handler was declared `async`.
  final bool isAsync;

  /// A `package:`-qualified import for the file declaring the handler.
  final String importPath;

  /// Public top-level symbols the declaring file defines, so the lowered body
  /// can still reach them through the aliased import.
  final Set<String> sourceSymbols;

  const DiscoveredJobHandler({
    required this.payloadType,
    required this.parameterName,
    required this.publicName,
    required this.expressionBody,
    required this.isAsync,
    required this.importPath,
    required this.sourceSymbols,
  });
}

/// Discovers `@DVJob` payloads and `@DVJob.handler()` functions and generates
/// the typed dispatch surface for them.
///
/// Without this, `@DVJob` was an annotation nothing read: an application had to
/// hand-write its payload class, its codec registration, and its handler
/// registration, and a queue name declared on the annotation had no effect on
/// `DV.Jobs.dispatch`.
class JobGenerator {
  static final _jobClassRegex = RegExp(
    r'@DVJob\s*\(([^)]*)\)\s*(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z0-9_]+)\b',
    dotAll: true,
  );

  static final _handlerRegex = RegExp(
    r'@DVJob\.handler\s*\(\s*\)\s*(?:@pragma\([^)]*\)\s*)*'
    r'(?:Future\s*<\s*void\s*>|void)\s+([A-Za-z0-9_]+)\s*\(',
    dotAll: true,
  );

  static final _fieldRegex = RegExp(
    r'final\s+(.+?)\s+([A-Za-z0-9_]+)\s*;',
    dotAll: true,
  );

  static Future<void> generate({
    required String root,
    required String pkgName,
    required String buildId,
  }) async {
    final jobs = <DiscoveredJob>[];
    final handlers = <DiscoveredJobHandler>[];

    for (final file in _dartFiles(root)) {
      final source = await file.readAsString();
      final importPath = p
          .relative(file.path, from: root)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      _collectJobs(source, file.path, root, jobs);
      _collectHandlers(source, file.path, root, importPath, handlers);
    }

    _validate(jobs, handlers);

    final output = File(
      p.join(root, 'lib', 'dartvel_client', 'jobs.g.dart'),
    );
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(_render(jobs, handlers, buildId));
  }

  static List<File> _dartFiles(String root) {
    const fs = LocalFileSystem();
    final files = <File>[];
    for (final entity in Glob(p.join('lib', '**.dart'))
        .listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      // Generated output is not an input; scanning it would rediscover the
      // public classes this generator just emitted.
      if (path.contains('/lib/dartvel_client/')) continue;
      files.add(File(entity.path));
    }
    files.sort((File a, File b) => a.path.compareTo(b.path));
    return files;
  }

  static void _collectJobs(
    String source,
    String path,
    String root,
    List<DiscoveredJob> jobs,
  ) {
    for (final match in _jobClassRegex.allMatches(source)) {
      final args = match.group(1) ?? '';
      final declared = match.group(2)!;
      if (!declared.startsWith('_')) {
        throw StateError(
          'Dartvel job generation inputs must be private. Rename $declared to '
          '_$declared in ${p.relative(path, from: root)} and dispatch the '
          'generated $declared type from '
          'dartvel_client/dartvel_client.dart.',
        );
      }
      final name = declared.substring(1);
      final body = _classBody(source, match.end);

      jobs.add(
        DiscoveredJob(
          name: name,
          queue: _stringArg(args, 'queue') ?? 'default',
          priority: _intArg(args, 'priority') ?? 0,
          maxAttempts: _intArg(args, 'maxAttempts') ?? 3,
          backoffSeconds: _intArg(args, 'backoffSeconds') ?? 30,
          fields: <Map<String, String>>[
            for (final field in _fieldRegex.allMatches(body))
              <String, String>{
                'type': field.group(1)!.trim(),
                'name': field.group(2)!,
              },
          ],
          hasConstConstructor:
              RegExp('\\bconst\\s+$declared\\s*\\(').hasMatch(source),
        ),
      );
    }
  }

  static void _collectHandlers(
    String source,
    String path,
    String root,
    String importPath,
    List<DiscoveredJobHandler> handlers,
  ) {
    for (final match in _handlerRegex.allMatches(source)) {
      final declared = match.group(1)!;
      final relative = p.relative(path, from: root);
      if (!declared.startsWith('_')) {
        throw StateError(
          'Dartvel job handler inputs must be private. Rename $declared to '
          '_$declared in $relative; the generated public handler is emitted '
          'into dartvel_client/jobs.g.dart.',
        );
      }

      final closeParen = _matchingParen(source, match.end - 1);
      final parameters = source.substring(match.end, closeParen).trim();
      final parameter = _singleParameter(parameters);
      if (parameter == null) {
        throw StateError(
          'Dartvel job handler $declared in $relative must take exactly one '
          'parameter, the generated job payload type.',
        );
      }

      final afterParams = _skipWhitespace(source, closeParen + 1);
      final isAsync = source.startsWith('async', afterParams);
      final bodyStart =
          isAsync ? _skipWhitespace(source, afterParams + 'async'.length) : afterParams;

      final expression = _expressionBodyAt(source, bodyStart);
      if (expression == null) {
        throw StateError(
          'Dartvel job handler $declared in $relative must use an expression '
          'body for this generator pass, for example '
          'Future<void> $declared(${parameter.$1} job) async => sendMail(job). '
          'Block-bodied private handlers require generated body lowering, the '
          'same restriction private pages and backend functions have.',
        );
      }

      handlers.add(
        DiscoveredJobHandler(
          payloadType: parameter.$1,
          parameterName: parameter.$2,
          publicName: declared.substring(1),
          expressionBody: expression,
          isAsync: isAsync,
          importPath: importPath,
          sourceSymbols: _topLevelSourceSymbols(source),
        ),
      );
    }
  }

  /// Rejects the states that would otherwise fail far from the cause: a
  /// handler for a job that does not exist, or two handlers for one job.
  static void _validate(
    List<DiscoveredJob> jobs,
    List<DiscoveredJobHandler> handlers,
  ) {
    final jobNames = jobs.map((DiscoveredJob job) => job.name).toSet();
    final seen = <String>{};
    for (final handler in handlers) {
      if (!jobNames.contains(handler.payloadType)) {
        throw StateError(
          'Job handler _${handler.publicName} takes '
          '${handler.payloadType}, which no @DVJob class generates. Declare '
          '@DVJob() class _${handler.payloadType}, or correct the parameter '
          'type.',
        );
      }
      if (!seen.add(handler.payloadType)) {
        throw StateError(
          '${handler.payloadType} has more than one @DVJob.handler(). A job '
          'payload runs exactly one handler; merge them into one function.',
        );
      }
    }
  }

  static String _render(
    List<DiscoveredJob> jobs,
    List<DiscoveredJobHandler> handlers,
    String buildId,
  ) {
    // A lowered handler body can reference anything its own file declares, so
    // that file is imported under an alias and those symbols are qualified.
    final handlerAliases = <String, String>{};
    for (final handler in handlers) {
      handlerAliases.putIfAbsent(
        handler.importPath,
        () => 'j${handlerAliases.length}',
      );
    }

    final sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      // unnecessary_import: dartvel_flutter re-exports core through a `show`
      // list, so the core import is only redundant for the symbols that list
      // happens to carry today.
      ..writeln('// ignore_for_file: non_constant_identifier_names, '
          'unused_element, unused_import, unnecessary_import')
      ..writeln('// Build ID: $buildId')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      // DV itself lives in dartvel_flutter, and a handler body commonly uses
      // it. Importing only core made the generated file fail to compile.
      ..writeln("import 'package:dartvel_flutter/dartvel_flutter.dart';");
    for (final entry in handlerAliases.entries) {
      sb.writeln("import '${entry.key}' as ${entry.value};");
    }
    sb.writeln();

    final queues = <String>{
      'default',
      for (final job in jobs) job.queue,
    }.toList()
      ..sort();
    sb
      ..writeln('/// Queue names declared by @DVJob annotations.')
      ..writeln('class DVJobQueues {')
      ..writeln('  const DVJobQueues._();');
    for (final queue in queues) {
      sb.writeln("  static const String ${_identifier(queue)} = '$queue';");
    }
    sb
      ..writeln('}')
      ..writeln();

    for (final job in jobs) {
      _renderJob(sb, job);
    }

    for (final handler in handlers) {
      _renderHandler(sb, handler, handlerAliases[handler.importPath]!);
    }

    sb
      ..writeln('/// Registers every generated job codec and handler.')
      ..writeln('///')
      ..writeln('/// Called by the generated runtime configuration, so a')
      ..writeln('/// dispatched job can always be encoded and run.')
      ..writeln('void registerDartvelJobs() {');
    // Declared only where they are used: an application with no jobs still
    // gets this function, and an unused local is a warning in its build.
    if (jobs.isNotEmpty) {
      sb.writeln('  const codecs = DVJobPayloadCodecs();');
    }
    if (handlers.isNotEmpty) {
      sb.writeln('  const queues = DVQueues();');
    }
    for (final job in jobs) {
      sb
        ..writeln('  codecs.register<${job.name}>(')
        ..writeln('    DVJobPayloadCodec<${job.name}>(')
        ..writeln("      name: '${job.name}',")
        ..writeln('      encode: (${job.name} job) => job.toJson(),')
        ..writeln('      decode: ${job.name}.fromJson,')
        ..writeln('    ),')
        ..writeln('  );');
    }
    for (final handler in handlers) {
      sb.writeln(
        '  queues.register<${handler.payloadType}>(${handler.publicName});',
      );
    }
    sb.writeln('}');

    return sb.toString();
  }

  static void _renderJob(StringBuffer sb, DiscoveredJob job) {
    final constPrefix = job.hasConstConstructor ? 'const ' : '';
    sb
      ..writeln('/// Generated job payload for [_${job.name}].')
      ..writeln('class ${job.name} {')
      ..writeln('  /// The queue this job is dispatched to by default.')
      ..writeln("  static const String queue = '${job.queue}';")
      ..writeln('  /// Dispatch priority declared by @DVJob(priority:).')
      ..writeln('  static const int priority = ${job.priority};')
      ..writeln('  /// Attempts before the job is treated as failed.')
      ..writeln('  static const int maxAttempts = ${job.maxAttempts};')
      ..writeln('  /// Backoff between attempts.')
      ..writeln('  static const Duration backoff = '
          'Duration(seconds: ${job.backoffSeconds});')
      ..writeln();

    for (final field in job.fields) {
      sb.writeln('  final ${field['type']} ${field['name']};');
    }
    sb
      ..writeln()
      ..writeln('  $constPrefix${job.name}({');
    for (final field in job.fields) {
      sb.writeln('    required this.${field['name']},');
    }
    sb
      ..writeln('  });')
      ..writeln()
      ..writeln('  /// Reads a payload back from a durable queue.')
      ..writeln('  static ${job.name} fromJson(Map<String, Object?> json) {')
      ..writeln('    return ${job.name}(');
    for (final field in job.fields) {
      sb.writeln(
        "      ${field['name']}: json['${field['name']}'] as ${field['type']},",
      );
    }
    sb
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  Map<String, Object?> toJson() => <String, Object?>{');
    for (final field in job.fields) {
      sb.writeln("        '${field['name']}': ${field['name']},");
    }
    sb
      ..writeln('      };')
      ..writeln()
      ..writeln('  /// Dispatches this payload with the settings declared on')
      ..writeln('  /// @DVJob, which plain DV.Jobs.dispatch cannot know.')
      ..writeln('  Future<DVJobEnvelope<${job.name}>> dispatch({')
      ..writeln('    String? queue,')
      ..writeln('    int? priority,')
      ..writeln('    int? maxAttempts,')
      ..writeln('    Duration? backoff,')
      ..writeln('  }) {')
      ..writeln('    return const DVQueues().dispatch<${job.name}>(')
      ..writeln('      this,')
      ..writeln('      queue: queue ?? ${job.name}.queue,')
      ..writeln('      priority: priority ?? ${job.name}.priority,')
      ..writeln('      maxAttempts: maxAttempts ?? ${job.name}.maxAttempts,')
      ..writeln('      backoff: backoff ?? ${job.name}.backoff,')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln('}')
      ..writeln();
  }

  static void _renderHandler(
    StringBuffer sb,
    DiscoveredJobHandler handler,
    String alias,
  ) {
    final asyncKeyword = handler.isAsync ? ' async' : '';
    // The handler's own parameter must not be rewritten to the alias, even if
    // the file happens to declare a top-level symbol with the same name.
    final symbols = handler.sourceSymbols
        .where((String symbol) => symbol != handler.parameterName)
        .toSet();
    final body = _qualifySourceSymbols(handler.expressionBody, alias, symbols);
    sb
      ..writeln('/// Generated public handler for [_${handler.publicName}].')
      ..writeln('Future<void> ${handler.publicName}(')
      ..writeln('  ${handler.payloadType} ${handler.parameterName},')
      ..writeln(')$asyncKeyword => $body;')
      ..writeln();
  }

  /// Public top-level symbols a handler's file declares, so a lowered body can
  /// still reach them.
  static Set<String> _topLevelSourceSymbols(String source) {
    final symbols = <String>{};
    for (final pattern in <RegExp>[
      RegExp(
        r'^(?:final|const|var)\s+(?:(?:[A-Za-z_][A-Za-z0-9_<>, ?]*)\s+)?'
        r'([A-Za-z][A-Za-z0-9_]*)\s*=',
        multiLine: true,
      ),
      RegExp(
        r'^(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)+([A-Za-z][A-Za-z0-9_]*)\s*(?:=|;)',
        multiLine: true,
      ),
      RegExp(
        r'^(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)+([A-Za-z][A-Za-z0-9_]*)\s*\(',
        multiLine: true,
      ),
      RegExp(r'^class\s+([A-Za-z][A-Za-z0-9_]*)', multiLine: true),
    ]) {
      for (final match in pattern.allMatches(source)) {
        symbols.add(match.group(1)!);
      }
    }
    return symbols;
  }

  static String _qualifySourceSymbols(
    String expression,
    String alias,
    Set<String> symbols,
  ) {
    var qualified = expression;
    // Longest first, so a symbol that is a prefix of another cannot claim it.
    final ordered = symbols.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    for (final symbol in ordered) {
      qualified = qualified.replaceAllMapped(
        RegExp('(?<![A-Za-z0-9_.])${RegExp.escape(symbol)}(?![A-Za-z0-9_])'),
        (Match _) => '$alias.$symbol',
      );
    }
    return qualified;
  }

  // --- source parsing -------------------------------------------------------

  static String _classBody(String source, int classNameEnd) {
    final open = source.indexOf('{', classNameEnd);
    if (open == -1) return '';
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) return source.substring(open + 1, i);
      }
    }
    return source.substring(open + 1);
  }

  static int _matchingParen(String source, int openParen) {
    var depth = 0;
    for (var i = openParen; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return source.length - 1;
  }

  /// Returns `(type, name)` when [parameters] is exactly one plain parameter.
  static (String, String)? _singleParameter(String parameters) {
    if (parameters.isEmpty) return null;
    if (parameters.contains(',')) return null;
    final parts = parameters.split(RegExp(r'\s+'));
    if (parts.length != 2) return null;
    return (parts[0], parts[1]);
  }

  static int _skipWhitespace(String source, int index) {
    var i = index;
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  static String? _expressionBodyAt(String source, int bodyStart) {
    if (bodyStart + 1 >= source.length ||
        source[bodyStart] != '=' ||
        source[bodyStart + 1] != '>') {
      return null;
    }
    final end = _statementEnd(source, bodyStart + 2);
    if (end == -1) return null;
    return source.substring(bodyStart + 2, end).trim();
  }

  /// Finds the `;` that ends an expression body, ignoring semicolons inside
  /// brackets and string literals.
  static int _statementEnd(String source, int start) {
    var depth = 0;
    String? quote;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        continue;
      }
      if (char == '(' || char == '[' || char == '{') depth++;
      if (char == ')' || char == ']' || char == '}') depth--;
      if (char == ';' && depth == 0) return i;
    }
    return -1;
  }

  static String? _stringArg(String args, String name) {
    final match = RegExp('''$name\\s*:\\s*['"]([^'"]*)['"]''').firstMatch(args);
    return match?.group(1);
  }

  static int? _intArg(String args, String name) {
    final match = RegExp('$name\\s*:\\s*(-?\\d+)').firstMatch(args);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// Dart keywords that cannot name a constant. A queue called `default` is
  /// the common case, so this is not hypothetical.
  static const Set<String> _reservedWords = <String>{
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
    'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  };

  /// Turns a queue name into a Dart identifier for the generated constant.
  static String _identifier(String queue) {
    final cleaned = queue.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    final parts = cleaned.split('_').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'queue';
    final buffer = StringBuffer(parts.first.toLowerCase());
    for (final part in parts.skip(1)) {
      buffer
        ..write(part[0].toUpperCase())
        ..write(part.substring(1).toLowerCase());
    }
    final identifier = buffer.toString();
    if (_reservedWords.contains(identifier)) return '${identifier}Queue';
    return RegExp(r'^[0-9]').hasMatch(identifier)
        ? 'queue$identifier'
        : identifier;
  }
}
