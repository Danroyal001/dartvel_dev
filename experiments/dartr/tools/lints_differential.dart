// Dart source: pkg/analyzer/lib/src/dart/analysis/library_analyzer.dart (_computeLints)
//
// Compares parsed or resolved lints to `dart analyze`; keeps the exact
// diagnostics and per-rule counts. A port of upstream dartr's
// tools/lints_differential.py; it writes the same files with the same bytes.
//
// Fixtures: dart tools/lints_differential.dart --fixtures --output target/lints/fixtures
// Corpora:  dart tools/lints_differential.dart --corpus sdk --output target/lints/sdk
//           dart tools/lints_differential.dart --corpus flutter --output target/lints/flutter
//
// The `sdk` corpus is `sdk/lib` of the Dart SDK source checkout:
// DARTR_DART_SDK_SOURCE, else third_party/dart-sdk. Exit code 0 when dartr
// and `dart analyze` agree, 1 when they differ or the run fails.

import 'dart:convert';
import 'dart:io';

import 'common/support.dart';

const _usage = '''
usage: dart tools/lints_differential.dart (--fixtures | --corpus {sdk,flutter} | --input-dir DIR)
           --output DIR [--binary PATH] [--language-version X.Y]
           [--enable-experiment NAME]... [--no-package-config] [--rules-file PATH]
           [--timeout SECONDS] [--reuse] [--rust-only]''';

Future<void> main(List<String> arguments) async {
  _Args args;
  try {
    args = _Args.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(_usage);
    stderr.writeln('lints_differential.dart: error: ${e.message}');
    exit(2);
  }
  try {
    final differ = await _differential(args);
    exit(differ ? 1 : 0);
  } on ToolError catch (e) {
    stderr.writeln('lints_differential.dart: $e');
    exit(1);
  }
}

class _Args {
  bool fixtures = false;
  String? corpus;
  String? inputDir;
  late String output;
  String binary = '$root/target/debug/lints_dump';
  String languageVersion = '3.13';
  List<String> experiments = [];
  bool packageConfig = true;
  String? rulesFile;
  int timeout = 600;
  bool reuse = false;
  bool rustOnly = false;

  static _Args parse(List<String> arguments) {
    final args = _Args();
    String? output;
    final sources = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      var argument = arguments[i];
      String? inline;
      final equals = argument.indexOf('=');
      if (argument.startsWith('--') && equals > 0) {
        inline = argument.substring(equals + 1);
        argument = argument.substring(0, equals);
      }
      String value() {
        if (inline != null) return inline;
        if (i + 1 >= arguments.length) {
          throw FormatException('argument $argument: expected one argument');
        }
        return arguments[++i];
      }

      switch (argument) {
        case '--fixtures':
          args.fixtures = true;
          sources.add(argument);
        case '--corpus':
          final corpus = value();
          if (corpus != 'sdk' && corpus != 'flutter') {
            throw FormatException(
              "argument --corpus: invalid choice: '$corpus' "
              "(choose from 'sdk', 'flutter')",
            );
          }
          args.corpus = corpus;
          sources.add(argument);
        case '--input-dir':
          args.inputDir = value();
          sources.add(argument);
        case '--output':
          output = value();
        case '--binary':
          args.binary = value();
        case '--language-version':
          args.languageVersion = value();
        case '--enable-experiment':
          args.experiments.add(value());
        case '--no-package-config':
          args.packageConfig = false;
        case '--rules-file':
          args.rulesFile = value();
        case '--timeout':
          final timeout = int.tryParse(value());
          if (timeout == null) {
            throw const FormatException(
              'argument --timeout: invalid int value',
            );
          }
          args.timeout = timeout;
        case '--reuse':
          args.reuse = true;
        case '--rust-only':
          args.rustOnly = true;
        default:
          throw FormatException('unrecognized arguments: $argument');
      }
    }
    if (sources.isEmpty) {
      throw const FormatException(
        'one of the arguments --fixtures --corpus --input-dir is required',
      );
    }
    if (sources.length > 1) {
      throw FormatException(
        'argument ${sources[1]}: not allowed with argument ${sources[0]}',
      );
    }
    if (output == null) {
      throw const FormatException(
        'the following arguments are required: --output',
      );
    }
    args.output = resolvePath(output);
    args.binary = resolvePath(args.binary);
    return args;
  }
}

/// A diagnostic as both tools report it: path, code, severity, offset,
/// length, message, correction.
typedef _Key = List<Object?>;

/// Python's `collections.Counter` of diagnostics, in insertion order.
class _Counter {
  final Map<String, _Key> keys = {};
  final Map<String, int> counts = {};

  void add(_Key key, [int count = 1]) {
    final id = jsonEncode(key);
    keys[id] ??= key;
    counts[id] = (counts[id] ?? 0) + count;
  }

  int operator [](String id) => counts[id] ?? 0;

  /// `self - other`: the positive differences, in the order of [this].
  _Counter minus(_Counter other) {
    final result = _Counter();
    for (final MapEntry(key: id, value: count) in counts.entries) {
      final left = count - other[id];
      if (left > 0) result.add(keys[id]!, left);
    }
    return result;
  }

  /// `self & other`: the minimum counts.
  _Counter intersect(_Counter other) {
    final result = _Counter();
    for (final MapEntry(key: id, value: count) in counts.entries) {
      final both = count < other[id] ? count : other[id];
      if (both > 0) result.add(keys[id]!, both);
    }
    return result;
  }

  int get total => counts.values.fold(0, (a, b) => a + b);

  bool get isEmpty => counts.isEmpty;

  int countFor(Set<Object?> codes) {
    var sum = 0;
    for (final MapEntry(key: id, value: count) in counts.entries) {
      if (codes.contains(keys[id]![1])) sum += count;
    }
    return sum;
  }
}

String _readText(String path) => File(path).readAsStringSync();

void _writeText(String path, String text) => File(path).writeAsStringSync(text);

Future<bool> _differential(_Args args) async {
  final started = Stopwatch()..start();
  final output = args.output;
  final binary = args.binary;
  Directory(output).createSync(recursive: true);
  var metadata = (jsonDecode(
    await checkOutput(binary, ['--list'], timeout: 30),
  ) as List).cast<Map<String, dynamic>>();
  if (args.rulesFile != null) {
    final requested = {
      for (var line in const LineSplitter().convert(_readText(args.rulesFile!)))
        if (line.trim().isNotEmpty) line.trim().toLowerCase(),
    };
    metadata = [
      for (var rule in metadata)
        if (requested.contains(rule['name'])) rule,
    ];
    final known = {for (var rule in metadata) rule['name']};
    final unknown = requested.where((name) => !known.contains(name)).toList()
      ..sort();
    if (unknown.isNotEmpty) {
      throw ToolError(
        'Unknown rules: [${unknown.map((u) => "'$u'").join(', ')}]',
      );
    }
  } else {
    metadata = [
      for (var rule in metadata)
        if (rule['implemented'] ?? true) rule,
    ];
  }
  final rules = [for (var rule in metadata) rule['name'] as String];
  if (rules.isEmpty) throw ToolError('No lint rules implemented');
  final project = '$output/project';
  if (args.rustOnly) {
    // Rerun only the Rust runner against the saved project and oracle output.
    final saved = (jsonDecode(_readText('$output/enabled_rules.json')) as List)
        .cast<Map<String, dynamic>>();
    if (!jsonEquals([for (var rule in saved) rule['name']], rules)) {
      throw ToolError('Saved metadata differs from the requested rules');
    }
    final version = await _version();
    final rust = await runProcess(
      binary,
      [],
      input: _readText('$output/request.jsonl'),
      timeout: args.timeout,
    );
    _writeText('$output/dartr.stdout.jsonl', rust.stdout);
    _writeText('$output/dartr.stderr.log', rust.stderr);
    if (rust.exitCode != 0) {
      throw ToolError(
        'Rust runner failed: ${rust.exitCode}, ${_tail(rust.stderr)}',
      );
    }
    return _compareOutputs(
      output,
      saved,
      project,
      filesUnder('$project/lib', '.dart'),
      jsonDecode(_readText('$output/oracle.stdout.json')),
      rust.stdout,
      version,
      started,
    );
  }
  if (args.reuse) {
    final saved = jsonDecode(_readText('$output/enabled_rules.json'));
    if (!jsonEquals(saved, metadata)) {
      throw ToolError('Saved metadata differs from the requested rules');
    }
    final version = await _version();
    return _compareOutputs(
      output,
      metadata,
      project,
      filesUnder('$project/lib', '.dart'),
      jsonDecode(_readText('$output/oracle.stdout.json')),
      _readText('$output/dartr.stdout.jsonl'),
      version,
      started,
    );
  }
  _writeText(
    '$output/runner_manifest.json',
    '${pyJson({'binary': binary, 'sha256': sha256Hex(File(binary).readAsBytesSync())}, indent: 2)}\n',
  );
  _writeText('$output/enabled_rules.json', '${pyJson(metadata, indent: 2)}\n');
  if (Directory(project).existsSync()) {
    Directory(project).deleteSync(recursive: true);
  }
  Directory(project).createSync();
  String source;
  if (args.fixtures) {
    source = '$root/crates/dartr_lints/tests/fixtures';
  } else if (args.corpus == 'sdk') {
    source = '${sdkSource()}/sdk/lib';
  } else if (args.corpus == 'flutter') {
    source =
        '${Platform.environment['HOME'] ?? ''}/fvm/default/packages/flutter/lib';
  } else {
    source = args.inputDir!;
  }
  if (!Directory(source).existsSync()) {
    throw ToolError('No such directory: $source');
  }
  copyTree(source, '$project/lib');
  for (var options in filesUnder(project, 'analysis_options.yaml')) {
    if (options.split('/').last == 'analysis_options.yaml') {
      File(options).deleteSync();
    }
  }
  final languageVersion = args.languageVersion;
  final experiments = args.experiments;
  _writeText(
    '$project/pubspec.yaml',
    "name: dartr_lint_corpus\nenvironment:\n  sdk: '>=$languageVersion.0 <4.0.0'\n",
  );
  final experimentOptions = experiments.isEmpty
      ? ''
      : 'analyzer:\n  enable-experiment:\n${experiments.map((name) => '    - $name\n').join()}';
  _writeText(
    '$project/analysis_options.yaml',
    '${experimentOptions}linter:\n  rules:\n${rules.map((rule) => '    - $rule\n').join()}',
  );
  // The analyzer uses package context even without external dependencies.
  if (args.packageConfig) {
    Directory('$project/.dart_tool').createSync();
    source = resolvePath(source);
    String? originalConfig;
    for (var dir = source; ; dir = _parent(dir)) {
      if (File('$dir/.dart_tool/package_config.json').existsSync()) {
        originalConfig = '$dir/.dart_tool/package_config.json';
        break;
      }
      if (dir == '/') break;
    }
    final packages = <Map<String, dynamic>>[];
    var sourceName = 'dartr_lint_corpus';
    final projectUri = Uri.file(resolvePath(project)).toString();
    if (originalConfig != null) {
      final configUri = Uri.file(originalConfig);
      final config = jsonDecode(_readText(originalConfig));
      for (var package in (config['packages'] as List)) {
        package = Map<String, dynamic>.of(package as Map<String, dynamic>);
        final rootUri = configUri.resolve(package['rootUri'] as String);
        final withSlash = Uri.parse(
          '${rootUri.toString().replaceFirst(RegExp(r'/+$'), '')}/',
        );
        final packageDir = resolvePath(
          withSlash
              .resolve((package['packageUri'] as String?) ?? '')
              .toFilePath(),
        );
        package['rootUri'] = rootUri.toString();
        if (packageDir == source) {
          sourceName = package['name'] as String;
          package['rootUri'] = '$projectUri/';
          package['packageUri'] = 'lib/';
          package['languageVersion'] = languageVersion;
        }
        packages.add(package);
      }
    }
    // The pinned analyzer oracle config supplies meta for standalone fixtures.
    if (args.fixtures || source.contains('fixtures_resolved')) {
      final oracleConfig = await oraclePackageConfig();
      final existing = {for (var p in packages) p['name']};
      final oracleUri = Uri.file(resolvePath(oracleConfig));
      for (var package
          in (jsonDecode(_readText(oracleConfig))['packages'] as List)) {
        if (package['name'] == 'meta' && !existing.contains(package['name'])) {
          package = Map<String, dynamic>.of(package as Map<String, dynamic>);
          package['rootUri'] = oracleUri
              .resolve(package['rootUri'] as String)
              .toString();
          packages.add(package);
        }
      }
    }
    if (sourceName == 'dartr_lint_corpus') {
      packages.add({
        'name': sourceName,
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': languageVersion,
      });
    }
    _writeText(
      '$project/pubspec.yaml',
      "name: $sourceName\nenvironment:\n  sdk: '>=$languageVersion.0 <4.0.0'\n",
    );
    _writeText(
      '$project/.dart_tool/package_config.json',
      pyJson({'configVersion': 2, 'packages': packages}, indent: 2),
    );
  }
  final version = await pinnedDartVersion();
  final oracle = await runProcess(dartBinary(), [
    'analyze',
    '--format=json',
    project,
  ], timeout: args.timeout);
  _writeText('$output/oracle.stdout.json', oracle.stdout);
  _writeText('$output/oracle.stderr.log', oracle.stderr);
  final raw = jsonDecode(oracle.stdout);
  if (![0, 1, 2, 3].contains(oracle.exitCode)) {
    throw ToolError('dart analyze failed: ${oracle.exitCode}');
  }
  final files = filesUnder('$project/lib', '.dart');
  final versionParts = [for (var v in languageVersion.split('.')) int.parse(v)];
  final request = files
      .map(
        (path) =>
            '${pyJson({'path': resolvePath(path), 'enabled': rules, 'languageVersion': versionParts, 'experiments': experiments})}\n',
      )
      .join();
  _writeText('$output/request.jsonl', request);
  final rust = await runProcess(
    binary,
    [],
    input: request,
    timeout: args.timeout,
  );
  _writeText('$output/dartr.stdout.jsonl', rust.stdout);
  _writeText('$output/dartr.stderr.log', rust.stderr);
  if (rust.exitCode != 0) {
    throw ToolError(
      'Rust runner failed: ${rust.exitCode}, ${_tail(rust.stderr)}',
    );
  }
  return _compareOutputs(
    output,
    metadata,
    project,
    files,
    raw,
    rust.stdout,
    version,
    started,
  );
}

Future<String> _version() async => (await checkOutput(
  dartBinary(),
  ['--version'],
  timeout: 30,
  mergeStderr: true,
)).trim();

String _parent(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}

/// The last 4000 characters (Python's `[-4000:]`).
String _tail(String text) =>
    text.length > 4000 ? text.substring(text.length - 4000) : text;

bool _compareOutputs(
  String output,
  List<Map<String, dynamic>> metadata,
  String project,
  List<String> files,
  Object? raw,
  String rustStdout,
  String version,
  Stopwatch started,
) {
  final projectRoot = resolvePath(project);
  final relativeCache = <String, String>{};
  String relative(String path) => relativeCache.putIfAbsent(path, () {
    final resolved = resolvePath(path);
    if (!resolved.startsWith('$projectRoot/')) {
      throw ToolError("'$resolved' is not in the subpath of '$projectRoot'");
    }
    return resolved.substring(projectRoot.length + 1);
  });
  final codes = {
    for (var rule in metadata)
      for (var code in rule['codes'] as List) code,
  };
  final expected = _Counter();
  for (var d in (raw as Map)['diagnostics'] as List) {
    if (!codes.contains(d['code']) || d['type'] != 'LINT') continue;
    final location = d['location'];
    final span = location['range'];
    expected.add([
      relative(location['file'] as String),
      d['code'],
      d['severity'],
      span['start']['offset'],
      (span['end']['offset'] as int) - (span['start']['offset'] as int),
      d['problemMessage'],
      d['correctionMessage'],
    ]);
  }
  final actual = _Counter();
  final panics = <Map<String, Object?>>[];
  final unresolvedParts = <String>[];
  final errors = <Map<String, Object?>>[];
  final records = <String>{};
  for (var line in const LineSplitter().convert(rustStdout)) {
    final record = jsonDecode(line) as Map<String, dynamic>;
    final recordPath = relative(record['path'] as String);
    if (records.contains(recordPath)) {
      throw ToolError('Duplicate Rust result for $recordPath');
    }
    records.add(recordPath);
    if (_truthy(record['panic'])) {
      panics.add({'path': recordPath, 'panic': record['panic']});
    }
    if (_truthy(record['unresolvedPart'])) unresolvedParts.add(recordPath);
    if (_truthy(record['error'])) {
      errors.add({'path': recordPath, 'error': record['error']});
    }
    for (var d in record['diagnostics'] as List) {
      actual.add([
        relative(record['path'] as String),
        d['code'],
        d['severity'],
        d['offset'],
        d['length'],
        d['message'],
        d['correction'],
      ]);
    }
  }
  final wanted = {for (var path in files) relative(path)};
  if (records.length != wanted.length || !records.containsAll(wanted)) {
    final missingFiles = wanted.difference(records).toList()..sort();
    final extraFiles = records.difference(wanted).toList()..sort();
    throw ToolError(
      'Incomplete Rust output; missing files: ${_pyList(missingFiles)}; '
      'extra files: ${_pyList(extraFiles)}',
    );
  }
  final missing = expected.minus(actual);
  final extra = actual.minus(expected);
  final affectedFiles = {
    for (var key in [...missing.keys.values, ...extra.keys.values]) key[0],
  };
  final rows = <Map<String, Object?>>[];
  for (var rule in metadata) {
    final ruleCodes = {...(rule['codes'] as List)};
    rows.add({
      'rule': rule['name'],
      'oracle': expected.countFor(ruleCodes),
      'dartr': actual.countFor(ruleCodes),
      'missing': missing.countFor(ruleCodes),
      'extra': extra.countFor(ruleCodes),
    });
  }
  final seconds =
      (started.elapsedMicroseconds / 1e6 * 100).roundToDouble() / 100;
  final summary = <String, Object?>{
    'dart': version,
    'files': files.length,
    'rules': metadata.length,
    'oracle': expected.total,
    'dartr': actual.total,
    'matched': expected.intersect(actual).total,
    'missing': missing.total,
    'extra': extra.total,
    'exact_files': files
        .where((path) => !affectedFiles.contains(relative(path)))
        .length,
    'seconds': seconds,
    'resolver_panics': panics,
    'unresolved_parts': unresolvedParts,
    'analysis_errors': errors,
    'per_rule': rows,
  };
  _writeText('$output/summary.json', '${pyJson(summary, indent: 2)}\n');
  List<Map<String, Object?>> entries(_Counter counter) => [
    for (final MapEntry(key: id, value: count) in counter.counts.entries)
      {'diagnostic': counter.keys[id], 'count': count},
  ];
  _writeText(
    '$output/diffs.json',
    '${pyJson({'missing': entries(missing), 'extra': entries(extra)}, indent: 2)}\n',
  );
  const columns = ['rule', 'oracle', 'dartr', 'missing', 'extra'];
  final table =
      'rule\toracle\tdartr\tmissing\textra\n'
      '${rows.map((row) => '${columns.map((c) => '${row[c]}').join('\t')}\n').join()}';
  _writeText('$output/per_rule.tsv', table);
  stdout.writeln(pyJson({...summary}..remove('per_rule'), indent: 2));
  stdout.writeln(table);
  return !missing.isEmpty || !extra.isEmpty;
}

/// Python truthiness of a decoded JSON value.
bool _truthy(Object? value) => switch (value) {
  null || false => false,
  final String s => s.isNotEmpty,
  final List l => l.isNotEmpty,
  final Map m => m.isNotEmpty,
  final num n => n != 0,
  _ => true,
};

String _pyList(List<String> items) =>
    '[${items.map((i) => "'$i'").join(', ')}]';
