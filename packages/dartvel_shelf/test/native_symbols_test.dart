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

  // The other direction, which the check above cannot see.
  //
  // When a refactor *removes* a symbol, the bindings and the committed library
  // are both left behind together, so they still agree with each other and the
  // comparison above stays green. That is not hypothetical: `a7ea535f` moved
  // the HTTP client to dartvel_core, and `dv_http_send`, `dv_http_cancel`,
  // `dv_http_next_event` and `dv_http_free_buf` stayed in this package's
  // bindings and in its committed library for weeks afterwards -- symbols
  // belonging to another package's library, which nothing here has ever
  // called. Anyone who followed the advice above and rebuilt from source got a
  // library without them, and the green test turned red for doing the right
  // thing.
  //
  // The header is the source of truth: cbindgen writes it from the Rust that
  // exists, so a symbol the header does not declare is one this crate no
  // longer builds.
  test('the bindings declare nothing the header no longer does', () {
    final File header = File('rust/include/dartvel_shelf.h');
    expect(header.existsSync(), isTrue,
        reason: 'the cbindgen header is missing: ${header.path}');

    final String source = header.readAsStringSync();
    final File bindings = File('lib/src/generated/bindings.dart');
    final Set<String> declared = RegExp(
      r"_lookup<.*?>\(\s*'([A-Za-z0-9_]+)'\s*\)",
      dotAll: true,
    ).allMatches(bindings.readAsStringSync()).map((m) => m.group(1)!).toSet();

    final List<String> orphaned = <String>[
      for (final String symbol in declared)
        if (!RegExp('\\b$symbol\\s*\\(').hasMatch(source)) symbol,
    ]..sort();

    expect(
      orphaned,
      isEmpty,
      reason: 'the bindings bind symbols this crate no longer declares, so '
          'they can only resolve against a stale committed library. '
          'Regenerate them: dart run ffigen --config ffigen.yaml. '
          'Orphaned: $orphaned',
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
