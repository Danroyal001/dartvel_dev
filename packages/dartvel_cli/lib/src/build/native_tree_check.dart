/// Where target-specific code lives.
///
/// Package Structure: target-specific and runtime-specific implementation
/// lives under `native/`, in a directory named for the target or runtime,
/// and there is no top-level `wasm/` or `nodejs/` integration tree beside
/// it -- a second location for the same kind of thing is how a convention
/// stops being one. A `native/` directory named for no target is work that
/// nothing reads, and the specification's rule for that is to fail during
/// validation rather than silently ignore it.
///
/// Top-level `web/` is not refused: it is Flutter's web scaffold, which
/// `dartvel build web` generates and Flutter reads from nowhere else.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'build_target.dart' show dvPaidTargets;

/// The directory names `native/` may hold: every target the specification
/// lists, the three runtimes, and every other target Dartvel builds.
final Set<String> dvNativeDirectories = <String>{
  'android', 'ios', 'macos', 'windows', 'linux', //
  'fireos', 'tvos', 'tizen', 'webos', 'sony-elinux', 'fuchsia',
  'web', 'wasm', 'nodejs',
  ...dvPaidTargets.keys,
};

/// Top-level trees that belong under `native/` instead.
const List<String> dvTopLevelIntegrationTrees = <String>['wasm', 'nodejs'];

class DVNativeTreeCheck {
  const DVNativeTreeCheck({required this.ok, required this.lines});

  /// Whether the layout is one the build reads all of.
  final bool ok;

  /// What to print. Empty when there is nothing wrong.
  final List<String> lines;

  static DVNativeTreeCheck run(String root) {
    final List<String> lines = <String>[];

    for (final String tree in dvTopLevelIntegrationTrees) {
      final Directory directory = Directory(p.join(root, tree));
      if (_holdsFiles(directory)) {
        lines.add(
          '   $tree/ is a top-level integration tree. Move it to '
          'native/$tree/: target- and runtime-specific code has one home.',
        );
      }
    }

    final Directory native = Directory(p.join(root, 'native'));
    if (native.existsSync()) {
      final List<Directory> children =
          native.listSync(followLinks: false).whereType<Directory>().toList()
            ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
      for (final Directory child in children) {
        final String name = p.basename(child.path);
        if (name.startsWith('.') || dvNativeDirectories.contains(name)) {
          continue;
        }
        if (!_holdsFiles(child)) continue;
        final String nearest = _nearest(name);
        lines.add(
          '   native/$name/ is named for no target, so no build reads '
          'it. Did you mean native/$nearest/? Valid names: '
          '${(dvNativeDirectories.toList()..sort()).join(', ')}.',
        );
      }
    }

    return DVNativeTreeCheck(ok: lines.isEmpty, lines: lines);
  }

  static bool _holdsFiles(Directory directory) {
    if (!directory.existsSync()) return false;
    return directory
        .listSync(recursive: true, followLinks: false)
        .any((FileSystemEntity entity) => entity is File);
  }

  static String _nearest(String name) {
    String best = dvNativeDirectories.first;
    int bestDistance = 1 << 30;
    for (final String candidate in dvNativeDirectories) {
      final int distance = _editDistance(name, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int _editDistance(String from, String to) {
    List<int> previous = List<int>.generate(to.length + 1, (int i) => i);
    for (int row = 1; row <= from.length; row++) {
      final List<int> current = List<int>.filled(to.length + 1, 0)..[0] = row;
      for (int column = 1; column <= to.length; column++) {
        final int substitution = from[row - 1] == to[column - 1] ? 0 : 1;
        current[column] = <int>[
          previous[column] + 1,
          current[column - 1] + 1,
          previous[column - 1] + substitution,
        ].reduce((int a, int b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous[to.length];
  }
}
