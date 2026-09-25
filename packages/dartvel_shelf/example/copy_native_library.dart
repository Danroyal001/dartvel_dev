// Copies the dartvel_shelf native library for this machine into a directory,
// for shipping next to a compiled executable (see compiled.dart).
//
//   dart run example/copy_native_library.dart <destination directory>
//
// Run it from the project that depends on dartvel_shelf: it finds the library
// through that project's package configuration, so it copies the version the
// project resolved.
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run copy_native_library.dart <directory>');
    exit(64);
  }
  final location = switch (Abi.current()) {
    Abi.linuxX64 => 'linux-x64/libdartvel_shelf.so',
    Abi.linuxArm64 => 'linux-arm64/libdartvel_shelf.so',
    Abi.macosArm64 => 'macos-arm64/libdartvel_shelf.dylib',
    Abi.macosX64 => 'macos-x64/libdartvel_shelf.dylib',
    Abi.windowsX64 => 'windows-x64/dartvel_shelf.dll',
    Abi.windowsArm64 => 'windows-arm64/dartvel_shelf.dll',
    final other => throw UnsupportedError('no library is shipped for $other'),
  };
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_shelf/native/$location'),
  );
  if (uri == null) {
    stderr.writeln('dartvel_shelf is not a dependency of this project');
    exit(1);
  }
  final source = File.fromUri(uri);
  final target = Directory(args.single)..createSync(recursive: true);
  final copied = source.copySync(
    target.uri.resolve(location.split('/').last).toFilePath(),
  );
  stdout.writeln('Copied ${source.path}\n    to ${copied.path}');
}
