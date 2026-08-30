/// The half of dartvel_shelf that only a server imports.
///
/// This is the native side: `serve()` runs the Axum runtime through FFI. An
/// application that only calls a remote API wants
/// `package:dartvel_shelf/core.dart` instead, and gets none of this.
///
/// The conditional export keeps the entrypoint importable on web, where there
/// is no `dart:ffi` and nothing to serve with: the stub reports the absence
/// rather than failing to resolve.
library dartvel_shelf.backend;

export 'core.dart';
export 'src/server_ffi_required.dart'
    if (dart.library.ffi) 'src/server.dart'
    show serve, ServerHandle, TlsConfig, CorsOptions;
