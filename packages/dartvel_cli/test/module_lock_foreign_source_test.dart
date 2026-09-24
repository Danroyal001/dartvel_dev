// A foreign source has no publisher, so the pin is all there is.
//
// Publisher pinning works because pub.dev verifies a publisher against a
// domain. A Maven coordinate, a crate, an .xcframework or an OpenAPI URL has
// no such anchor: nobody vouches for it, nothing is signed, and the only thing
// standing between a project and a substituted artifact is what was written
// down when it was first resolved.
//
// So a foreign entry pins two digests rather than one. `sourceDigest` is what
// was fetched and `wrapperHash` is what was generated from it, and the pair is
// what tells a supply-chain event apart from a generator bug: a changed source
// is DV-MODULE-004, and a wrapper that changed while the source and the
// generator did not is DV-BIND-002. The fixes are opposite, so a lockfile that
// could not distinguish them would send every reader to the wrong one.
import 'dart:io';

import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _root(String lock) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_lock_foreign_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, dvModuleLockFile)).writeAsStringSync(lock);
  return root.path;
}

const String _foreign = '''
scanner:
  source: "maven:com.vendor:scanner"
  version: "4.2.0"
  sourceDigest: "3b1f2c4d5e6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c"
  wrapperHash: "9e04a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e"
  generator: "1.7.2"
  resolvedFrom: "https://repo1.maven.org/maven2/com/vendor/scanner/4.2.0/"
  targets: [android]
  capabilities: [nativeBindings]
''';

void main() {
  test('a foreign pin round-trips through the lockfile', () {
    final DVModuleLock lock = DVModuleLock.read(_root(_foreign));

    expect(lock.problems, isEmpty);
    final DVModulePin pin = lock.pins['scanner']!;
    expect(pin.source, 'maven:com.vendor:scanner');
    expect(pin.sourceDigest, startsWith('3b1f'));
    expect(pin.wrapperHash, startsWith('9e04'));
    expect(pin.generator, '1.7.2');
    expect(pin.resolvedFrom, 'https://repo1.maven.org/maven2/com/vendor/scanner/4.2.0/');
    expect(pin.targets, <String>['android']);
  });

  test('rendering it back produces a lockfile that reads the same', () {
    // A pin that survives a read and not a write is a pin that is lost the
    // next time anything touches the file.
    final DVModuleLock lock = DVModuleLock.read(_root(_foreign));
    final DVModuleLock again = DVModuleLock.read(_root(lock.render()));

    expect(again.problems, isEmpty);
    expect(again.pins['scanner']!.sourceDigest, lock.pins['scanner']!.sourceDigest);
    expect(again.pins['scanner']!.wrapperHash, lock.pins['scanner']!.wrapperHash);
    expect(again.pins['scanner']!.targets, <String>['android']);
  });

  test('a pub.dev pin still reads, and carries none of them', () {
    // The existing shape is the common one and must not need the new fields.
    final DVModuleLock lock = DVModuleLock.read(_root('''
store:
  version: "1.2.0"
  sha256: "${'a' * 64}"
  publisher: "example.com"
  key: null
  capabilities: [cron]
'''));

    expect(lock.problems, isEmpty);
    expect(lock.pins['store']!.source, isNull);
    expect(lock.pins['store']!.sourceDigest, isNull);
  });

  test('a source digest that is not a digest is refused, not ignored', () {
    // The whole reason the file exists. A malformed digest that was skipped
    // would be the lockfile saying nothing about that module, which is what
    // somebody substituting an artifact would write.
    final DVModuleLock lock = DVModuleLock.read(_root('''
scanner:
  source: "cargo:image"
  version: "0.25.0"
  sourceDigest: "3b1f"
  wrapperHash: "${'9' * 64}"
  generator: "1.7.2"
  capabilities: []
'''));

    expect(lock.pins, isEmpty);
    expect(lock.problems.single, contains('sourceDigest'));
  });

  test('a wrapper hash that is not a digest is refused too', () {
    final DVModuleLock lock = DVModuleLock.read(_root('''
scanner:
  source: "cargo:image"
  version: "0.25.0"
  sourceDigest: "${'3' * 64}"
  wrapperHash: "not a hash"
  generator: "1.7.2"
  capabilities: []
'''));

    expect(lock.pins, isEmpty);
    expect(lock.problems.single, contains('wrapperHash'));
  });

  test('a foreign source with no digest is refused', () {
    // A pin with nothing pinned is worse than no pin: it reads as resolved.
    final DVModuleLock lock = DVModuleLock.read(_root('''
scanner:
  source: "cargo:image"
  version: "0.25.0"
  capabilities: []
'''));

    expect(lock.pins, isEmpty);
    // Both are named, not just the first: a reader told to add a source
    // digest and then told to add a wrapper hash has been sent round twice.
    expect(lock.problems, hasLength(2));
    expect(lock.problems.join(' '), contains('sourceDigest'));
    expect(lock.problems.join(' '), contains('wrapperHash'));
  });

  test('a foreign entry needs no sha256, which pins a pub archive', () {
    // The two are different things: sha256 is the pub.dev archive, and a
    // Maven artifact does not have one.
    expect(DVModuleLock.read(_root(_foreign)).pins['scanner']!.sha256, isNull);
  });

  test('what a pin is compared against is the digest it actually carries', () {
    // The trap in making sha256 nullable: verification compared the installed
    // digest against pin.sha256, which is null for a foreign source, so every
    // foreign module would have failed DV-MODULE-004 for having exactly the
    // bytes it was pinned with.
    final DVModulePin foreign = DVModuleLock.read(_root(_foreign))
        .pins['scanner']!;
    final DVModulePin fromPub = DVModuleLock.read(_root('''
store:
  version: "1.2.0"
  sha256: "${'a' * 64}"
  publisher: "example.com"
  key: null
  capabilities: []
''')).pins['store']!;

    expect(foreign.pinnedDigest, foreign.wrapperHash);
    expect(fromPub.pinnedDigest, fromPub.sha256);
  });
}
