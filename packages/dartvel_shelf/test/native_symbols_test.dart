// The compiled library under lib/native/ is committed, and the build hook that
// regenerates it skips — deliberately — when cargo or cbindgen is absent, so
// that a `dart run` on something unrelated does not have to compile Rust.
//
// The consequence went unnoticed for six days: a Rust change was made, the
// hook skipped, and the committed library stayed as it was. Nothing compared
// the two, so the generated bindings declared a symbol the shipped library did
// not export and the failure appeared at the first call rather than at build.
//
// This compares them. It is the cheapest check that the binary and the
// bindings describe the same library.
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the committed library exports every symbol the bindings declare', () {
    final bindings =
        File('lib/src/generated/bindings.dart');
    expect(bindings.existsSync(), isTrue,
        reason: 'generated bindings are missing entirely');

    // ffigen emits one _lookup<...>('name') per bound symbol. The type
    // argument nests its own angle brackets and wraps across lines, so this
    // matches lazily up to the `>('` that opens the call rather than trying to
    // describe the type.
    final declared = RegExp(
        r"_lookup<.*?>\(\s*'([A-Za-z0-9_]+)'\s*\)",
        dotAll: true,
      )
        .allMatches(bindings.readAsStringSync())
        .map((match) => match.group(1)!)
        .toSet();
    expect(declared, isNotEmpty,
        reason: 'no symbols were found in the bindings; the pattern this test '
            'scrapes may have changed with the ffigen version');

    final libraryFile = File(_libraryPath());
    if (!libraryFile.existsSync()) {
      markTestSkipped('no committed library for this platform: ${libraryFile.path}');
      return;
    }

    final library = ffi.DynamicLibrary.open(libraryFile.path);
    final missing = <String>[
      for (final symbol in declared)
        if (!_exports(library, symbol)) symbol,
    ]..sort();

    expect(
      missing,
      isEmpty,
      reason: 'the committed library is older than the bindings. Rebuild it: '
          'cargo build --release --target <triple> in rust/, then copy the '
          'result over ${libraryFile.path}. Missing: $missing',
    );
  });
}

bool _exports(ffi.DynamicLibrary library, String symbol) {
  try {
    library.lookup<ffi.Void>(symbol);
    return true;
  } on ArgumentError {
    return false;
  }
}

String _libraryPath() {
  if (Platform.isMacOS) {
    final arch = _arch();
    return 'lib/native/macos-$arch/libdartvel_shelf.dylib';
  }
  if (Platform.isWindows) {
    return 'lib/native/windows-x64/dartvel_shelf.dll';
  }
  return 'lib/native/linux-${_arch()}/libdartvel_shelf.so';
}

String _arch() =>
    Platform.version.contains('arm64') ? 'arm64' : 'x64';
