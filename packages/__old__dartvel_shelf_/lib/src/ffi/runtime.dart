import 'dart:ffi' as ffi;
import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'bindings.dart';
export 'bindings.dart' show SliceU8, RequestEnvelope, ResponseEnvelope;

ffi.DynamicLibrary _openDartvelShelf() {
  final envPath = io.Platform.environment['DARTVEL_SHELF_LIB'];

  String? libPath;

  if (envPath != null && envPath.isNotEmpty && io.File(envPath).existsSync()) {
    libPath = envPath;
  }

  if (libPath == null) {
    final name = io.Platform.isLinux
        ? 'libdartvel_shelf.so'
        : (io.Platform.isMacOS
            ? 'libdartvel_shelf.dylib'
            : 'dartvel_shelf.dll');

    final pathCandidates = <String>[
      path.join(io.Directory.current.path, name),
      path.normalize(path.join(io.Directory.current.path,
          '../../packages/dartvel_shelf/rust/target/release', name)),
      path.normalize(path.join(io.Directory.current.path,
          '../packages/dartvel_shelf/rust/target/release', name)),
      path.normalize(path.join(io.Directory.current.path,
          'packages/dartvel_shelf/rust/target/release', name)),
    ];

    for (final candidate in pathCandidates) {
      if (io.File(candidate).existsSync()) {
        libPath = candidate;
        break;
      }
    }
  }

  if (libPath != null) {
    return ffi.DynamicLibrary.open(libPath);
  }

  throw ArgumentError('Failed to locate dartvel_shelf native library.\n'
      'Build it and set DARTVEL_SHELF_LIB or place it at one of:\n'
      '  - ./libdartvel_shelf.so (cwd)\n'
      '  - ../../packages/dartvel_shelf/rust/target/release/libdartvel_shelf.so\n'
      '  - ../packages/dartvel_shelf/rust/target/release/libdartvel_shelf.so\n'
      'Build with: `cd packages/dartvel_shelf && make release`');
}

final DartvelShelfBindings _bartvelShelfBindings =
    DartvelShelfBindings(_openDartvelShelf());

// Top-level function proxies to preserve existing gen.* calls
SliceU8 dvLastError() => _bartvelShelfBindings.dv_last_error();

int dvServerBootstrap(ffi.Pointer<ffi.Uint8> p, int len) =>
    _bartvelShelfBindings.dv_server_bootstrap(p, len);

int dvServerPollJob(int server, ffi.Pointer<RequestEnvelope> outReq) =>
    _bartvelShelfBindings.dv_server_poll_job(server, outReq);

int dvServerSubmitResponse(int server, ffi.Pointer<ResponseEnvelope> env) =>
    _bartvelShelfBindings.dv_server_submit_response(server, env);

int dvRequestMetadataRead(
        int requestHandleId,
        ffi.Pointer<ffi.Uint8> destinationBuffer,
        int destinationBufferCapacity) =>
    _bartvelShelfBindings.dv_request_metadata_read(
        requestHandleId, destinationBuffer, destinationBufferCapacity);

int dvResponseWriteChunk(
        int responseHandleId, ffi.Pointer<ffi.Uint8> s, int l) =>
    _bartvelShelfBindings.dv_response_write_chunk(responseHandleId, s, l);

int dvResponseOpenStream(int responseIdentifier) =>
    _bartvelShelfBindings.dv_response_open_stream(responseIdentifier);

int dvResponseFinalizeStream(int tx) =>
    _bartvelShelfBindings.dv_response_finalize_stream(tx);

int dvResponseWriteForRequest(
        int responseIdentifier, ffi.Pointer<ffi.Uint8> s, int l) =>
    _bartvelShelfBindings.dv_response_write_for_request(
        responseIdentifier, s, l);

int dvWsSendText(int wsConnectionHandle, ffi.Pointer<ffi.Uint8> s, int l) =>
    _bartvelShelfBindings.dv_ws_send_text(wsConnectionHandle, s, l);

int dvWsSendBin(int wsConnectionHandle, ffi.Pointer<ffi.Uint8> s, int l) =>
    _bartvelShelfBindings.dv_ws_send_bin(wsConnectionHandle, s, l);

int dvWsClose(
        int wsConnectionHandle, int code, ffi.Pointer<ffi.Uint8> r, int l) =>
    _bartvelShelfBindings.dv_ws_close(wsConnectionHandle, code, r, l);
