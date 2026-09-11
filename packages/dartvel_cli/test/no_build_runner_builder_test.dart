// dartvel_cli is the generator, not a builder inside someone else's build.
//
// The package shipped `lib/builder.dart`, a Builder that logged a fine-level
// message and wrote nothing, from when Dartvel's generation was meant to run
// under build_runner. No build.yaml ever declared it, here or anywhere, so it
// could not run even if a project wanted it to -- it was a public library
// promising an integration that does not exist, and the `build` dependency it
// needed was resolved by every user of the CLI.
//
// The build_runner path is retired. This is the test that keeps it retired.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The dartvel_cli package root, found by walking up from the test's own
/// working directory rather than assumed to be it.
String _packageRoot() {
  bool isPackage(Directory dir) {
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    return pubspec.existsSync() &&
        RegExp(r'^name: dartvel_cli$', multiLine: true)
            .hasMatch(pubspec.readAsStringSync());
  }

  var dir = Directory.current;
  while (!isPackage(dir)) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not find the dartvel_cli package root');
    }
    dir = parent;
  }
  return dir.path;
}

void main() {
  test('the package ships no build_runner builder', () {
    expect(File(p.join(_packageRoot(), 'lib', 'builder.dart')).existsSync(),
        isFalse);
    expect(File(p.join(_packageRoot(), 'build.yaml')).existsSync(), isFalse);
  });

  test('and so does not make every install resolve package:build', () {
    final String pubspec =
        File(p.join(_packageRoot(), 'pubspec.yaml')).readAsStringSync();
    final String dependencies = pubspec.split('dev_dependencies:').first;

    expect(RegExp(r'^  build:', multiLine: true).hasMatch(dependencies), isFalse,
        reason: 'nothing in lib/ imports package:build any more');
  });
}
