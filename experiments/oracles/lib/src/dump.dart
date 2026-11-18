import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/formatter_options.dart' as a;
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'corpus.dart';
import 'tool_versions.dart';

/// Which original tool a dump records.
enum DumpTool { format, analyze }

/// Marks a manifest as written by this harness, so a later dump may replace
/// the directory holding it and nothing else.
const harnessName = 'dartvel-oracles';

/// The manifest's format. Bump it when the layout of a dump changes.
const manifestSchema = 1;

/// What a finished dump contained.
class DumpSummary {
  final int fileCount;
  final int errorCount;
  final String overallSha256;
  const DumpSummary(this.fileCount, this.errorCount, this.overallSha256);
}

/// One output file of a dump, before it is written.
class _Output {
  final CorpusFile input;
  final String suffix;
  final String content;
  final _FormatSettings? settings;
  _Output(this.input, this.suffix, this.content, {this.settings});

  String get path => '${input.relativePath}$suffix';
  bool get isError => suffix.endsWith('-error');
}

/// Runs [tool] over every `.dart` file under [roots] and writes one output
/// per file plus `manifest.json` into [outDir].
///
/// [languageVersion] (`major.minor`) fixes the formatter's language version;
/// without it each file uses the lower bound of the SDK constraint in its
/// nearest `pubspec.yaml`, or the formatter's latest version when there is
/// none.
Future<DumpSummary> dump({
  required List<String> roots,
  required String outDir,
  required DumpTool tool,
  String? languageVersion,
}) async {
  final corpus = Corpus.discover(roots);
  _prepareOutDir(outDir);
  final paths = _PathScrubber(corpus.rootsByLabel);

  final List<_Output> outputs;
  final Map<String, Object?> toolVersions;
  final Map<String, Object?> settings;
  switch (tool) {
    case DumpTool.format:
      outputs = await _format(corpus, paths, languageVersion);
      toolVersions = {'dart_style': await packageVersion('dart_style')};
      settings = {
        'languageVersion': languageVersion ?? 'pubspec sdk lower bound',
        'pageWidth': 'analysis_options formatter.page_width, else 80',
        'trailingCommas': 'analysis_options formatter.trailing_commas',
        'perFile': 'languageVersion, pageWidth, trailingCommas in files[]',
      };
    case DumpTool.analyze:
      outputs = await _analyze(corpus, paths);
      toolVersions = {
        'analyzer': await packageVersion('analyzer'),
        '_fe_analyzer_shared': await packageVersion('_fe_analyzer_shared'),
      };
      settings = {'sdk': 'running'};
  }

  outputs.sort((a, b) => a.path.compareTo(b.path));
  final entries = <Map<String, Object?>>[];
  final overall = StringBuffer();
  for (final output in outputs) {
    final bytes = utf8.encode(output.content);
    final file = File(p.joinAll([outDir, ...output.path.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    final hash = sha256.convert(bytes).toString();
    overall.write('${output.path}\t$hash\n');
    entries.add({
      'input': output.input.relativePath,
      'inputSha256': sha256
          .convert(File(output.input.absolutePath).readAsBytesSync())
          .toString(),
      'output': output.path,
      'sha256': hash,
      ...?output.settings?.toJson(),
    });
  }
  final overallHash = sha256.convert(utf8.encode(overall.toString()));
  final errorCount = outputs.where((o) => o.isError).length;
  final manifest = <String, Object?>{
    'harness': harnessName,
    'schema': manifestSchema,
    'tool': tool.name,
    'toolVersions': toolVersions,
    'dartSdk': dartSdkVersion(),
    'settings': settings,
    'corpusRoots': corpus.rootsByLabel.keys.toList(),
    'fileCount': corpus.files.length,
    'errorCount': errorCount,
    'overallSha256': overallHash.toString(),
    'files': entries,
  };
  File(p.join(outDir, 'manifest.json')).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  return DumpSummary(corpus.files.length, errorCount, overallHash.toString());
}

/// The formatter settings one file was formatted with.
class _FormatSettings {
  final String languageVersion;
  final int pageWidth;
  final String trailingCommas;
  const _FormatSettings(
    this.languageVersion,
    this.pageWidth,
    this.trailingCommas,
  );

  Map<String, Object?> toJson() => {
    'languageVersion': languageVersion,
    'pageWidth': pageWidth,
    'trailingCommas': trailingCommas,
  };
}

/// The page width and trailing-comma mode `dart format` would use for
/// [file]: the `formatter:` section of its analysis options, or the
/// formatter's defaults.
(int, TrailingCommas) _formatterOptions(
  AnalysisContextCollection collection,
  CorpusFile file,
) {
  a.FormatterOptions? options;
  try {
    final context = collection.contextFor(file.absolutePath);
    options = context
        .getAnalysisOptionsForFile(
          context.contextRoot.resourceProvider.getFile(file.absolutePath),
        )
        .formatterOptions;
  } on Object {
    options = null;
  }
  final trailingCommas = switch (options?.trailingCommas) {
    a.TrailingCommas.preserve => TrailingCommas.preserve,
    a.TrailingCommas.automate || null => TrailingCommas.automate,
  };
  return (options?.pageWidth ?? DartFormatter.defaultPageWidth, trailingCommas);
}

/// Creates [outDir], or empties it when it holds an earlier dump. Refuses
/// any other non-empty directory rather than deleting someone's files.
void _prepareOutDir(String outDir) {
  final dir = Directory(outDir);
  if (dir.existsSync() && dir.listSync().isNotEmpty) {
    final manifest = File(p.join(outDir, 'manifest.json'));
    Object? decoded;
    try {
      decoded = jsonDecode(manifest.readAsStringSync());
    } on Object {
      decoded = null;
    }
    if (decoded is! Map || decoded['harness'] != harnessName) {
      throw StateError(
        '$outDir is not empty and does not hold an earlier dump; refusing to '
        'overwrite it.',
      );
    }
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
}

Future<List<_Output>> _format(
  Corpus corpus,
  _PathScrubber paths,
  String? fixedLanguageVersion,
) async {
  final fixed = fixedLanguageVersion == null
      ? null
      : _parseLanguageVersion(fixedLanguageVersion);
  final versions = _PubspecLanguageVersions();
  // `dart format` reads `formatter: page_width` and `trailing_commas` from
  // the analysis options that apply to each file, through the analyzer.
  final collection = AnalysisContextCollection(
    includedPaths: corpus.rootsByLabel.values.toList(),
  );
  final outputs = <_Output>[];
  for (final file in corpus.files) {
    final version = fixed ?? versions.forFile(file.absolutePath);
    final recorded = '${version.major}.${version.minor}';
    final (pageWidth, trailingCommas) = _formatterOptions(collection, file);
    final formatter = DartFormatter(
      languageVersion: version,
      pageWidth: pageWidth,
      trailingCommas: trailingCommas,
    );
    final settings = _FormatSettings(recorded, pageWidth, trailingCommas.name);
    try {
      final source = File(file.absolutePath).readAsStringSync();
      final formatted = formatter.format(source, uri: file.relativePath);
      outputs.add(_Output(file, '.formatted', formatted, settings: settings));
    } on FormatterException catch (e) {
      outputs.add(
        _Output(
          file,
          '.format-error',
          paths.scrub(e.message()),
          settings: settings,
        ),
      );
    } on Object catch (e) {
      // Anything else the formatter throws is recorded the same way: the
      // type and message, never a stack trace, which names machine paths.
      outputs.add(
        _Output(
          file,
          '.format-error',
          paths.scrub('${e.runtimeType}: $e\n'),
          settings: settings,
        ),
      );
    }
  }
  await collection.dispose();
  return outputs;
}

Version _parseLanguageVersion(String text) {
  final match = RegExp(r'^(\d+)\.(\d+)$').firstMatch(text);
  if (match == null) {
    throw ArgumentError.value(text, 'languageVersion', 'expected major.minor');
  }
  return Version(int.parse(match[1]!), int.parse(match[2]!), 0);
}

/// The language version a package declares: the lower bound of
/// `environment: sdk:` in the nearest `pubspec.yaml` above a file.
class _PubspecLanguageVersions {
  final _byDirectory = <String, Version>{};

  Version forFile(String path) => _forDirectory(p.dirname(path));

  Version _forDirectory(String dir) => _byDirectory.putIfAbsent(dir, () {
    final pubspec = File(p.join(dir, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      return _declared(pubspec) ?? DartFormatter.latestLanguageVersion;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return DartFormatter.latestLanguageVersion;
    return _forDirectory(parent);
  });

  static Version? _declared(File pubspec) {
    try {
      final yaml = loadYaml(pubspec.readAsStringSync());
      final environment = yaml is YamlMap ? yaml['environment'] : null;
      final sdk = environment is YamlMap ? environment['sdk'] : null;
      if (sdk is! String) return null;
      final constraint = VersionConstraint.parse(sdk);
      if (constraint is VersionRange && constraint.min != null) {
        final min = constraint.min!;
        return Version(min.major, min.minor, 0);
      }
    } on Object {
      return null;
    }
    return null;
  }
}

Future<List<_Output>> _analyze(Corpus corpus, _PathScrubber paths) async {
  final collection = AnalysisContextCollection(
    includedPaths: corpus.rootsByLabel.values.toList(),
  );
  final outputs = <_Output>[];
  try {
    for (final file in corpus.files) {
      try {
        final context = collection.contextFor(file.absolutePath);
        final result = await context.currentSession.getErrors(
          file.absolutePath,
        );
        if (result is ErrorsResult) {
          outputs.add(
            _Output(
              file,
              '.diagnostics.jsonl',
              _diagnosticLines(result.diagnostics, paths),
            ),
          );
        } else {
          outputs.add(
            _Output(file, '.analyze-error', '${result.runtimeType}\n'),
          );
        }
      } on Object catch (e) {
        outputs.add(
          _Output(
            file,
            '.analyze-error',
            paths.scrub('${e.runtimeType}: $e\n'),
          ),
        );
      }
    }
  } finally {
    await collection.dispose();
  }
  return outputs;
}

/// One canonical JSON object per line, sorted by offset, then code, then
/// the remaining fields so that equal (offset, code) pairs still order the
/// same way every run.
String _diagnosticLines(List<Diagnostic> diagnostics, _PathScrubber paths) {
  final records = [
    for (final d in diagnostics)
      <String, Object?>{
        'offset': d.offset,
        'code': d.diagnosticCode.lowerCaseName,
        'severity': d.diagnosticCode.severity.name.toLowerCase(),
        'length': d.length,
        'message': paths.scrub(d.message),
      },
  ];
  int compare(Map<String, Object?> a, Map<String, Object?> b) {
    for (final key in ['offset', 'code', 'length', 'severity', 'message']) {
      final c = (a[key] as Comparable).compareTo(b[key]);
      if (c != 0) return c;
    }
    return 0;
  }

  records.sort(compare);
  return records.map((r) => '${jsonEncode(r)}\n').join();
}

/// Replaces machine-specific absolute paths in recorded text with stable
/// names: each corpus root becomes its label, its parent `<label>/..`, the
/// running Dart SDK `<dart-sdk>` and the pub cache `<pub-cache>`.
class _PathScrubber {
  final List<(String, String)> _replacements;

  _PathScrubber(Map<String, String> rootsByLabel)
    : _replacements = _build(rootsByLabel);

  static List<(String, String)> _build(Map<String, String> rootsByLabel) {
    final pairs = <(String, String)>[
      for (final MapEntry(key: label, value: root) in rootsByLabel.entries) ...[
        (root, label),
        (p.dirname(root), '$label/..'),
      ],
      (p.dirname(p.dirname(Platform.resolvedExecutable)), '<dart-sdk>'),
      (_pubCache(), '<pub-cache>'),
    ];
    // Longest first, so a root is replaced before its parent.
    pairs.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    return pairs.where((pair) => pair.$1.length > 1).toList();
  }

  static String _pubCache() {
    final env = Platform.environment['PUB_CACHE'];
    if (env != null && env.isNotEmpty) return p.normalize(p.absolute(env));
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, '.pub-cache');
  }

  String scrub(String text) {
    var result = text;
    for (final (from, to) in _replacements) {
      result = result.replaceAll(from, to);
    }
    return result;
  }
}
