// The digest of an installed module, which the signature and the lockfile
// both pin.
//
// It is recomputed from the bytes on disk every time and never read from
// anything the module ships, and it has to cover every byte the parent will
// run: a file left out of the digest is a file the publisher can change
// without the pin noticing.
import 'dart:io';

import 'package:dartvel_cli/src/module_trust/package_digest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory package(Map<String, String> files) {
  final Directory root = Directory.systemTemp.createTempSync(
    'dartvel_moddigest_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((String path, String contents) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  });
  return root;
}

const Map<String, String> base = <String, String>{
  'pubspec.yaml': 'name: acme_payments\nversion: 2.1.0\n',
  'lib/acme_payments.dart': 'void pay() {}\n',
};

void main() {
  test('is 64 lowercase hex characters and stable', () {
    final Directory a = package(base);
    final String digest = dvModulePackageDigest(a.path);
    expect(dvIsModuleDigest(digest), isTrue);
    expect(dvModulePackageDigest(a.path), digest);
    expect(
      dvModulePackageDigest(package(base).path),
      digest,
      reason: 'the same files in another directory are the same package',
    );
  });

  test('changes when one byte of code changes', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        'lib/acme_payments.dart': 'void pay() {} \n',
      }).path,
    );
    expect(after, isNot(before));
  });

  test('changes when a file is renamed with the same contents', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        'pubspec.yaml': base['pubspec.yaml']!,
        'lib/other.dart': base['lib/acme_payments.dart']!,
      }).path,
    );
    expect(after, isNot(before));
  });

  test('changes when a file is added, including a build hook', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        'hook/build.dart': 'void main() {}\n',
      }).path,
    );
    expect(after, isNot(before));
  });

  test('a boundary moved between path and contents is a different package', () {
    // Concatenating path and contents without lengths makes these two equal.
    final String a = dvModulePackageDigest(
      package(<String, String>{'lib/ab': 'c'}).path,
    );
    final String b = dvModulePackageDigest(
      package(<String, String>{'lib/a': 'bc'}).path,
    );
    expect(a, isNot(b));
  });

  test('leaves out the root signature file, which cannot sign itself', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        dvModuleSignatureFile: '{"anything": true}',
      }).path,
    );
    expect(after, before);
  });

  test('but not a file of that name anywhere else', () {
    // Excluding by basename would give the publisher a file in lib/ that no
    // pin covers.
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        'lib/$dvModuleSignatureFile': 'void evil() {}',
      }).path,
    );
    expect(after, isNot(before));
  });

  test('leaves out what the parent regenerates locally', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        '.dart_tool/package_config.json': '{}',
        'build/web/main.dart.js': 'x',
        'pubspec.lock': 'packages: {}',
      }).path,
    );
    expect(after, before);
  });

  test('but a build directory below the root is code like any other', () {
    final String before = dvModulePackageDigest(package(base).path);
    final String after = dvModulePackageDigest(
      package(<String, String>{
        ...base,
        'lib/build/x.dart': 'void x() {}',
      }).path,
    );
    expect(after, isNot(before));
  });

  test('refuses a symbolic link rather than guessing what it points at', () {
    final Directory root = package(base);
    Link(
      p.join(root.path, 'lib', 'linked.dart'),
    ).createSync(p.join(root.path, 'lib', 'acme_payments.dart'));
    expect(
      () => dvModulePackageDigest(root.path),
      throwsA(isA<DVModuleDigestException>()),
    );
  });

  test('a digest is only ever exactly 64 lowercase hex characters', () {
    final String digest = dvModulePackageDigest(package(base).path);
    expect(dvIsModuleDigest(digest.toUpperCase()), isFalse);
    expect(dvIsModuleDigest(digest.substring(0, 12)), isFalse);
    expect(dvIsModuleDigest('$digest '), isFalse);
    expect(dvIsModuleDigest('${digest}00'), isFalse);
  });
}
