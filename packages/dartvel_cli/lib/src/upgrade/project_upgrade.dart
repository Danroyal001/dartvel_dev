/// What `dartvel upgrade --project` does: moves the Dartvel constraints in a
/// project's pubspec.yaml to the release of the CLI it is run with.
///
/// It exists because a caret does not cross a version line. Dartvel was 0.x
/// until 0.13.51 and takes Flutter's major and minor from 3.47.0, and
/// `^0.13.51` stops below 0.14.0, so `pub upgrade` keeps an existing project
/// on 0.13.51 and reports nothing wrong. The constraint has to change, and a
/// constraint is text in a file the developer owns: only the constraint is
/// rewritten, in place, and every comment, blank line and other dependency is
/// left as written.
library;

import 'package:pub_semver/pub_semver.dart';

import '../templates/project_templates.dart';

/// The packages published together as one Dartvel release.
const List<String> dvReleasedPackages = <String>[
  'dartvel_core',
  'dartvel_shelf',
  'dartvel_flutter',
  'dartvel_scene',
  'dartvel_generator',
  'dartvel_cli',
  'dartvel_dev',
];

/// One constraint that was moved.
class DVConstraintMove {
  const DVConstraintMove(this.package, this.from, this.to);
  final String package;
  final String from;
  final String to;
}

/// One Dartvel dependency that was not moved, and why.
class DVConstraintLeft {
  const DVConstraintLeft(this.package, this.reason);
  final String package;
  final String reason;
}

/// The result of planning the rewrite of one pubspec.
class DVProjectUpgrade {
  const DVProjectUpgrade({
    required this.pubspec,
    required this.moved,
    required this.left,
    required this.blocked,
  });

  /// The pubspec to write. The text it was given when nothing moves, or when
  /// anything is [blocked].
  final String pubspec;
  final List<DVConstraintMove> moved;
  final List<DVConstraintLeft> left;

  /// Reasons the project cannot be moved at all. Nothing is rewritten while
  /// there is one.
  final List<String> blocked;
}

String _targetFor(String package) =>
    package == 'dartvel_shelf' ? dartvelShelfVersion : dartvelPackageVersion;

final RegExp _topLevelKey = RegExp(r'^([A-Za-z_][\w]*):');
final RegExp _entry = RegExp(r'^  (dartvel_\w+):[ \t]*([^#\n]*?)[ \t]*(#.*)?$');
final RegExp _nestedVersion = RegExp(
  r'''^(\s{4,}version:[ \t]*)(["']?)([^"'#\n]+?)\2([ \t]*(?:#.*)?)$''',
);

/// [pubspecText] with each hosted Dartvel constraint that excludes this CLI's
/// release replaced by a caret on it.
DVProjectUpgrade dvUpgradeProjectPubspec(String pubspecText) {
  final List<String> lines = pubspecText.split('\n');
  final List<DVConstraintMove> moved = <DVConstraintMove>[];
  final List<DVConstraintLeft> left = <DVConstraintLeft>[];
  final List<String> blocked = <String>[];

  String? section;
  for (int i = 0; i < lines.length; i += 1) {
    final String line = lines[i];
    final RegExpMatch? top = _topLevelKey.firstMatch(line);
    if (top != null) {
      section = top.group(1);
      continue;
    }
    if (section != 'dependencies' &&
        section != 'dev_dependencies' &&
        section != 'dependency_overrides') {
      continue;
    }
    final RegExpMatch? entry = _entry.firstMatch(line);
    if (entry == null) continue;
    final String package = entry.group(1)!;
    if (!dvReleasedPackages.contains(package)) continue;
    final String target = _targetFor(package);

    if (section == 'dependency_overrides') {
      left.add(
        DVConstraintLeft(
          package,
          'a dependency override, which bypasses constraint solving; set it '
              'to $target by hand or remove it',
        ),
      );
      continue;
    }

    final String inline = entry.group(2)!;
    if (inline.isNotEmpty) {
      final String text = _unquote(inline);
      final String? replacement = _moveConstraint(
        package,
        text,
        target,
        left,
        blocked,
      );
      if (replacement == null) continue;
      final String comment = entry.group(3) == null ? '' : ' ${entry.group(3)}';
      lines[i] = '  $package: $replacement$comment';
      moved.add(DVConstraintMove(package, text, replacement));
      continue;
    }

    // The long form: the constraint, if there is one, is a nested `version:`.
    int? versionLine;
    for (int j = i + 1; j < lines.length; j += 1) {
      if (lines[j].trim().isEmpty) continue;
      if (!lines[j].startsWith('    ')) break;
      if (_nestedVersion.hasMatch(lines[j])) {
        versionLine = j;
        break;
      }
    }
    if (versionLine == null) {
      left.add(
        DVConstraintLeft(
          package,
          'declared from a path, git or SDK source, which has no version to '
              'move',
        ),
      );
      continue;
    }
    final RegExpMatch nested = _nestedVersion.firstMatch(lines[versionLine])!;
    final String text = nested.group(3)!.trim();
    final String? replacement = _moveConstraint(
      package,
      text,
      target,
      left,
      blocked,
    );
    if (replacement == null) continue;
    lines[versionLine] = '${nested.group(1)}$replacement${nested.group(4)}';
    moved.add(DVConstraintMove(package, text, replacement));
  }

  if (blocked.isNotEmpty) {
    return DVProjectUpgrade(
      pubspec: pubspecText,
      moved: const <DVConstraintMove>[],
      left: left,
      blocked: blocked,
    );
  }
  return DVProjectUpgrade(
    pubspec: moved.isEmpty ? pubspecText : lines.join('\n'),
    moved: moved,
    left: left,
    blocked: blocked,
  );
}

String _unquote(String value) {
  final String trimmed = value.trim();
  if (trimmed.length >= 2 &&
      (trimmed.startsWith('"') && trimmed.endsWith('"') ||
          trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

/// The constraint to write in place of [text], or null when it stays.
String? _moveConstraint(
  String package,
  String text,
  String targetText,
  List<DVConstraintLeft> left,
  List<String> blocked,
) {
  final Version target = Version.parse(targetText);
  final VersionConstraint constraint;
  try {
    constraint = VersionConstraint.parse(text);
  } on FormatException {
    left.add(
      DVConstraintLeft(package, '"$text" is not a constraint this can read'),
    );
    return null;
  }
  if (constraint.allows(target)) return null;
  final Version? floor = constraint is Version
      ? constraint
      : (constraint is VersionRange ? constraint.min : null);
  if (floor != null && floor > target) {
    blocked.add(
      '$package "$text" is newer than this CLI\'s $targetText; run `dartvel '
      'update` and try again rather than moving backwards',
    );
    return null;
  }
  return '^$targetText';
}
