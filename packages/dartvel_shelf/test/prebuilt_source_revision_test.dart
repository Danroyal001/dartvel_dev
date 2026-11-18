// Every prebuilt library in lib/native/ must be compiled from the Rust source
// in rust/, and so from the same source as each other.
//
// Six platforms, and until November 2026 they were built in two places: Linux
// and windows-x64 on the server, macOS and windows-arm64 on hosted runners.
// Version 3.47.4 fixed a TLS bug in the Rust (a plain server started after a
// TLS one in the same process also spoke TLS) and rebuilt three of the six.
// The other three still had the bug, and still lacked the rustls security
// update from October. Nothing showed it: the ABI version had not changed, so
// the Dart side loaded them, and the symbol test only opens the library for
// the platform it runs on.
//
// build.rs stamps each library with a hash of the source it was compiled
// from. This reads the stamp out of every copy as plain bytes, without loading
// any of them, so it checks the macOS and Windows libraries from a Linux
// machine too, and compares each with the hash of the source as it is now.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_shelf/src/native_library.dart'
    show nativeServerLibraryFor;
import 'package:test/test.dart';

const String _marker = 'dartvel_shelf source revision ';

const List<Abi> _shippedAbis = <Abi>[
  Abi.linuxX64,
  Abi.linuxArm64,
  Abi.macosArm64,
  Abi.macosX64,
  Abi.windowsX64,
  Abi.windowsArm64,
];

void main() {
  final String sourceRevision = rustSourceRevision(Directory('rust'));

  test('the source revision is sixteen hex digits', () {
    expect(sourceRevision, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  for (final Abi abi in _shippedAbis) {
    final ({String subdir, String name}) location =
        nativeServerLibraryFor(abi)!;
    final String path = 'lib/native/${location.subdir}/${location.name}';

    test('$path is built from the source in rust/', () {
      final File library = File(path);
      expect(library.existsSync(), isTrue,
          reason: 'no prebuilt library at $path');
      final List<String> stamps = revisionStamps(library.readAsBytesSync());
      expect(
        stamps,
        <String>[sourceRevision],
        reason: stamps.isEmpty
            ? '$path carries no source revision: it was built before build.rs '
                'stamped one. Rebuild it (doc/building-from-source.md).'
            : '$path was built from source revision ${stamps.join(', ')}, and '
                'rust/ is now $sourceRevision. Rebuild every copy in '
                'lib/native/ from the current source '
                '(doc/building-from-source.md).',
      );
    });
  }
}

/// The source revisions stamped into [bytes], in order of appearance.
List<String> revisionStamps(Uint8List bytes) {
  final List<int> marker = ascii.encode(_marker);
  final List<String> found = <String>[];
  for (int start = 0; start + marker.length + 16 <= bytes.length; start++) {
    int matched = 0;
    while (matched < marker.length && bytes[start + matched] == marker[matched]) {
      matched++;
    }
    if (matched < marker.length) continue;
    final String digits = ascii.decode(
        bytes.sublist(start + marker.length, start + marker.length + 16),
        allowInvalid: true);
    if (RegExp(r'^[0-9a-f]{16}$').hasMatch(digits)) found.add(digits);
  }
  return found;
}

/// The hash build.rs stamps into the library, computed the same way: FNV-1a
/// 64 over Cargo.toml, Cargo.lock, build.rs and every file under src/ sorted
/// by path, feeding for each its path, a NUL, its bytes with CRLF read as LF,
/// and a NUL.
String rustSourceRevision(Directory crate) {
  final List<String> sources = <String>[
    for (final FileSystemEntity entity
        in Directory('${crate.path}/src').listSync(recursive: true))
      if (entity is File)
        entity.path
            .substring(crate.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
  ]..sort();
  final List<String> files = <String>[
    'Cargo.toml',
    'Cargo.lock',
    'build.rs',
    ...sources,
  ];

  // Dart's int is a 64-bit two's complement integer on the VM, so the
  // multiplication wraps exactly as Rust's wrapping_mul does.
  int hash = 0xcbf29ce484222325;
  void feed(List<int> bytes) {
    for (final int byte in bytes) {
      hash ^= byte;
      hash *= 0x00000100000001b3;
    }
  }

  for (final String relative in files) {
    final Uint8List bytes = File('${crate.path}/$relative').readAsBytesSync();
    final BytesBuilder normalised = BytesBuilder(copy: false);
    for (int index = 0; index < bytes.length; index++) {
      if (bytes[index] == 0x0d &&
          index + 1 < bytes.length &&
          bytes[index + 1] == 0x0a) {
        continue;
      }
      normalised.addByte(bytes[index]);
    }
    feed(utf8.encode(relative));
    feed(const <int>[0]);
    feed(normalised.takeBytes());
    feed(const <int>[0]);
  }
  // In two halves: a VM int is signed, so toUnsigned(64) leaves a hash
  // with its top bit set negative, and it printed with a minus sign where
  // Rust's {:016x} prints sixteen digits.
  String half(int value) => value.toRadixString(16).padLeft(8, '0');
  return half((hash >> 32) & 0xffffffff) + half(hash & 0xffffffff);
}
