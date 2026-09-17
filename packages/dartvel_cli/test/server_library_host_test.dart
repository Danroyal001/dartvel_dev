// The server library a web-server build embeds is the one for the host it
// builds on. The directory was chosen from Platform.version, which says
// `linux_arm64` and `windows_arm64` -- never `aarch64` or `ARM64`, which is
// what was looked for -- so an arm64 build embedded an x64 library, or said
// there was none when there was.
import 'dart:ffi';

import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:test/test.dart';

void main() {
  test('each host names its own library', () {
    expect(dvServerLibraryFor(Abi.linuxArm64),
        (subdir: 'linux-arm64', name: 'libdartvel_shelf.so'));
    expect(dvServerLibraryFor(Abi.windowsArm64),
        (subdir: 'windows-arm64', name: 'dartvel_shelf.dll'));
    expect(dvServerLibraryFor(Abi.macosX64),
        (subdir: 'macos-x64', name: 'libdartvel_shelf.dylib'));
    expect(dvServerLibraryFor(Abi.linuxX64),
        (subdir: 'linux-x64', name: 'libdartvel_shelf.so'));
  });

  test('the build host is looked up by its ABI', () {
    expect(dvHostServerLibrary(), dvServerLibraryFor(Abi.current()));
  });
}
