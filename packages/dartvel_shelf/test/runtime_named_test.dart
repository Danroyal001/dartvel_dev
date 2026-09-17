// What the package says it is built on is what rust/Cargo.toml builds it on.
//
// The README, the pub description and the example's start-up line said
// Actix Web for as long as the server has been Axum, so anyone reading the
// package to find the framework under it went looking in the wrong one.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String cargo = File('rust/Cargo.toml').readAsStringSync();

  test('the server is built on Axum', () {
    expect(cargo, contains(RegExp(r'^axum\s*=', multiLine: true)));
    expect(cargo.toLowerCase(), isNot(contains('actix')));
  });

  for (final String path in <String>[
    'README.md',
    'pubspec.yaml',
    'example/hello.dart',
  ]) {
    test('$path names no framework the server does not use', () {
      expect(File(path).readAsStringSync().toLowerCase(),
          isNot(contains('actix')));
    });
  }

  test('the README and the pub description name Axum', () {
    expect(File('README.md').readAsStringSync(), contains('Axum'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('Axum'));
  });
}
