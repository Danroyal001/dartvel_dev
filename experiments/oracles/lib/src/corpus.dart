import 'dart:io';

import 'package:path/path.dart' as p;

/// One `.dart` file found under a corpus root.
class CorpusFile {
  /// The label of the root it was found under.
  final String rootLabel;

  /// Absolute path on this machine. Never written to a dump.
  final String absolutePath;

  /// `<rootLabel>/<path below the root>`, always with `/` separators. This is
  /// the only name a dump uses for the file.
  final String relativePath;

  const CorpusFile(this.rootLabel, this.absolutePath, this.relativePath);
}

/// The roots of a corpus and every `.dart` file under them.
///
/// A root is named by a label, its basename, so nothing written to a dump
/// depends on where the corpus sits on this machine. Two roots with the same
/// basename are told apart as `lib`, `lib~2`, … in command-line order.
///
/// Files are found without following links, skipping every directory whose
/// name starts with `.` (`.dart_tool`, `.git`), and sorted by relative path
/// in code-unit order.
class Corpus {
  /// Label -> absolute, normalized root path, in command-line order.
  final Map<String, String> rootsByLabel;

  /// Every `.dart` file, sorted by [CorpusFile.relativePath].
  final List<CorpusFile> files;

  Corpus._(this.rootsByLabel, this.files);

  static Corpus discover(List<String> roots) {
    final rootsByLabel = <String, String>{};
    final files = <CorpusFile>[];
    for (final root in roots) {
      final absolute = p.normalize(p.absolute(root));
      if (!Directory(absolute).existsSync()) {
        throw ArgumentError.value(root, 'roots', 'is not a directory');
      }
      final base = p.basename(absolute);
      var label = base;
      for (var n = 2; rootsByLabel.containsKey(label); n++) {
        label = '$base~$n';
      }
      rootsByLabel[label] = absolute;
      _walk(Directory(absolute), absolute, label, files);
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return Corpus._(rootsByLabel, files);
  }

  static void _walk(
    Directory dir,
    String root,
    String label,
    List<CorpusFile> into,
  ) {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (!name.startsWith('.')) _walk(entity, root, label, into);
      } else if (entity is File && name.endsWith('.dart')) {
        final below = p.split(p.relative(entity.path, from: root)).join('/');
        into.add(CorpusFile(label, entity.path, '$label/$below'));
      }
    }
  }
}
