import 'dart:ffi' as ffi;
import 'dart:io' as io;
import 'package:path/path.dart' as p;

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
        : (io.Platform.isMacOS ? 'libdartvel_shelf.dylib' : 'dartvel_shelf.dll');
    final candidates = <String>[
      p.join(io.Directory.current.path, name),
      p.normalize(p.join(io.Directory.current.path, '../../packages/dartvel_shelf/rust/target/release', name)),
      p.normalize(p.join(io.Directory.current.path, '../packages/dartvel_shelf/rust/target/release', name)),
      p.normalize(p.join(io.Directory.current.path, 'packages/dartvel_shelf/rust/target/release', name)),
    ];
    for (final c in candidates) {
      if (io.File(c).existsSync()) {
        libPath = c;
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

final DartvelShelfBindings _b = DartvelShelfBindings(_openDartvelShelf());

// Top-level function proxies to preserve existing gen.* calls
dv_last_error() => _b.dv_last_error();
int dv_server_bootstrap(ffi.Pointer<ffi.Uint8> p, int len) =>
    _b.dv_server_bootstrap(p, len);
int dv_server_poll_job(int s, ffi.Pointer<RequestEnvelope> outReq) =>
    _b.dv_server_poll_job(s, outReq);
int dv_server_submit_response(int s, ffi.Pointer<ResponseEnvelope> env) =>
    _b.dv_server_submit_response(s, env);
int dv_request_metadata_read(int h, ffi.Pointer<ffi.Uint8> d, int cap) =>
    _b.dv_request_metadata_read(h, d, cap);
int dv_response_write_chunk(int h, ffi.Pointer<ffi.Uint8> s, int l) =>
    _b.dv_response_write_chunk(h, s, l);
int dv_response_open_stream(int r) => _b.dv_response_open_stream(r);
int dv_response_finalize_stream(int tx) => _b.dv_response_finalize_stream(tx);
int dv_response_write_for_request(int r, ffi.Pointer<ffi.Uint8> s, int l) =>
    _b.dv_response_write_for_request(r, s, l);
int dv_ws_send_text(int ws, ffi.Pointer<ffi.Uint8> s, int l) =>
    _b.dv_ws_send_text(ws, s, l);
int dv_ws_send_bin(int ws, ffi.Pointer<ffi.Uint8> s, int l) =>
    _b.dv_ws_send_bin(ws, s, l);
int dv_ws_close(int ws, int code, ffi.Pointer<ffi.Uint8> r, int l) =>
    _b.dv_ws_close(ws, code, r, l);
