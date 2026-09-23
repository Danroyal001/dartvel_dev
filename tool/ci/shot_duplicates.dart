// Two routes cannot honestly have the same picture.
//
// The site build photographs every route at two sizes and checks that each
// picture is not one flat colour. A docs page draws its sidebar from the
// shell's chunk and its article from the route's own, so a capture taken
// between the two is a full sidebar and an empty page: plenty of variation,
// nothing wrong reported. One build produced 23 under-rendered pictures out
// of 57 that way, and 12 of them were byte-identical to each other.
//
// Identical bytes is the part that cannot be argued with. Two different
// routes that produced the same file did not both render, whatever the
// reason, so this fails the build and names them.
//
// Usage: dart tool/ci/shot_duplicates.dart <dir-of-pngs>
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: shot_duplicates.dart <dir>');
    exit(2);
  }

  final Directory dir = Directory(args.single);
  if (!dir.existsSync()) {
    stderr.writeln('::error::${dir.path} does not exist');
    exit(1);
  }

  // Grouped by the bytes, per size: the same route at two sizes is expected
  // to differ, and two sizes never collide anyway, but grouping by size keeps
  // the message readable.
  final Map<String, List<String>> byContent = <String, List<String>>{};
  int counted = 0;
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.png')) continue;
    counted++;
    final List<int> bytes = entity.readAsBytesSync();
    // The bytes themselves as the key. A hash would do, and would need a
    // dependency; a screenshot is under a megabyte and there are a hundred.
    final String key = String.fromCharCodes(bytes);
    byContent.putIfAbsent(key, () => <String>[]).add(
          entity.uri.pathSegments.last,
        );
  }

  if (counted == 0) {
    stderr.writeln('::error::no screenshots in ${dir.path}');
    exit(1);
  }

  final List<List<String>> collisions = <List<String>>[
    for (final List<String> names in byContent.values)
      if (names.length > 1) (names..sort()),
  ];

  if (collisions.isEmpty) {
    stdout.writeln('$counted screenshots, every one its own picture.');
    return;
  }

  for (final List<String> names in collisions) {
    stderr.writeln(
      '::error::${names.length} routes were photographed identically, so at '
      'least ${names.length - 1} of them had not finished drawing: '
      '${names.join(', ')}',
    );
  }
  exit(1);
}
