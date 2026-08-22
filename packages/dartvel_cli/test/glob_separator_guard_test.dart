// A glob pattern is not a filesystem path. Its separator is always `/`, and a
// backslash is its *escape* character — so building a pattern with p.join
// produces `lib\models\**.dart` on Windows, where `\m` and `\*` are escapes
// and the pattern matches nothing at all.
//
// It fails silently: zero files found, an empty generated file, and an error
// hundreds of lines later about a type that does not exist. On Windows this
// emptied models.g.dart, so `User` was undefined and router.g.dart would not
// compile — an error that named neither models nor globs.
//
// Guarded as a signature because, like the separator bug it rhymes with, it is
// easy to write, reads as correct, and is a no-op on the platform it is
// written on.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no glob pattern is built with p.join', () {
    final offenders = <String>[];

    for (final packageDir in Directory('..').listSync().whereType<Directory>()) {
      final lib = Directory('${packageDir.path}/lib');
      if (!lib.existsSync()) continue;

      for (final file in lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        // Matches `Glob(p.join(` across a line break too, since the call is
        // often wrapped.
        final collapsed = source.replaceAll(RegExp(r'\s+'), ' ');
        if (collapsed.contains('Glob( p.join(') ||
            collapsed.contains('Glob(p.join(')) {
          offenders.add(file.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'glob separators are always "/", never the host separator:\n'
          '${offenders.join('\n')}',
    );
  });
}
