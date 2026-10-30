import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One output file that two dumps do not agree on.
class FileDifference {
  /// The file's path inside the dump, with `/` separators.
  final String path;

  /// What differs: which side lacks the file, or the first differing line.
  final String description;

  const FileDifference(this.path, this.description);

  @override
  String toString() => '$path: $description';
}

/// The result of [compareDumps].
class Comparison {
  /// Every output file that differs, sorted by path.
  final List<FileDifference> differences;

  /// Manifest fields that differ but do not decide the result, such as the
  /// tool versions: a port names itself, and that is not a mismatch.
  final List<String> notes;

  const Comparison(this.differences, this.notes);

  bool get identical => differences.isEmpty;
}

/// Manifest fields that describe who produced a dump rather than what it
/// contains. Everything else in the manifest is checked by the files
/// themselves.
const _metadataFields = ['tool', 'toolVersions', 'dartSdk', 'settings'];

/// Compares every output file of two dumps byte for byte. `manifest.json`
/// is not compared as bytes, because it names the tool that wrote the dump;
/// its descriptive fields are reported as [Comparison.notes].
Comparison compareDumps(String dirA, String dirB) {
  final manifestA = _manifest(dirA);
  final manifestB = _manifest(dirB);
  final filesA = _files(dirA);
  final filesB = _files(dirB);
  final paths = {...filesA.keys, ...filesB.keys}.toList()..sort();

  final differences = <FileDifference>[];
  for (final path in paths) {
    final a = filesA[path];
    final b = filesB[path];
    if (b == null) {
      differences.add(FileDifference(path, 'only in A'));
    } else if (a == null) {
      differences.add(FileDifference(path, 'only in B'));
    } else {
      final bytesA = a.readAsBytesSync();
      final bytesB = b.readAsBytesSync();
      final description = _firstDifference(bytesA, bytesB);
      if (description != null) {
        differences.add(FileDifference(path, description));
      }
    }
  }

  final notes = <String>[
    for (final field in _metadataFields)
      if (jsonEncode(manifestA[field]) != jsonEncode(manifestB[field]))
        '$field: A=${jsonEncode(manifestA[field])} '
            'B=${jsonEncode(manifestB[field])}',
  ];
  return Comparison(differences, notes);
}

Map<String, Object?> _manifest(String dir) {
  final file = File(p.join(dir, 'manifest.json'));
  if (!file.existsSync()) {
    throw ArgumentError.value(dir, 'dir', 'has no manifest.json; not a dump');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw ArgumentError.value(dir, 'dir', 'manifest.json is not an object');
  }
  return decoded;
}

/// Every file under [dir] except the top-level manifest, by `/` path.
Map<String, File> _files(String dir) => {
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File && !p.equals(entity.path, p.join(dir, 'manifest.json')))
      p.split(p.relative(entity.path, from: dir)).join('/'): entity,
};

/// `null` when equal; otherwise the first differing line, 1-based, with both
/// versions of it.
String? _firstDifference(List<int> a, List<int> b) {
  var index = 0;
  final shorter = a.length < b.length ? a.length : b.length;
  while (index < shorter && a[index] == b[index]) {
    index++;
  }
  if (index == a.length && index == b.length) return null;

  var line = 1;
  var lineStart = 0;
  for (var i = 0; i < index; i++) {
    if (a[i] == 0x0A) {
      line++;
      lineStart = i + 1;
    }
  }
  String lineOf(List<int> bytes) {
    if (lineStart >= bytes.length) return '<end of file>';
    var end = bytes.indexOf(0x0A, lineStart);
    if (end < 0) end = bytes.length;
    final text = utf8.decode(
      bytes.sublist(lineStart, end),
      allowMalformed: true,
    );
    return jsonEncode(text.length > 200 ? '${text.substring(0, 200)}…' : text);
  }

  return 'first difference at line $line, byte $index: '
      'A ${lineOf(a)} | B ${lineOf(b)} '
      '(A is ${a.length} bytes, B is ${b.length})';
}
