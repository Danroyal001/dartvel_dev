// Whether this host can run a module's binding kind.
//
// Testing: "A binding kind that cannot run on the host -- JNI without a JVM,
// a web binding without a browser -- is skipped by target rather than failed,
// and the skip is reported." A generated module's tests ask this before
// calling into a carrier, and pass the answer as the test's skip reason, so a
// CI machine without Node reports an npm module's calls as skipped, naming
// why, instead of failing them or passing them silently.
@TestOn('vm')
library;

import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

String? Function(String) onPath(Set<String> present) =>
    (String name) => present.contains(name) ? '/usr/bin/$name' : null;

void main() {
  group('a kind carried by Node', () {
    test('runs where node is on PATH', () {
      expect(
        dvModuleHostRefusal('npm', which: onPath(<String>{'node'}), environment: const <String, String>{}),
        isNull,
      );
      expect(
        dvModuleHostRefusal('wasm', which: onPath(<String>{'node'}), environment: const <String, String>{}),
        isNull,
      );
    });

    test('runs where DARTVEL_NODE names one, as the carrier reads it', () {
      expect(
        dvModuleHostRefusal('npm',
            which: onPath(<String>{}),
            environment: const <String, String>{'DARTVEL_NODE': '/opt/node/bin/node'}),
        isNull,
      );
    });

    test('is refused, naming Node and the fix, where there is none', () {
      final String? why = dvModuleHostRefusal('npm',
          which: onPath(<String>{}), environment: const <String, String>{});
      expect(why, contains('Node'));
      expect(why, contains('DARTVEL_NODE'));
    });
  });

  group('a Swift kind', () {
    test('runs on a Mac, or wherever swiftc is', () {
      expect(dvModuleHostRefusal('apple', which: onPath(<String>{}), os: 'macos'), isNull);
      expect(dvModuleHostRefusal('apple', which: onPath(<String>{'swiftc'}), os: 'linux'), isNull);
    });

    test('is refused elsewhere, naming swiftc', () {
      expect(dvModuleHostRefusal('apple', which: onPath(<String>{}), os: 'linux'), contains('swiftc'));
    });
  });

  test('a JVM kind is refused on the Dart VM, which is not a JVM', () {
    // It is reached over JNI on Android; the VM running a suite has no JVM
    // attached, whatever is installed on the machine.
    expect(dvModuleHostRefusal('jvm', which: onPath(<String>{'java'})), contains('JNI'));
  });

  test('a Dart package or a C library needs nothing more than the VM', () {
    expect(dvModuleHostRefusal('dartPackage', which: onPath(<String>{})), isNull);
    expect(dvModuleHostRefusal('ffi', which: onPath(<String>{})), isNull);
  });
}
