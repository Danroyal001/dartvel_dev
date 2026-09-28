// Every Studio screenshot the site shows is a file, and each is its own
// picture.
//
// The formula bar and the command palette were shown on /studio as two
// captions over one image: both files held the same bytes, a formula bar with
// an error under it, so a visitor reading about the command palette saw no
// command palette. A size check would not have caught it -- both were real
// PNGs -- so this compares what the files hold.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every asset path under assets/studio named in the site's own source.
Set<String> referenced() => <String>{
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart') && !f.path.contains('dartvel_client'))
          for (final Match m in RegExp(r"'(assets/studio[^']*\.png)'")
              .allMatches(f.readAsStringSync()))
            m.group(1)!,
    };

void main() {
  test('every Studio screenshot the site names exists', () {
    final Set<String> paths = referenced();
    expect(paths, isNotEmpty);
    for (final String path in paths) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('no two Studio screenshots are the same picture', () {
    final Map<String, String> byDigest = <String, String>{};
    for (final String path in referenced().toList()..sort()) {
      final String digest = sha256.convert(File(path).readAsBytesSync()).toString();
      final String? other = byDigest[digest];
      expect(other, isNull, reason: '$path holds the same bytes as $other');
      byDigest[digest] = path;
    }
  });
}
