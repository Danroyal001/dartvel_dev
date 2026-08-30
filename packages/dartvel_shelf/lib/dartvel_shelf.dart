library dartvel_shelf;

export 'package:dartvel_core/dartvel.dart'
    show Request, Response, Headers, Body, URLPattern, Router;
export 'src/server_ffi_required.dart' if (dart.library.ffi) 'src/server.dart'
    show serve, ServerHandle, TlsConfig, CorsOptions;
