// Which lib/native directory the outbound HTTP/2 client library is loaded
// from. Platform.version says `linux_arm64` and `windows_arm64`; the lookup
// checked it for `aarch64` and `ARM64`, so both arm64 hosts were sent to the
// x64 library.
@TestOn('vm')
library;

import 'dart:ffi';

import 'package:dartvel_core/src/http/native_client_location.dart';
import 'package:test/test.dart';

void main() {
  test('each host names its own client library', () {
    expect(nativeClientLibraryFor(Abi.linuxArm64),
        (subdir: 'linux-arm64', name: 'libdartvel_client.so'));
    expect(nativeClientLibraryFor(Abi.windowsArm64),
        (subdir: 'windows-arm64', name: 'dartvel_client.dll'));
    expect(nativeClientLibraryFor(Abi.macosArm64),
        (subdir: 'macos-arm64', name: 'libdartvel_client.dylib'));
    expect(nativeClientLibraryFor(Abi.linuxX64),
        (subdir: 'linux-x64', name: 'libdartvel_client.so'));
  });
}
