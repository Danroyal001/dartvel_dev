import 'dart:io';

import 'package:path/path.dart' as p;

import '../build/render_backends.dart';
import 'routes_generator.dart' as routes;

/// What `dartvel generate --check` found.
class DVGenerateCheckResult {
  const DVGenerateCheckResult({
    required this.stale,
    required this.unstable,
    this.lineChanges = const <String, (int, int)>{},
  });

  /// DV-GEN-001: paths that running the generator would change, add or
  /// remove. Forward slashes, relative to the project, sorted.
  final List<String> stale;

  /// DV-GEN-002: paths that came out different from two generations of the
  /// same input, at two different locations.
  final List<String> unstable;

  /// For each stale path, the lines regenerating would add and remove, as
  /// `(added, removed)`. A file only one side has counts all its lines on
  /// that side. Counted as a multiset of lines rather than a minimal edit
  /// script, so a moved line is one added and one removed.
  final Map<String, (int, int)> lineChanges;

  bool get ok => stale.isEmpty && unstable.isEmpty;
}

/// Directories neither copied nor compared. None is generation input:
/// version control, tool caches and dependency installs. `.dart_tool` also
/// holds the backend half of the output, which is never committed, so a
/// project that has not built since a clone is not stale for lacking it.
const Set<String> _notCompared = <String>{'.git', '.dart_tool', 'node_modules'};

/// Regenerates [root] into a scratch location and compares, without writing
/// anything into [root].
///
/// The project is copied twice, to two different paths, and generated in
/// each. The first copy is compared with the project: anything that differs
/// is stale. The two copies are compared with each other: anything that
/// differs is output that depends on something other than the input — a
/// clock, a listing order, where the project happens to be.
///
/// [generator] is the real orchestrator unless a test supplies one.
Future<DVGenerateCheckResult> dvGenerateCheck(
  String root, {
  Future<void> Function(String root)? generator,
  Set<DVRenderBackend>? renderBackends,
}) async {
  final Future<void> Function(String) generate = generator ??
      (String at) => routes.generate(root_: at, renderBackends: renderBackends);
  final Directory project = Directory(root).absolute;
  final Directory scratch =
      Directory.systemTemp.createTempSync('dartvel_generate_check_');
  try {
    // Same folder name in both, so a project whose output did depend on its
    // own name is reported once, as unstable, rather than stale everywhere.
    final String name = p.basename(project.path);
    final Directory first = Directory(p.join(scratch.path, 'a', name));
    final Directory second = Directory(p.join(scratch.path, 'b', name));
    _copy(project, first);
    _copy(project, second);

    await generate(first.path);
    await generate(second.path);

    final List<String> stale =
        _differences(project, first, skip: _notCompared);
    return DVGenerateCheckResult(
      stale: stale,
      lineChanges: <String, (int, int)>{
        for (final String path in stale)
          path: _lineChanges(
            File(p.join(project.path, path)),
            File(p.join(first.path, path)),
          ),
      },
      unstable: _differences(first, second, skip: const <String>{}),
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

void _copy(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final FileSystemEntity entity in from.listSync(followLinks: false)) {
    final String name = p.basename(entity.path);
    if (_notCompared.contains(name)) continue;
    final String target = p.join(to.path, name);
    if (entity is Link) {
      Link(target).createSync(entity.targetSync());
    } else if (entity is Directory) {
      _copy(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Every file under [root] by forward-slash relative path, skipping any
/// directory named in [skip] at any depth.
Map<String, File> _files(Directory root, Set<String> skip) {
  final Map<String, File> files = <String, File>{};
  void walk(Directory dir) {
    for (final FileSystemEntity entity in dir.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (!skip.contains(p.basename(entity.path))) walk(entity);
      } else if (entity is File) {
        files[p.relative(entity.path, from: root.path).replaceAll(r'\', '/')] =
            entity;
      }
    }
  }

  if (root.existsSync()) walk(root);
  return files;
}

List<String> _differences(Directory a, Directory b,
    {required Set<String> skip}) {
  final Map<String, File> left = _files(a, skip);
  final Map<String, File> right = _files(b, skip);
  final List<String> differing = <String>[
    for (final String path in <String>{...left.keys, ...right.keys})
      if (left[path] == null ||
          right[path] == null ||
          !_sameBytes(left[path]!, right[path]!))
        path,
  ]..sort();
  return differing;
}

bool _sameBytes(File a, File b) {
  if (a.lengthSync() != b.lengthSync()) return false;
  final List<int> x = a.readAsBytesSync();
  final List<int> y = b.readAsBytesSync();
  for (int i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

(int, int) _lineChanges(File before, File after) {
  List<String> lines(File f) {
    if (!f.existsSync()) return const <String>[];
    try {
      return f.readAsLinesSync();
    } on FormatException {
      return const <String>[];
    }
  }

  final Map<String, int> remaining = <String, int>{};
  for (final String line in lines(before)) {
    remaining[line] = (remaining[line] ?? 0) + 1;
  }
  int added = 0;
  for (final String line in lines(after)) {
    final int count = remaining[line] ?? 0;
    if (count > 0) {
      remaining[line] = count - 1;
    } else {
      added++;
    }
  }
  final int removed = remaining.values.fold(0, (int a, int b) => a + b);
  return (added, removed);
}
