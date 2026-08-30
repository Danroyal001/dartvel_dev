// The native HTTP client resolves out of dartvel_core, not dartvel_shelf.
//
// The client used to be compiled into dartvel_shelf's crate alongside the Axum
// server, so an application that only calls a remote API linked a server to
// get a client. The client is now its own crate here. This checks the thing
// that actually breaks if the move is half-done: the library resolves, opens,
// and carries the client symbols.
@Tags(<String>['native'])
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// The platform-specific file name, as native_client.dart derives it.
String get libraryName => Platform.isWindows
    ? 'dartvel_client.dll'
    : Platform.isMacOS
        ? 'libdartvel_client.dylib'
        : 'libdartvel_client.so';

String get subdir => Platform.isMacOS
    ? (Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64')
    : Platform.isLinux
        ? (Platform.version.contains('aarch64') ? 'linux-arm64' : 'linux-x64')
        : (Platform.version.contains('ARM64')
            ? 'windows-arm64'
            : 'windows-x64');

void main() {
  test('the library resolves from dartvel_core', () async {
    final Uri? uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_core/native/$subdir/$libraryName'),
    );

    expect(uri, isNotNull,
        reason: 'the client library must ship with dartvel_core');
    expect(File(uri!.toFilePath()).existsSync(), isTrue);
  }, skip: Platform.isLinux ? false : 'only linux-x64 is committed so far');

  test('it opens and carries the client symbols', () async {
    final Uri? uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_core/native/$subdir/$libraryName'),
    );
    final ffi.DynamicLibrary library =
        ffi.DynamicLibrary.open(uri!.toFilePath());

    // These four are the client ABI. A lookup that throws means the library is
    // there but is not the one this package expects.
    for (final String symbol in <String>[
      'dv_http_send',
      'dv_http_next_event',
      'dv_http_cancel',
    ]) {
      expect(
        () => library.lookup<ffi.NativeFunction<ffi.Void Function()>>(symbol),
        returnsNormally,
        reason: '$symbol is part of the client ABI',
      );
    }
  }, skip: Platform.isLinux ? false : 'only linux-x64 is committed so far');

  test('it carries none of the server ABI', () async {
    // The point of the split. If `aw_start` resolves here, the crates were not
    // actually separated and the frontend is still linking a server.
    final Uri? uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_core/native/$subdir/$libraryName'),
    );
    final ffi.DynamicLibrary library =
        ffi.DynamicLibrary.open(uri!.toFilePath());

    for (final String symbol in <String>['aw_start', 'aw_stop', 'aw_serve']) {
      expect(
        () => library.lookup<ffi.NativeFunction<ffi.Void Function()>>(symbol),
        throwsA(isA<ArgumentError>()),
        reason: '$symbol belongs to the server, which is a different package',
      );
    }
  }, skip: Platform.isLinux ? false : 'only linux-x64 is committed so far');
}
