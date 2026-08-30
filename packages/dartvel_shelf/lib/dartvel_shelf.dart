library dartvel_shelf;

export 'package:dartvel_core/http.dart';
export 'src/server_ffi_required.dart' if (dart.library.ffi) 'src/server.dart'
    show serve, ServerHandle, TlsConfig, CorsOptions;
