// Which lib/native directory the server library is looked up in, per host.
//
// It was read off Platform.version, which ends `on "linux_arm64"` or
// `on "windows_arm64"`. The check looked for `aarch64` on Linux and `ARM64`
// on Windows, neither of which that string contains, so both arm64 hosts
// looked in the x64 directory and loaded -- or embedded -- a library for the
// wrong architecture. Only linux-x64 had a library, so nothing noticed.
import 'dart:ffi';

import 'package:dartvel_shelf/src/native_library.dart';
import 'package:test/test.dart';

void main() {
  test('every server host maps to its own directory and file name', () {
    expect(nativeServerLibraryFor(Abi.linuxX64), (
      subdir: 'linux-x64',
      name: 'libdartvel_shelf.so',
    ));
    expect(nativeServerLibraryFor(Abi.linuxArm64), (
      subdir: 'linux-arm64',
      name: 'libdartvel_shelf.so',
    ));
    expect(nativeServerLibraryFor(Abi.macosArm64), (
      subdir: 'macos-arm64',
      name: 'libdartvel_shelf.dylib',
    ));
    expect(nativeServerLibraryFor(Abi.macosX64), (
      subdir: 'macos-x64',
      name: 'libdartvel_shelf.dylib',
    ));
    expect(nativeServerLibraryFor(Abi.windowsX64), (
      subdir: 'windows-x64',
      name: 'dartvel_shelf.dll',
    ));
    expect(nativeServerLibraryFor(Abi.windowsArm64), (
      subdir: 'windows-arm64',
      name: 'dartvel_shelf.dll',
    ));
  });

  test('a host with no server library is named, not mapped to another', () {
    expect(nativeServerLibraryFor(Abi.androidArm64), isNull);
    expect(nativeServerLibraryFor(Abi.linuxRiscv64), isNull);
  });

  test('this process looks where its own ABI says', () {
    expect(
      nativeServerLibraryLocation(),
      nativeServerLibraryFor(Abi.current()),
    );
  });
}
