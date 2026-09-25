import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'symbol_qualifier.dart';
import 'function_body.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'primary_constructors.dart';

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
  /// The scanned body, block or expression, with its `async` modifier.
  final DVFunctionBody body;

  /// Whether the handler was declared `async`.

  /// A `package:`-qualified import for the file declaring the handler.
  final String importPath;

  /// The file declaring the handler, on disk.
  final String sourcePath;

  /// Public top-level symbols the declaring file defines, so the lowered body
  /// can still reach them through the aliased import.
  final Set<String> sourceSymbols;

  const DiscoveredJobHandler({
    required this.payloadType,
    required this.parameterName,
    required this.publicName,
    required this.body,
    required this.importPath,
    required this.sourcePath,
    required this.sourceSymbols,
  });
}

/// A handler with the file it is generated into decided.
class _PlacedHandler {
  const _PlacedHandler({
    required this.handler,
    required this.alias,
    required this.rendered,
    required this.usesOwnFile,
    required this.clientOnlyBecause,
  });

  final DiscoveredJobHandler handler;

  /// The alias its declaring file is imported under, where it is imported.
  final String alias;

  /// The lowered body, with the declaring file's symbols qualified.
  final String rendered;

  /// Whether the body reaches anything its declaring file declares, which is
  /// the only reason to import that file.
  final bool usesOwnFile;

  /// Why only a Flutter process can run it, or null when a server can.
  final String? clientOnlyBecause;
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

  /// Writes `jobs.g.dart`, the server half, and `client_jobs.g.dart`, the
  /// Flutter half, and returns a warning for each handler only the client
  /// can run.
  ///
  /// The generated backend imports `jobs.g.dart`, and a server process has
  /// no dart:ui, so nothing reachable from it may import Flutter. It used to
  /// import dartvel_flutter for every application, which is why no server
  /// could register a handler and a worker refused to start. A handler goes
  /// to the client half when its body names `DV`, which lives in
  /// dartvel_flutter, or when it uses what its own file declares and that
  /// file reaches Flutter -- directly, through another file of the
  /// application, through the generated barrel, or through a package that
  /// depends on Flutter.
  static Future<List<String>> generate({
    required String root,
    required String pkgName,
    /// Accepted and not written anywhere. A build id in generated files
    /// rewrote every file on every build.
    String? buildId,
  }) async {
    final jobs = <DiscoveredJob>[];
    final handlers = <DiscoveredJobHandler>[];

    for (final file in _dartFiles(root)) {
      final source = await file.readAsString();
      final importPath = p
          .relative(file.path, from: root)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      _collectJobs(dvDesugarPrimaryConstructors(source), file.path, root, jobs);
      _collectHandlers(source, file.path, root, importPath, handlers);
    }

    _validate(jobs, handlers);

    // A lowered handler body can reference anything its own file declares,
    // so that file is imported under an alias and those symbols qualified.
    final aliases = <String, String>{};
    for (final handler in handlers) {
      aliases.putIfAbsent(handler.importPath, () => 'j${aliases.length}');
    }
    final placed = <_PlacedHandler>[
      for (final handler in handlers)
        _place(
          handler,
          aliases[handler.importPath]!,
          root: root,
          pkgName: pkgName,
        ),
    ];

    final output = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(p.join(output.path, 'jobs.g.dart'))
        .writeAsStringSync(_renderServer(jobs, placed));
    File(p.join(output.path, 'client_jobs.g.dart'))
        .writeAsStringSync(_renderClient(placed));

    return <String>[
      for (final placement in placed)
        if (placement.clientOnlyBecause != null)
          'dartvel: @DVJob.handler() _${placement.handler.publicName} in '
              '${p.relative(placement.handler.sourcePath, from: root)} runs in '
              'the client only: ${placement.clientOnlyBecause}. A '
              'DARTVEL_ROLE=worker process cannot run '
              '${placement.handler.payloadType} jobs; write the handler '
              'against dartvel_core, without DV, to run it on the server.',
    ];
  }

  static final RegExp _namesDV =
      RegExp(r'(?<![A-Za-z0-9_$.])DV(?![A-Za-z0-9_$])');

  static _PlacedHandler _place(
    DiscoveredJobHandler handler,
    String alias, {
    required String root,
    required String pkgName,
  }) {
    // The handler's own parameter must not be rewritten to the alias, even if
    // the file happens to declare a top-level symbol with the same name.
    final symbols = handler.sourceSymbols
        .where((String symbol) => symbol != handler.parameterName)
        .toSet();
    final String raw = handler.body.isBlock
        ? handler.body.statements!
        : handler.body.expression!;
    final String rendered = _qualifySourceSymbols(raw, alias, symbols);
    final bool usesOwnFile = rendered != raw;
    String? because;
    // Against the code alone: a comment saying the handler "leaves DV.Database
    // to the application" is not a use of DV, and treating it as one put a
    // core-only handler where no worker could run it.
    if (_namesDV.hasMatch(_codeOnly(raw))) {
      because = 'its body names DV, which lives in dartvel_flutter';
    } else if (usesOwnFile) {
      final String? reached = _flutterReachedFrom(
        handler.sourcePath,
        root: root,
        pkgName: pkgName,
        seen: <String>{},
      );
      if (reached != null) {
        because = 'it uses what '
            '${p.relative(handler.sourcePath, from: root)} declares, and '
            'that file reaches Flutter through $reached';
      }
    }
    return _PlacedHandler(
      handler: handler,
      alias: alias,
      rendered: rendered,
      usesOwnFile: usesOwnFile,
      clientOnlyBecause: because,
    );
  }

  /// [source] with comments and the text of string literals blanked, keeping
  /// the code inside `${...}` and a `$name` interpolation, which is code.
  static String _codeOnly(String source) {
    final StringBuffer out = StringBuffer();
    _scanCode(source, 0, out: out, untilBrace: false);
    return out.toString();
  }

  /// Copies code from [start], blanking comments and strings, and returns the
  /// index after the `}` that closes an interpolation when [untilBrace].
  static int _scanCode(
    String s,
    int start, {
    required StringBuffer out,
    required bool untilBrace,
  }) {
    int depth = 0;
    int i = start;
    while (i < s.length) {
      final String c = s[i];
      if (s.startsWith('//', i)) {
        final int end = s.indexOf('\n', i);
        i = end < 0 ? s.length : end;
        out.write(' ');
        continue;
      }
      if (s.startsWith('/*', i)) {
        int nest = 0;
        while (i < s.length) {
          if (s.startsWith('/*', i)) {
            nest++;
            i += 2;
          } else if (s.startsWith('*/', i)) {
            nest--;
            i += 2;
            if (nest == 0) break;
          } else {
            i++;
          }
        }
        out.write(' ');
        continue;
      }
      final bool raw = (c == 'r' || c == 'R') &&
          i + 1 < s.length &&
          (s[i + 1] == "'" || s[i + 1] == '"') &&
          (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[i - 1]));
      if (raw || c == "'" || c == '"') {
        i = _scanString(s, raw ? i + 1 : i, out: out, raw: raw);
        continue;
      }
      if (untilBrace) {
        if (c == '{') depth++;
        if (c == '}') {
          if (depth == 0) return i + 1;
          depth--;
        }
      }
      out.write(c);
      i++;
    }
    return i;
  }

  /// Blanks the string literal opening at [start] and returns the index
  /// after it, copying out any interpolated code.
  static int _scanString(
    String s,
    int start, {
    required StringBuffer out,
    required bool raw,
  }) {
    final String quote = s[start];
    final String triple = quote * 3;
    final bool isTriple = s.startsWith(triple, start);
    final String close = isTriple ? triple : quote;
    int i = start + close.length;
    out.write(' ');
    while (i < s.length) {
      if (s.startsWith(close, i)) return i + close.length;
      final String c = s[i];
      if (!isTriple && c == '\n') return i;
      if (!raw && c == r'\') {
        i += 2;
        continue;
      }
      if (!raw && c == r'$') {
        if (i + 1 < s.length && s[i + 1] == '{') {
          out.write(' ');
          i = _scanCode(s, i + 2, out: out, untilBrace: true);
          out.write(' ');
          continue;
        }
        final Match? name =
            RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(s, i + 1);
        if (name != null) {
          out
            ..write(' ')
            ..write(name.group(0))
            ..write(' ');
          i = name.end;
          continue;
        }
      }
      i++;
    }
    return i;
  }

  static final RegExp _directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// Packages that are Flutter whatever their pubspec says.
  static const Set<String> _flutterPackages = <String>{
    'flutter',
    'flutter_test',
    'flutter_web_plugins',
    'dartvel_flutter',
  };

  /// The import through which [path] reaches Flutter, or null when it does
  /// not. The generated server cannot import a file that does, which the
  /// policy registrations have to know as well as the job handlers.
  static String? flutterReachedFrom(
    String path, {
    required String root,
    required String pkgName,
  }) =>
      _flutterReachedFrom(path, root: root, pkgName: pkgName, seen: <String>{});

  static String? _flutterReachedFrom(
    String path, {
    required String root,
    required String pkgName,
    required Set<String> seen,
  }) {
    final File file = File(path);
    if (!seen.add(p.normalize(file.absolute.path)) || !file.existsSync()) {
      return null;
    }
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final String? reached = _flutterReachedThrough(
        match.group(1)!,
        from: path,
        root: root,
        pkgName: pkgName,
        seen: seen,
      );
      if (reached != null) return reached;
    }
    return null;
  }

  /// The import through which one directive's [uri], written in the file at
  /// [from], reaches Flutter, or null when it does not.
  static String? flutterReachedThrough(
    String uri, {
    required String from,
    required String root,
    required String pkgName,
  }) =>
      _flutterReachedThrough(uri,
          from: from, root: root, pkgName: pkgName, seen: <String>{});

  static String? _flutterReachedThrough(
    String uri, {
    required String from,
    required String root,
    required String pkgName,
    required Set<String> seen,
  }) {
    final String clientDir = p.join(root, 'lib', 'dartvel_client');
    const String generatedClient = 'the generated client, which exports Flutter';
    if (uri == 'dart:ui') return uri;
    if (uri.startsWith('dart:')) return null;
    String? target;
    if (uri.startsWith('package:')) {
      final String rest = uri.substring('package:'.length);
      final int slash = rest.indexOf('/');
      if (slash < 0) return null;
      final String package = rest.substring(0, slash);
      if (package != pkgName) {
        if (_flutterPackages.contains(package) ||
            _dependsOnFlutter(root, package)) {
          return uri;
        }
        return null;
      }
      target = p.join(root, 'lib', rest.substring(slash + 1));
    } else {
      target = p.normalize(p.join(p.dirname(from), uri));
    }
    // The generated client is regenerated after this runs, so it is judged
    // by what it is rather than read: everything in it but this server
    // half is reached through the barrel, which exports dartvel_flutter.
    if (p.isWithin(clientDir, target)) {
      if (p.basename(target) == 'jobs.g.dart') return null;
      return '$uri, $generatedClient';
    }
    return _flutterReachedFrom(
      target,
      root: root,
      pkgName: pkgName,
      seen: seen,
    );
  }

  /// Whether [package] declares a Flutter SDK dependency, read through the
  /// project's package configuration. A package it cannot find is taken not
  /// to: the server build then names the import it cannot compile.
  static bool _dependsOnFlutter(String root, String package) {
    if (package == 'dartvel_core') return false;
    final File config = File(p.join(root, '.dart_tool', 'package_config.json'));
    if (!config.existsSync()) return false;
    try {
      final Object? json = jsonDecode(config.readAsStringSync());
      final Object? packages = json is Map ? json['packages'] : null;
      if (packages is! List) return false;
      for (final Object? entry in packages) {
        if (entry is! Map || entry['name'] != package) continue;
        final Uri base = Uri.file(config.absolute.path)
            .resolveUri(Uri.parse('${entry['rootUri']}'));
        final File pubspec = File(p.join(base.toFilePath(), 'pubspec.yaml'));
        return pubspec.existsSync() &&
            RegExp(r'sdk:\s*flutter\b').hasMatch(pubspec.readAsStringSync());
      }
    } on Object {
      return false;
    }
    return false;
  }

  static List<File> _dartFiles(String root) {
    const fs = LocalFileSystem();
    final files = <File>[];
    // Always '/', never the host separator: see model_generator.
    for (final entity in Glob('lib/**.dart')
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

      final DVFunctionBody? body = dvFunctionBodyAfter(source, closeParen);
      if (body == null) {
        throw StateError(
          'Dartvel job handler $declared in $relative has no body, for example '
          'Future<void> $declared(${parameter.$1} job) async => sendMail(job) '
          'or the same with a block.',
        );
      }

      handlers.add(
        DiscoveredJobHandler(
          payloadType: parameter.$1,
          parameterName: parameter.$2,
          publicName: declared.substring(1),
          body: body,
          importPath: importPath,
          sourcePath: path,
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

  static void _writeAliasedImports(
    StringBuffer sb,
    Iterable<_PlacedHandler> placed,
  ) {
    final imports = <String, String>{
      for (final placement in placed)
        if (placement.usesOwnFile)
          placement.handler.importPath: placement.alias,
    };
    for (final entry in imports.entries) {
      sb.writeln("import '${entry.key}' as ${entry.value};");
    }
  }

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');

  /// The half the generated backend imports: dartvel_core and the handlers'
  /// own files, never Flutter.
  static String _renderServer(
    List<DiscoveredJob> jobs,
    List<_PlacedHandler> placed,
  ) {
    final server = placed
        .where((_PlacedHandler h) => h.clientOnlyBecause == null)
        .toList();
    final clientOnly = placed
        .where((_PlacedHandler h) => h.clientOnlyBecause != null)
        .toList();

    final sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('//')
      ..writeln('// The server half of the jobs: the generated backend imports')
      ..writeln('// this, and a server has no dart:ui, so nothing reachable from')
      ..writeln('// it imports Flutter. The handlers only a Flutter process can')
      ..writeln('// run are in client_jobs.g.dart.')
      ..writeln('// ignore_for_file: non_constant_identifier_names, '
          'unused_element, unused_import, unnecessary_import')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    _writeAliasedImports(sb, server);
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

    for (final placement in server) {
      _renderHandler(sb, placement);
    }

    sb
      ..writeln('/// The jobs whose handler only a Flutter process can run, and')
      ..writeln('/// why. A server registers no handler for them, and a worker')
      ..writeln('/// names them rather than dead-lettering them in silence.');
    if (clientOnly.isEmpty) {
      sb.writeln('const Map<String, String> dartvelClientOnlyJobHandlers = '
          '<String, String>{};');
    } else {
      sb.writeln('const Map<String, String> dartvelClientOnlyJobHandlers = '
          '<String, String>{');
      for (final placement in clientOnly) {
        sb.writeln("  '${placement.handler.payloadType}': "
            "'${_escape('_${placement.handler.publicName}: '
                '${placement.clientOnlyBecause}')}',");
      }
      sb.writeln('};');
    }
    sb
      ..writeln()
      ..writeln('/// Registers every generated job codec, and the handlers a')
      ..writeln('/// server can run.')
      ..writeln('///')
      ..writeln('/// Called by the generated backend in every role, so a job a')
      ..writeln('/// web process dispatches can be encoded and a worker can run')
      ..writeln('/// it, and by the client through registerDartvelClientJobs.')
      ..writeln('void registerDartvelJobs() {');
    // Declared only where they are used: an application with no jobs still
    // gets this function, and an unused local is a warning in its build.
    if (jobs.isNotEmpty) {
      sb.writeln('  const codecs = DVJobPayloadCodecs();');
    }
    if (server.isNotEmpty) {
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
    for (final placement in server) {
      sb.writeln('  queues.register<${placement.handler.payloadType}>('
          '${placement.handler.publicName});');
    }
    sb.writeln('}');

    return sb.toString();
  }

  /// The half only a Flutter process loads: the handlers that need Flutter,
  /// and the registration the client runtime calls.
  static String _renderClient(List<_PlacedHandler> placed) {
    final client = placed
        .where((_PlacedHandler h) => h.clientOnlyBecause != null)
        .toList();
    final sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('//')
      ..writeln('// The client half of the jobs. Never imported by the generated')
      ..writeln('// backend: these handlers need Flutter.')
      // unnecessary_import: dartvel_flutter re-exports core through a `show`
      // list, so the core import is only redundant for the symbols that list
      // happens to carry today.
      ..writeln('// ignore_for_file: non_constant_identifier_names, '
          'unused_element, unused_import, unnecessary_import')
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';");
    if (client.isNotEmpty) {
      // DV lives in dartvel_flutter, and it is why most of these are here.
      sb.writeln("import 'package:dartvel_flutter/dartvel_flutter.dart';");
    }
    sb.writeln("import 'jobs.g.dart';");
    _writeAliasedImports(sb, client);
    sb.writeln();
    for (final placement in client) {
      _renderHandler(sb, placement);
    }
    sb
      ..writeln('/// Registers every job codec and handler, including the ones')
      ..writeln('/// only the client can run. Called by the client runtime, so a')
      ..writeln('/// dispatched job can always be encoded and run.')
      ..writeln('void registerDartvelClientJobs() {')
      ..writeln('  registerDartvelJobs();');
    if (client.isNotEmpty) {
      sb.writeln('  const queues = DVQueues();');
      for (final placement in client) {
        sb.writeln('  queues.register<${placement.handler.payloadType}>('
            '${placement.handler.publicName});');
      }
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

  static void _renderHandler(StringBuffer sb, _PlacedHandler placement) {
    final DiscoveredJobHandler handler = placement.handler;
    final String asyncKeyword =
        handler.body.modifier == null ? '' : ' ${handler.body.modifier}';
    final String rendered = placement.rendered;
    sb
      ..writeln('/// Generated public handler for [_${handler.publicName}].')
      ..writeln('Future<void> ${handler.publicName}(')
      ..writeln('  ${handler.payloadType} ${handler.parameterName},')
      ..write(')$asyncKeyword');
    if (handler.body.isBlock) {
      sb
        ..writeln(' {')
        ..writeln(rendered)
        ..writeln('}');
    } else {
      sb.writeln(' => $rendered;');
    }
    sb.writeln();
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
  ) =>
      dvQualifySourceSymbols(expression, alias, symbols);

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
