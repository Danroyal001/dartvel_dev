/// Where dartvel_core ships its native client library, per host.
///
/// Its own file, not exported: the client itself is exported conditionally
/// beside a web stand-in, and this needs dart:ffi.
library;

import 'dart:ffi' as ffi;

/// The directory and file name of the client library for [abi], or null for
/// an ABI it is not built for.
///
/// Read from the ABI, not from Platform.version, which says `linux_arm64` and
/// `windows_arm64`: checking it for `aarch64` and `ARM64` sent both arm64
/// hosts to the x64 library.
({String subdir, String name})? nativeClientLibraryFor(ffi.Abi abi) =>
    switch (abi) {
      ffi.Abi.linuxX64 => (subdir: 'linux-x64', name: 'libdartvel_client.so'),
      ffi.Abi.linuxArm64 =>
        (subdir: 'linux-arm64', name: 'libdartvel_client.so'),
      ffi.Abi.macosArm64 =>
        (subdir: 'macos-arm64', name: 'libdartvel_client.dylib'),
      ffi.Abi.macosX64 =>
        (subdir: 'macos-x64', name: 'libdartvel_client.dylib'),
      ffi.Abi.windowsX64 =>
        (subdir: 'windows-x64', name: 'dartvel_client.dll'),
      ffi.Abi.windowsArm64 =>
        (subdir: 'windows-arm64', name: 'dartvel_client.dll'),
      _ => null,
    };
