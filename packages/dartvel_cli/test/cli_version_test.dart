// What `dartvel --version` reports.
//
// It used to be discovered at run time, by walking up from the working
// directory looking for any pubspec.yaml. That is right when the CLI runs from
// its own source tree and wrong everywhere else: a compiled binary invoked
// inside someone's project finds *their* pubspec and reports *their* app's
// version as the Dartvel CLI version. With no pubspec above it at all, it fell
// back to a hardcoded number that had already drifted -- the released 0.2.1
// binary announced itself as 0.2.0.
//
// A binary carries its own version. Nothing it finds on disk can tell it.
import 'dart:io';

import 'package:dartvel_cli/src/commands/version_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('the version the binary reports', () {
    test('it matches what the package declares', () {
      // The two are separate strings and this is what keeps them equal. The
      // scaffold's version constraints drifted exactly this way and shipped a
      // template asking for a release that never existed.
      final pubspec = File(p.join(_packageRoot(), 'pubspec.yaml'));
      final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec.readAsStringSync())!
          .group(1);

      expect(dartvelCliVersion, declared);
    });

    test('it does not change with the working directory', () {
      // The property that failed. A compiled binary run inside a user's
      // project must not pick up their pubspec.
      final before = dartvelCliVersion;
      final previous = Directory.current;
      final elsewhere = Directory.systemTemp.createTempSync('dartvel-ver-');
      addTearDown(() {
        Directory.current = previous;
        elsewhere.deleteSync(recursive: true);
      });

      File(p.join(elsewhere.path, 'pubspec.yaml'))
          .writeAsStringSync('name: someones_app\nversion: 9.9.9\n');
      Directory.current = elsewhere;

      expect(dartvelCliVersion, before);
      expect(dartvelCliVersion, isNot('9.9.9'));
    });

    test('it is a version, not a placeholder', () {
      expect(dartvelCliVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
    });
  });
}

/// The dartvel_cli package root, found from the working directory upward.
String _packageRoot() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync() ||
      !File(p.join(dir.path, 'bin', 'dartvel.dart')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not find the dartvel_cli package root');
    }
    dir = parent;
  }
  return dir.path;
}
