/// `dartvel test --impacted`: the tests a diff can reach.
///
/// The usual way to answer this is to infer it from the coverage of the last
/// run. Dartvel does not have to: the project knows what each test imports
/// and the project graph knows which models, functions, routes and jobs each
/// changed file declares. The answer is a query against those, which also
/// sees what coverage does not -- a backend function a test calls over HTTP
/// and never imports.
///
/// The silent failure here is a test that should have run and did not, so
/// every doubt widens the set. A changed file the query cannot place -- a
/// migration, the pubspec, configuration, an asset -- runs everything, and
/// the command refuses outright on a dirty generated tree (DV-GEN-001), where
/// the graph it queries is stale and the answer confidently wrong.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/generate_check.dart';
import '../graph/project_graph.dart';

/// Where `--impacted` gets the diff and the generated tree's state from.
///
/// Both are functions so a test can answer them without a repository or a
/// generator run; the defaults ask git and `dartvel generate --check`.
class DartvelImpactSource {
  const DartvelImpactSource({
    this.changed = _gitChanged,
    this.staleGenerated = _staleGenerated,
  });

  /// The project-relative paths the diff touches, deleted files included.
  final Future<List<String>> Function(String root) changed;

  /// The generated paths that regenerating would change: DV-GEN-001.
  final Future<List<String>> Function(String root) staleGenerated;

  /// What changed against HEAD, staged or not, plus files git does not track
  /// yet -- a new test is part of the diff.
  static Future<List<String>> _gitChanged(String root) async {
    final ProcessResult diff = await Process.run(
      'git',
      <String>['diff', '--name-only', '--relative', 'HEAD'],
      workingDirectory: root,
    );
    if (diff.exitCode != 0) {
      throw StateError('--impacted needs a git repository: ${diff.stderr}');
    }
    final ProcessResult untracked = await Process.run(
      'git',
      <String>['ls-files', '--others', '--exclude-standard'],
      workingDirectory: root,
    );
    return <String>[
      ...'${diff.stdout}'.split('\n'),
      ...'${untracked.stdout}'.split('\n'),
    ].map((String l) => l.trim()).where((String l) => l.isNotEmpty).toList();
  }

  static Future<List<String>> _staleGenerated(String root) async =>
      (await dvGenerateCheck(root)).stale;
}

/// Selects the impacted tests.
abstract final class DartvelImpactedTests {
  /// The test files under `test/` that [changed] can reach, relative to
  /// [root] with forward slashes; null when a change cannot be placed and the
  /// whole suite has to run.
  static Future<Set<String>?> select({
    required String root,
    required List<String> changed,
  }) async {
    final Set<String> changedDart = <String>{};
    for (final String raw in changed) {
      final String path = raw.replaceAll('\\', '/');
      // Prose changes nothing a test can observe.
      if (path.endsWith('.md')) continue;
      final bool placed = path.endsWith('.dart') &&
          (path.startsWith('lib/') || path.startsWith('test/'));
      if (!placed) return null;
      changedDart.add(path);
    }
    if (changedDart.isEmpty) return <String>{};

    final String package = _packageName(root);
    final Map<String, Set<String>> imports = <String, Set<String>>{};
    final Map<String, String> sources = <String, String>{};
    for (final String file in _dartFiles(root)) {
      final String source = File(p.join(root, file)).readAsStringSync();
      sources[file] = source;
      imports[file] = _importsOf(file, source, package);
    }

    // What the changed files declare, as the strings a test would use to
    // reach them without importing them: a data model's public name, a
    // function's or a page's path, a job's name.
    final DartvelProjectGraph graph =
        await DartvelProjectGraph.build(root: root, pkgName: package);
    bool declaredInChange(String source) =>
        changedDart.contains(source.split(':').first);
    final List<RegExp> names = <RegExp>[
      for (final DVGraphModel m in graph.models)
        if (declaredInChange(m.source)) RegExp('\\b${RegExp.escape(m.name)}\\b'),
      for (final DVGraphJob j in graph.jobs)
        if (declaredInChange(j.source)) RegExp('\\b${RegExp.escape(j.name)}\\b'),
    ];
    final List<String> paths = <String>[
      for (final DVGraphFunction f in graph.functions)
        if (declaredInChange(f.source)) _literalPrefix(f.path),
      for (final DVGraphRoute r in graph.routes)
        if (declaredInChange(r.source)) _literalPrefix(r.path),
    ];

    final Set<String> impacted = <String>{};
    for (final String test in sources.keys) {
      if (!test.startsWith('test/') || !test.endsWith('_test.dart')) continue;
      final String source = sources[test]!;
      if (_reaches(test, imports, changedDart) ||
          names.any((RegExp name) => name.hasMatch(source)) ||
          paths.any(source.contains)) {
        impacted.add(test);
      }
    }
    // A changed test that is not on disk any more has nothing to run.
    return impacted;
  }

  /// Whether [from], or anything it imports transitively, is in [targets].
  /// A path that is not on disk -- a deleted file -- is still a node, so a
  /// test that imported it is reached.
  static bool _reaches(
    String from,
    Map<String, Set<String>> imports,
    Set<String> targets,
  ) {
    final Set<String> seen = <String>{};
    final List<String> queue = <String>[from];
    while (queue.isNotEmpty) {
      final String next = queue.removeLast();
      if (!seen.add(next)) continue;
      if (targets.contains(next)) return true;
      queue.addAll(imports[next] ?? const <String>{});
    }
    return false;
  }

  static final RegExp _directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  static Set<String> _importsOf(String file, String source, String package) {
    final Set<String> found = <String>{};
    for (final Match match in _directive.allMatches(source)) {
      final String uri = match.group(1)!;
      if (uri.startsWith('package:$package/')) {
        found.add('lib/${uri.substring('package:$package/'.length)}');
      } else if (!uri.contains(':')) {
        found.add(p.posix.normalize(p.posix.join(p.posix.dirname(file), uri)));
      }
    }
    return found;
  }

  /// A path up to its first parameter: `/blog/<id>` is reached by a test
  /// that calls `/blog/`.
  static String _literalPrefix(String path) {
    final int param = path.indexOf('<');
    return param == -1 ? path : path.substring(0, param);
  }

  static List<String> _dartFiles(String root) => <String>[
        for (final String dir in <String>['lib', 'test'])
          if (Directory(p.join(root, dir)).existsSync())
            for (final FileSystemEntity e in Directory(p.join(root, dir))
                .listSync(recursive: true, followLinks: false))
              if (e is File && e.path.endsWith('.dart'))
                p.relative(e.path, from: root).replaceAll('\\', '/'),
      ]..sort();

  static String _packageName(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return '';
    final Match? name = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    return name?.group(1) ?? '';
  }
}
