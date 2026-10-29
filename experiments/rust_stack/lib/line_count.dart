/// Counting what the Rust port has to port, the way the proposal states it:
/// non-blank lines, split into implementation and tests, per language.
///
/// The rules live here rather than in a shell pipeline so that a reader can
/// check them and a test can hold them still. The proposal's Part 2 table is
/// only worth something if the next measurement counts the same way.
library;

import 'dart:io';

/// The languages the port reads. Everything else in a checkout (Java, Python,
/// GN files, docs) is not counted, because it is not ported.
enum Language { dart, cpp, objc }

/// One row of the proposal's Part 2 table: a named part of upstream, as one
/// or more directories under a checkout, minus anything another row counts.
final class Component {
  const Component({
    required this.name,
    required this.roots,
    this.checkout = 'sdk',
    this.excludes = const [],
    this.languages,
    this.ported = true,
    this.partOf,
  });

  final String name;

  /// Which upstream checkout [roots] are in: a key of `checkouts`.
  final String checkout;

  /// Directories relative to the checkout root.
  final List<String> roots;

  /// Directories under [roots] that belong to another row.
  final List<String> excludes;

  /// The languages this row counts, or every [Language] when null. The
  /// engine's `lib/ui` holds both the C++ natives, which are ported, and the
  /// `dart:ui` sources, which are API surface; this is how the row keeps them
  /// apart.
  final Set<Language>? languages;

  /// Whether the proposal ports this component or keeps it as API surface.
  final bool ported;

  /// The row this one is a breakdown of ("...of which"), or null. A breakdown
  /// is printed but never added to a total, which would count it twice.
  final String? partOf;
}

final class Count {
  Count(this.component);

  final Component component;
  int implementation = 0;
  int tests = 0;
  final Map<Language, int> byLanguage = {};

  int get total => implementation + tests;
}

/// Lines with at least one non-whitespace character.
int countNonBlank(String text) {
  var count = 0;
  for (final line in text.split('\n')) {
    if (line.trim().isNotEmpty) count++;
  }
  return count;
}

Language? languageOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < path.lastIndexOf('/')) return null;
  return switch (path.substring(dot + 1)) {
    'dart' => .dart,
    'cc' || 'cpp' || 'cxx' || 'c' || 'h' || 'hpp' => .cpp,
    'mm' || 'm' => .objc,
    _ => null,
  };
}

const _testDirectories = {
  'test',
  'tests',
  'testing',
  'testcases',
  'test_data',
  'testdata',
  'fixture',
  'fixtures',
  'benchmark',
  'benchmarks',
};

/// `ffi_test/`, `ffi_unit_test/`, `parser_testcases/`, `dap_tests/`: a
/// directory named for what it tests, then the word.
const _testDirectorySuffixes = ['_test', '_tests', '_testcases'];

const _testFileSuffixes = [
  '_test',
  '_tests',
  '_unittest',
  '_unittests',
  '_benchmark',
  '_benchmarks',
];

/// Whether a file counts as a test: its path names a test, fixture, benchmark
/// or testing directory, or its own name says it is one.
///
/// The file-name rule is needed because the Dart VM and the Flutter engine
/// keep their tests beside the code (`object.cc`, `object_test.cc`). One
/// exception to the directory rule: in Dart, everything under `lib/` ships, so
/// `flutter_tools/lib/src/test/` is the implementation of `flutter test`, not
/// a test of it.
bool isTestPath(String path) {
  final segments = path.split('/');
  final file = segments.removeLast();
  final stem = file.contains('.') ? file.substring(0, file.indexOf('.')) : file;
  if (_testFileSuffixes.any(stem.endsWith)) return true;

  final isDart = languageOf(path) == Language.dart;
  for (final segment in segments) {
    if (isDart && segment == 'lib') return false;
    if (_testDirectories.contains(segment)) return true;
    if (_testDirectorySuffixes.any(segment.endsWith)) return true;
  }
  return false;
}

const _neverCounted = {'.dart_tool', '.git', 'third_party'};

/// Build output a fresh checkout may still carry, at the top of a root only:
/// a source directory deeper down that happens to be called `build` is code.
const _outputsAtRoot = {'build', 'out'};

/// Counts [component] under [checkout]. A root that does not exist is an
/// error: a zero would read as a measurement.
Count measure(Component component, Directory checkout) {
  final count = Count(component);
  final excludes = [
    for (final exclude in component.excludes) '${checkout.path}/$exclude',
  ];

  for (final root in component.roots) {
    final directory = Directory('${checkout.path}/$root');
    if (!directory.existsSync()) {
      throw StateError('${component.name}: $root is not in ${checkout.path}');
    }
    _walk(directory, root, excludes, count, atRoot: true);
  }
  return count;
}

void _walk(
  Directory directory,
  String relative,
  List<String> excludes,
  Count count, {
  required bool atRoot,
}) {
  final entries = directory.listSync(followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entry in entries) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final path = '$relative/$name';
    if (entry is Directory) {
      if (_neverCounted.contains(name)) continue;
      if (atRoot && _outputsAtRoot.contains(name)) continue;
      if (excludes.any(
        (e) => entry.path == e || entry.path.startsWith('$e/'),
      )) {
        continue;
      }
      _walk(entry, path, excludes, count, atRoot: false);
    } else if (entry is File) {
      final language = languageOf(name);
      if (language == null) continue;
      final only = count.component.languages;
      if (only != null && !only.contains(language)) continue;
      final lines = countNonBlank(entry.readAsStringSync());
      if (isTestPath(path)) {
        count.tests += lines;
      } else {
        count.implementation += lines;
      }
      count.byLanguage[language] = (count.byLanguage[language] ?? 0) + lines;
    }
  }
}
