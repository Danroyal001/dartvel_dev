// A server compiled to a native executable.
//
// Under `dart run`, serve() finds the native library inside the dartvel_shelf
// package. A compiled executable has no packages to look in, so it has to be
// handed the library's bytes with embedNativeServerLibrary() before serve().
// Here they are read from a file shipped next to the executable.
//
//   dart build cli --target example/compiled.dart
//   dart run example/copy_native_library.dart build/cli/linux_x64/bundle/bin
//   build/cli/linux_x64/bundle/bin/compiled
//
// The directory under build/cli/ is named for your platform; check what
// `dart build cli` printed.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

/// The library's file name on this operating system.
String get nativeLibraryName => Platform.isWindows
    ? 'dartvel_shelf.dll'
    : Platform.isMacOS
    ? 'libdartvel_shelf.dylib'
    : 'libdartvel_shelf.so';

Future<void> main() async {
  final beside = File.fromUri(
    File(Platform.resolvedExecutable).parent.uri.resolve(nativeLibraryName),
  );
  // Under `dart run`, resolvedExecutable is the Dart VM and the package's own
  // copy is used instead, so this program works both ways.
  if (beside.existsSync()) {
    embedNativeServerLibrary(beside.readAsBytesSync());
  }

  final router = Router()
    ..get('/', (req) async => Response.text('Served by a compiled binary\n'));

  final server = await serve(
    router.call,
    host: '0.0.0.0',
    port: int.parse(Platform.environment['PORT'] ?? '8080'),
  );
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);
  await server.stop();
  exit(0);
}
